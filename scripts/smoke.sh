#!/bin/sh
# Scripted UI smoke test (SV-703). Opens fixture images and writes what the
# window shows to build/smoke/*.png through the app's SVIEW_SNAPSHOT hook,
# which needs no Screen Recording permission. Fails if a snapshot is missing.
set -eu
APP=build/sView.app/Contents/MacOS/sView
OUT=build/smoke
rm -rf "$OUT"
mkdir -p "$OUT"
status=0
for name in photo-01.jpg photo-03.png photo-04.jpg wide.jpg; do
    shot="$OUT/${name%.*}.png"
    SVIEW_SNAPSHOT="$PWD/$shot" "$APP" "$PWD/fixtures/sample/$name" >/dev/null 2>&1 &
    pid=$!
    ( sleep 10; kill "$pid" 2>/dev/null ) &
    wait "$pid" || true
    if [ -s "$shot" ]; then
        echo "smoke: ok $shot"
    else
        echo "smoke: FAIL no snapshot for $name"
        status=1
    fi
done
# The key help owns input (SV-310), in a window small enough that the list
# has to scroll: G and the wheel reach the last row, gg
# the first, j does not move the image behind it, q closes it and gives the
# keyboard back so n moves the image.
config=$(mktemp -d)
help=$(XDG_CONFIG_HOME="$config" SVIEW_DEBUG=1 SVIEW_WINDOW_SIZE=700x480 \
    SVIEW_KEYS="? pause j G pause g g pause wheel@-40 pause q pause n" \
    "$APP" "$PWD/fixtures/sample/photo-01.jpg" 2>&1 >/dev/null &
    pid=$!; sleep 5; kill "$pid" 2>/dev/null)
rm -rf "$config"
tops=$(echo "$help" | awk '/^help top/ {print $3 "/" $5}' | tr '\n' ' ')
# Images shown, in order, with the close in between: nothing moves before q.
order=$(echo "$help" | awk '/^title/ {print $2} /^help closed/ {print "closed"}' | uniq | tr '\n' ' ')
if echo "$tops" | grep -Eq '^0/([1-9][0-9]*) 1/\1 \1/\1 0/\1 \1/\1 $' \
    && [ "$order" = "photo-01.jpg closed photo-02.jpg " ]; then
    echo "smoke: ok help pane scrolls to the last row and closes ($tops)"
else
    echo "smoke: FAIL help pane ($tops; $order)"
    echo "$help" | grep -E '^(help|title|command)' | sed 's/^/smoke:   /'
    status=1
fi

# Settings (SV-511) opens over the first window with a scratch config, and
# the default config it shows is the one written on first run.
config=$(mktemp -d)
shot="$OUT/settings.png"
rm -f "$shot"
settings=$(XDG_CONFIG_HOME="$config" SVIEW_DEBUG=1 SVIEW_SETTINGS=1 SVIEW_SNAPSHOT="$PWD/$shot" SVIEW_SNAPSHOT_DELAY=1.5 \
    "$APP" "$PWD/fixtures/sample/photo-01.jpg" 2>&1 >/dev/null)
written=$(grep -c '^restore_session false$' "$config/sview/config" 2>/dev/null || true)
rm -rf "$config"
if echo "$settings" | grep -q '^settings shown$' && [ -s "$shot" ] && [ "$written" = 1 ]; then
    echo "smoke: ok settings window opens ($shot)"
else
    echo "smoke: FAIL settings window"
    status=1
fi

# Every default binding fires in the running app (Phase 3 check), with a
# scratch config so the user's keymap and settings are not involved.
config=$(mktemp -d)
keys=$(XDG_CONFIG_HOME="$config" SVIEW_BENCH=keys "$APP" "$PWD/fixtures/sample/photo-01.jpg" 2>/dev/null || true)
rm -rf "$config"
echo "$keys" | sed 's/^/smoke: /'
if ! echo "$keys" | grep -q '^keys fired' || echo "$keys" | grep -q '^keys missing'; then
    echo "smoke: FAIL key bindings"
    status=1
fi
exit $status
