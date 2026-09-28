import sys
from docx import Document
from docx.oxml.ns import qn

sys.stdout.reconfigure(encoding='utf-8')
doc = Document(sys.argv[1])
start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
end = int(sys.argv[3]) if len(sys.argv) > 3 else 10000
for i, element in enumerate(doc.element.body):
    if not start <= i < end:
        continue
    if element.tag == qn('w:tbl'):
        print(f'[{i}] TABLE')
        for row in element.findall(qn('w:tr')):
            print(' | '.join(''.join(cell.itertext()) if False else ''.join(t.text or '' for t in cell.iter(qn('w:t'))) for cell in row.findall(qn('w:tc'))))
    else:
        print(f'[{i}] ' + ''.join(t.text or '' for t in element.iter(qn('w:t'))))
