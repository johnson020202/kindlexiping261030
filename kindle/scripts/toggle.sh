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
. "$BASE/blanket_renderers.sh"
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
    DISPLAY=:0 xrefresh >>"$LOG" 2>&1
    return 0
}
show() {
    prepare_runtime
    "$BIN/fbink_hf" -q -c -m -M -B WHITE -C BLACK -S 5 "$1"
    sleep 2
    DISPLAY=:0 xrefresh
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
        if is_running; then show "每日名著锁屏
已经启用"; exit 0; fi
        disable
        sh "$BASE/daemon.sh" >/dev/null 2>&1 &
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
