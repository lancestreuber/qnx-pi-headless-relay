#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT" || exit 1
FAIL=0
TMP_ROOT=""

ok() { printf 'ok:   %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=1; }
section() { printf '\n== %s ==\n' "$*"; }
cleanup() {
    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then rm -rf "$TMP_ROOT"; fi
}
trap cleanup 0 1 2 15

section "required files"
REQUIRED="
.gitignore LICENSE README.md ARCHITECTURE.md SECURITY.md CONTRIBUTING.md
docs/CTI-INTEGRATION.md
docs/PROVIDERS.md deploy/vps/docker-compose.yml deploy/vps/Caddyfile deploy/vps/.env.example deploy/vps/README.md
relay/Dockerfile relay/start.sh relay/sshd_config relay/wsbridge.py relay/authorized_keys.example
qnx/onboot qnx/qnx-connect.conf.example qnx/qnx-connect-supervisor.sh qnx/qnx-tunnel-launcher.sh qnx/qnx-tunnel.sh qnx/wsproxy.py
client/wsproxy.py client/ssh-config.example
scripts/configure.py scripts/install-to-sd.sh scripts/verify.sh scripts/test-wsproxy.py scripts/integration-relay.sh
cti/install-overlay.sh cti/snippets/post_start.~85.qnx_headless_connect cti/snippets/system_files.custom.qnx_headless_connect
skills/qnx-headless-remote-access/SKILL.md
"
for file in $REQUIRED; do
    if [ -f "$file" ]; then ok "$file"; else fail "$file missing"; fi
done

section "syntax"
for file in relay/wsbridge.py qnx/wsproxy.py client/wsproxy.py scripts/configure.py scripts/test-wsproxy.py; do
    if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1], encoding="utf-8").read())' "$file"; then
        ok "$file parses"
    else
        fail "$file does not parse"
    fi
done
for file in relay/start.sh qnx/onboot qnx/qnx-connect-supervisor.sh qnx/qnx-tunnel-launcher.sh qnx/qnx-tunnel.sh scripts/install-to-sd.sh scripts/verify.sh scripts/integration-relay.sh cti/install-overlay.sh; do
    if sh -n "$file"; then ok "$file passes sh -n"; else fail "$file fails sh -n"; fi
done

section "executable files"
for file in relay/start.sh relay/wsbridge.py qnx/onboot qnx/qnx-connect-supervisor.sh qnx/qnx-tunnel-launcher.sh qnx/qnx-tunnel.sh qnx/wsproxy.py client/wsproxy.py scripts/configure.py scripts/install-to-sd.sh scripts/verify.sh scripts/test-wsproxy.py scripts/integration-relay.sh cti/install-overlay.sh; do
    if [ -x "$file" ]; then ok "$file"; else fail "$file is not executable"; fi
done

section "QNX boot and network invariants"
for needle in '/proc/boot/on -d' 'qnx-connect-supervisor.sh'; do
    grep -qF "$needle" qnx/onboot && ok "onboot has $needle" || fail "onboot lacks $needle"
done
for needle in 'qnx-connect-supervisor.lock' 'retry in 5s' '1048576'; do
    grep -qF "$needle" qnx/qnx-connect-supervisor.sh && ok "supervisor has $needle" || fail "supervisor lacks $needle"
done
for needle in 'qnx-connect.conf' 'SOCK=/wifi ifconfig bcm0' 'SOCK=/wifi /proc/boot/.ssh-server.sh' 'CONNECT_HOME' 'RELAY_URL' 'REMOTE_PORT' 'waiting for a bcm0 IPv4 address' 'BIND_ADDRESS="$WIFI_ADDRESS"'; do
    grep -qF -- "$needle" qnx/qnx-tunnel-launcher.sh && ok "launcher has $needle" || fail "launcher lacks $needle"
done
if grep -qF '. "$CONFIG"' qnx/qnx-tunnel-launcher.sh; then
    fail "launcher executes its boot-volume config"
else
    ok "launcher parses boot-volume config as data"
fi
grep -qF 'qnx-tunnel-launcher.lock' qnx/qnx-tunnel-launcher.sh && ok "launcher has a single-instance lock" || fail "launcher lock missing"
grep -qF '1048576' qnx/qnx-tunnel.sh && ok "tunnel log is bounded" || fail "tunnel log rotation missing"
for needle in 'ssh -n -N' '-b "$BIND_ADDRESS"' 'BIND_ADDRESS must be the bcm0 Wi-Fi address' 'BatchMode=yes' 'NumberOfPasswordPrompts=0' 'ConnectTimeout=20' 'ExitOnForwardFailure=yes' 'StrictHostKeyChecking=yes' 'ServerAliveInterval=15' 'ServerAliveCountMax=20' 'sleep 5'; do
    grep -qF -- "$needle" qnx/qnx-tunnel.sh && ok "tunnel has $needle" || fail "tunnel lacks $needle"
done
if grep -qF 'DEAD_CONNECTION_TIMEOUT' qnx/wsproxy.py client/wsproxy.py; then
    fail "false WebSocket receive watchdog is present"
else
    ok "no false WebSocket receive watchdog"
fi

section "relay restrictions"
for needle in 'ListenAddress 127.0.0.1' 'PermitRootLogin no' 'PasswordAuthentication no' 'GatewayPorts no' 'PermitTunnel no'; do
    grep -qF "$needle" relay/sshd_config && ok "sshd has $needle" || fail "sshd lacks $needle"
done
grep -qF 'permitlisten="127.0.0.1:2222"' relay/authorized_keys.example && ok "example restricts listen" || fail "example permitlisten missing"
grep -qF 'permitopen="127.0.0.1:2222"' relay/authorized_keys.example && ok "example restricts open" || fail "example permitopen missing"
grep -qF 'TUNNEL_AUTHORIZED_KEYS_B64' relay/start.sh && ok "base64 authorized keys supported" || fail "base64 authorized keys unsupported"
if cmp -s qnx/wsproxy.py client/wsproxy.py; then ok "QNX and client proxies match"; else fail "QNX and client proxies drifted"; fi
for needle in 'Sec-WebSocket-Accept' 'MAX_FRAME_BYTES'; do
    grep -qF "$needle" client/wsproxy.py && ok "proxy has $needle" || fail "proxy lacks $needle"
done
for needle in 'wait -n' 'sshd -t'; do
    grep -qF "$needle" relay/start.sh && ok "relay supervisor has $needle" || fail "relay supervisor lacks $needle"
done

section "provider portability"
grep -qF 'reverse_proxy relay:8080' deploy/vps/Caddyfile && ok "Caddy forwards to relay" || fail "Caddy relay route missing"
grep -qF 'restart: unless-stopped' deploy/vps/docker-compose.yml && ok "VPS services restart" || fail "VPS restart policy missing"
if grep -qE '^[[:space:]]*ports:[[:space:]]*$|22:22|2222:2222' deploy/vps/docker-compose.yml | grep -qE '22:22|2222:2222'; then
    fail "VPS compose publishes an SSH port"
else
    ok "VPS compose publishes no SSH port"
fi

section "source-tree secret scan"
if grep -RIlE --exclude-dir=.git --exclude=verify.sh -- '-----BEGIN (OPENSSH|RSA|EC|DSA)? ?PRIVATE KEY-----' . | grep -q .; then
    fail "private key marker found"
else
    ok "no private key markers"
fi
if grep -RIl --exclude-dir=.git --exclude=verify.sh -- 'qnx-jump-server-production-812e' . | grep -q .; then
    fail "production relay URL remains in publishable source"
else
    ok "no production relay URL"
fi
if grep -RIl --exclude-dir=.git --exclude=verify.sh -- 'lancestreuber' . | grep -q .; then
    fail "machine-specific username remains in publishable source"
else
    ok "no machine-specific username"
fi

section "bundle generator smoke test"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/qnx-headless-connect.XXXXXX") || exit 1
BUNDLE=$TMP_ROOT/bundle
if python3 scripts/configure.py --relay-url wss://relay.example.test/socket --device-name test-qnx --remote-port 2244 --output "$BUNDLE" >/dev/null; then
    ok "configure.py completed"
else
    fail "configure.py failed"
fi
if python3 scripts/configure.py --relay-url wss://relay.example.test --device-name bad-port --remote-port 22 --output "$TMP_ROOT/bad-port" >/dev/null 2>&1; then
    fail "configure.py accepted a privileged relay port"
else
    ok "configure.py rejects privileged relay ports"
fi
for file in boot/qnx-connect.conf boot/qnx_tunnel_key boot/qnx_laptop.pub client/qnx_laptop client/qnx_relay client/ssh_config client/connection.sh relay/relay.env relay/ssh_host_ed25519_key relay/authorized_keys; do
    [ -f "$BUNDLE/$file" ] && ok "generated $file" || fail "missing generated $file"
done
grep -qF 'RELAY_URL=wss://relay.example.test/socket' "$BUNDLE/boot/qnx-connect.conf" && ok "relay URL rendered" || fail "relay URL not rendered"
grep -qF 'REMOTE_PORT=2244' "$BUNDLE/boot/qnx-connect.conf" && ok "port rendered" || fail "port not rendered"
grep -qF 'permitlisten="127.0.0.1:2244"' "$BUNDLE/relay/authorized_keys" && ok "generated permitlisten" || fail "generated permitlisten wrong"
grep -qF 'permitopen="127.0.0.1:2244"' "$BUNDLE/relay/authorized_keys" && ok "generated permitopen" || fail "generated permitopen wrong"
grep -qF 'qnx-rdv ssh-ed25519 ' "$BUNDLE/boot/relay_known_hosts" && ok "QNX relay alias pinned" || fail "QNX relay alias wrong"
grep -qF 'qnx-rdv-test-qnx ssh-ed25519 ' "$BUNDLE/client/relay_known_hosts" && ok "client relay alias pinned" || fail "client relay alias wrong"
if ssh -F "$BUNDLE/client/ssh_config" -G test-qnx >/dev/null 2>&1; then ok "generated SSH config parses"; else fail "generated SSH config does not parse"; fi

section "SD installer smoke test"
VOLUME=$TMP_ROOT/volume
mkdir -p "$VOLUME"
printf 'binary text /boot/onboot marker\n' > "$VOLUME/qnx_sdp.ifs"
printf 'old onboot\n' > "$VOLUME/onboot"
printf 'old bootstrap key\n' > "$VOLUME/qnx_tunnel_key"
if sh scripts/install-to-sd.sh "$BUNDLE/boot" "$VOLUME" >/dev/null; then
    ok "installer accepted compatible test image"
else
    fail "installer rejected compatible test image"
fi
if find "$VOLUME" -maxdepth 1 -name 'onboot.before-qnx-connect.*' | grep -q .; then ok "installer backed up replaced file"; else fail "installer backup missing"; fi
if find "$VOLUME" -maxdepth 1 -name 'qnx_tunnel_key.before-qnx-connect.*' | grep -q .; then fail "installer left a private-key backup on FAT"; else ok "installer does not back up private key"; fi
if find "$VOLUME" -maxdepth 1 -name '.qnx-connect-stage.*' | grep -q .; then fail "installer left its staging directory"; else ok "installer removed staging directory"; fi
if sh -n "$BUNDLE/client/connection.sh"; then ok "generated connection helper parses"; else fail "generated connection helper does not parse"; fi
BAD_VOLUME=$TMP_ROOT/bad-volume
mkdir -p "$BAD_VOLUME"
printf 'no startup hook here\n' > "$BAD_VOLUME/qnx_sdp.ifs"
if sh scripts/install-to-sd.sh "$BUNDLE/boot" "$BAD_VOLUME" >/dev/null 2>&1; then
    fail "installer accepted an image without /boot/onboot"
else
    ok "installer rejected image without boot hook"
fi

section "summary"
if [ "$FAIL" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
    exit 0
fi
echo "VERIFICATION FAILED"
exit 1
