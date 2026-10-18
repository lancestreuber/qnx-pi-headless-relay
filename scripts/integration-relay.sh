#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IMAGE=${1:-qnx-headless-connect:integration}
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qnx-relay-integration.XXXXXX")
CONTROL_DIR=$(mktemp -d /tmp/qnx-rv.XXXXXX)
CONTROL_SOCKET=$CONTROL_DIR/s
CONTAINER="qnx-relay-integration-$$"
ECHO_PID=""

cleanup() {
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        docker stop "$CONTAINER" >/dev/null 2>&1 || true
    fi
    if [ -n "$ECHO_PID" ]; then
        kill "$ECHO_PID" 2>/dev/null || true
    fi
    case "$TEST_ROOT" in
        "${TMPDIR:-/tmp}"/qnx-relay-integration.*) rm -rf "$TEST_ROOT" ;;
    esac
    case "$CONTROL_DIR" in
        /tmp/qnx-rv.*) rm -rf "$CONTROL_DIR" ;;
    esac
}
trap cleanup 0 1 2 15

docker build -t "$IMAGE" "$ROOT/relay" >/dev/null
python3 "$ROOT/scripts/configure.py" \
    --relay-url wss://relay.example.test \
    --device-name integration \
    --remote-port 2244 \
    --output "$TEST_ROOT/bundle" >/dev/null

python3 - "$TEST_ROOT/echo-port" <<'PY' &
from pathlib import Path
import socketserver
import sys


class Echo(socketserver.BaseRequestHandler):
    def handle(self):
        while True:
            data = self.request.recv(65536)
            if not data:
                return
            self.request.sendall(data)


with socketserver.TCPServer(("127.0.0.1", 0), Echo) as server:
    Path(sys.argv[1]).write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()
PY
ECHO_PID=$!

attempt=0
while [ ! -s "$TEST_ROOT/echo-port" ]; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 50 ] || { echo "echo server did not start" >&2; exit 1; }
    sleep 1
done
ECHO_PORT=$(cat "$TEST_ROOT/echo-port")

docker run --rm -d --name "$CONTAINER" \
    -p 127.0.0.1::8080 \
    --env-file "$TEST_ROOT/bundle/relay/relay.env" \
    "$IMAGE" >/dev/null
RELAY_PORT=$(docker port "$CONTAINER" 8080/tcp | sed 's/.*://')

attempt=0
until docker logs "$CONTAINER" 2>&1 | grep -q "ws bridge listening"; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 20 ] || { docker logs "$CONTAINER" >&2; exit 1; }
    sleep 1
done

PROXY="python3 $TEST_ROOT/bundle/client/wsproxy.py ws://127.0.0.1:$RELAY_PORT"
ssh -M -S "$CONTROL_SOCKET" -f -N \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ExitOnForwardFailure=yes \
    -o "ProxyCommand=$PROXY" \
    -o HostKeyAlias=qnx-rdv \
    -o UserKnownHostsFile="$TEST_ROOT/bundle/boot/relay_known_hosts" \
    -o StrictHostKeyChecking=yes \
    -o IdentityFile="$TEST_ROOT/bundle/boot/qnx_tunnel_key" \
    -o IdentitiesOnly=yes \
    -R "127.0.0.1:2244:127.0.0.1:$ECHO_PORT" \
    tunnel@qnx-rdv

RESULT=$(printf 'relay-round-trip-ok' | ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o "ProxyCommand=$PROXY" \
    -o HostKeyAlias=qnx-rdv-integration \
    -o UserKnownHostsFile="$TEST_ROOT/bundle/client/relay_known_hosts" \
    -o StrictHostKeyChecking=yes \
    -o IdentityFile="$TEST_ROOT/bundle/client/qnx_relay" \
    -o IdentitiesOnly=yes \
    -W 127.0.0.1:2244 \
    tunnel@qnx-rdv-integration)
[ "$RESULT" = relay-round-trip-ok ] || {
    echo "relay round trip returned unexpected data: $RESULT" >&2
    exit 1
}

ssh -S "$CONTROL_SOCKET" -O exit tunnel@qnx-rdv >/dev/null 2>&1 || true
docker exec "$CONTAINER" pkill sshd >/dev/null 2>&1 || true
attempt=0
while docker inspect "$CONTAINER" >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 20 ] || { echo "container survived sshd exit" >&2; exit 1; }
    sleep 1
done

if docker run --rm \
    -e TUNNEL_AUTHORIZED_KEYS=not-a-key \
    "$IMAGE" >"$TEST_ROOT/invalid-relay.log" 2>&1; then
    echo "relay accepted invalid authorized_keys" >&2
    exit 1
fi
grep -q "authorized_keys is empty or contains an invalid key line" \
    "$TEST_ROOT/invalid-relay.log"

echo "Relay container integration passed"
