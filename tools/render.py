#!/usr/bin/env python3
"""Render real Chinese glyphs into 1072x1448 e-ink images with breathing room."""
import argparse, datetime, json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / 'assets/fonts/SmileySans-Oblique.ttf'
WIDTH, HEIGHT = 1072, 1448

# Layout shared with the on-device renderer (kindle/scripts/draw.sh).
# tests/test_project.py asserts the shell constants still match these.
MARGIN_X = 96
BOX_WIDTH = WIDTH - 2 * MARGIN_X         # 880: the box FBInk is given
# Wrap meaningfully narrower than the box. PIL and stb_truetype measure glyph
# advances slightly differently, so a line that fits exactly can still overflow
# in FBInk, which wraps it a second time and drops the remainder onto the next
# baseline as a stray glyph (the lone 山/牛 seen on device).
TEXT_WIDTH = BOX_WIDTH - 30              # 850
BODY_TOP = 280
BODY_BUDGET = 820                        # vertical px available for the body
LINE_HEIGHT_RATIO = 1.85
MAX_FONT_SIZE = 53
MIN_FONT_SIZE = 30

# Fixed type sizes for the header and the metadata blocks.
HEADER_SIZE = 23
TITLE_SIZE = 43
AUTHOR_SIZE = 28
META_SIZE = 26

# FBInk's `px=` is NOT a font size. It feeds stbtt_ScaleForPixelHeight, which
# divides by (ascent - descent) = 1200 for this font, while the em box is 1000.
# So a glyph rendered at px=N has an em of N * 1000/1200 = 0.833N: the 0.1.x
# release drew every line ~17% small and left a matching gap on the right.
# To get an em equal to a PIL `size`, ask FBInk for size * 1.2.
FBINK_PX_PER_PIL_SIZE = 1.2


def fbink_px(pil_size):
    """Convert a PIL font size to the FBInk px value that renders at that size."""
    return round(pil_size * FBINK_PX_PER_PIL_SIZE)


def daily_index(date, total):
    value = 2166136261
    for byte in f'kindlexiping261030:v1:{date}'.encode():
        value ^= byte
        value = (value * 16777619) & 0xffffffff
    return value % total


def text_width(font, text):
    return font.getlength(text)


NO_LINE_START = '，。！？；：、）】》”’'


def wrap(text, font, width):
    """Split text into lines, none wider than `width`.

    The 0.1.x version appended closing punctuation without re-checking the width,
    which produced lines up to 1018px in an 880px box. That overflow was masked
    on device because FBInk drew everything at 83% size; fixing the scale alone
    would have pushed text off the page, so the guarantee has to live here.
    """
    lines, current = [], ''
    for char in text:
        if not current:
            current = char
        elif text_width(font, current + char) <= width:
            current += char
        elif char in NO_LINE_START and len(current) >= 2:
            # Make room for the punctuation by carrying the last glyph down.
            trimmed, carried = current[:-1], current[-1]
            if text_width(font, trimmed + char) <= width:
                lines.append(trimmed + char)
                current = carried
            else:
                lines.append(current)
                current = char
        else:
            lines.append(current)
            current = char
    if current:
        lines.append(current)

    # Avoid a final line holding a single stray glyph, but never exceed width.
    if len(lines) >= 2 and len(lines[-1]) == 1 and len(lines[-2]) >= 3:
        prev, last = lines[-2], lines[-1]
        merged = prev[-1] + last
        if text_width(font, merged) <= width:
            lines[-2] = prev[:-1]
            lines[-1] = merged
    return lines


def render(quote, title, author, when, destination, width=WIDTH, height=HEIGHT):
    image = Image.new('L', (width, height), 248)
    draw = ImageDraw.Draw(image)
    small = ImageFont.truetype(str(FONT), HEADER_SIZE)
    draw.text((MARGIN_X, 93), '一百部经典 · 每日一段', font=small, fill=110)
    draw.line((MARGIN_X, 210, MARGIN_X + 41, 210), fill=110, width=2)

    font_size = MAX_FONT_SIZE
    while font_size >= MIN_FONT_SIZE:
        font = ImageFont.truetype(str(FONT), font_size)
        lines = wrap(quote, font, TEXT_WIDTH)
        line_height = round(font_size * LINE_HEIGHT_RATIO)
        widest = max(text_width(font, line) for line in lines)
        if widest <= TEXT_WIDTH and len(lines) * line_height <= BODY_BUDGET:
            break
        font_size -= 1
    else:
        raise ValueError('Quote is too long to preserve comfortable margins')

    y = BODY_TOP
    for line in lines:
        draw.text((MARGIN_X, y), line, font=font, fill=25)
        y += line_height

    book_font = ImageFont.truetype(str(FONT), TITLE_SIZE)
    author_font = ImageFont.truetype(str(FONT), AUTHOR_SIZE)
    time_font = ImageFont.truetype(str(FONT), META_SIZE)
    right = width - MARGIN_X
    draw.text((right, height - 226), f'《{title}》', font=book_font, fill=30, anchor='ra')
    draw.text((right, height - 153), author, font=author_font, fill=80, anchor='ra')
    date = f'{when.year} 年 {when.month} 月 {when.day} 日'
    time_text = when.strftime('%H:%M')
    draw.text((MARGIN_X, height - 210), date, font=time_font, fill=90)
    draw.text((MARGIN_X, height - 158), time_text, font=time_font, fill=90)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, optimize=True)
    return destination


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--index', type=int)
    parser.add_argument('--date', default=datetime.date.today().isoformat())
    parser.add_argument('--output')
    args = parser.parse_args()
    books = json.loads((ROOT / 'content/books.json').read_text())
    entries = [(b, q) for b in books for q in b['excerpts']]
    if args.all:
        for i, (book, quote) in enumerate(entries):
            render(quote['text'], book['title'], book['author'] + (' 著 · ' + book['translator'] + ' 译' if book['translator'] else ' 著'),
                   datetime.datetime.fromisoformat(args.date + 'T06:30'), ROOT / 'build/images' / f'{i:05}.png')
            if (i+1) % 500 == 0:
                print(f'Rendered {i+1}/{len(entries)}')
    else:
        i = args.index if args.index is not None else daily_index(args.date, len(entries))
        book, quote = entries[i]
        output = Path(args.output) if args.output else ROOT / 'preview.png'
        render(quote['text'], book['title'], book['author'] + (' 著 · ' + book['translator'] + ' 译' if book['translator'] else ' 著'),
               datetime.datetime.now(), output)
        print(f'{output}: index={i}, book={book["title"]}, excerpt={quote["id"]}')


if __name__ == '__main__':
    main()
