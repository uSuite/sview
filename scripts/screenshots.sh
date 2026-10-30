#!/bin/sh
# README screenshots from the generated fixtures only (never real captures),
# through the app's snapshot hook, into docs/images/.
set -eu
APP=build/sView.app/Contents/MacOS/sView
OUT=docs/images
CONFIG=$(mktemp -d)
mkdir -p "$OUT"
shot() {
    name=$1
    target=$2
    keys=$3
    XDG_CONFIG_HOME="$CONFIG" SVIEW_WINDOW_SIZE=1200x760 SVIEW_SNAPSHOT_DELAY=2.5 \
        SVIEW_KEYS="$keys" SVIEW_SNAPSHOT="$PWD/$OUT/$name.png" "$APP" "$target" >/dev/null 2>&1
    sips -Z 1200 "$OUT/$name.png" >/dev/null
    echo "screenshots: $OUT/$name.png"
}
shot viewer "$PWD/fixtures/sample/photo-01.jpg" "t i"
shot sidebar "$PWD/fixtures/poc/poc-demo/poc-demo-vm-start" "s pause j"
shot memo "$PWD/fixtures/poc/poc-demo/poc-demo-vm-start/poc-demo-vm-start-01.png" "I t"
shot help "$PWD/fixtures/sample/photo-03.png" "?"
rm -rf "$CONFIG"
