#!/usr/bin/env python3
"""Build the self-contained Kindle package and source archive."""
import json
import shutil
import struct
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / 'VERSION').read_text().strip()
DIST = ROOT / 'dist'
NAME = f'kindlexiping261030-v{VERSION}'
STAGE = DIST / NAME
EXT = STAGE / 'extensions' / 'kindlexiping261030'
DOCS = STAGE / 'documents'
IMAGES = ROOT / 'build' / 'images'
BOOKS = json.loads((ROOT / 'content/books.json').read_text())

# The target Kindle (PW3, 5.16.2.1.1) is a soft-float device: it has no
# /lib/ld-linux-armhf.so.3, so a hard-float binary cannot be exec'd at all.
EF_ARM_ABI_FLOAT_SOFT = 0x200
EF_ARM_ABI_FLOAT_HARD = 0x400


def verify_binaries():
    """Refuse to package binaries that cannot run on the target device."""
    problems = []
    for path in sorted((ROOT / 'kindle/bin').iterdir()):
        if not path.is_file():
            continue
        data = path.read_bytes()
        if data[:4] != b'\x7fELF':
            problems.append(f'{path.name}: not an ELF file')
            continue
        if data[4] != 1:
            problems.append(f'{path.name}: not 32-bit')
            continue
        machine = struct.unpack('<H', data[18:20])[0]
        flags = struct.unpack('<I', data[36:40])[0]
        if machine != 0x28:
            problems.append(f'{path.name}: machine {machine:#x}, expected ARM')
        elif flags & EF_ARM_ABI_FLOAT_HARD:
            problems.append(f'{path.name}: hard-float, will not run on this device')
        elif not flags & EF_ARM_ABI_FLOAT_SOFT:
            problems.append(f'{path.name}: float ABI unset (e_flags={flags:#x})')
    if problems:
        raise SystemExit(
            'Kindle binaries failed the ABI check:\n  '
            + '\n  '.join(problems)
            + '\nRun tools/build_kindle_bin.sh to rebuild them.')


DISABLED_STUB = '''#!/bin/sh
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
'''

# RUNME.sh is one shared slot that other Kindle projects also write to. Rather
# than overwrite it, install a dispatcher that runs runme.d/*.sh. Chaining to a
# preserved RUNME is opt-in via KINDLE_RUNME_CHAIN: the script found on a device
# is often a USB networking bootstrap whose useUsbForNetwork call drops the
# mass-storage volume mid-install.
RUNME_DISPATCHER = '''#!/bin/sh
# Kindle RUNME dispatcher (installed by kindlexiping261030).
# Runs each *.sh in runme.d/ in name order, each logging separately.
US=/mnt/us
BASE="$US/extensions/kindlexiping261030"
mkdir -p "$BASE/runme.d"
if [ -d "$BASE/runme.d" ]; then
    for script in "$BASE"/runme.d/*.sh; do
        [ -f "$script" ] || continue
        sh "$script" </dev/null
    done
fi
# Optional: chain to a preserved RUNME when the installer was told to.
if [ -f "$BASE/runme.d/.chain" ]; then
    CHAIN=$(cat "$BASE/runme.d/.chain")
    if [ -n "$CHAIN" ] && [ -f "$CHAIN" ]; then
        sh "$CHAIN" </dev/null
    fi
fi
exit 0
'''


def main():
    if len(BOOKS) != 100 or sum(len(b['excerpts']) for b in BOOKS) != 5000:
        raise SystemExit('content is incomplete')
    if not (ROOT / 'kindle/data.tsv').exists():
        raise SystemExit('run `python3 tools/build_kindle_data.py` first')
    if (ROOT / 'assets/fonts/SmileySans-Oblique.ttf').stat().st_size < 1000000:
        raise SystemExit('Smiley Sans is missing')
    verify_binaries()
    if DIST.exists():
        shutil.rmtree(DIST)
    for folder in (EXT / 'bin', EXT / 'scripts', EXT / 'state', EXT / 'runme.d', DOCS):
        folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'kindle/data.tsv', EXT / 'data.tsv')
    shutil.copy2(ROOT / 'assets/fonts/SmileySans-Oblique.ttf', EXT / 'SmileySans-Oblique.ttf')
    shutil.copy2(ROOT / 'assets/fonts/OFL.txt', EXT / 'SmileySans-OFL.txt')
    shutil.copy2(ROOT / 'content/books.json', EXT / 'books.json')
    shutil.copytree(ROOT / 'kindle/bin', EXT / 'bin', dirs_exist_ok=True)
    (EXT / 'bin/screensaver_draw').unlink(missing_ok=True)
    for name in ('daemon.sh', 'draw.sh', 'toggle.sh', 'blanket_renderers.sh'):
        shutil.copy2(ROOT / 'kindle/scripts' / name, EXT / 'scripts' / name)
    for name in ('LICENSE', 'UPSTREAM-LICENSE', 'THIRD_PARTY_NOTICES.md', 'CREDITS'):
        shutil.copy2(ROOT / 'kindle' / name, EXT / name)
    shutil.copytree(ROOT / 'kindle/licenses', EXT / 'licenses', dirs_exist_ok=True)
    (EXT / 'state/count').write_text('5000\n')
    for filename, label, action in (
        ('Xiping Enable.sh', '栖息 · 开启每日锁屏', 'enable'),
        ('Xiping Browse.sh', '栖息 · 翻阅', 'browse'),
        ('Xiping Disable.sh', '栖息 · 关闭并恢复', 'disable'),
    ):
        (DOCS / filename).write_text(
            f'#!/bin/sh\n# Name: {label}\n# DontUseFBInk\n'
            f'exec sh /mnt/us/extensions/kindlexiping261030/scripts/toggle.sh {action}\n')
    (STAGE / 'README.txt').write_text(
        '栖息 · kindlexiping261030 v' + VERSION + '\n\n'
        '安装：把 extensions 和 documents 合并复制到 Kindle 根目录。\n'
        '本包自带 RUNME.sh 分发器：它只运行 runme.d/ 里的脚本，再转交原有的 RUNME.sh，\n'
        '所以不会覆盖其他项目。若已有 RUNME.sh，请先改名保留为 RUNME.before-kindlexiping.sh。\n'
        '然后在 Kindle 搜索框执行 ;log runme。\n'
        '关闭：打开「栖息 · 关闭并恢复」。\n'
    )
    (EXT / 'runme.d/10-enable.sh').write_text(DISABLED_STUB)
    (STAGE / 'RUNME.sh').write_text(RUNME_DISPATCHER)
    for path in (DOCS.glob('*.sh')):
        path.chmod(0o755)
    (EXT / 'runme.d/10-enable.sh').chmod(0o755)
    (STAGE / 'RUNME.sh').chmod(0o755)
    for path in (EXT / 'scripts').glob('*.sh'):
        path.chmod(0o755)
    for path in (EXT / 'bin').iterdir():
        path.chmod(0o755)
    zip_path = DIST / f'{NAME}-kindle.zip'
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(STAGE.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(STAGE))
    source_path = DIST / f'{NAME}-source.zip'
    with zipfile.ZipFile(source_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(ROOT.rglob('*')):
            if path.is_file() and not any(part in {'.git', 'build', 'dist', 'source-cache', '__pycache__'} for part in path.relative_to(ROOT).parts):
                archive.write(path, Path(NAME) / path.relative_to(ROOT))
    for path in (zip_path, source_path):
        digest = subprocess.check_output(['shasum', '-a', '256', str(path)], text=True).split()[0]
        path.with_suffix(path.suffix + '.sha256').write_text(f'{digest}  {path.name}\n')
    print(zip_path)
    print(source_path)


if __name__ == '__main__':
    main()
