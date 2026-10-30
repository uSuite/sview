#!/bin/sh
# Idle energy and leak check (SV-705, SV-706). Exercises the viewer, lets it
# settle on a still image, samples its CPU with top, then runs leaks on the
# live process with allocation stacks recorded. Fails when idle CPU is above
# 1% or when any leaked allocation was made from sView code. macOS frameworks
# (Foundation, AppIntents, SwiftUI) leak a fixed ~20 KB at launch; those are
# reported but not counted.
set -u
APP=build/sView.app/Contents/MacOS/sView
CONFIG=$(mktemp -d)
MallocStackLogging=1 XDG_CONFIG_HOME="$CONFIG" SVIEW_KEYS="n n n t i i s esc G p p gg" \
    "$APP" "$PWD/fixtures/sample/photo-01.jpg" >/dev/null 2>&1 &
pid=$!
sleep 6
cpu=$(top -l 4 -s 2 -pid "$pid" -stats cpu | awk 'NR > 1 && /^[0-9.]+$/ {last = $1} END {print last + 0}')
leaks "$pid" >"$CONFIG/leaks.txt" 2>/dev/null
kill "$pid"
wait "$pid" 2>/dev/null
summary=$(grep -E '^Process .* leaks? for' "$CONFIG/leaks.txt" | head -1)
# Stack frames in our code, before the binary image list at the end.
ours=$(awk '/^Binary Images:/ {exit} {print}' "$CONFIG/leaks.txt" \
    | grep -E 'sView\.debug\.dylib|SViewCore|  sView ' | grep -cvE '^(Process|Path|Identifier):')
rm -rf "$CONFIG"
echo "idle: cpu ${cpu}% after settling"
echo "idle: ${summary:-leaks gave no summary}; ${ours} stack frames in sView code"
status=0
awk -v c="$cpu" 'BEGIN {exit !(c > 1.0)}' && status=1
[ "$ours" -eq 0 ] || status=1
exit $status
