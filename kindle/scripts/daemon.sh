#!/bin/sh
# Adapted from chengandre/kindle-custom-screensaver v0.6.0 (MIT).
# Adds deterministic daily selection and a live local timestamp.
# This file lives in <extension>/scripts/, but every path below is relative to
# the extension root, so BASE is the parent directory of this script.
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RUNTIME="/var/tmp/kindlexiping-bin"
mkdir -p "$RUNTIME"
cp "$BASE"/bin/* "$RUNTIME"/ 2>/dev/null
chmod 755 "$RUNTIME"/* 2>/dev/null
BIN="$RUNTIME"
PIDFILE="/tmp/custom_ss_daemon.pid"
SHIELD_PIDFILE="/tmp/custom_ss_shield.pid"
STATEFILE="/tmp/custom_ss_restore_renderers"
FIFO="/tmp/custom_ss_events.fifo"
LOG="$BASE/custom_ss.log"
SLEEP_PID=""
WAKE_PID=""
CLEANED=0
. "$BASE/scripts/blanket_renderers.sh"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }
shield_down() {
    if [ -f "$SHIELD_PIDFILE" ]; then
        kill "$(cat "$SHIELD_PIDFILE")" 2>/dev/null
        wait "$(cat "$SHIELD_PIDFILE")" 2>/dev/null
        rm -f "$SHIELD_PIDFILE"
    fi
}
shield_up() {
    shield_down
    DISPLAY=:0 "$BIN/screensaver_shield" >> "$LOG" 2>&1 &
    echo "$!" > "$SHIELD_PIDFILE"
}
# xrefresh is an X11 client and is not installed on this device; calling it
# unguarded only writes "xrefresh: not found" to the log. FBInk already wrote
# the pixels to /dev/fb0, so this is a best-effort nudge for X clients only.
refresh_display() {
    if command -v xrefresh >/dev/null 2>&1; then
        DISPLAY=:0 xrefresh >>"$LOG" 2>&1
    fi
}
cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
    [ -n "$WAKE_PID" ] && kill "$WAKE_PID" 2>/dev/null
    shield_down
    exec 3>&- 2>/dev/null
    exec 3<&- 2>/dev/null
    rm -f "$FIFO" "$PIDFILE"
    if restore_original_renderers; then rm -f "$STATEFILE"; fi
    refresh_display
    log "Stopped; original renderers restored"
}
draw_screensaver() {
    COUNT="$(cat "$BASE/state/count" 2>/dev/null)"
    [ -n "$COUNT" ] || return 1
    INDEX="$("$BIN/daily-index" "$(date '+%Y-%m-%d')" "$COUNT")" || return 1
    echo "$INDEX" > "$BASE/state/daily-index"
    "$BASE/scripts/draw.sh" "$INDEX" >> "$LOG" 2>&1 || return 1
    # Capture what the screen actually shows. PW3 fb0 is 8bpp grayscale,
    # 1072 px wide with rows padded to 1088 bytes. This is the only way the
    # host can verify the lock screen without being told what it looks like.
    if dd if=/dev/fb0 of="$BASE/screen-lockscreen.raw" bs=1088 count=1448 2>>"$LOG"; then
        log "captured screen-lockscreen.raw"
    else
        log "framebuffer capture failed"
    fi
    return 0
}

[ -f "$BASE/state/count" ] || { log "Missing content"; exit 1; }
chmod +x "$BIN/fbink_hf" "$BIN/screensaver_shield" "$BIN/daily-index"
echo $$ > "$PIDFILE"
if ! capture_renderer_state; then rm -f "$PIDFILE" "$STATEFILE"; exit 1; fi
trap 'cleanup; exit 0' HUP INT TERM
trap 'cleanup' EXIT
rm -f "$FIFO"
mkfifo "$FIFO" || exit 1
exec 3<>"$FIFO"
lipc-wait-event -m com.lab126.powerd goingToScreenSaver >&3 2>>"$LOG" & SLEEP_PID=$!
lipc-wait-event -m com.lab126.powerd outOfScreenSaver,goingToPasswdDlg >&3 2>>"$LOG" & WAKE_PID=$!
if ! disable_original_renderers; then exit 1; fi
log "READY"
while read -r LINE <&3; do
    log "EVENT: $LINE"
    case "$LINE" in
        *goingToScreenSaver*)
            shield_up
            if ! draw_screensaver; then log "Draw failed"; exit 1; fi
            ;;
        *goingToPasswdDlg*)
            if [ -f "$SHIELD_PIDFILE" ]; then kill -USR1 "$(cat "$SHIELD_PIDFILE")" 2>>"$LOG"; fi
            ;;
        *outOfScreenSaver*)
            shield_down
            "$BIN/fbink_hf" -k -f -W GC16 >>"$LOG" 2>&1
            refresh_display
            ;;
    esac
done
