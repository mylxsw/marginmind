import json, sys
from pypdf import PdfReader, PdfWriter
w = PdfWriter(clone_from=PdfReader(sys.argv[1]))
chap = None
for level, title, page in json.load(open(sys.argv[2])):
    if level == 0: chap = w.add_outline_item(title, page)
    elif chap is not None: w.add_outline_item(title, page, parent=chap)
w.page_mode = "/UseOutlines"
w.write(sys.argv[3])
