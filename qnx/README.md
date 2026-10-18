# QNX-side files

The generated deployment bundle copies these files onto the FAT boot partition
for the QSTI path:

| File | Purpose |
| --- | --- |
| `onboot` | Detaches the supervisor with QNX's `/proc/boot/on -d` |
| `qnx-connect.conf` | Per-device relay URL, name, and reverse port |
| `qnx-connect-supervisor.sh` | Restarts the launcher if the full tunnel process exits |
| `qnx-tunnel-launcher.sh` | Waits for userspace and chooses the correct network stack |
| `qnx-tunnel.sh` | Holds the reverse SSH forward and retries after failure |
| `wsproxy.py` | Wraps SSH bytes in WebSocket frames over TLS 443 |
| `relay_known_hosts` | Pins the generated relay host key |
| `qnx_tunnel_key` | Bootstrap private key, moved off FAT on first boot |
| `qnx_laptop.pub` | Public key authorized for `qnxuser` login |
| `qnx_relay.pub` | Relay-only public key, explicitly excluded from QNX login |

Do not copy the source-tree example files by hand. Run
`scripts/configure.py`, then install the generated `boot/` directory with
`scripts/install-to-sd.sh`. The installer verifies that `qnx_sdp.ifs` contains
the `/boot/onboot` hook before it changes the card.

On QNX Raspberry Pi 5 images, Wi-Fi may belong to a separate io-sock instance.
The launcher checks both `ifconfig bcm0` and `SOCK=/wifi ifconfig bcm0`. When
the latter succeeds, it starts SSH with
`SOCK=/wifi /proc/boot/.ssh-server.sh` and launches the outbound tunnel with
the same `SOCK` setting. In either layout, it waits for a `bcm0` IPv4 address
and binds OpenSSH to that address. It does not fall back to Ethernet.

For a maintained image, use the CTI overlay under `cti/` instead. It installs
the scripts under `/usr/lib/qnx-headless-connect` and starts them through a
post-start snippet. Per-device keys and settings remain outside the image.
