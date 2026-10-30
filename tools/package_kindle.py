#!/usr/bin/env python3
"""Build the self-contained Kindle package and source archive."""
import json
import shutil
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


def main():
    if len(BOOKS) != 100 or sum(len(b['excerpts']) for b in BOOKS) != 5000:
        raise SystemExit('content is incomplete')
    if not (ROOT / 'kindle/data.tsv').exists():
        raise SystemExit('run `python3 tools/build_kindle_data.py` first')
    if (ROOT / 'assets/fonts/SmileySans-Oblique.ttf').stat().st_size < 1000000:
        raise SystemExit('Smiley Sans is missing')
    if DIST.exists():
        shutil.rmtree(DIST)
    for folder in (EXT / 'bin', EXT / 'scripts', EXT / 'state', DOCS):
        folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'kindle/data.tsv', EXT / 'data.tsv')
    shutil.copy2(ROOT / 'assets/fonts/SmileySans-Oblique.ttf', EXT / 'SmileySans-Oblique.ttf')
    shutil.copy2(ROOT / 'assets/fonts/OFL.txt', EXT / 'SmileySans-OFL.txt')
    shutil.copy2(ROOT / 'content/books.json', EXT / 'books.json')
    shutil.copytree(ROOT / 'kindle/bin', EXT / 'bin', dirs_exist_ok=True)
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
        '安装：把 extensions 和 documents 合并复制到 Kindle 根目录，保留原 RUNME.sh。\n'
        '然后在 Kindle 搜索框执行 ;log runme（安装脚本会替换 RUNME.sh 并保留备份）。\n'
        '关闭：打开「栖息 · 关闭并恢复」。\n'
    )
    (STAGE / 'RUNME.sh').write_text(
        '#!/bin/sh\n'
        'exec >> /mnt/us/extensions/kindlexiping261030/install.log 2>&1\n'
        'set -x\n'
        'date\n'
        'uname -a\n'
        'BASE=/mnt/us/extensions/kindlexiping261030\n'
        'mkdir -p /var/tmp/kindlexiping-bin\n'
        'cp "$BASE"/bin/* /var/tmp/kindlexiping-bin/\n'
        'chmod 755 /var/tmp/kindlexiping-bin/*\n'
        'sh "$BASE/scripts/toggle.sh" enable\n'
        'date\n'
        'sync\n'
    )
    for path in (DOCS.glob('*.sh')):
        path.chmod(0o755)
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
