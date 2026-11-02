#!/bin/bash
# Run-script phase for the app, widget and watch targets.
#
# Gives every target in one build the same, ever-increasing CFBundleVersion. The number lives in
# build_number.txt (commit it, so builds from different machines keep counting up). The first
# target to run bumps it; the others, starting seconds later, reuse that number, so the app and
# its embedded widget and watch app always match. A build more than WINDOW seconds after the
# previous bump counts as a new build.
set -euo pipefail

WINDOW=60
counter="${SRCROOT}/build_number.txt"
lock="${TMPDIR:-/tmp}/snowboarders-build-number.lock"

# Targets can build in parallel; only one may read-modify-write the counter at a time.
for _ in $(seq 1 100); do
    mkdir "$lock" 2>/dev/null && break
    sleep 0.1
done
trap 'rmdir "$lock" 2>/dev/null || true' EXIT

if [ ! -f "$counter" ]; then
    echo "${CURRENT_PROJECT_VERSION:-1}" > "$counter"
    touch -t 197001010000 "$counter"   # so the first build bumps it
fi

number=$(tr -dc '0-9' < "$counter")
number=${number:-${CURRENT_PROJECT_VERSION:-1}}
age=$(( $(date +%s) - $(stat -f %m "$counter") ))
if [ "$age" -gt "$WINDOW" ]; then
    number=$((number + 1))
    echo "$number" > "$counter"
fi

# Stamp the built product's Info.plist; this runs before code signing.
plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $number" "$plist"
echo "note: ${TARGET_NAME} build number $number"
