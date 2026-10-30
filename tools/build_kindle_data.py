#!/usr/bin/env python3
"""Build compact on-device layout data instead of shipping 5,000 PNG files."""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from render import wrap, FONT, HEIGHT
from PIL import ImageFont

ROOT = Path(__file__).resolve().parents[1]
books = json.loads((ROOT / 'content/books.json').read_text())
rows = []
for book in books:
    author = book['author'] + (' 著 · ' + book['translator'] + ' 译' if book['translator'] else ' 著')
    for quote in book['excerpts']:
        text = quote['text']
        chosen = None
        for size in range(53, 29, -1):
            font = ImageFont.truetype(str(FONT), size)
            lines = wrap(text, font, 880)
            if len(lines) * round(size * 1.85) <= 730:
                chosen = (size, lines)
                break
        if chosen is None:
            raise SystemExit(f'Quote too long: {quote["id"]}')
        size, lines = chosen
        rows.append((quote['id'], book['title'], author, str(size), '|'.join(lines)))
out = ROOT / 'kindle/data.tsv'
out.parent.mkdir(exist_ok=True)
out.write_text('\n'.join('\t'.join(row) for row in rows) + '\n')
print(f'Wrote {out}: {len(rows)} rows, {out.stat().st_size / 1048576:.2f} MB')
