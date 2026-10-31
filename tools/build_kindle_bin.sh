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
#   - daily-index / kindlexiping-reader are static musl: no libc version risk
#   - screensaver_shield links the device's libX11.so.6 and libpthread.so.0
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ZIG="${ZIG:-zig}"
OUT="$ROOT/kindle/bin"
UPSTREAM="$ROOT/source-cache/upstream-shield"

command -v "$ZIG" >/dev/null 2>&1 || {
    echo "error: zig not found. Install it or set ZIG=/path/to/zig" >&2
    echo "       (zig cross-compiles arm-linux-musleabi out of the box)" >&2
    exit 1
}
[ -f "$UPSTREAM/screensaver_shield.c" ] || {
    echo "error: missing $UPSTREAM/screensaver_shield.c" >&2
    echo "       fetch from chengandre/kindle-custom-screensaver src/shield/" >&2
    exit 1
}

mkdir -p "$OUT"

echo "==> daily-index (static musl)"
"$ZIG" cc -target arm-linux-musleabi -mcpu=cortex_a9 -Os -s -static \
    -o "$OUT/daily-index" "$ROOT/native/daily.c" 2>/dev/null

echo "==> kindlexiping-reader (static musl)"
"$ZIG" cc -target arm-linux-musleabi -mcpu=cortex_a9 -Os -s -static \
    -o "$OUT/kindlexiping-reader" "$ROOT/native/reader.c" 2>/dev/null

# screensaver_shield talks X11, so it cannot be static. Build it against the
# device's glibc 2.20 and link the real soname. A stub archive supplies the
# symbols at link time only; the device provides the implementation.
echo "==> screensaver_shield (dynamic, glibc 2.20, libX11.so.6)"
X11INC="${X11INC:-/opt/homebrew/include}"
X11STUB="$(mktemp -d)"
trap 'rm -rf "$X11STUB"' EXIT
[ -f "$X11INC/X11/Xlib.h" ] || {
    echo "error: X11 headers not found at $X11INC (set X11INC=...)" >&2
    exit 1
}
: > "$X11STUB/stub.c"
for sym in XCloseDisplay XConfigureWindow XCreateWindow XDestroyWindow \
           XFetchName XFlush XFree XGetErrorText XGetWindowAttributes \
           XMapRaised XNextEvent XOpenDisplay XPending XQueryTree XSelectInput \
           XSetErrorHandler XStoreName XSync XUnmapWindow; do
    echo "void *$sym(void){return 0;}" >> "$X11STUB/stub.c"
done
"$ZIG" cc -target arm-linux-gnueabi -mcpu=cortex_a9 -shared -fPIC \
    -Wl,-soname,libX11.so.6 -o "$X11STUB/libX11.so.6" "$X11STUB/stub.c" 2>/dev/null
cp "$X11STUB/libX11.so.6" "$X11STUB/libX11.so"
"$ZIG" cc -target arm-linux-gnueabi.2.20 -mcpu=cortex_a9 -Os -s \
    -I"$X11INC" -o "$OUT/screensaver_shield" "$UPSTREAM/screensaver_shield.c" \
    -L"$X11STUB" -lX11 2>/dev/null

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
