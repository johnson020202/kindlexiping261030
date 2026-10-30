#!/usr/bin/env python3
"""Extract exact, non-overlapping source spans. Never invent quotations."""
import ast
import hashlib
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import quote
from opencc import OpenCC

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'source-cache'
CC = OpenCC('t2s')
SKIP = ('殆知阁', 'http', 'www.', '制作信息', '内容简介', '钦定四库全书', '总纂官',
        '总校官', '御制读', '【杂事之属】', '【游记之属】', '【杂学之属】', '文中提及的书名')
PUA = re.compile(r'[\ue000-\uf8ff]')


def curated():
    for node in ast.parse((ROOT / 'tools/catalog.py').read_text()).body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'CHINESE' for t in node.targets):
            return ast.literal_eval(node.value)


def download(url, path):
    if path.exists() and path.stat().st_size > 500:
        return path.read_text(encoding='utf-8-sig')
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['curl', '-fLsS', '--retry', '2', '--max-time', '60', url, '-o', str(path)], check=True)
    return path.read_text(encoding='utf-8-sig')


def font_characters():
    from fontTools.ttLib import TTFont
    font = TTFont(ROOT / 'assets/fonts/SmileySans-Oblique.ttf')
    return {chr(code) for table in font['cmap'].tables for code in table.cmap}


SUPPORTED = font_characters()
SEEN_SOURCE = set()


def source_units(raw, title):
    seen = set()
    if title == '红楼梦':
        raw = raw[raw.find('此开卷第一回也'):]
    chapter = '正文'
    for line in raw.replace('\r', '\n').split('\n'):
        text = re.sub(r'\s+', '', line)
        if not text:
            continue
        if re.fullmatch(r'第.{0,35}[回卷章节幕场].{0,50}', text) or re.fullmatch(r'.{1,25}第[一二三四五六七八九十百零〇0-9]+', text):
            chapter = text
            continue
        if len(text) < 25 or any(x in text for x in SKIP) or text.startswith('<子部,') or PUA.search(text):
            continue
        for sentence in re.findall(r'[^。！？；]+[。！？；](?:[”’』」])?|[^。！？；]+$', text):
            if len(sentence) >= 18 and not PUA.search(sentence) and sentence not in seen:
                seen.add(sentence)
                yield sentence, chapter


def select(units, title):
    candidates = []
    current, chapter = '', '正文'
    seen = set()

    def emit(text, location):
        simplified = CC.convert(text)
        if (70 <= len(text) <= 260 and text not in seen and not PUA.search(text)
                and all(char in SUPPORTED for char in simplified)):
            seen.add(text)
            candidates.append({'sourceExcerpt': text, 'chapter': location})

    for sentence, location in units:
        if len(sentence) > 260:
            if current:
                emit(current, chapter)
                current = ''
            remainder = sentence
            while len(remainder) > 260:
                end = max(remainder.rfind(mark, 70, 261) for mark in '，：；')
                if end < 70:
                    break
                emit(remainder[:end + 1], location)
                remainder = remainder[end + 1:]
            if remainder:
                current, chapter = remainder, location
            continue
        if current and len(current) + len(sentence) > 230:
            emit(current, chapter)
            current = ''
        if not current:
            chapter = location
        current += sentence
        if len(current) >= 140:
            emit(current, chapter)
            current = ''
    if current:
        emit(current, chapter)
    if len(candidates) < 50:
        raise ValueError(f'{title}: {len(candidates)} unique source passages')
    # Even sampling covers the entire work. No selected passage overlaps another.
    chosen = [candidates[round(i * (len(candidates)-1) / 49)] for i in range(50)]
    for item in chosen:
        item['text'] = CC.convert(item['sourceExcerpt'])
        item['length'] = len(item['text'])
    return chosen


def make_book(index, title, author, translator, source, excerpts):
    return {'id': f'book-{index:03}', 'title': title, 'author': author, 'translator': translator,
            'source': source, 'excerpts': excerpts}


def chinese_books():
    books, skipped = [], []
    for title, author, relative in curated():
        if len(books) == 70:
            break
        url = 'https://raw.githubusercontent.com/garychowcmu/daizhigev20/master/' + quote(relative)
        try:
            raw = download(url, CACHE / 'daizhige' / relative)
            spans = select(source_units(raw, title), title)
        except Exception as error:
            skipped.append({'title': title, 'reason': str(error)})
            continue
        for j, excerpt in enumerate(spans, 1):
            excerpt.update({'id': f'book-{len(books)+1:03}-{j:02}', 'kind': '连续原文（OpenCC 简繁转换）'})
        books.append(make_book(len(books)+1, title, author, None,
            {'edition': '殆知阁古代文献 TXT 集', 'url': url, 'sha256': hashlib.sha256(raw.encode()).hexdigest()}, spans))
    if len(books) != 70:
        raise RuntimeError(f'Chinese works {len(books)}/70: {skipped}')
    (ROOT/'content').mkdir(exist_ok=True)
    (ROOT/'content/import-skipped.json').write_text(json.dumps(skipped, ensure_ascii=False, indent=2)+'\n')
    print('Chinese:', len(books), 'unsuitable editions skipped:', len(skipped))
    return books


def play_books():
    base = 'https://raw.githubusercontent.com/bzy-debug/shakespeare/main/'
    catalog = json.loads(download(base+'data/chinese-collection/catalog.json', CACHE/'shakespeare/catalog.json'))
    works = [w for w in catalog if w['translator'] == '朱生豪' and w['attributionStatus'] == 'explicit']
    books = []
    for work in works:
        raw = download(base+work['file'], CACHE/'shakespeare'/Path(work['file']).name)
        data = json.loads(raw.splitlines()[1].split('=', 1)[1].strip().rstrip(';'))
        units = []
        for section in data['sections']:
            if section.get('kind') == 'preface':
                continue
            for block in section['blocks']:
                text = re.sub(r'\s+', '', block.get('text', ''))
                if block.get('tag') in ('p', 'blockquote') and len(text) >= 18 and not any(x in text for x in ['朱生豪译', '方平校', '剧中人物', '注释']):
                    units.append((text, section['label']))
        spans = select(units, work['title'])
        i = len(books)+71
        for j, excerpt in enumerate(spans, 1):
            excerpt.update({'id': f'book-{i:03}-{j:02}', 'kind': '朱生豪连续译文（OpenCC 简繁转换）'})
        books.append(make_book(i, work['title'], '威廉·莎士比亚', '朱生豪',
            {'edition': '莎士比亚全集，人民文学出版社，ISBN 978-7-02-010568-7', 'url': base+work['file'],
             'workId': work['id'], 'sha256': hashlib.sha256(raw.encode()).hexdigest()}, spans))
    assert len(books) == 30
    return books


def main():
    books = chinese_books() + play_books()
    texts = [q['text'] for book in books for q in book['excerpts']]
    assert len(books) == 100 and all(len(book['excerpts']) == 50 for book in books)
    assert len(set(texts)) == 5000 and all(70 <= len(text) <= 260 for text in texts)
    assert not any(any(bad in text for bad in SKIP) or PUA.search(text) for text in texts)
    payload = json.dumps(books, ensure_ascii=False, separators=(',', ':'))
    (ROOT/'content/books.json').write_text(payload+'\n')
    (ROOT/'content/books.js').write_text('window.BOOKS = '+payload+';\n')
    print(f'Built {len(books)} books; {len(texts)} unique excerpts; mean {sum(map(len,texts))/len(texts):.1f} chars')


if __name__ == '__main__':
    main()
