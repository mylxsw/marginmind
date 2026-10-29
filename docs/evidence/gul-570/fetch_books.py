"""Download original Gutenberg EPUB3 files, recording hashes and source metadata."""
import hashlib
import json
from pathlib import Path
import urllib.request
import zipfile
import io

ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT / 'packages/mm_reflow/example/assets'
books = [(7337, '道德經', 'Laozi', 'Chinese'),
         (33283, 'Calculus Made Easy', 'Silvanus P. Thompson (d. 1916)', 'tables'),
         (28885, "Alice’s Adventures in Wonderland", 'Lewis Carroll (d. 1898); Arthur Rackham (d. 1939); Austin Dobson (d. 1921)', 'illustrated')]
manifest = []
pinned_path = Path(__file__).with_name('books.json')
pinned = {b['id']:b['sha256'] for b in json.loads(pinned_path.read_text())} if pinned_path.exists() else {}
for number, title, author, role in books:
    url = f'https://www.gutenberg.org/ebooks/{number}.epub3.images'
    data = urllib.request.urlopen(url, timeout=90).read()
    digest = hashlib.sha256(data).hexdigest()
    if number in pinned and digest != pinned[number]:
        raise ValueError(f'Upstream EPUB changed for {number}: {digest}; restore a matching local sample or review the new upstream hash')
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        assert z.read('mimetype') == b'application/epub+zip'
        names = z.namelist()
        tables = sum(z.read(n).lower().count(b'<table') for n in names if n.endswith(('.html', '.xhtml')))
        images = sum(n.lower().endswith(('.png', '.jpg', '.jpeg', '.gif')) for n in names)
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / f'{number}.epub').write_bytes(data)
    item = dict(id=number, title=title, author=author, role=role, url=url,
                catalog=f'https://www.gutenberg.org/ebooks/{number}',
                sha256=hashlib.sha256(data).hexdigest(), bytes=len(data),
                table_elements=tables, image_files=images,
                license='Project Gutenberg license included in EPUB; underlying historical work public domain in US',
                downloaded='2026-10-29')
    manifest.append(item)
    print(json.dumps(item, ensure_ascii=False), flush=True)
Path(__file__).with_name('books.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
