#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 PATH_TO_CUSTOM_TARGET_IMAGE_CHECKOUT" >&2
    exit 2
fi

cti=$1
here=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
if [ ! -f "$cti/Makefile" ] || [ ! -d "$cti/snippets" ] || [ ! -d "$cti/system" ]; then
    echo "not a QNX Custom Target Image checkout: $cti" >&2
    exit 2
fi

destination=$cti/system/usr/lib/qnx-headless-connect
mkdir -p "$destination"
cp "$here/qnx/qnx-connect-supervisor.sh" "$destination/qnx-connect-supervisor.sh"
cp "$here/qnx/qnx-tunnel-launcher.sh" "$destination/qnx-tunnel-launcher.sh"
cp "$here/qnx/qnx-tunnel.sh" "$destination/qnx-tunnel.sh"
cp "$here/qnx/wsproxy.py" "$destination/wsproxy.py"
cp "$here/cti/snippets/post_start.~85.qnx_headless_connect" "$cti/snippets/"
cp "$here/cti/snippets/system_files.custom.qnx_headless_connect" "$cti/snippets/"

echo "Installed the QNX Headless Connect overlay into $cti"
echo "Build with: make TARGET=rpi5"
