#!/bin/sh
# Name: 栖息 · 名著锁屏
# DontUseFBInk
BASE="/mnt/us/extensions/kindlexiping261030"
BIN="/var/tmp/kindlexiping-bin"
SHIELD_PIDFILE="/tmp/custom_ss_shield.pid"   # retired helper; only cleaned up
PIDFILE="/tmp/custom_ss_daemon.pid"
STATEFILE="/tmp/custom_ss_restore_renderers"
FIFO="/tmp/custom_ss_events.fifo"
LOG="$BASE/launcher.log"
prepare_runtime() {
    mkdir -p "$BIN"
    cp "$BASE"/bin/* "$BIN"/ 2>/dev/null
    chmod 755 "$BIN"/* 2>/dev/null
}
# A hard-float build needs /lib/ld-linux-armhf.so.3; soft-float Kindles lack it,
# so a mismatched binary fails to exec with no visible error. Detect it up front.
abi_mismatch() {
    [ -f "$BIN/fbink_hf" ] || return 1
    if [ -f /lib/ld-linux-armhf.so.3 ]; then return 1; fi
    if LC_ALL=C grep -q 'ld-linux-armhf' "$BIN/fbink_hf" 2>/dev/null; then
        return 0
    fi
    return 1
}
# Fail loudly if a required file is missing. Without this, a bad path turns into
# a silently dead launcher: the script exits after sourcing, nothing is drawn,
# and the only trace is a line buried in install.log.
require_file() {
    [ -f "$1" ] && return 0
    echo "$(date '+%Y-%m-%d %H:%M:%S') MISSING: $1" >> "$LOG"
    mkdir -p "$BIN" 2>/dev/null
    cp "$BASE"/bin/fbink_hf "$BIN"/ 2>/dev/null
    chmod 755 "$BIN"/fbink_hf 2>/dev/null
    "$BIN/fbink_hf" -q -c -m -M -B WHITE -C BLACK -S 5 "安装不完整
缺少：$(basename "$1")" 2>/dev/null
    exit 1
}
require_file "$BASE/scripts/blanket_renderers.sh"
require_file "$BASE/scripts/daemon.sh"
require_file "$BASE/state/count"
require_file "$BASE/data.tsv"

. "$BASE/scripts/blanket_renderers.sh"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }
is_running() {
    [ -f "$PIDFILE" ] || return 1
    PID="$(cat "$PIDFILE")"
    [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}
stop_reader() {
    if [ -f /tmp/kindlexiping-reader.pid ]; then
        kill "$(cat /tmp/kindlexiping-reader.pid)" 2>/dev/null
        rm -f /tmp/kindlexiping-reader.pid
    fi
    # Leftovers from the retired screensaver_shield helper.
    rm -f /tmp/kindlexiping-reader-shield.pid /tmp/kindlexiping-reader-cover.pid
}
disable() {
    stop_reader
    if is_running; then kill "$(cat "$PIDFILE")" 2>/dev/null; sleep 2; fi
    if [ -f "$SHIELD_PIDFILE" ]; then kill "$(cat "$SHIELD_PIDFILE")" 2>/dev/null; fi
    restore_original_renderers
    rm -f "$PIDFILE" /tmp/custom_ss_shield.pid "$FIFO" "$STATEFILE"
    refresh_display
    return 0
}
# FBInk draws straight into /dev/fb0, underneath the X server, so X never learns
# that the pixels changed and repaints nothing. xscreen forces every window to
# redraw. It replaces xredraw, which was built dynamically against libX11.so.6
# and never executed on this device (see native/xscreen.c).
refresh_display() {
    DISPLAY=:0 "$BIN/xscreen" wake </dev/null >>"$LOG" 2>&1
}
show() {
    prepare_runtime
    FONT="$BASE/SmileySans-Oblique.ttf"
    # Must pass -t: without it FBInk falls back to its built-in 8x8 bitmap font,
    # which has no CJK glyphs, so every Chinese character is reported as
    # "not covered by this font" and nothing readable is drawn.
    # -t draws a single line, so multi-line messages are laid out here.
    # px must be 1.2x the intended size; see px_of in draw.sh.
    "$BIN/fbink_hf" -q -c -B WHITE
    Y=520
    OLD_IFS="$IFS"
    IFS='
'
    for LINE in $1; do
        [ -n "$LINE" ] || continue
        "$BIN/fbink_hf" -q -b -m -B WHITE -C BLACK \
            -t regular="$FONT",px=58,top="$Y",left=96,right=96,notrunc "$LINE"
        Y=$((Y + 96))
    done
    IFS="$OLD_IFS"
    "$BIN/fbink_hf" -q -s top=0,left=0,width=1072,height=1448 -W GC16 -f
    sleep 1
    refresh_display
}
case "${1:-browse}" in
    browse)
        # Browsing is a foreground action and must work whether or not the
        # sleep daemon happens to be running; it used to refuse to start
        # otherwise, which read as "there is no way to change the quote".
        prepare_runtime
        stop_reader
        "$BIN/kindlexiping-reader" "${KINDLE_TOUCH:-/dev/input/event1}" >>"$LOG" 2>&1 &
        echo $! > /tmp/kindlexiping-reader.pid
        ;;
    enable)
        prepare_runtime
        if abi_mismatch; then
            log "ABI mismatch: runtime binaries are hard-float but this device has no /lib/ld-linux-armhf.so.3"
            show "二进制架构不符
请重新安装软浮点版本"
            exit 1
        fi
        # Always restart instead of short-circuiting on "already running".
        # The daemon keeps its script in memory, so a no-op here meant every
        # fix to daemon.sh stayed dormant until the device rebooted -- which
        # is exactly why the white-screen fix appeared not to work.
        disable
        # Detach into its own session, don't just background it.
        #
        # A plain `&` leaves the daemon in the launching shell's process group,
        # and this device runs documents from a short-lived shell: when that
        # shell exits, the group is signalled. nohup only ignores SIGHUP, so it
        # does not help if the group receives SIGTERM. setsid leaves the group
        # entirely, which is what the daemon needs to outlive the click.
        if command -v setsid >/dev/null 2>&1; then
            setsid sh "$BASE/scripts/daemon.sh" >/dev/null 2>&1 &
        elif command -v nohup >/dev/null 2>&1; then
            nohup sh "$BASE/scripts/daemon.sh" >/dev/null 2>&1 &
        else
            sh "$BASE/scripts/daemon.sh" >/dev/null 2>&1 &
        fi
        sleep 3
        # Record the outcome in launcher.log. Without this the only evidence of a
        # failed start was a missing READY line in custom_ss.log, which looks the
        # same as "enable was never run at all".
        if is_running; then
            log "daemon started pid=$(cat "$PIDFILE")"
            show "每日名著锁屏
已启用"
        else
            log "daemon did NOT start"
            show "未能启用
请查看运行日志"
            exit 1
        fi
        # One more check after the message is drawn, to catch a daemon that
        # starts and then dies with its parent.
        sleep 2
        if is_running; then
            log "daemon still running after the message"
        else
            log "daemon DIED right after starting"
        fi
        ;;
    disable)
        disable
        show "已恢复原厂锁屏
重启不会改变此状态"
        ;;
    status)
        if is_running; then show "每日名著锁屏
运行中"; else show "每日名著锁屏
未启用"; fi
        ;;
esac
