#!/bin/sh
# Adapted from chengandre/kindle-custom-screensaver v0.6.0 (MIT).
# Adds deterministic daily selection and a live local timestamp.
BASE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
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
. "$BASE/blanket_renderers.sh"

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
    DISPLAY=:0 xrefresh >> "$LOG" 2>&1
    log "Stopped; original renderers restored"
}
draw_screensaver() {
    COUNT="$(cat "$BASE/state/count" 2>/dev/null)"
    [ -n "$COUNT" ] || return 1
    INDEX="$("$BIN/daily-index" "$(date '+%Y-%m-%d')" "$COUNT")" || return 1
    echo "$INDEX" > "$BASE/state/daily-index"
    "$BASE/scripts/draw.sh" "$INDEX" >> "$LOG" 2>&1 || return 1
}

[ -f "$BASE/state/count" ] || { log "Missing content"; exit 1; }
chmod +x "$BIN/fbink_hf" "$BIN/screensaver_shield" "$BIN/screensaver_draw" "$BIN/daily-index"
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
            DISPLAY=:0 xrefresh >>"$LOG" 2>&1
            ;;
    esac
done
