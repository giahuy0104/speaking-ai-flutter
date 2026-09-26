import re
import sys
from docx import Document
from docx.oxml.ns import qn
from docx.table import Table

sys.stdout.reconfigure(encoding='utf-8')
original, revised = [Document(path) for path in sys.argv[1:3]]
before, after = list(original.element.body), list(revised.element.body)
assert len(before) == len(after)
changed = {1, 13, 17, 20, 25, 43, 46, 82, 103, 106, 115, 128, 137,
           141, 143, 146, 147, 150, 154, 157, 159, 161, 162, 166, 168, 171, 172, 173}
def text(element):
    return ''.join(t.text or '' for t in element.iter(qn('w:t')))
for index, (a, b) in enumerate(zip(before, after)):
    if index not in changed:
        assert text(a) == text(b), f'Unplanned content change at block {index}'
menu = 'Bạn muốn tiếp tục dịch, học Chủ đề hay Bộ từ vựng?'
expected = [
 ['TRANSLATE_CONTINUOUS_INTRO', 'Bắt đầu dịch liên tục', 'Bạn cứ nói từng câu. Muốn dừng thì nói “Dừng lại”.', 'Một câu tiếng Việt cần dịch.', 'Mở mic liên tục; mỗi câu tiếng Việt hợp lệ được dịch sang tiếng Anh.'],
 ['TRANSLATE_STOP', 'Trẻ nói chính xác “Dừng lại” khi đang dịch', 'Đã dừng.', 'Không cần trả lời.', 'Thoát vòng ghi âm dịch và kết thúc phiên. Muốn học tiếp, trẻ phải nhấn MAIN.'],
 ['TRANSLATE_MAIN_AFTER_STOP', 'Sau khi đã dừng dịch, trẻ nhấn MAIN', menu, 'Tiếp tục dịch / Học Chủ đề / Học Bộ từ vựng', 'Mở node lựa chọn và chờ đúng một trong ba câu trả lời.'],
 ['TRANSLATE_CONTINUE_AFTER_STOP', 'Trẻ chọn “Tiếp tục dịch” sau khi nhấn MAIN', 'Mình tiếp tục nhé.', 'Tiếp tục dịch / Tiếp tục / Dịch tiếp / Dịch', 'Quay lại TRANSLATE_CONTINUOUS, mở mic và bắt đầu một phiên dịch mới.'],
 ['TRANSLATE_SWITCH_CONFIRM', 'Trẻ nói muốn học phần khác khi đang dịch', menu, 'Tiếp tục dịch / Học Chủ đề / Học Bộ từ vựng', 'Không dịch câu điều hướng. Chờ đúng một trong ba lựa chọn.'],
 ['TRANSLATE_NO_RESPONSE_1', 'Im lặng/quá ngắn lần 1', 'HOMI chưa nghe rõ. Bạn nói lại nhé.', 'Nói lại câu tiếng Việt.', 'Mở mic lại; chưa thoát dịch.'],
 ['TRANSLATE_NO_RESPONSE_2', 'Im lặng/quá ngắn lần 2', 'Mình tạm dừng nhé.', 'Không cần trả lời.', 'Pause phiên dịch và reset lượt nghe; lần sau vào dịch bắt đầu một lượt mới.'],
]
norm = lambda s: re.sub(r'\s+', ' ', s).strip()
actual = [[norm(c.text) for c in r.cells] for r in Table(after[147], revised).rows[1:]]
assert actual == expected, 'Translation table differs from the approved second image'
tts = {r.cells[1].text: r.cells[2].text for r in Table(after[103], revised).rows[1:]}
states = {r.cells[0].text.split('] ', 1)[-1]: r.cells[1].text for r in Table(after[20], revised).rows[1:]}
for state in ['TRANSLATE_STOP', 'TRANSLATE_MAIN_AFTER_STOP', 'TRANSLATE_SWITCH_CONFIRM']:
    assert states[state] == tts[state]
assert tts['TRANSLATE_CONTINUE_AFTER_STOP'] == 'Mình tiếp tục nhé.'
all_text = '\n'.join(map(text, after))
for forbidden in ['Đã dừng dịch tiếng Anh. Bạn muốn', 'Mình tiếp tục dịch tiếng Anh nhé.', 'MAIN hoặc AFTER_TRANSLATE_STOP', 'thoát dịch → AFTER_TRANSLATE_STOP', 'Chỉ thêm bốn nhóm', 'Thêm bốn intent']:
    assert forbidden not in all_text, forbidden
for tbl in revised.tables:
    assert tbl.rows[0]._tr.xpath('./w:trPr/w:tblHeader')
    assert all(row._tr.xpath('./w:trPr/w:cantSplit') for row in tbl.rows)
assert len(Table(after[128], revised).rows) == 24
print(f'PASS: all {len(after)} body blocks audited; all 35 translation cells match image 2; state/TTS/intent/QA cross-checks pass; unrelated text unchanged.')
