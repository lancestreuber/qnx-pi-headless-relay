# Architecture

## Network path

```text
laptop                     WebSocket relay                    QNX Pi

ssh qnxpi                  TLS terminates here                sshd
    |                              |                             ^
    +-- ProxyJump over WSS ------> sshd on 127.0.0.1:22          |
                                   |                             |
                                   +-- 127.0.0.1:2222 -----------+
                                       reverse SSH listener

QNX Pi -- outbound WSS:443 --> relay SSH -- -R loopback port --> QNX sshd
```

The QNX Pi never accepts an internet-facing connection. It opens an outbound
SSH session, wrapped in WebSocket frames over TLS 443, and requests a reverse
forward on the relay's loopback interface. The laptop opens a separate WSS
connection to the relay and uses `ProxyJump` to reach that loopback port.

The launcher waits for an IPv4 address on the QNX Pi's `bcm0` interface and
passes that address to OpenSSH with `-b`. An Ethernet interface cannot become
the tunnel's source path. If Wi-Fi is unavailable, the launcher keeps waiting
instead of silently changing transports.

The public edge is replaceable. Railway can terminate TLS and forward the
WebSocket directly, or Caddy can provide the same `wss://` endpoint on a VPS.
Nothing in the tunnel protocol depends on Railway's API.

The default bundle supports one QNX Pi per relay. Multiple devices are possible
with a unique port and fresh keys per device, but the generated single-device
deployment is easier to reason about and harder to misconfigure.

## Key roles

| Key | Private half lives on | Capability |
| --- | --- | --- |
| Tunnel key | QNX Pi | May listen only on the configured relay loopback port |
| Relay client key | Laptop | May open only that relay loopback port |
| QNX login key | Laptop | May authenticate only to the QNX Pi's `qnxuser` account |
| Relay host key | Relay | Gives both clients a stable relay identity across redeploys |

The first two public keys use OpenSSH `permitlisten` and `permitopen`
restrictions. The relay disables shell, PTY, X11, password login, root login,
public listeners, and arbitrary forwarding for those keys.

## QNX startup

The QSTI path places `onboot` on the FAT partition. The installer verifies that
the image contains a `/boot/onboot` call before it copies anything. `onboot`
uses `/proc/boot/on -d` to detach the supervisor safely.

The launcher then:

1. Reads non-secret settings from `/boot/qnx-connect.conf`.
2. Waits for Python, OpenSSH, sockets, and the data partition.
3. Detects whether `bcm0` is on the default stack or `SOCK=/wifi`.
4. Starts the QNX SSH server inside `/wifi` when that stack owns `bcm0`.
5. Waits for a `bcm0` IPv4 address and binds outbound SSH to it.
6. Installs keys and pinned host information with restricted permissions.
7. Runs the reconnect loop in the same network stack as `bcm0`.

For CTI, the same scripts belong in `/usr/lib/qnx-headless-connect` and a
`post_start` snippet launches the supervisor after networking. Only the per-device config,
bootstrap key, login public key, and pinned relay key need provisioning.

## Liveness

There are four independent layers:

- WebSocket pings keep the hosting edge from treating the connection as idle.
- SSH keepalives determine whether the end-to-end transport is alive.
- The QNX reconnect loop waits five seconds and starts a new tunnel after any
  clean or unclean exit.
- The detached boot supervisor restarts the launcher if the reconnect loop
  itself disappears.

The client connection helper keeps one real remote session open because the
tested QNX SSH server closes a multiplex master that has no session channels.
Manual stop uses the SSH control socket, which also ends the harmless sleeper.

## Trust boundary

The relay handles encrypted WebSocket transport and SSH forwarding, but it
does not receive the laptop-to-QNX private key. Authentication to the final QNX
SSH server remains end to end. The relay operator can disrupt or observe SSH
ciphertext and connection metadata but cannot decrypt the QNX SSH session from
the relay keys alone.
