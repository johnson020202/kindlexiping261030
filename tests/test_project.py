#!/usr/bin/env python3
"""Validate content, font coverage, images and scripts before a release."""
import json
import subprocess
import unittest
from pathlib import Path
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
BOOKS = json.loads((ROOT / 'content/books.json').read_text())


class ProjectTests(unittest.TestCase):
    def test_books_and_counts(self):
        self.assertEqual(len(BOOKS), 100)
        self.assertTrue(all(len(book['excerpts']) == 50 for book in BOOKS))

    def test_unique_and_length(self):
        texts = [q['text'] for book in BOOKS for q in book['excerpts']]
        self.assertEqual(len(texts), 5000)
        self.assertEqual(len(set(texts)), 5000)
        self.assertTrue(all(70 <= len(text) <= 260 for text in texts))

    def test_source_provenance(self):
        for book in BOOKS:
            self.assertTrue(book['source']['url'].startswith('https://'))
            self.assertEqual(len(book['source']['sha256']), 64)
            self.assertTrue(book['title'] and book['author'])

    def test_no_editorial_text(self):
        forbidden = ('文中提及的书名', '【杂事之属】', '【游记之属】', '殆知阁')
        for book in BOOKS:
            for quote in book['excerpts']:
                self.assertFalse(any(word in quote['text'] for word in forbidden), quote['id'])

    def test_font_coverage(self):
        font = TTFont(ROOT / 'assets/fonts/SmileySans-Oblique.ttf')
        cmap = {code for table in font['cmap'].tables for code in table.cmap}
        missing = sorted({char for book in BOOKS for q in book['excerpts'] for char in q['text'] if ord(char) not in cmap})
        self.assertEqual(missing, [])

    def test_images_when_present(self):
        images = sorted((ROOT / 'build/images').glob('*.png'))
        if images:
            self.assertEqual(len(images), 5000)
            self.assertEqual(images[0].name, '00000.png')
            self.assertEqual(images[-1].name, '04999.png')

    def test_shell_syntax(self):
        for path in (ROOT / 'kindle/scripts').glob('*.sh'):
            subprocess.run(['/bin/sh', '-n', str(path)], check=True)

    def test_script_paths_exist_in_deployed_layout(self):
        """Every $BASE reference must resolve under the installed layout.

        The 0.1.1 release shipped scripts that sourced $BASE/blanket_renderers.sh
        while the file actually lives in $BASE/scripts/: the launcher died as it
        sourced, drew nothing, and the only trace was one line in install.log.
        Paths are checked against what tools/install_kindle.sh deploys, not
        against the source tree.
        """
        import re
        deployed = {
            'bin/daily-index', 'bin/fbink_hf', 'bin/kindlexiping-reader',
            'bin/xscreen', 'data.tsv', 'books.tsv',
            'books.json', 'SmileySans-Oblique.ttf', 'state/count',
            'scripts/daemon.sh', 'scripts/draw.sh', 'scripts/draw_books.sh',
            'scripts/toggle.sh', 'scripts/blanket_renderers.sh',
            'runme.d/10-enable.sh',
        }
        # Created at runtime rather than shipped.
        written = {'launcher.log', 'custom_ss.log', 'install.log',
                   'state/daily-index', 'state/browser-index',
                   'screen-lockscreen.raw', 'screen-after-run.raw',
                   'screen-after-wake.raw', 'state/manual-date',
                   'state/last-index',
                   'diag.log', 'diag.err'}

        problems = []
        for path in sorted((ROOT / 'kindle/scripts').glob('*.sh')):
            for number, line in enumerate(path.read_text().splitlines(), 1):
                for match in re.finditer(r'\$BASE/?([A-Za-z0-9_./-]+)', line):
                    rel = match.group(1).strip('/')
                    if not rel or rel in deployed or rel in written:
                        continue
                    # Directory prefixes before a glob, e.g. "bin/" in "$BASE"/bin/*
                    if any(name.startswith(rel) for name in deployed | written):
                        continue
                    problems.append(f'{path.name}:{number} -> {rel}')
        self.assertEqual(problems, [], 'unresolved $BASE paths: ' + '; '.join(problems))

    def test_sourcing_includes_scripts_dir(self):
        """Guard the exact regression: these files live in the scripts/ subdir."""
        for name in ('toggle.sh', 'daemon.sh'):
            text = (ROOT / 'kindle/scripts' / name).read_text()
            self.assertNotIn('. "$BASE/blanket_renderers.sh"', text,
                             f'{name} sources blanket_renderers.sh from the extension root')
            self.assertIn('. "$BASE/scripts/blanket_renderers.sh"', text,
                          f'{name} must source blanket_renderers.sh from scripts/')

    def test_daily_index_vectors(self):
        import sys
        sys.path.insert(0, str(ROOT / 'tools'))
        from render import daily_index
        self.assertEqual(daily_index('2026-10-31', 5000), 2621)
        self.assertEqual(daily_index('2026-11-01', 5000), daily_index('2026-11-01', 5000))


if __name__ == '__main__':
    unittest.main()
