# Test results

## Live QNX Pi validation

The prototype path was exercised on October 17, 2026 with a QNX 8.0.0 Quick
Start Target Image on a Raspberry Pi 5, a Railway-hosted relay, and a macOS SSH
client. The evidence below was recovered from timestamped command output, not
from a later summary.

- The QNX Pi opened its outbound tunnel after boot over `bcm0`.
- Five consecutive SSH sessions completed successfully.
- After the outbound tunnel process was deliberately stopped, the reconnect
  loop recorded the drop, waited five seconds, and established a replacement
  SSH/WebSocket process. Three subsequent SSH sessions completed successfully.
- An SSH command remained silent for 90 seconds and then returned
  `IDLE_TEST_SURVIVED` with exit status 0. This crossed the 45-second failure
  window of an earlier proxy implementation.
- A later check showed the retained client master running before and after a
  live command. The persistent command runner was also running, with no new
  watchdog failures after the current boot marker.
- A C program was copied to the QNX Pi, compiled there, and executed through
  the relay. It returned:

```text
Hello from the QNX Pi!
system=QNX release=8.0.0 machine=RaspberryPi5
```

The live prototype used the same WebSocket/reverse-SSH architecture as this
repository, but it predated the generalized bundle generator and the separate
launcher supervisor. A fresh-card test of the generated package and a clean
CTI build therefore remain release gates; the evidence above should not be
read as validation of every supported deployment mode.

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

## Remaining physical tests

Before describing the generated package as production-ready, test it from a
fresh SD card and record:

1. first boot using Wi-Fi only;
2. recovery after a QNX Pi reboot;
3. recovery after a relay restart;
4. a silent session lasting at least five minutes; and
5. SD-card-only Wi-Fi credential recovery.
