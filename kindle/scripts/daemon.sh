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
STATEFILE="/tmp/custom_ss_restore_renderers"
FIFO="/tmp/custom_ss_events.fifo"
LOG="$BASE/custom_ss.log"
SLEEP_PID=""
WAKE_PID=""
CLEANED=0
. "$BASE/scripts/blanket_renderers.sh"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

# Written before anything can fail, so the log answers "did it even start?"
# instead of only showing a gap between one READY and the next.
log "starting pid=$$ parent=$PPID"

# Force the Kindle UI to repaint.
#
# The poster is drawn by FBInk straight into /dev/fb0, underneath the X server,
# so X believes its windows are still on screen and repaints nothing on wake.
# The panel therefore keeps showing the poster, and each tap reveals only the
# few pixels the framework happens to consider dirty -- which is exactly the
# "tap a bit, wake a bit" symptom.
#
# xscreen exits 2 when the panel still matches the captured poster, so a repaint
# that silently did nothing can no longer pass for a successful one. Retrying on
# that code costs nothing and covers the case where the UI was still mapping
# when the first attempt ran.
refresh_display() {
    ATTEMPT=1
    while [ "$ATTEMPT" -le 3 ]; do
        DISPLAY=:0 "$BIN/xscreen" wake </dev/null >>"$LOG" 2>&1
        RC=$?
        case "$RC" in
            0)
                log "repaint ok (attempt $ATTEMPT)"
                return 0
                ;;
            2)
                log "repaint did not reach the panel (attempt $ATTEMPT)"
                ;;
            *)
                log "repaint failed rc=$RC (attempt $ATTEMPT)"
                return "$RC"
                ;;
        esac
        ATTEMPT=$((ATTEMPT + 1))
        [ "$ATTEMPT" -le 3 ] && sleep 1
    done
    return 2
}

# Ask the framework to bring its own UI forward.
#
# This is the direct answer to "waking should land me on the interface": appmgrd
# starting the home booklet is a real UI action, so the framework redraws through
# its normal path instead of being asked to repaint a display whose contents X
# believes are already correct.
#
# Used as a fallback, after a repaint that provably did not reach the panel. Not
# used up front because it replaces whatever page was open with the home screen;
# that is acceptable when the alternative is a stuck poster.
restore_ui() {
    log "asking appmgrd for the home UI"
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home \
        </dev/null >>"$LOG" 2>&1
    sleep 2
}

cleanup() {
    [ "$CLEANED" -eq 1 ] && return
    CLEANED=1
    [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
    [ -n "$WAKE_PID" ] && kill "$WAKE_PID" 2>/dev/null
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

    # Each sleep shows a different excerpt, deliberately drawn at random rather
    # than from the date. The date-seeded pick repeated the same poster for a
    # whole day; the request here is a different one every time.
    # wc -l rather than awk: awk segfaults on this device's busybox. Normalise
    # with a case pattern instead of tr so a stray space can never reach the
    # numeric test below.
    BOOKS="$(wc -l < "$BASE/books.tsv" 2>/dev/null)"
    case "$BOOKS" in
        ''|*[!0-9]*) BOOKS=100 ;;
    esac
    [ "$BOOKS" -ge 1 ] 2>/dev/null || BOOKS=100

    LAST="$(cat "$BASE/state/last-index" 2>/dev/null)"
    [ -n "$LAST" ] || LAST=-1

    # A pick made on the browse page applies to the next sleep only. Treating it
    # as a whole-day override would stop the random rotation the moment the user
    # flipped through a few excerpts.
    TODAY="$(date '+%Y-%m-%d')"
    MANUAL_DATE="$(cat "$BASE/state/manual-date" 2>/dev/null)"
    MANUAL_INDEX="$(cat "$BASE/state/browser-index" 2>/dev/null)"
    if [ "$MANUAL_DATE" = "$TODAY" ] && [ -n "$MANUAL_INDEX" ] &&
       [ "$MANUAL_INDEX" -ge 0 ] 2>/dev/null && [ "$MANUAL_INDEX" -lt "$COUNT" ] 2>/dev/null; then
        INDEX="$MANUAL_INDEX"
        log "using manual pick $INDEX (next sleep only)"
        rm -f "$BASE/state/manual-date"
    else
        INDEX="$("$BIN/daily-index" random "$COUNT" "$BOOKS" "$LAST")" || return 1
        log "random pick $INDEX (books=$BOOKS last=$LAST)"
    fi

    echo "$INDEX" > "$BASE/state/last-index"
    echo "$INDEX" > "$BASE/state/daily-index"
    "$BASE/scripts/draw.sh" "$INDEX" >> "$LOG" 2>&1 || return 1
    # Capture what the screen actually shows. PW3 fb0 is 8bpp grayscale,
    # 1072 px wide with rows padded to 1088 bytes. This is the only way the
    # host can verify the lock screen without being told what it looks like,
    # and xscreen compares the live panel against this file to decide whether a
    # repaint actually reached it.
    if dd if=/dev/fb0 of="$BASE/screen-lockscreen.raw" bs=1088 count=1448 2>>"$LOG"; then
        log "captured screen-lockscreen.raw"
    else
        log "framebuffer capture failed"
    fi
    return 0
}

[ -f "$BASE/state/count" ] || { log "Missing content"; exit 1; }
chmod +x "$BIN/xscreen" "$BIN/fbink_hf" "$BIN/daily-index"
echo $$ > "$PIDFILE"
if ! capture_renderer_state; then rm -f "$PIDFILE" "$STATEFILE"; exit 1; fi
# SIGHUP must not be fatal. The Kindle runs documents and RUNME from short-lived
# shells, and the whole process group gets a hangup when one exits. Treating that
# as "stop" killed a daemon that had just been reported as started, which reads
# to the user as "it said 已启用 but no poster ever appears".
trap 'log "got SIGHUP (parent shell exited); staying up"' HUP
trap 'cleanup; exit 0' INT TERM
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
            if ! draw_screensaver; then log "Draw failed"; exit 1; fi
            ;;
        *outOfScreenSaver*|*goingToPasswdDlg*)
            # Never clear the framebuffer here. An earlier version ran
            # `fbink -k -f -W GC16`, which paints the panel white, and then
            # depended on a repaint that never happened -- so the screen stayed
            # blank or kept the poster until the user tapped around.
            #
            # The UI also needs a moment to map itself before it can repaint,
            # so give it one before forcing the redraw.
            sleep 1
            refresh_display
            # rc 2 means the panel provably still holds the poster after every
            # retry, so stop retrying and let the framework restore itself.
            [ "$?" -eq 2 ] && restore_ui
            # Capture right after wake so the host can confirm the panel is no
            # longer showing the poster, instead of inferring it from logs.
            dd if=/dev/fb0 of="$BASE/screen-after-wake.raw" bs=1088 count=1448 2>>"$LOG" \
                && log "captured screen-after-wake.raw"
            ;;
    esac
done
