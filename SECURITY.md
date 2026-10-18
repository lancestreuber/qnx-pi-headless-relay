# Security

## Generated material

`scripts/configure.py` creates four private keys. They live under the generated
output directory, which Git ignores by default. Do not commit, upload, or send
that directory through ordinary email.

If generated material is exposed, replace all four keys and redeploy the relay.
Deleting a Git commit is not enough after a public push.

## Design boundaries

- The relay's SSH daemon listens only on `127.0.0.1`.
- Reverse listeners also bind only to relay loopback.
- Tunnel and relay-client keys are restricted with `permitlisten` and
  `permitopen` respectively.
- Password and root login are disabled on the relay.
- The final laptop-to-QNX SSH key is never installed on the relay.
- The QNX login key uses trust on first use because the stock QNX host key is
  not known before a completely headless first boot.

This project does not change the QNX image's default account passwords or VNC
configuration. Operators remain responsible for the rest of the target's
security posture.

## Reporting a problem

Do not paste private keys, Wi-Fi passwords, relay environment variables, or
full logs into a public issue. Revoke exposed credentials first. Once the
project has a public repository, use its private vulnerability-reporting
channel when available.
