#!/usr/bin/env python3
"""Render real Chinese glyphs into 1072x1448 e-ink images with breathing room."""
import argparse, datetime, json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / 'assets/fonts/SmileySans-Oblique.ttf'
WIDTH, HEIGHT = 1072, 1448


def daily_index(date, total):
    value = 2166136261
    for byte in f'kindlexiping261030:v1:{date}'.encode():
        value ^= byte
        value = (value * 16777619) & 0xffffffff
    return value % total


def text_width(font, text):
    return font.getlength(text)


def wrap(text, font, width):
    lines, current = [], ''
    for char in text:
        if text_width(font, current + char) <= width or not current:
            current += char
        else:
            # Prohibit punctuation at the start of a line; don't create one-character lines.
            if char in '，。！？；：、）】》”’':
                current += char
                lines.append(current)
            else:
                lines.append(current)
                current = char
    if current:
        if len(current.strip('，。！？；：、）】》”’')) <= 1 and lines:
            carry = lines.pop()
            while carry and text_width(font, carry + current) > width:
                current = carry[-1] + current
                carry = carry[:-1]
            if carry:
                lines.append(carry)
        lines.append(current)
    return lines


def render(quote, title, author, when, destination, width=WIDTH, height=HEIGHT):
    image = Image.new('L', (width, height), 248)
    draw = ImageDraw.Draw(image)
    small = ImageFont.truetype(str(FONT), 23)
    draw.text((96, 93), '一百部经典 · 每日一段', font=small, fill=110)
    draw.line((96, 210, 137, 210), fill=110, width=2)
    available_width = width - 192
    font_size = 53
    while font_size >= 30:
        font = ImageFont.truetype(str(FONT), font_size)
        lines = wrap(quote, font, available_width)
        line_height = round(font_size * 1.85)
        if len(lines) * line_height <= 730:
            break
        font_size -= 1
    else:
        raise ValueError('Quote is too long to preserve comfortable margins')
    y = 280
    for line in lines:
        draw.text((96, y), line, font=font, fill=25)
        y += line_height
    book_font = ImageFont.truetype(str(FONT), 43)
    author_font = ImageFont.truetype(str(FONT), 28)
    time_font = ImageFont.truetype(str(FONT), 26)
    draw.text((width - 96, height - 226), f'《{title}》', font=book_font, fill=30, anchor='ra')
    draw.text((width - 96, height - 153), author, font=author_font, fill=80, anchor='ra')
    date = f'{when.year} 年 {when.month} 月 {when.day} 日'
    time_text = when.strftime('%H:%M')
    draw.text((96, height - 210), date, font=time_font, fill=90)
    draw.text((96, height - 158), time_text, font=time_font, fill=90)
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
