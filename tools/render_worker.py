#!/usr/bin/env python3
import datetime, json, sys
from pathlib import Path
from render import render, ROOT
worker, total = int(sys.argv[1]), int(sys.argv[2])
books = json.loads((ROOT / 'content/books.json').read_text())
entries = [(b, q) for b in books for q in b['excerpts']]
for i in range(worker, len(entries), total):
    book, quote = entries[i]
    author = book['author'] + (' 著 · ' + book['translator'] + ' 译' if book['translator'] else ' 著')
    render(quote['text'], book['title'], author, datetime.datetime.fromisoformat('2026-10-31T06:30'),
           ROOT / 'build/images' / f'{i:05}.png')
print(f'worker {worker}: done')
