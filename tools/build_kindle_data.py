#!/usr/bin/env python3
"""Build compact on-device layout data instead of shipping 5,000 PNG files.

Writes two files consumed by the device:
  kindle/data.tsv   one row per quote: id, title, author, size, body|lines
  kindle/books.tsv  one row per book:  id, title, author, first_index, count

Line breaking and size selection live in render.py so the PNG preview and the
on-device FBInk renderer cannot drift apart. Two constraints must hold at once:
  - width:  no line wider than TEXT_WIDTH, or FBInk wraps it a second time and
            drops a stray glyph on the following baseline
  - height: total block fits BODY_BUDGET, or it collides with the metadata
"""
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from render import (wrap, text_width, FONT, MAX_FONT_SIZE, MIN_FONT_SIZE,
                    TEXT_WIDTH, BOX_WIDTH, BODY_BUDGET, LINE_HEIGHT_RATIO)
from PIL import ImageFont

ROOT = Path(__file__).resolve().parents[1]
books = json.loads((ROOT / 'content/books.json').read_text())
rows = []
book_rows = []
sizes_used = {}

for book in books:
    author = book['author'] + (' 著 · ' + book['translator'] + ' 译' if book['translator'] else ' 著')
    first_index = len(rows)
    for quote in book['excerpts']:
        text = quote['text']
        chosen = None
        for size in range(MAX_FONT_SIZE, MIN_FONT_SIZE - 1, -1):
            font = ImageFont.truetype(str(FONT), size)
            lines = wrap(text, font, TEXT_WIDTH)
            fits_width = max(text_width(font, line) for line in lines) <= TEXT_WIDTH
            fits_height = len(lines) * round(size * LINE_HEIGHT_RATIO) <= BODY_BUDGET
            if fits_width and fits_height:
                chosen = (size, lines)
                break
        if chosen is None:
            raise SystemExit(f'Quote too long: {quote["id"]}')
        size, lines = chosen
        sizes_used[size] = sizes_used.get(size, 0) + 1
        rows.append((quote['id'], book['title'], author, str(size), '|'.join(lines)))
    # Book id is the quote id without its trailing -NN.
    book_id = book['excerpts'][0]['id'].rsplit('-', 1)[0]
    book_rows.append((book_id, book['title'], author,
                      str(first_index), str(len(book['excerpts']))))


def wrap_ok():
    """Every stored line must fit the box FBInk is actually given."""
    bad = []
    for row in rows:
        size = int(row[3])
        font = ImageFont.truetype(str(FONT), size)
        for line in row[4].split('|'):
            if text_width(font, line) > TEXT_WIDTH:
                bad.append((row[0], size, round(text_width(font, line))))
                break
    return bad


bad = wrap_ok()
if bad:
    raise SystemExit(f'{len(bad)} rows overflow TEXT_WIDTH, e.g. {bad[:3]}')

out = ROOT / 'kindle/data.tsv'
out.parent.mkdir(exist_ok=True)
out.write_text('\n'.join('\t'.join(row) for row in rows) + '\n')

books_out = ROOT / 'kindle/books.tsv'
books_out.write_text('\n'.join('\t'.join(r) for r in book_rows) + '\n')

print(f'Wrote {out}: {len(rows)} rows, {out.stat().st_size / 1048576:.2f} MB')
print(f'Wrote {books_out}: {len(book_rows)} books')
print(f'wrap width {TEXT_WIDTH} of box {BOX_WIDTH}; slack {BOX_WIDTH - TEXT_WIDTH}px')
print('size distribution:', dict(sorted(sizes_used.items(), reverse=True)))
