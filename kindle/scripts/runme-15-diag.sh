#!/bin/sh
# Pinpoint the draw.sh segfault in ONE device run.
#
# Each probe runs in a subshell, so a crashing child is recorded (rc=139) and
# the script keeps going. Without this the first crash kills the whole run and
# each attempt costs the user a USB unplug/replug cycle.
#
# What is already known from earlier runs:
#   - fbink -t with CJK worked in toggle.sh's show() (no crash, no missing glyphs)
#   - draw.sh crashes before its first fbink call returns
# So the suspects are the data-extraction steps, not FBInk itself.
BASE=/mnt/us/extensions/kindlexiping261030
BIN=/var/tmp/kindlexiping-bin
FB="$BIN/fbink_hf"
FONT="$BASE/SmileySans-Oblique.ttf"
DATA="$BASE/data.tsv"
LOG="$BASE/diag.log"
ERR="$BASE/diag.err"

exec >>"$LOG" 2>&1
echo "===== diag $(date '+%Y-%m-%d %H:%M:%S') ====="

probe() {
    desc="$1"; shift
    ( "$@" ) >/dev/null 2>"$ERR"
    rc=$?
    echo "$desc => rc=$rc :: $(head -1 "$ERR" 2>/dev/null)"
}

echo "--- environment ---"
echo "cpujit: $(uname -m)"
echo "fbink:  $(wc -c < "$FB" 2>/dev/null) bytes"
echo "font:   $(wc -c < "$FONT" 2>/dev/null) bytes"
echo "data:   $(wc -c < "$DATA" 2>/dev/null) bytes"

echo "--- fbink capability probes ---"
probe "clear"              "$FB" -q -c -B WHITE
probe "ascii-no-ttf"       "$FB" -q -b "Hello"
probe "ascii-ttf"          "$FB" -q -b -t regular="$FONT",px=40,top=100 "Hello"
probe "cjk-ttf"            "$FB" -q -b -t regular="$FONT",px=40,top=200 "每日一句"
probe "cjk-ttf-notrunc"    "$FB" -q -b -t regular="$FONT",px=40,top=300,left=96,right=96,notrunc "每日一句"
probe "cjk-ttf-centered"   "$FB" -q -b -m -t regular="$FONT",px=40,top=400 "每日一句"
probe "title-line"         "$FB" -q -b -B WHITE -C BLACK -t regular="$FONT",px=23,top=93,left=96,right=96,notrunc "一百部经典 · 每日一段"
probe "refresh"            "$FB" -q -s top=0,left=0,width=1072,height=1448 -W GC16 -f

echo "--- extraction probes (the actual suspects) ---"
probe "awk-simple"         awk 'BEGIN{print "ok"}'
probe "awk-row"            awk -F '\t' -v n=2622 'NR == n { print length($0); exit }' "$DATA"
probe "sed-row"            sed -n '2622p' "$DATA"
probe "tr-split"           sh -c "printf 'a|b|c' | tr '|' '\n'"

echo "--- manual extraction with sizes ---"
ROW="$(sed -n '2622p' "$DATA")"
echo "sed row length: ${#ROW}"
if [ -n "$ROW" ]; then
    OLD_IFS="$IFS"
    IFS='	'
    set -- $ROW
    IFS="$OLD_IFS"
    echo "field count: $#"
    echo "field4(size): [$4]"
    echo "field2(title): [$2]"
    BODY="$5"
    echo "body length: ${#BODY}"
    probe "tr-on-body" sh -c "printf '%s' \"\$1\" | tr '|' '\n'" _ "$BODY"
fi

echo "--- last drawn index ---"
cat "$BASE/state/daily-index" 2>/dev/null
echo
echo "===== diag end ====="
