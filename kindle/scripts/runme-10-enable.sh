#!/bin/sh
# Invoked by the RUNME dispatcher; runs with root.
#
# One trigger must answer every open question, because each device test costs
# the user a USB unplug/replug cycle:
#   1. float ABI of the device
#   2. whether each binary actually executes (copying proves nothing)
#   3. a real render, exercised immediately instead of waiting for sleep
#   4. a framebuffer dump, so the host can LOOK at the result instead of
#      inferring it from logs
#   5. whether the daemon arms itself
BASE=/mnt/us/extensions/kindlexiping261030
RUNTIME=/var/tmp/kindlexiping-bin
LOG="$BASE/install.log"

exec >> "$LOG" 2>&1
set -x
echo "===== run $(date '+%Y-%m-%d %H:%M:%S') ====="
date
uname -a
[ -f /lib/ld-linux-armhf.so.3 ] && echo "device: hard-float (armhf)" || echo "device: soft-float (armel)"

mkdir -p "$RUNTIME"
cp "$BASE"/bin/* "$RUNTIME"/
chmod 755 "$RUNTIME"/*

# Each binary gets an argument it actually understands: daily-index is a tiny
# tool with no --version flag, so probing it that way reports a false failure.
echo "--- executable check ---"
"$RUNTIME/fbink_hf" -V >/dev/null 2>&1 \
    && echo "fbink_hf: starts" || echo "fbink_hf: FAILED"
"$RUNTIME/daily-index" 2026-10-31 5000 >/dev/null 2>&1 \
    && echo "daily-index: starts" || echo "daily-index: FAILED"
# screensaver_shield is an X11 app; it has no --version and is not headless-safe
# to probe, so only its loader/elf is checked here.
[ -x "$RUNTIME/screensaver_shield" ] \
    && echo "screensaver_shield: present" || echo "screensaver_shield: MISSING"
echo "daily-index(2026-10-31,5000) = $("$RUNTIME/daily-index" 2026-10-31 5000 2>&1)"

# Render one page now. Same code path the screensaver uses, so a rendering bug
# surfaces here instead of after a sleep cycle. NOTE: this device's awk
# segfaults on any input (rc=139), which is why draw.sh uses sed.
echo "--- render self-test ---"
INDEX="$(cat "$BASE/state/daily-index" 2>/dev/null)"
[ -n "$INDEX" ] || INDEX=0
if sh "$BASE/scripts/draw.sh" "$INDEX" browse; then
    echo "render: OK (index $INDEX)"
    RENDER_OK=1
else
    echo "render: FAILED (index $INDEX)"
    RENDER_OK=0
fi

# Dump the framebuffer so the host can decode it and look at the actual screen.
# PW3 fb0 is 8bpp grayscale, 1072 px wide, rows padded to 1088 bytes.
echo "--- framebuffer capture ---"
if [ "$RENDER_OK" -eq 1 ]; then
    if dd if=/dev/fb0 of="$BASE/screen-after-run.raw" bs=1088 count=1448 2>/dev/null; then
        echo "captured $BASE/screen-after-run.raw ($(wc -c < "$BASE/screen-after-run.raw" 2>/dev/null) bytes)"
    else
        echo "framebuffer capture failed"
    fi
else
    echo "skipped capture (render failed)"
fi

# Arm the daemon.
echo "--- daemon ---"
if sh "$BASE/scripts/toggle.sh" enable; then
    echo "daemon: enabled"
else
    echo "FAILED: toggle.sh enable returned non-zero"
fi

date
sync
echo "===== end ====="
