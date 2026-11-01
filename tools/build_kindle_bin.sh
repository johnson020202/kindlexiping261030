#!/bin/sh
# Build the Kindle runtime binaries and fail loudly if any of them ends up
# hard-float or otherwise unable to run on a soft-float Kindle.
#
# Why this exists: the 0.1.0 release shipped armhf binaries. A soft-float
# device has no /lib/ld-linux-armhf.so.3, so every one of them failed to exec
# with no visible error, and the project looked "installed but inert".
#
# Target: Kindle PW3 (7th gen, i.MX6, armv7l), firmware 5.16.2.1.1.
#   - float ABI must be SOFT (EF_ARM_ABI_FLOAT_SOFT, e_flags bit 0x200)
#   - every shipped helper is static musl: no libc or library-version risk
#
# The 0.1.x line shipped two dynamically linked X11 helpers (xredraw and
# screensaver_shield). Neither ever ran on the device, and no log line recorded
# why: the shield prints "starting" as its first statement and that line never
# reached custom_ss.log, so it died before main(). xscreen replaces both with a
# static binary that speaks the X11 wire protocol directly.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ZIG="${ZIG:-zig}"
OUT="$ROOT/kindle/bin"

command -v "$ZIG" >/dev/null 2>&1 || {
    echo "error: zig not found. Install it or set ZIG=/path/to/zig" >&2
    echo "       (zig cross-compiles arm-linux-musleabi out of the box)" >&2
    exit 1
}

mkdir -p "$OUT"

echo "==> daily-index (static musl)"
"$ZIG" cc -target arm-linux-musleabi -mcpu=cortex_a9 -Os -s -static \
    -o "$OUT/daily-index" "$ROOT/native/daily.c" 2>/dev/null

echo "==> kindlexiping-reader (static musl)"
"$ZIG" cc -target arm-linux-musleabi -mcpu=cortex_a9 -Os -s -static \
    -o "$OUT/kindlexiping-reader" "$ROOT/native/reader.c" 2>/dev/null

# xscreen speaks the X11 wire protocol over the local socket instead of
# linking libX11, so it is an ordinary static musl binary.
#
# The previous design shipped xredraw and screensaver_shield, both built
# dynamically against the device's libX11.so.6. Neither ever executed on the
# target PW3: the shield prints "starting" as its first statement and
# custom_ss.log never contained that line, so it died in the dynamic loader.
# With nothing to repaint the UI, wake left FBInk's poster on the panel and
# only the status-bar clock strip ever changed.
echo "==> xscreen (static musl)"
"$ZIG" cc -target arm-linux-musleabi -mcpu=cortex_a9 -Os -s -static \
    -o "$OUT/xscreen" "$ROOT/native/xscreen.c" 2>/dev/null

# Retired: superseded by xscreen and known not to run on this device.
rm -f "$OUT/xredraw" "$OUT/screensaver_shield"

# fbink is not built here: FBInk's build needs a full koxtoolchain sysroot.
# Copy the copy the jailbreak itself installs at /mnt/us/libkh/bin/fbink, which
# is already running on the device and therefore known to match its ABI.
echo "==> fbink_hf (vendored from the jailbreak payload)"
FBINK_SRC="${FBINK_SRC:-}"
if [ -z "$FBINK_SRC" ]; then
    for candidate in \
        "$ROOT/../kindle-jailbreak/downloads/payload/kindlepw2/bin/fbink" \
        "${KINDLE_MOUNT:-/Volumes/Kindle}/libkh/bin/fbink"
    do
        [ -f "$candidate" ] && { FBINK_SRC="$candidate"; break; }
    done
fi
[ -n "$FBINK_SRC" ] || {
    echo "error: soft-float fbink not found." >&2
    echo "       Provide FBINK_SRC=/path/to/kindlepw2/fbink" >&2
    exit 1
}
cp "$FBINK_SRC" "$OUT/fbink_hf"

chmod 755 "$OUT"/*
rm -f "$OUT/screensaver_draw"   # superseded: draw.sh renders via fbink directly

echo
echo "==> verifying float ABI"
python3 - "$OUT" <<'PY'
import struct, sys, os
out = sys.argv[1]
bad = []
for name in sorted(os.listdir(out)):
    path = os.path.join(out, name)
    if not os.path.isfile(path):
        continue
    data = open(path, 'rb').read()
    if data[:4] != b'\x7fELF':
        print(f'  {name:24s} NOT ELF')
        bad.append(name)
        continue
    if data[4] != 1:
        print(f'  {name:24s} not 32-bit')
        bad.append(name)
        continue
    flags = struct.unpack('<I', data[36:40])[0]
    machine = struct.unpack('<H', data[18:20])[0]
    if machine != 0x28:
        print(f'  {name:24s} machine={machine:#x} (expected ARM 0x28)')
        bad.append(name)
        continue
    if flags & 0x400:
        print(f'  {name:24s} HARD-FLOAT (e_flags={flags:#x}) - will not run')
        bad.append(name)
        continue
    if not flags & 0x200:
        print(f'  {name:24s} float ABI unset (e_flags={flags:#x})')
        bad.append(name)
        continue
    print(f'  {name:24s} OK  float=soft  e_flags={flags:#x}')
if bad:
    print()
    print('FAILED: ' + ', '.join(bad))
    sys.exit(1)
PY

echo
echo "Built into $OUT"
ls -l "$OUT"
