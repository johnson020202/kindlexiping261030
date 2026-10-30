#!/usr/bin/env python3
"""Import traceable spans. No LLM text generation or quotation expansion."""
import argparse, concurrent.futures, hashlib, json, re, subprocess, time
from pathlib import Path
from opencc import OpenCC
from catalog import CHINESE, CORPUS

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / 'source-cache'
DATA = ROOT / 'content'
CC = OpenCC('t2s')
UA = 'kindlexiping261030/0.1.0 (personal offline literary screensaver)'


def fetch(url, destination):
    if destination.exists() and destination.stat().st_size > 100:
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(3):
        result = subprocess.run(['curl', '-fLsS', '--retry', '1', '--max-time', '60',
                                 '-A', UA, url, '-o', str(destination)])
        if result.returncode == 0:
            time.sleep(.12)
            return destination
    raise RuntimeError(f'Unable to fetch {url}; remove partial cache before retrying')


def chapter_for(text, position):
    prefix = text[:position]
    patterns = [r'(?m)^[\s　]*(第[^\n]{0,30}[回卷章节幕场][^\n]{0,50})$',
                r'(?m)^[\s　]*([^\n]{0,25}第[一二三四五六七八九十百零〇0-9]+)[\s　]*$']
    matches = []
    for pattern in patterns:
        matches.extend(re.finditer(pattern, prefix))
    return re.sub(r'[\s　]+', '', matches[-1].group(1)) if matches else '正文'


def chinese_units(raw):
    raw = raw.replace('\r\n', '\n').replace('\r', '\n')
    lines = raw.split('\n')
    # Drop editorial metadata and the first table of contents, preserving original text later.
    start = 0
    for i, line in enumerate(lines[:500]):
        if re.search(r'[。！？；]', line) and len(line.strip()) > 60:
            start = i
            break
    text = '\n'.join(lines[start:])
    # Some Siku editions have an entire volume on a single physical line.
    # Split after sentence punctuation, never at an arbitrary byte or character.
    paragraphs = re.split(r'\n|(?<=[。！？])(?:[”’』」])?', text)
    units, cursor = [], 0
    for paragraph in paragraphs:
        stripped = re.sub(r'\s+', '', paragraph)
        if len(stripped) < 15 or len(re.findall(r'[\u3400-\u9fff]', stripped)) < 12:
            continue
        if any(x in stripped for x in ['殆知阁', 'http', 'www.', '校对', '制作信息', '内容简介']):
            continue
        if re.match(r'^(第.{0,20}[回卷章节幕场]|[一二三四五六七八九十]+、)$', stripped):
            continue
        offset = None
        chapter = '正文'
        units.append({'text': stripped, 'chapter': chapter})
    return units


def split_exact(units, minimum=90, target=150, maximum=190):
    groups, current = [], ''
    for unit in units:
        sentence = unit['text']
        if len(sentence) > maximum:
            if current:
                groups.append(current)
                current = ''
            # Long classical paragraphs are cut only at an internal clause boundary.
            remainder = sentence
            while len(remainder) > maximum:
                boundary = max(remainder.rfind(mark, minimum, maximum + 1)
                               for mark in ['；', '：', '，'])
                if boundary < minimum:
                    break
                groups.append(remainder[:boundary + 1])
                remainder = remainder[boundary + 1:]
            if len(remainder) >= minimum:
                current = remainder
            elif remainder and current and len(current) + len(remainder) <= maximum:
                current += remainder
            continue
        if current and len(current) + len(sentence) > maximum:
            groups.append(current)
            current = sentence
        else:
            current += sentence
        if len(current) >= target:
            groups.append(current)
            current = ''
    if current:
        groups.append(current)
    return groups


def select_evenly(candidates, count=50):
    if len(candidates) < count:
        raise ValueError(f'Only {len(candidates)} suitable source passages')
    seen, unique = set(), []
    for value in candidates:
        if value not in seen:
            unique.append(value)
            seen.add(value)
    if len(unique) < count:
        raise ValueError('Duplicate passages prevented 50 unique excerpts')
    positions = sorted(set(round(i * (len(unique) - 1) / (count - 1)) for i in range(count)))
    if len(positions) < count:
        raise ValueError('Selection positions collide')
    return [unique[i] for i in positions]


def import_chinese(item):
    index, (title, author, relative) = item
    url = f'https://raw.githubusercontent.com/{CORPUS}/master/' + '/'.join(
        __import__('urllib.parse', fromlist=['quote']).quote(part) for part in relative.split('/'))
    path = RAW / 'daizhige' / relative
    raw = fetch(url, path).read_text(encoding='utf-8-sig')
    units = chinese_units(raw)
    excerpts = select_evenly(split_exact(units, minimum=35, maximum=260))
    return {
        'id': f'book-{index:03}', 'title': title, 'author': author, 'translator': None,
        'language': 'zh-Hans', 'genre': '中国古典文学与人文经典',
        'source': {'repository': CORPUS, 'edition': '殆知阁古代文献 TXT 集',
                   'url': url, 'licenseNote': '古籍原文；数字文本来源无明确授权声明，见 CONTENT.md'},
        'excerpts': [{'id': f'book-{index:03}-{j:02}', 'text': CC.convert(value),
                      'chapter': '正文', 'length': len(CC.convert(value)),
                      'kind': '连续原文（OpenCC 简繁转换）',
                      'sourceSha256': hashlib.sha256(raw.encode()).hexdigest()}
                     for j, value in enumerate(excerpts, 1)]
    }


def import_plays():
    catalog_url = 'https://raw.githubusercontent.com/bzy-debug/shakespeare/main/data/chinese-collection/catalog.json'
    catalog = json.loads(fetch(catalog_url, RAW / 'shakespeare/catalog.json').read_text())
    chosen = [x for x in catalog if x['translator'] == '朱生豪' and x['attributionStatus'] == 'explicit']
    assert len(chosen) == 30, len(chosen)
    books = []
    for i, work in enumerate(chosen, len(CHINESE) + 1):
        url = 'https://raw.githubusercontent.com/bzy-debug/shakespeare/main/' + work['file']
        file = RAW / 'shakespeare' / Path(work['file']).name
        raw = fetch(url, file).read_text()
        payload = json.loads(raw[raw.index('=') + 1:].strip().rstrip(';'))
        units = []
        for section in payload['sections']:
            for block in section['blocks']:
                text = re.sub(r'\s+', '', block.get('text', ''))
                if block.get('tag') in ('p', 'blockquote') and len(text) >= 18 and not any(
                        bad in text for bad in ['朱生豪译', '方平校', '剧中人物', '注释']):
                    units.append({'text': text, 'chapter': section['label']})
        excerpts = select_evenly(split_exact(units, 70, 145, 200))
        books.append({
            'id': f'book-{i:03}', 'title': work['title'], 'author': '威廉·莎士比亚',
            'translator': '朱生豪', 'language': 'zh-Hans', 'genre': '世界文学 · 戏剧',
            'source': {'repository': 'bzy-debug/shakespeare',
                       'edition': '莎士比亚全集，人民文学出版社，ISBN 978-7-02-010568-7',
                       'url': url, 'workId': work['id'],
                       'licenseNote': '朱生豪（1912–1944）译文；原译公版状态见 CONTENT.md'},
            'excerpts': [{'id': f'book-{i:03}-{j:02}', 'text': CC.convert(value),
                          'chapter': '正文', 'length': len(CC.convert(value)),
                          'kind': '连续译文（OpenCC 简繁转换）',
                          'sourceSha256': hashlib.sha256(raw.encode()).hexdigest()}
                         for j, value in enumerate(excerpts, 1)]
        })
    return books


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plays-only', action='store_true')
    args = parser.parse_args()
    DATA.mkdir(exist_ok=True)
    if not args.plays_only:
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
            chinese = list(executor.map(import_chinese, enumerate(CHINESE, 1)))
        (DATA / 'chinese.json').write_text(json.dumps(chinese, ensure_ascii=False, indent=2) + '\n')
        print(f'Imported {len(chinese)} Chinese works')
    else:
        chinese = json.loads((DATA / 'chinese.json').read_text())
    books = chinese + import_plays()
    assert len(books) == 100
    for book in books:
        assert len(book['excerpts']) >= 50, book['title']
        assert len({x['text'] for x in book['excerpts']}) == len(book['excerpts'])
    (DATA / 'books.json').write_text(json.dumps(books, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'{len(books)} books; {sum(len(b["excerpts"]) for b in books)} excerpts')


if __name__ == '__main__':
    main()
