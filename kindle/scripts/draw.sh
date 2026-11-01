#!/bin/sh
# Draw one quote directly to the Kindle framebuffer. No PNG collection needed.
#
# Every step is announced BEFORE it runs ("TRACE: ..."). A crash then leaves the
# last TRACE line as the exact culprit, which matters because each device test
# costs a user a USB unplug/replug cycle.
#
# Deliberate choices, all learned on this device:
#  - sed -n Np instead of awk: awk segfaults on ANY input here (rc=139).
#  - date is only called with ASCII format strings; CJK in the format string is
#    a plausible crash source on this busybox.
#  - Body lines are drawn with right=0, not right=96. Each stored line is
#    pre-wrapped to fit 850px, but FBInk measures glyph advances slightly wider
#    than PIL. With a 880px box a near-limit line gets wrapped a second time and
#    the remainder lands as a stray glyph (the lone 山/牛 seen on device).
#    Handing FBInk a 976px box leaves ~126px of slack so it never re-wraps.
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

# ASCII-only date calls, assembled in the shell.
D_YEAR="$(date '+%Y')"
D_MONTH="$(date '+%m')"
D_DAY="$(date '+%d')"
D_TIME="$(date '+%H:%M')"
DATE_LINE="$D_YEAR 年 $D_MONTH 月 $D_DAY 日"

# FBInk's px= is NOT a font size: it divides by (ascent-descent)=1200 while the
# em box is 1000, so a glyph at px=N has em=0.833N. Request px = size * 1.2.
# Keep in sync with FBINK_PX_PER_PIL_SIZE in tools/render.py.
px_of() { echo $(( ($1 * 12 + 5) / 10 )); }

SIZE_PX="$(px_of "$SIZE")"

# The four bottom buttons and their hit zones share one geometry: the screen is
# split into four equal columns and each label is drawn inside its own column.
# Previously the labels were one centred string while hit testing used thirds,
# so tapping a visible label could trigger a neighbouring action (worst case
# "exit", which released the touch grab and let taps fall through to the
# Amazon UI underneath).
ZONE_W=268
BTN_Y=1330
BTN_PX="$(px_of 25)"
BTN_IDX="${ID##*-}"

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
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 23)",top=93,left=96,right=0,notrunc "一百部经典 · 每日一段"

Y=280
set -f
OLD_IFS="$IFS"; IFS='
'
for LINE in $BODY; do
    [ -n "$LINE" ] || continue
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$SIZE_PX",top="$Y",left=96,right=0,notrunc "$LINE"
    Y=$((Y + (SIZE * 185 + 50) / 100))
done
IFS="$OLD_IFS"
set +f

# Metadata sits above the button row so the two never collide.
fb -q -b -B WHITE -C BLACK -m -t regular="$FONT",px="$(px_of 40)",top=1150,bottom=0,left=500,right=96,notrunc "《$TITLE》"
fb -q -b -B WHITE -C BLACK -m -t regular="$FONT",px="$(px_of 26)",top=1222,bottom=0,left=500,right=96,notrunc "$AUTHOR"
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 24)",top=1150,left=96,right=0,notrunc "$DATE_LINE"
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 24)",top=1216,left=96,right=0,notrunc "$D_TIME"

if [ "$BROWSE" = "browse" ]; then
    # One label per hit zone, centred inside it. Left values come from the same
    # 4x268 split the reader hit-tests, so a visible label can never fire a
    # neighbouring action. A CJK glyph advances one em = px/1.2 = 25px here,
    # so a 3-char label is 75px wide and a 2-char label 50px.
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$BTN_PX",top="$BTN_Y",left=96,right=0,notrunc "上一句"
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$BTN_PX",top="$BTN_Y",left=377,right=0,notrunc "书目"
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$BTN_PX",top="$BTN_Y",left=632,right=0,notrunc "下一句"
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$BTN_PX",top="$BTN_Y",left=913,right=0,notrunc "退出"
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 20)",top=1396,left=96,right=0,notrunc "本篇第 $BTN_IDX 句"
fi

trace "final refresh"
fb -q -s top=0,left=0,width=1072,height=1448 -W GC16 -f
trace "done, steps=$STEP"
