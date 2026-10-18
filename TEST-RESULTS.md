# Test results

## Live QNX Pi validation

The SD-card installation path was exercised on October 17, 2026 with a QNX
8.0.0 Quick Start Target Image on a Raspberry Pi 5, a Railway-hosted relay, and
a macOS SSH client. The QNX Pi had no Ethernet connection during these tests.
The evidence below was recovered from timestamped command output, not from a
later summary.

- Files were installed through the FAT boot partition, followed by repeated
  remove-card, insert-card, and boot cycles. The boot log recorded four
  autostart invocations through `/boot/onboot`.
- The running target showed QNX's Raspberry Pi 5 Wi-Fi driver, `wpa_supplicant`
  attached to `bcm0`, DHCP, the tunnel launcher, the outbound SSH process, and
  `wsproxy.py`. A later boot log explicitly recorded `bcm0 uses the default
  network stack` before starting reverse port 2222.
- Five consecutive SSH sessions completed successfully.
- After the outbound SSH process was deliberately terminated, the first two
  probes failed and the third succeeded eight seconds later. Three additional
  SSH sessions then completed through the replacement SSH/WebSocket process.
- After a QNX Pi reboot, the first two probes failed while the system started;
  the third succeeded. The response identified QNX 8.0.0 on Raspberry Pi 5 and
  showed both the relay launcher and persistent command runner starting from
  the boot hook.
- An SSH command remained silent for 90 seconds and then returned
  `IDLE_TEST_SURVIVED` with exit status 0. This crossed the 45-second failure
  window of an earlier proxy implementation.
- A later check showed the retained client connection still running after more
  than six minutes, before and after a live command. The persistent command
  runner was also running, with no new watchdog failures after the current boot
  marker.
- A C program was copied to the QNX Pi, compiled there, and executed through
  the relay. It returned:

```text
Hello from the QNX Pi!
system=QNX release=8.0.0 machine=RaspberryPi5
```

The live files were the direct predecessors of this repository's generalized
bundle. They prove the Wi-Fi-only SD-card boot, reverse tunnel, reconnect, and
remote execution path on physical QNX hardware. They do not prove that every
future generated bundle is configured correctly, and the optional CTI overlay
still needs a clean image build.

## Relay integration

The repository's container integration test generates temporary keys and then
checks the complete forwarding path:

- a tunnel key creates a loopback-only reverse listener;
- a separate client key carries data through that listener to an echo server;
- the returned payload must equal `relay-round-trip-ok`;
- invalid `authorized_keys` input must stop startup; and
- terminating the relay SSH daemon must stop the container rather than leave a
  false-online WebSocket process.

The WebSocket protocol tests also reject an invalid server accept value, a
masked server frame, and a frame larger than 1 MiB. GitHub Actions runs these
checks on every push and pull request.

## Remaining release checks

Before describing a tagged release as production-ready:

1. repeat the physical test with the exact output of the tagged bundle
   generator, rather than its manually assembled predecessor;
2. restart the relay service itself and record the QNX Pi reconnecting;
3. verify SD-card-only recovery after changing to a different Wi-Fi SSID; and
4. build the optional CTI overlay from a clean QNX CTI checkout.
