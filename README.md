# QNX Pi Headless Relay

Remote SSH access to a headless QNX 8 Raspberry Pi 5 over Wi-Fi, with no
Ethernet cable, monitor, keyboard, mouse, or serial adapter.

The QNX Pi waits for `bcm0` to receive a Wi-Fi address, binds an outbound SSH
connection to that address, wraps it in a secure WebSocket on port 443, and
opens a loopback-only reverse port inside a small public relay. A laptop uses a
second WebSocket connection to reach that port.

## Why this exists

QNX hackathons often provide Raspberry Pi targets that developers need to
reach over SSH. That is straightforward with an Ethernet cable or a monitor,
keyboard, and mouse, but becomes difficult when that extra hardware is not
available. Venue Wi-Fi can also isolate wireless clients, preventing a laptop
from reaching the QNX Pi directly even when both devices are on the same
network.

This project avoids that local-network requirement. The QNX Pi and laptop each
make an outbound connection to the same public relay, so Wi-Fi client isolation
does not prevent SSH access.

The QNX Pi only needs Wi-Fi it can join without opening a browser. An open
network, an ordinary password-protected network, or a phone hotspot can work as
long as it permits outbound HTTPS and WebSocket traffic on port 443. Captive
portals that require an email address, terms acceptance, or another browser
login step are not supported during headless boot.

This project is intentionally Wi-Fi-only. It does not fall back to Ethernet.
If `bcm0` never receives an IPv4 address, the remote tunnel does not start.

```text
QNX Pi bcm0                 public relay                    laptop

sshd :22 <--- reverse SSH --- 127.0.0.1:2222 <--- SSH ProxyJump
     \------ outbound WSS:443 ------^             over WSS:443
```

Railway is the hosted relay tested so far. The protocol is not tied to
Railway; [`deploy/vps/`](deploy/vps/README.md) runs the same container behind
Caddy on an ordinary VPS.

## What is included

- A WebSocket-to-SSH relay container.
- A per-device generator for fresh keys and configuration.
- A boot payload for the QNX 8.0 Quick Start Target Image on Raspberry Pi 5.
- Wi-Fi stack detection for both the default stack and `SOCK=/wifi`.
- A supervisor and reconnect loop that recover after tunnel or relay failure.
- A laptop SSH configuration and retained-connection helper.
- An SD-card installer that verifies the image hook before changing the card.
- An opt-in QNX Custom Target Image overlay.

## Requirements

- A QNX 8.0 Raspberry Pi 5 image with Python 3 and OpenSSH.
- Working Wi-Fi credentials for the network where the QNX Pi will boot.
- A public `wss://` relay endpoint. Only outbound TCP 443 is required.
- Python 3, OpenSSH, and `ssh-keygen` on the setup computer.
- Either the `/boot/onboot` hook in `qnx_sdp.ifs` or the CTI integration.

The SD installer checks for `/boot/onboot` and refuses an incompatible image
instead of producing a card that silently cannot start the tunnel.

## Setup

### 1. Choose the relay URL

Reserve a Railway public domain, or point a DNS name at the VPS that will run
the relay. You need the final hostname before generating the device bundle.

### 2. Generate a deployment bundle

```sh
python3 scripts/configure.py \
  --relay-url wss://YOUR-RELAY-HOST \
  --device-name qnxpi \
  --remote-port 2222
```

This creates `.qnx-connect/qnxpi/`:

```text
boot/     SD-card payload for the QNX Pi
client/   laptop SSH configuration and keys
relay/    relay host key and authorized-key environment
```

The generated directory contains private keys and is ignored by Git. Do not
upload it or send it through ordinary email.

### 3. Deploy the relay

Build the container in `relay/`. On Railway, set these two service variables
from the generated `relay/relay.env`:

```text
TUNNEL_HOST_KEY_B64
TUNNEL_AUTHORIZED_KEYS_B64
```

Expose the container through Railway's normal public domain. Railway terminates
TLS and forwards WebSockets to `$PORT`; do not publish a separate SSH port.

For a provider-independent deployment, follow the
[Docker VPS instructions](deploy/vps/README.md). Keep the same `relay.env` when
moving providers so the pinned host identity and device keys do not change.

### 4. Configure Wi-Fi and install the SD payload

Create `/boot/wpa_supplicant.conf` using
[`qnx/wpa_supplicant.example.conf`](qnx/wpa_supplicant.example.conf), then run:

```sh
scripts/install-to-sd.sh \
  .qnx-connect/qnxpi/boot \
  /path/to/mounted/qnx-boot-volume
```

The installer validates the QNX image and generated keys, stages the complete
payload, and installs the boot hook last. On first successful boot, the QNX Pi
moves its tunnel private key from the FAT partition to the data partition.

Eject the card cleanly, install it in the QNX Pi, and power it on. No local
interaction with the QNX Pi is required.

### 5. Connect from the laptop

```sh
.qnx-connect/qnxpi/client/connection.sh start
ssh -F .qnx-connect/qnxpi/client/ssh_config qnxpi
```

The first command keeps one harmless session open because the SSH server in the
tested QNX image closes an otherwise idle multiplex master. Later commands
reuse the same transport and avoid rebuilding both SSH hops.

```sh
.qnx-connect/qnxpi/client/connection.sh status
.qnx-connect/qnxpi/client/connection.sh stop
```

## Headless recovery

If the QNX Pi does not appear, power it off and mount the FAT partition on
another computer. Check these files in order:

1. `qnx-onboot.log`
2. `qnx-supervisor.log`
3. `qnx-tunnel.log`

Correct `wpa_supplicant.conf` or `qnx-connect.conf`, eject the card, and boot
again. Logs rotate at 1 MiB so repeated Wi-Fi or relay failures cannot fill the
boot partition.

The QNX Pi may initially have a 1970 clock and reject the relay certificate.
The reconnect loop keeps trying; it connects after network time synchronization
makes the certificate valid.

## Why the connection survives failures

- The boot supervisor restarts the full launcher if it exits.
- The tunnel process reconnects five seconds after an SSH or WebSocket failure.
- SSH keepalives provide end-to-end liveness without a fragile proxy timeout.
- The relay container exits if either its SSH daemon or WebSocket bridge dies,
  allowing Railway or Docker's restart policy to replace it.
- The relay host key is stable and pinned on both the QNX Pi and laptop.
- Reverse and client forwarding keys are restricted to one loopback port.

The relay never receives the private key used to log in to the QNX Pi. Its SSH
daemon, reverse listener, and forwarding destination all remain loopback-only.
See [ARCHITECTURE.md](ARCHITECTURE.md) for the full network and key model.

## Changing relay providers

See [docs/PROVIDERS.md](docs/PROVIDERS.md). A move keeps the generated
`relay.env` and changes only the relay URL in the QNX Pi and laptop
configuration. Leave the old endpoint running until the new path passes an SSH
test.

## Validation

Run the fast offline checks:

```sh
sh scripts/verify.sh
python3 scripts/test-wsproxy.py
```

With Docker available, test the complete generated-key reverse-forward path:

```sh
sh scripts/integration-relay.sh
```

The relay container and local end-to-end path pass. The physical predecessor of
this package also passed repeated Wi-Fi-only SD-card boots, a QNX Pi reboot,
multiple SSH sessions, and forced tunnel-process recovery. Before calling a
tagged release production-ready, repeat the hardware test with that release's
exact generated payload, restart the relay service itself, and complete a clean
build of the optional CTI overlay.

See [TEST-RESULTS.md](TEST-RESULTS.md) for the recovered live QNX Pi evidence,
the automated relay coverage, and the remaining release checks.

## License

Apache License 2.0. See [LICENSE](LICENSE).
