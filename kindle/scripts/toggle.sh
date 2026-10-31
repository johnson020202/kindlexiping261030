#!/bin/sh
# Name: 栖息 · 名著锁屏
# DontUseFBInk
BASE="/mnt/us/extensions/kindlexiping261030"
BIN="/var/tmp/kindlexiping-bin"
SHIELD_PIDFILE="/tmp/custom_ss_shield.pid"
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
    if [ -f /tmp/kindlexiping-reader-shield.pid ]; then
        kill "$(cat /tmp/kindlexiping-reader-shield.pid)" 2>/dev/null
        rm -f /tmp/kindlexiping-reader-shield.pid
    fi
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
# xrefresh is an X11 client and is NOT installed on this device, so calling it
# unguarded just writes "xrefresh: not found" to the log. FBInk already wrote
# the pixels to /dev/fb0; only nudge the X server when a client is present.
refresh_display() {
    if command -v xrefresh >/dev/null 2>&1; then
        DISPLAY=:0 xrefresh >>"$LOG" 2>&1
    fi
}
show() {
    prepare_runtime
    FONT="$BASE/SmileySans-Oblique.ttf"
    # Must pass -t: without it FBInk falls back to its built-in 8x8 bitmap font,
    # which has no CJK glyphs, so every Chinese character is reported as
    # "not covered by this font" and nothing readable is drawn.
    # -t draws a single line, so multi-line messages are laid out here.
    "$BIN/fbink_hf" -q -c -B WHITE
    Y=520
    OLD_IFS="$IFS"
    IFS='
'
    for LINE in $1; do
        [ -n "$LINE" ] || continue
        "$BIN/fbink_hf" -q -b -m -B WHITE -C BLACK \
            -t regular="$FONT",px=48,top="$Y",left=96,right=96,notrunc "$LINE"
        Y=$((Y + 96))
    done
    IFS="$OLD_IFS"
    "$BIN/fbink_hf" -q -s top=0,left=0,width=1072,height=1448 -W GC16 -f
    sleep 1
    refresh_display
}
case "${1:-browse}" in
    browse)
        if is_running; then
            stop_reader
            prepare_runtime
            DISPLAY=:0 "$BIN/screensaver_shield" >>"$LOG" 2>&1 &
            echo $! > /tmp/kindlexiping-reader-shield.pid
            "$BIN/kindlexiping-reader" "${KINDLE_TOUCH:-/dev/input/event1}" >>"$LOG" 2>&1 &
            echo $! > /tmp/kindlexiping-reader.pid
        else
            show "栖息已关闭
再次打开可启动锁屏"
        fi
        ;;
    enable)
        prepare_runtime
        if abi_mismatch; then
            log "ABI mismatch: runtime binaries are hard-float but this device has no /lib/ld-linux-armhf.so.3"
            show "二进制架构不符
请重新安装软浮点版本"
            exit 1
        fi
        if is_running; then show "每日名著锁屏
已经启用"; exit 0; fi
        disable
        sh "$BASE/scripts/daemon.sh" >/dev/null 2>&1 &
        sleep 2
        if is_running; then show "每日名著锁屏
已启用"; else show "未能启用
请查看运行日志"; exit 1; fi
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
