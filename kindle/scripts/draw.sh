#!/bin/sh
# Draw one quote directly to the Kindle framebuffer. No PNG collection needed.
#
# Every step is announced BEFORE it runs ("TRACE: ..."). A crash then leaves the
# last TRACE line as the exact culprit, which matters because each device test
# costs the user a USB unplug/replug cycle.
#
# Deliberate choices, both to avoid a segfault seen on this device:
#  - sed -n Np instead of awk: awk was the only non-trivial external command on
#    the path that crashed, and it crashed before any FBInk call.
#  - date is only ever called with ASCII format strings. An earlier version used
#    date '+%Y 年 %m 月 %d 日'; on this busybox a multibyte format string is a
#    plausible crash source, and show() -- which never calls date and never
#    crashed -- is the control case.
BASE="/mnt/us/extensions/kindlexiping261030"
BIN="/var/tmp/kindlexiping-bin"
FONT="$BASE/SmileySans-Oblique.ttf"
FB="$BIN/fbink_hf"
INDEX="${1:-0}"
BROWSE="${2:-}"
DATA="$BASE/data.tsv"

case "$INDEX" in
    ''|*[!0-9]*) INDEX=0 ;;
esac

trace() { echo "TRACE(draw): $*" >&2; }

trace "start index=$INDEX browse=$BROWSE"
[ -f "$DATA" ] || { trace "missing $DATA"; exit 1; }
[ -x "$FB" ]   || { trace "missing or not executable $FB"; exit 1; }
[ -f "$FONT" ] || { trace "missing $FONT"; exit 1; }

LINE_NO=$((INDEX + 1))
trace "extract line $LINE_NO"
ROW="$(sed -n "${LINE_NO}p" "$DATA")"
if [ -z "$ROW" ]; then trace "line $LINE_NO empty"; exit 1; fi
trace "row length ${#ROW}"

OLD_IFS="$IFS"
IFS='	'
set -- $ROW
IFS="$OLD_IFS"
ID="$1"; TITLE="$2"; AUTHOR="$3"; SIZE="$4"; BODY="$5"
trace "size=$SIZE title=$TITLE"
[ -n "$SIZE" ] || { trace "empty SIZE (line $LINE_NO)"; exit 1; }

trace "split body"
BODY="$(printf '%s' "$BODY" | tr '|' '\n')"
trace "body ready"

# Build the date line from ASCII-only date calls, then assemble in the shell.
D_YEAR="$(date '+%Y')"
D_MONTH="$(date '+%m')"
D_DAY="$(date '+%d')"
D_TIME="$(date '+%H:%M')"
DATE_LINE="$D_YEAR 年 $D_MONTH 月 $D_DAY 日"
trace "date line built"

STEP=0
fb() {
    STEP=$((STEP + 1))
    trace "fbink step $STEP"
    "$FB" "$@"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        trace "fbink step $STEP FAILED rc=$rc"
    fi
    return "$rc"
}

fb -q -c -B WHITE
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px=23,top=93,left=96,right=96,notrunc "一百部经典 · 每日一段"

Y=280
set -f
OLD_IFS="$IFS"; IFS='
'
for LINE in $BODY; do
    [ -n "$LINE" ] || continue
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$SIZE",top="$Y",left=96,right=96,notrunc "$LINE"
    Y=$((Y + (SIZE * 185 + 50) / 100))
done
IFS="$OLD_IFS"
set +f

fb -q -b -B WHITE -C BLACK -m -t regular="$FONT",px=43,top=1218,bottom=0,left=500,right=96,notrunc "《$TITLE》"
fb -q -b -B WHITE -C BLACK -m -t regular="$FONT",px=28,top=1295,bottom=0,left=500,right=96,notrunc "$AUTHOR"
fb -q -b -B WHITE -C BLACK -m -t regular="$FONT",px=26,top=1218,bottom=0,left=0,right=700,notrunc "$DATE_LINE"
fb -q -b -B WHITE -C BLACK -m -t regular="$FONT",px=26,top=1275,bottom=0,left=0,right=700,notrunc "$D_TIME"

if [ "$BROWSE" = "browse" ]; then
    fb -q -b -B WHITE -C BLACK -m -t regular="$FONT",px=28,top=-132,bottom=12,left=0,right=0,notrunc "上一句          返回阅读          下一句"
fi

trace "final refresh"
fb -q -s top=0,left=0,width=1072,height=1448 -W GC16 -f
trace "done, steps=$STEP"
