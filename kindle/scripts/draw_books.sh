#!/bin/sh
# Draw the book index: one page of book titles, plus paging controls.
#
# Layout is shared with kindlexiping-reader, which hit-tests the same
# rectangles. Keep ROW_TOP/ROW_H/PER_PAGE in sync with the constants there.
BASE="/mnt/us/extensions/kindlexiping261030"
BIN="/var/tmp/kindlexiping-bin"
FONT="$BASE/SmileySans-Oblique.ttf"
FB="$BIN/fbink_hf"
BOOKS="$BASE/books.tsv"

PAGE="${1:-0}"
case "$PAGE" in ''|*[!0-9]*) PAGE=0 ;; esac

PER_PAGE=8
ROW_TOP=220
ROW_H=120

trace() { echo "TRACE(books): $*" >&2; }
[ -f "$BOOKS" ] || { trace "missing $BOOKS"; exit 1; }
[ -x "$FB" ] || { trace "missing $FB"; exit 1; }

TOTAL=$(wc -l < "$BOOKS")
PAGES=$(( (TOTAL + PER_PAGE - 1) / PER_PAGE ))
[ "$PAGE" -ge "$PAGES" ] && PAGE=$((PAGES - 1))
[ "$PAGE" -lt 0 ] && PAGE=0

px_of() { echo $(( ($1 * 12 + 5) / 10 )); }
STEP=0
fb() {
    STEP=$((STEP + 1))
    "$FB" "$@"
    rc=$?
    [ "$rc" -eq 0 ] || trace "fbink step $STEP FAILED rc=$rc"
    return "$rc"
}

fb -q -c -B WHITE
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 26)",top=93,left=96,right=0,notrunc "书目 · 共 $TOTAL 本"
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 26)",top=93,left=700,right=0,notrunc "第 $((PAGE + 1)) / $PAGES 页"

I=0
while [ "$I" -lt "$PER_PAGE" ]; do
    LINE_NO=$(( PAGE * PER_PAGE + I + 1 ))
    [ "$LINE_NO" -le "$TOTAL" ] || break
    ROW="$(sed -n "${LINE_NO}p" "$BOOKS")"
    [ -n "$ROW" ] || break
    OLD_IFS="$IFS"; IFS='	'; set -- $ROW; IFS="$OLD_IFS"
    TITLE="$2"
    AUTHOR="$3"
    Y=$(( ROW_TOP + I * ROW_H ))
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 30)",top="$Y",left=110,right=0,notrunc "$((I + 1)). $TITLE"
    fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 20)",top=$((Y + 56)),left=150,right=0,notrunc "$AUTHOR"
    I=$((I + 1))
done

# Three zones at the bottom: prev page / next page / back, split at 357 and 715.
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 25)",top=1330,left=90,right=0,notrunc "上一页"
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 25)",top=1330,left=460,right=0,notrunc "下一页"
fb -q -b -B WHITE -C BLACK -t regular="$FONT",px="$(px_of 25)",top=1330,left=820,right=0,notrunc "返回"

fb -q -s top=0,left=0,width=1072,height=1448 -W GC16 -f
trace "done page=$PAGE steps=$STEP"
