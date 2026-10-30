#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VOLUME="${KINDLE_VOLUME:-/Volumes/Kindle}"
BASE="$VOLUME/extensions/kindlexiping261030"
STAMP="$(date '+%Y%m%d-%H%M%S')"

[ -d "$VOLUME" ] || { echo "Kindle not mounted at $VOLUME" >&2; exit 1; }
[ -f "$ROOT/kindle/data.tsv" ] || { echo "Run 'python3 tools/build_kindle_data.py' first" >&2; exit 1; }

mkdir -p "$ROOT/backups" "$VOLUME/extensions" "$VOLUME/documents" "$BASE"/{bin,scripts,state}
if [ -f "$VOLUME/RUNME.sh" ] && [ ! -f "$VOLUME/RUNME.before-kindlexiping.sh" ]; then
    cp "$VOLUME/RUNME.sh" "$VOLUME/RUNME.before-kindlexiping.sh"
    cp "$VOLUME/RUNME.sh" "$ROOT/backups/RUNME-before-kindlexiping-$STAMP.sh"
fi
cp -R "$ROOT/kindle/bin/." "$BASE/bin/"
cp "$ROOT"/kindle/scripts/*.sh "$BASE/scripts/"
cp "$ROOT/assets/fonts/SmileySans-Oblique.ttf" "$BASE/"
cp "$ROOT/assets/fonts/OFL.txt" "$BASE/SmileySans-OFL.txt"
cp "$ROOT/content/books.json" "$BASE/books.json"
cp "$ROOT/kindle/data.tsv" "$BASE/data.tsv"
cp "$ROOT/kindle/LICENSE" "$ROOT/kindle/UPSTREAM-LICENSE" "$ROOT/kindle/THIRD_PARTY_NOTICES.md" "$ROOT/kindle/CREDITS" "$BASE/"
chmod -R u+rwX "$BASE"
printf '5000\n' > "$BASE/state/count"

for pair in "Xiping Enable.sh|栖息 · 开启每日锁屏|enable" "Xiping Browse.sh|栖息 · 翻阅|browse" "Xiping Disable.sh|栖息 · 关闭并恢复|disable"; do
    file="${pair%%|*}"; rest="${pair#*|}"; label="${rest%%|*}"; action="${rest#*|}"
    printf '#!/bin/sh\n# Name: %s\n# DontUseFBInk\nexec sh /mnt/us/extensions/kindlexiping261030/scripts/toggle.sh %s\n' "$label" "$action" > "$VOLUME/documents/$file"
    chmod 755 "$VOLUME/documents/$file"
done

cat > "$VOLUME/RUNME.sh" <<'EOF'
#!/bin/sh
exec >> /mnt/us/extensions/kindlexiping261030/install.log 2>&1
set -x
date
uname -a
BASE=/mnt/us/extensions/kindlexiping261030
mkdir -p /var/tmp/kindlexiping-bin
cp "$BASE"/bin/* /var/tmp/kindlexiping-bin/
chmod 755 /var/tmp/kindlexiping-bin/*
sh "$BASE/scripts/toggle.sh" enable
date
sync
EOF
chmod 755 "$VOLUME/RUNME.sh"
sync
echo "Files installed to $BASE"
echo "Existing RUNME backed up as RUNME.before-kindlexiping.sh"
echo "Safely eject, then type ';log runme' in the Kindle search box once."
echo "Device lock-screen verification is still pending until that action is performed."
