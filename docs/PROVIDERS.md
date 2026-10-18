# Relay providers

The connectivity protocol is not tied to Railway. It needs only a container
that receives WebSocket traffic and a public `wss://` endpoint. The reverse SSH
listener stays inside that container on `127.0.0.1`.

## Railway

Railway is the path tested with the current QNX Pi. Build `relay/`, load the two
values from the generated `relay/relay.env`, and expose the service through a
Railway public domain. Railway terminates TLS and forwards WebSocket traffic to
the container's `$PORT`.

## Any Docker VPS

Use [`deploy/vps/`](../deploy/vps/README.md) for a plain Linux VPS. Docker
Compose runs the relay and Caddy. Caddy handles the certificate and WebSocket
reverse proxy, so the public endpoint has the same shape as Railway:

```text
wss://relay.example.com
```

No provider-specific API or hostname is built into the QNX scripts.

## Moving an existing QNX Pi

Keep the generated `relay/relay.env`. It contains the relay host key and the
authorized client keys. Reusing it means a provider move does not require new
keys or a new trust prompt.

After the new endpoint is online:

1. Change `RELAY_URL` in the generated `boot/qnx-connect.conf`.
2. Change the URL at the end of `ProxyCommand` in `client/ssh_config`.
3. Put the updated `qnx-connect.conf` on the QNX Pi's FAT boot partition.
4. Boot the QNX Pi and run `client/connection.sh start`.

Leave the old relay running until the new connection passes an SSH test. If the
new provider fails, restoring the old two URLs moves the QNX Pi back without
changing keys.

## Provider requirements

- Public TLS with a certificate trusted by the QNX CA bundle.
- WebSocket upgrade support and long-lived connections.
- A writable runtime for the container's generated SSH files.
- Automatic restart when the relay container exits.
- No public mapping for the relay's internal SSH port.

Serverless request handlers are usually a poor fit because the tunnel is a
long-lived bidirectional connection, not a short HTTP request.
