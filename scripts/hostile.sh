#!/bin/sh
# Hostile fixture pass in the UI (SV-704): the app must survive every case
# and say something sensible. Prints one line per case; exits non-zero if
# the app died on any. Uses a scratch config so user settings stay out.
set -u
APP=build/sView.app/Contents/MacOS/sView
DATA=build/hostile
[ -d "$DATA/many" ] || xcrun swift scripts/make-hostile.swift "$DATA" >/dev/null
CONFIG=$(mktemp -d)
LOG=$(mktemp)
status=0

# run <label> <path> [action]: launch, optionally act, check survival.
run() {
    label=$1
    target=$2
    action=${3:-}
    XDG_CONFIG_HOME="$CONFIG" SVIEW_DEBUG=1 "$APP" "$target" >"$LOG" 2>&1 &
    pid=$!
    sleep 2
    if [ -n "$action" ]; then
        sh -c "$action"
        sleep 2
    else
        sleep 2
    fi
    if kill -0 "$pid" 2>/dev/null; then
        rss=$(ps -o rss= -p "$pid" | awk '{printf "%d", $1 / 1024}')
        said=$(grep -E '^(title|toast)' "$LOG" | tail -1 | cut -c1-90)
        printf 'hostile: ok    %-24s %5s MB  %s\n' "$label" "$rss" "$said"
        kill "$pid"
        wait "$pid" 2>/dev/null
    else
        printf 'hostile: DIED  %-24s\n' "$label"
        tail -5 "$LOG"
        status=1
    fi
}

for file in zero-byte.png truncated.jpg fake.png frames-500.gif huge-20k.png; do
    run "$file" "$PWD/$DATA/files/$file"
done
run "10000-file folder" "$PWD/$DATA/many/img-05000.png"

SCRATCH=$(mktemp -d)
mkdir -p "$SCRATCH/replace" "$SCRATCH/gone"
cp fixtures/sample/photo-01.jpg fixtures/sample/photo-02.jpg "$SCRATCH/replace/"
cp fixtures/sample/photo-01.jpg "$SCRATCH/gone/"
run "file replaced" "$SCRATCH/replace/photo-01.jpg" "cp fixtures/sample/wide.jpg '$SCRATCH/replace/photo-01.jpg'"
run "folder deleted" "$SCRATCH/gone/photo-01.jpg" "rm -rf '$SCRATCH/gone'"

rm -rf "$CONFIG" "$SCRATCH" "$LOG"
exit $status
