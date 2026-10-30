#!/bin/sh
# Draw one quote directly to the Kindle framebuffer. No PNG collection needed.
BASE="/mnt/us/extensions/kindlexiping261030"
BIN="/var/tmp/kindlexiping-bin"
FONT="$BASE/SmileySans-Oblique.ttf"
FB="$BIN/fbink_hf"
INDEX="${1:-0}"
BROWSE="${2:-}"
DATA="$BASE/data.tsv"
[ -f "$DATA" ] || exit 1
ROW="$(awk -F '\t' -v n="$((INDEX + 1))" 'NR == n { print; exit }' "$DATA")"
[ -n "$ROW" ] || exit 1
OLD_IFS="$IFS"
IFS='	'
set -- $ROW
IFS="$OLD_IFS"
ID="$1"; TITLE="$2"; AUTHOR="$3"; SIZE="$4"; BODY="$5"
BODY="$(printf '%s' "$BODY" | tr '|' '\n')"
"$FB" -q -c -B WHITE
"$FB" -q -b -o -B WHITE -C BLACK -t regular="$FONT",px=23,top=93,left=96,right=96,notrunc "一百部经典 · 每日一段"
Y=280
set -f
OLD_IFS="$IFS"; IFS='
'
for LINE in $BODY; do
    "$FB" -q -b -o -B WHITE -C BLACK -t regular="$FONT",px="$SIZE",top="$Y",left=96,right=96,notrunc "$LINE"
    Y=$((Y + (SIZE * 185 + 50) / 100))
done
IFS="$OLD_IFS"
set +f
"$FB" -q -b -o -B WHITE -C BLACK -m -t regular="$FONT",px=43,top=1218,bottom=0,left=500,right=96,notrunc "《$TITLE》"
"$FB" -q -b -o -B WHITE -C BLACK -m -t regular="$FONT",px=28,top=1295,bottom=0,left=500,right=96,notrunc "$AUTHOR"
"$FB" -q -b -o -B WHITE -C BLACK -m -t regular="$FONT",px=26,top=1218,bottom=0,left=0,right=700,notrunc "$(date '+%Y 年 %m 月 %d 日')"
"$FB" -q -b -o -B WHITE -C BLACK -m -t regular="$FONT",px=26,top=1275,bottom=0,left=0,right=700,notrunc "$(date '+%H:%M')"
if [ "$BROWSE" = "browse" ]; then
    "$FB" -q -b -o -B WHITE -C BLACK -m -t regular="$FONT",px=28,top=-132,bottom=12,left=0,right=0,notrunc "上一句          返回阅读          下一句"
fi
"$FB" -q -s top=0,left=0,width=1072,height=1448 -W GC16 -f
