#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 GENERATED_BOOT_DIRECTORY MOUNTED_QNX_BOOT_VOLUME" >&2
    exit 2
fi

payload=$1
volume=$2
required="onboot qnx-connect.conf qnx-connect-supervisor.sh qnx-tunnel-launcher.sh qnx-tunnel.sh wsproxy.py relay_known_hosts qnx_tunnel_key qnx_laptop.pub qnx_relay.pub"
stage=""
cleanup() {
    if [ -n "$stage" ] && [ -d "$stage" ]; then
        rm -rf "$stage"
    fi
}
trap cleanup 0 1 2 15

if [ ! -d "$payload" ] || [ ! -d "$volume" ]; then
    echo "both arguments must be directories" >&2
    exit 2
fi
case "$volume" in
    /|"$HOME")
        echo "refusing unsafe destination: $volume" >&2
        exit 2
        ;;
esac
if [ ! -f "$volume/qnx_sdp.ifs" ]; then
    echo "destination does not look like a QNX boot volume: qnx_sdp.ifs is missing" >&2
    exit 2
fi
if ! LC_ALL=C grep -a -q '/boot/onboot' "$volume/qnx_sdp.ifs"; then
    echo "this image does not contain the /boot/onboot startup hook" >&2
    echo "use the CTI integration path instead of copying a FAT payload" >&2
    exit 2
fi
for name in $required; do
    if [ ! -f "$payload/$name" ]; then
        echo "missing payload file: $payload/$name" >&2
        exit 2
    fi
done
if ! ssh-keygen -y -f "$payload/qnx_tunnel_key" >/dev/null 2>&1; then
    echo "payload tunnel private key is invalid" >&2
    exit 2
fi
for key in qnx_laptop.pub qnx_relay.pub; do
    if ! ssh-keygen -l -f "$payload/$key" >/dev/null 2>&1; then
        echo "payload public key is invalid: $key" >&2
        exit 2
    fi
done
if ! grep -q '^RELAY_URL=wss://' "$payload/qnx-connect.conf"; then
    echo "payload qnx-connect.conf has no secure relay URL" >&2
    exit 2
fi

# Copy and sync the complete payload before replacing live files. Install the
# boot hook last so a first-time install cannot activate a partial payload.
stage="$volume/.qnx-connect-stage.$$"
mkdir "$stage"
for name in $required; do
    cp "$payload/$name" "$stage/$name"
done
sync

stamp=$(date +%Y%m%d%H%M%S)
for name in qnx-connect.conf qnx-connect-supervisor.sh qnx-tunnel-launcher.sh qnx-tunnel.sh wsproxy.py relay_known_hosts qnx_laptop.pub qnx_relay.pub; do
    if [ -e "$volume/$name" ]; then
        cp -p "$volume/$name" "$volume/$name.before-qnx-connect.$stamp"
    fi
    mv -f "$stage/$name" "$volume/$name"
done
# The bootstrap private key is intentionally not backed up on the FAT volume.
# The QNX Pi moves it to the data partition on first successful startup.
mv -f "$stage/qnx_tunnel_key" "$volume/qnx_tunnel_key"
if [ -e "$volume/onboot" ]; then
    cp -p "$volume/onboot" "$volume/onboot.before-qnx-connect.$stamp"
fi
mv -f "$stage/onboot" "$volume/onboot"
rmdir "$stage"
stage=""
sync
echo "Installed QNX headless-connectivity payload to $volume"
echo "Backups of replaced files use suffix .before-qnx-connect.$stamp"
