#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
NEW="${1:?usage: tools/release.sh 0.1.1 [notes]}"
NOTES="${2:-版本 $NEW}"
OLD="$(cat VERSION)"
python3 - "$OLD" "$NEW" <<'PY'
import re, sys
old, new = sys.argv[1:]
def key(v): return tuple(int(x) for x in v.split('.'))
if not re.fullmatch(r'\d+\.\d+\.\d+', new) or key(new) <= key(old):
    raise SystemExit(f'VERSION must increase semantically: {old} -> {new}')
PY
printf '%s\n' "$NEW" > VERSION
python3 - "$NEW" "$NOTES" <<'PY'
import datetime, sys
from pathlib import Path
new, notes = sys.argv[1:]
path = Path('CHANGELOG.md')
text = path.read_text()
entry = f"## {new} — {datetime.date.today().isoformat()}\n\n- {notes}\n\n"
lines = text.splitlines(True)
lines.insert(2, entry)
path.write_text(''.join(lines))
PY
make test
make kindle-data
make package
git add -A
git commit -m "release: v$NEW"
git tag -a "v$NEW" -m "kindlexiping261030 v$NEW"
git push origin main
git push origin "v$NEW"
if command -v gh >/dev/null 2>&1; then
  gh release create "v$NEW" dist/*.zip dist/*.sha256 --title "v$NEW" --notes "$NOTES"
else
  echo "Release assets are in dist/. Create the GitHub Release manually or via API."
fi
