# Generic VPS deployment

This is the portable alternative to Railway. It runs the same relay container
behind Caddy, which obtains and renews the TLS certificate. The QNX Pi and the
laptop still connect to `wss://YOUR_DOMAIN` on port 443.

You need a Linux VPS with Docker Compose, a public IPv4 or IPv6 address, and a
DNS name pointed at that address. Allow inbound TCP 80 and 443. The relay's SSH
port is not published.

From this directory:

```sh
cp .env.example .env
# Set RELAY_DOMAIN in .env.
cp ../../.qnx-connect/qnxpi/relay/relay.env relay.env
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 relay caddy
```

`relay.env` contains private key material. Keep it on the VPS, mode `0600`, and
do not commit it. Keep the same file when moving between hosts so the pinned
relay identity and access keys remain valid.

To leave Railway, bring this stack up first, verify that Caddy has a certificate,
then change the relay URL in the generated boot and client configuration. The
relay host key does not change as long as you reuse the same `relay.env`.
