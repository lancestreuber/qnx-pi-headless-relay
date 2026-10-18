---
name: qnx-headless-remote-access
description: "Configure and diagnose outbound-only remote SSH access for headless QNX 8 Raspberry Pi targets through a WebSocket relay. Read this when provisioning a target without a console, integrating the service into QSTI or CTI boot, debugging the Raspberry Pi 5 /wifi stack, or making agent SSH sessions durable."
---

# QNX headless remote access

Use the QNX Pi Headless Relay project containing this skill to provision a
target. Treat QSTI boot-payload installation and CTI image integration as
separate modes.

## Workflow

1. Confirm QNX 8, Python 3, OpenSSH, Raspberry Pi model, and network interface.
2. For QSTI, prove the image contains its boot hook before copying anything:

   ```sh
   strings qnx_sdp.ifs | grep -C 2 /boot/onboot
   ```

   If the hook is absent, use CTI. Do not claim that arbitrary FAT files run on
   boot merely because `network` and `wpa_supplicant.conf` are supported.

3. Generate a new deployment. Never reuse a tunnel key, relay-client key,
   QNX-login key, relay host key, or reverse port from another device.
4. Deploy the loopback-only relay and pin its generated host key.
5. Install the generated boot payload or CTI overlay. Keep Wi-Fi settings and
   all private keys out of source control.
6. Boot the QNX Pi, then inspect `qnx-onboot.log`, `qnx-supervisor.log`, and
   `qnx-tunnel.log` before changing the design when a connection fails.
7. Verify a shell, a silent session longer than five minutes, a QNX Pi reboot,
   and a relay restart. Record exact commands and scope for any new fact.

## QNX-specific rules

- Detach early boot work with `/proc/boot/on -d`. A shell command ending in `&`
  did not survive the tested startup environment.
- Check both `ifconfig bcm0` and `SOCK=/wifi ifconfig bcm0`. When `/wifi` owns
  the interface, start SSH with `SOCK=/wifi /proc/boot/.ssh-server.sh` and run
  the outbound tunnel with the same `SOCK` value.
- Wait for an IPv4 address on `bcm0` and pass it to SSH with `-b`. This project
  is for cable-free provisioning and must not fall back to Ethernet.
- Export `SSL_CERT_FILE=/etc/ssl/certs/cacert.pem` before invoking SSH. QNX's
  shell did not accept an inline assignment inside `ProxyCommand`.
- Expect TLS verification to fail while the clock is still at 1970. Retry after
  time sync instead of disabling certificate verification.
- Let SSH keepalives determine liveness. A 45-second receive timer in the
  Python WebSocket proxy falsely terminated healthy QNX TLS sessions.
- Use `ssh -n -N`, `BatchMode=yes`, `NumberOfPasswordPrompts=0`,
  `ConnectTimeout=20`, `ExitOnForwardFailure=yes`, and a bounded retry delay.
- Keep relay listeners on `127.0.0.1`; never make the reverse port public.
- A retained client master needs one active remote session on the tested QNX
  image. Use a sleeping shell and close it deliberately through the control
  socket.

## Recovery

For a fully headless target, the FAT boot partition is the offline recovery
surface. Preserve readable launcher and tunnel logs there. A Wi-Fi change must
be recoverable by replacing `wpa_supplicant.conf` and rebooting, without an
existing SSH connection.
