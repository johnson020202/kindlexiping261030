#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VOLUME="${KINDLE_VOLUME:-/Volumes/Kindle}"
BASE="$VOLUME/extensions/kindlexiping261030"
STAMP="$(date '+%Y%m%d-%H%M%S')"

[ -d "$VOLUME" ] || { echo "Kindle not mounted at $VOLUME" >&2; exit 1; }
[ -f "$ROOT/kindle/data.tsv" ] || { echo "Run 'python3 tools/build_kindle_data.py' first" >&2; exit 1; }

mkdir -p "$ROOT/backups" "$VOLUME/extensions" "$VOLUME/documents" "$BASE"/{bin,scripts,state} "$BASE/runme.d"
if [ -f "$VOLUME/RUNME.sh" ] && [ ! -f "$VOLUME/RUNME.before-kindlexiping.sh" ]; then
    cp "$VOLUME/RUNME.sh" "$VOLUME/RUNME.before-kindlexiping.sh"
    cp "$VOLUME/RUNME.sh" "$ROOT/backups/RUNME-before-kindlexiping-$STAMP.sh"
fi
cp -R "$ROOT/kindle/bin/." "$BASE/bin/"
rm -f "$BASE/bin/screensaver_draw"
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

cat > "$BASE/runme.d/10-enable.sh" <<'EOF'
#!/bin/sh
# Invoked by the RUNME dispatcher; runs with root.
BASE=/mnt/us/extensions/kindlexiping261030
RUNTIME=/var/tmp/kindlexiping-bin
LOG="$BASE/install.log"
exec >> "$LOG" 2>&1
set -x
echo "===== run $(date '+%Y-%m-%d %H:%M:%S') ====="
date
uname -a
[ -f /lib/ld-linux-armhf.so.3 ] && echo "device: hard-float (armhf)" || echo "device: soft-float (armel)"
mkdir -p "$RUNTIME"
cp "$BASE"/bin/* "$RUNTIME"/
chmod 755 "$RUNTIME"/*
if ! sh "$BASE/scripts/toggle.sh" enable; then
    echo "FAILED: toggle.sh enable returned non-zero"
fi
date
sync
EOF
chmod 755 "$BASE/runme.d/10-enable.sh"

# RUNME.sh is one shared slot that other Kindle projects also write to. Rather
# than overwrite it, install a dispatcher that runs runme.d/*.sh and then, only
# if asked, chains to a preserved RUNME.
#
# Chaining is OFF by default: the RUNME.sh found on a device is often a USB
# networking bootstrap that calls useUsbForNetwork, which drops the mass-storage
# volume the installer is writing through. Set KINDLE_RUNME_CHAIN=<file> to
# opt in with a specific, known-safe script.
CHAIN_FILE="${KINDLE_RUNME_CHAIN:-}"
cat > "$VOLUME/RUNME.sh" <<EOF
#!/bin/sh
# Kindle RUNME dispatcher (installed by kindlexiping261030).
# Runs each *.sh in runme.d/ in name order, each logging separately.
US=/mnt/us
BASE="\$US/extensions/kindlexiping261030"
mkdir -p "\$BASE/runme.d"
if [ -d "\$BASE/runme.d" ]; then
    for script in "\$BASE"/runme.d/*.sh; do
        [ -f "\$script" ] || continue
        sh "\$script" </dev/null
    done
fi
if [ -f "\$BASE/runme.d/.chain" ]; then
    CHAIN=\$(cat "\$BASE/runme.d/.chain")
    if [ -n "\$CHAIN" ] && [ -f "\$CHAIN" ]; then
        sh "\$CHAIN" </dev/null
    fi
fi
exit 0
EOF
chmod 755 "$VOLUME/RUNME.sh"
if [ -n "$CHAIN_FILE" ]; then
    printf '%s\n' "$CHAIN_FILE" > "$BASE/runme.d/.chain"
    echo "RUNME will chain to: $CHAIN_FILE"
elif [ -f "$BASE/runme.d/.chain" ]; then
    rm -f "$BASE/runme.d/.chain"
fi
sync
echo "Files installed to $BASE"
echo "Existing RUNME backed up as RUNME.before-kindlexiping.sh"
echo "Safely eject, then type ';log runme' in the Kindle search box once."
echo "Device lock-screen verification is still pending until that action is performed."
