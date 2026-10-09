"""Surgical update of the supplied Master; preserve the original and formatting."""
import copy
import json
from pathlib import Path
import sys
from docx import Document
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from docx.table import Table, _Row
from docx.text.paragraph import Paragraph

sys.stdout.reconfigure(encoding='utf-8')
source, target = map(Path, sys.argv[1:3])
doc = Document(source)
blocks = list(doc.element.body)
changes = []

def put(paragraph, text):
    before = paragraph.text
    if before == text:
        return
    # Retain paragraph properties and the first run's original text style.
    template = copy.deepcopy(paragraph.runs[0]._r.rPr) if paragraph.runs and paragraph.runs[0]._r.rPr is not None else None
    paragraph.clear()
    run = paragraph.add_run(text)
    if template is not None:
        run._r.insert(0, template)
    changes.append({'before': before, 'after': text})

def paragraph(index, text):
    put(Paragraph(blocks[index], doc), text)

def table(index):
    return Table(blocks[index], doc)

def cell(row, column, text):
    dest = row.cells[column]
    for extra in dest.paragraphs[1:]:
        extra._p.getparent().remove(extra._p)
    put(dest.paragraphs[0], text)

def row_values(row, values):
    assert len(row.cells) == len(values)
    for i, value in enumerate(values):
        cell(row, i, value)

def insert_row_after(tbl, anchor, values):
    clone = copy.deepcopy(anchor._tr)
    anchor._tr.addnext(clone)
    row = _Row(clone, tbl)
    row_values(row, values)
    return row

menu = 'Bạn muốn tiếp tục dịch, học Chủ đề hay Bộ từ vựng?'
stop = 'Đã dừng.'
resume = 'Mình tiếp tục nhé.'

paragraph(1, 'FINAL GỬI IT\nChủ đề • Bộ từ vựng • Dịch tiếng Anh • Runtime và QA\nCập nhật luồng dừng dịch và nhấn MAIN ngày 16/09/2026')
paragraph(13, '☐ STOP có ưu tiên cao nhất trong activity. Ngoài dịch dùng STOP_GLOBAL để PAUSE, không SKIP/COMPLETE. Trong dịch chỉ STOP_TRANSLATE khớp chính xác “Dừng lại”; kết thúc phiên, tắt mic và chờ nhấn MAIN theo Mục 11.2.')
paragraph(17, '☐ NO_RESPONSE tại node đang chờ lựa chọn: nhắc lại một lần; lần hai vẫn im lặng thì “Mình tạm dừng nhé.” và lưu checkpoint. TRANSLATE_STOP không phải node chờ câu trả lời, nên không chạy bộ đếm này; no-response khi đang dịch theo Mục 11.2.')

map_table = table(20)
anchor = map_table.rows[1]
for values in [
    ['[SỬA] TRANSLATE_STOP', stop, 'Không nhận câu trả lời; chỉ chờ sự kiện nhấn MAIN', 'Kết thúc phiên dịch; không tự mở mic/menu.'],
    ['[MỚI] TRANSLATE_MAIN_AFTER_STOP', menu, 'CONTINUE_TRANSLATE / OPEN_SUBJECT / OPEN_VOCAB', 'Chỉ mở sau khi trẻ nhấn MAIN từ trạng thái đã dừng dịch.'],
    ['[SỬA] TRANSLATE_SWITCH_CONFIRM', menu, 'CONTINUE_TRANSLATE / OPEN_SUBJECT / OPEN_VOCAB', 'Mở khi trẻ yêu cầu học phần khác trong lúc dịch; không dịch câu điều hướng.'],
]:
    anchor = insert_row_after(map_table, anchor, values)

cell(table(25).rows[1], 0, 'Mọi activity trừ TRANSLATE_CONTINUOUS và trạng thái dịch đã dừng')
cell(table(25).rows[1], 2, 'PAUSE unit hiện tại, lưu checkpoint. Dịch dùng STOP_TRANSLATE riêng tại Mục 11.5; khi đã dừng không còn mic nhận lệnh.')
for index in (43, 46):
    cell(table(index).rows[1], 0, 'MAIN / TRANSLATE_MAIN_AFTER_STOP / TRANSLATE_SWITCH_CONFIRM')

# Resolve the existing S04/T09 contradiction without changing the learning flow.
s04 = table(82).rows[1]
cell(s04, 1, s04.cells[1].text.replace('; Học tiếp;', ';'))
cell(s04, 2, 'Mở đúng Bài kế đã unlock. Riêng câu “Học tiếp” tại LESSON_END là mơ hồ: hỏi lại theo T09, không tự chọn Bài kế.')

tts = table(103)
anchor = tts.rows[-1]
for values in [
    ['[SỬA]', 'TRANSLATE_STOP', stop, 'Chỉ thông báo; kết thúc phiên, không mở mic/menu.'],
    ['[MỚI]', 'TRANSLATE_MAIN_AFTER_STOP', menu, 'Chỉ phát khi nhấn MAIN sau dừng dịch.'],
    ['[SỬA]', 'TRANSLATE_CONTINUE_AFTER_STOP', resume, 'Sau lựa chọn tiếp tục; bắt đầu phiên dịch mới.'],
    ['[SỬA]', 'TRANSLATE_SWITCH_CONFIRM', menu, 'Ba lựa chọn, dùng mic điều hướng.'],
]:
    anchor = insert_row_after(tts, anchor, values)

deprecated = table(106)
insert_row_after(deprecated, deprecated.rows[-1], [
    'Tự mở AFTER_TRANSLATE_STOP ngay sau câu dừng dịch', '[LOẠI]',
    'Thay bằng TRANSLATE_STOP: “Đã dừng.”, kết thúc phiên và chờ MAIN. Chỉ khi nhấn MAIN mới vào TRANSLATE_MAIN_AFTER_STOP.'
])
paragraph(115, '☐ Ngoài dịch, STOP_GLOBAL ưu tiên hơn câu trả lời học/đáp án và chỉ PAUSE. Trong dịch, STOP_TRANSLATE kết thúc phiên và chờ nhấn MAIN; không chạy STOP_GLOBAL hoặc tự mở menu.')

qa = table(128)
anchor = qa.rows[-1]
for values in [
    ['T16', 'TRANSLATE_CONTINUOUS', '“Dừng lại”', 'STOP_TRANSLATE', 'Chỉ nói “Đã dừng.”; kết thúc phiên, mic dịch/mic lựa chọn đều tắt.'],
    ['T17', 'TRANSLATE_STOP chưa nhấn MAIN', '“Tiếp tục dịch” / wake-word / im lặng', 'Không nhận intent', 'Không mở mic/menu; không dịch câu mới, không tự chạy retry.'],
    ['T18', 'TRANSLATE_STOP', 'Nhấn MAIN', 'Sự kiện MAIN', 'Vào TRANSLATE_MAIN_AFTER_STOP; đọc đúng ba lựa chọn và mở mic điều hướng.'],
    ['T19', 'TRANSLATE_MAIN_AFTER_STOP', '“Tiếp tục dịch” / “Tiếp tục” / “Dịch tiếp” / “Dịch”', 'CONTINUE_TRANSLATE', 'Nói “Mình tiếp tục nhé.”; bắt đầu phiên dịch mới và reset lượt nghe.'],
    ['T20', 'TRANSLATE_MAIN_AFTER_STOP', '“Học Chủ đề” / “Học Bộ từ vựng”', 'OPEN_SUBJECT / OPEN_VOCAB', 'Bàn giao đúng module; không gửi câu chọn vào backend dịch.'],
    ['T21', 'TRANSLATE_CONTINUOUS', '“Mình muốn học phần khác”', 'LEAVE_TRANSLATE', 'Vào TRANSLATE_SWITCH_CONFIRM; hỏi đúng ba lựa chọn, không cần bấm MAIN ở nhánh này.'],
    ['T22', 'TRANSLATE_MAIN_AFTER_STOP / TRANSLATE_SWITCH_CONFIRM', 'Câu ngoài phạm vi; im lặng 2 lần', 'OUT_OF_SCOPE / NO_RESPONSE_PAUSE', 'Nhắc đúng ba lựa chọn; im lặng lần hai tạm dừng và lưu node lựa chọn.'],
    ['T23', 'TRANSLATE_CONTINUOUS', 'Im lặng/quá ngắn 2 lần', 'TRANSLATE_NO_RESPONSE_1/2', 'Lần một nhắc nói lại và mở mic dịch; lần hai tạm dừng/reset lượt, không tự mở menu sau dừng.'],
]:
    anchor = insert_row_after(qa, anchor, values)
paragraph(137, '☐ 23 test ở Mục 9 pass trên thiết bị thật, gồm dừng/resume, ASR không rõ và nhấn MAIN sau khi dừng dịch.')
paragraph(141, '[BỔ SUNG] Phần này quy định chi tiết dịch, lỗi/ASR và wake-word. Các bảng state, TTS, deprecated và QA tại Mục 1–10 đã được đồng bộ phần liên quan; quy tắc học Chủ đề và Bộ từ vựng giữ nguyên.')
for row in table(143).rows[1:]:
    if row.cells[0].text.startswith('Im lặng'):
        cell(row, 2, 'Bổ sung phần khác biệt tại 11.3.')
    elif row.cells[0].text.startswith('Wake-word'):
        cell(row, 2, 'Bổ sung tại 11.4; không đánh thức ở TRANSLATE_STOP đang chờ nhấn MAIN.')
    elif row.cells[0].text.startswith('Intent riêng'):
        cell(row, 2, 'Bổ sung tại 11.5; STOP_TRANSLATE chỉ có một câu khóa cứng.')
paragraph(146, '[SỬA] Dừng dịch kết thúc phiên ngay và chỉ thông báo “Đã dừng.”. Không mở menu hoặc mic tiếp theo. Sau đó trẻ phải nhấn MAIN để vào TRANSLATE_MAIN_AFTER_STOP; luồng này thay thế hoàn toàn hành vi tự mở AFTER_TRANSLATE_STOP trước đây.')

flow = table(147)
rows = {row.cells[0].text: row for row in flow.rows[1:]}
row_values(rows['TRANSLATE_STOP'], [
    'TRANSLATE_STOP', 'Trẻ nói chính xác “Dừng lại” khi đang dịch', stop,
    'Không cần trả lời.', 'Thoát vòng ghi âm dịch và kết thúc phiên. Muốn học tiếp, trẻ phải nhấn MAIN.'
])
insert_row_after(flow, rows['TRANSLATE_STOP'], [
    'TRANSLATE_MAIN_AFTER_STOP', 'Sau khi đã dừng dịch, trẻ nhấn MAIN', menu,
    'Tiếp tục dịch / Học Chủ đề / Học Bộ từ vựng',
    'Mở node lựa chọn và chờ đúng một trong ba câu trả lời.'
])
row_values(rows['TRANSLATE_CONTINUE_AFTER_STOP'], [
    'TRANSLATE_CONTINUE_AFTER_STOP', 'Trẻ chọn “Tiếp tục dịch” sau khi nhấn MAIN', resume,
    'Tiếp tục dịch / Tiếp tục / Dịch tiếp / Dịch',
    'Quay lại TRANSLATE_CONTINUOUS, mở mic và bắt đầu một phiên dịch mới.'
])
cell(rows['TRANSLATE_SWITCH_CONFIRM'], 2, menu)
cell(rows['TRANSLATE_SWITCH_CONFIRM'], 3, 'Tiếp tục dịch / Học Chủ đề / Học Bộ từ vựng')
paragraph(150, '[ĐÃ CHỐT] Trong Dịch tiếng Anh/Dịch liên tục, chỉ câu chính xác “Dừng lại” mới kích hoạt dừng. Chỉ chuẩn hóa chữ hoa/thường, khoảng trắng và dấu câu; giữ nguyên dấu tiếng Việt. Không dùng 27 biến thể còn lại của INT-018. STOP_TRANSLATE kết thúc phiên, tắt mic, nói “Đã dừng.” và chờ nhấn MAIN; không tự hỏi tiếp. Sau nhấn MAIN mới mở TRANSLATE_MAIN_AFTER_STOP. Ở các module khác, STOP_GLOBAL vẫn theo Mục 4.')

asr = table(154)
cell(asr.rows[2], 2, 'Lần hai nói “Mình tạm dừng nhé.”; pause phiên và reset lượt nghe theo 11.2.')
insert_row_after(asr, asr.rows[1], [
    'TRANSLATE_MAIN_AFTER_STOP / TRANSLATE_SWITCH_CONFIRM đang chờ', menu,
    'Mình tạm dừng nhé. → Pause và lưu WAITING_FOR_CHOICE.',
    'Chỉ chạy khi node lựa chọn đã mở; không chạy ở TRANSLATE_STOP đang chờ nhấn MAIN.'
])
wake = table(157)
cell(wake.rows[1], 2, 'Ngoài TRANSLATE_STOP đang chờ MAIN, mở MAIN và nhận OPEN_SUBJECT / OPEN_VOCAB / OPEN_TRANSLATE. Sau STOP_TRANSLATE chỉ nhấn MAIN mới mở menu.')
paragraph(159, '[CẤU HÌNH RUNTIME] WAKE_WORD chỉ được bật khi firmware/sản phẩm hỗ trợ đánh thức bằng giọng nói. Nếu bản phát hành chỉ dùng nút MAIN, tắt INT-022 và AI-069. Riêng sau STOP_TRANSLATE, không tự nghe wake-word; chỉ sự kiện nhấn MAIN mới mở TRANSLATE_MAIN_AFTER_STOP.')
paragraph(161, '[BỔ SUNG] Năm nhóm riêng cho dịch liên tục/wake-word. STOP_TRANSLATE chỉ có một câu khóa cứng, là ngoại lệ của yêu cầu ít nhất 5 mẫu. CONTINUE_TRANSLATE chỉ hợp lệ tại hai node lựa chọn đã mở; không nhận khi đang chờ nhấn MAIN.')
intents = table(162)
cell(intents.rows[1], 1, 'MAIN')
cell(intents.rows[3], 3, 'Exact match “Dừng lại” sau chuẩn hóa chữ hoa/thường, khoảng trắng và dấu câu, giữ dấu tiếng Việt. Thoát dịch → TRANSLATE_STOP; nói “Đã dừng.”, tắt mic và chờ nhấn MAIN, không tự mở node lựa chọn.')
cell(intents.rows[4], 1, 'Chỉ khi wake-word được bật; trừ TRANSLATE_STOP đang chờ nhấn MAIN')
insert_row_after(intents, intents.rows[-1], [
    'T05 CONTINUE_TRANSLATE', 'TRANSLATE_MAIN_AFTER_STOP / TRANSLATE_SWITCH_CONFIRM',
    'Tiếp tục dịch; Tiếp tục; Dịch tiếp; Dịch; Mình muốn dịch tiếp',
    'Nói “Mình tiếp tục nhé.”; vào TRANSLATE_CONTINUOUS với phiên mới và reset lượt nghe. Không xử lý trước khi nhấn MAIN sau STOP_TRANSLATE.'
])
paragraph(166, '☐ Thêm đủ intro, stop, main-after-stop, continue-after-stop, switch-confirm và hai cấp no-response theo 11.2.')
paragraph(168, '☐ Khóa cứng STOP_TRANSLATE: chỉ exact match “Dừng lại”; chỉ nói “Đã dừng.”, kết thúc phiên và tắt mic. Không mở menu/mic lựa chọn trước khi nhấn MAIN.')
paragraph(171, '☐ Cấu hình WAKE_WORD theo bản phát hành; sau STOP_TRANSLATE vẫn phải chờ nhấn MAIN, không tự nghe wake-word.')
paragraph(172, '☐ Thêm năm intent ở 11.5, gồm CONTINUE_TRANSLATE; loại mapping tự chuyển từ STOP_TRANSLATE sang AFTER_TRANSLATE_STOP. Chỉ sự kiện MAIN mở TRANSLATE_MAIN_AFTER_STOP.')
paragraph(173, '☐ Test T16–T23 ở Mục 9 trên thiết bị thật; kiểm tra không còn mic mở hoặc câu hỏi tự phát sau dừng. Chạy lại nhóm học/dịch liên quan nếu có thay đổi adapter bàn giao; không thay engine học/dịch vì cập nhật này.')

# Keep headings with table content and never split a record across pages.
for tbl in doc.tables:
    for row_index, row in enumerate(tbl.rows):
        for height in row._tr.xpath('./w:trPr/w:trHeight'):
            height.getparent().remove(height)
        if not row._tr.xpath('./w:trPr/w:cantSplit'):
            row._tr.get_or_add_trPr().append(OxmlElement('w:cantSplit'))
        for dest in row.cells:
            for p in dest.paragraphs:
                p.paragraph_format.keep_with_next = row_index == 0
            tc_pr = dest._tc.get_or_add_tcPr()
            borders = tc_pr.find(qn('w:tcBorders'))
            if borders is None:
                borders = OxmlElement('w:tcBorders')
                tc_pr.append(borders)
            for edge in ('top', 'bottom', 'left', 'right'):
                elem = borders.find(qn('w:' + edge))
                if elem is None:
                    elem = OxmlElement('w:' + edge)
                    borders.append(elem)
                for name, value in [('val', 'single'), ('sz', '4'), ('color', 'D9D9D9')]:
                    elem.set(qn('w:' + name), value)
            if row_index:
                shading = tc_pr.find(qn('w:shd'))
                if shading is None:
                    shading = OxmlElement('w:shd')
                    tc_pr.append(shading)
                shading.set(qn('w:fill'), 'FFFFFF' if row_index % 2 else 'F2F6FA')
    if not tbl.rows[0]._tr.xpath('./w:trPr/w:tblHeader'):
        tbl.rows[0]._tr.get_or_add_trPr().append(OxmlElement('w:tblHeader'))

# Remove the old title rule, and keep the revised seven-state table together
# below its heading on a fresh page. Section 11 can use the gap after section 10.
for root in [blocks[0], doc.styles['Title']._element]:
    for border in root.xpath('.//w:pBdr'):
        border.getparent().remove(border)
for index in (139, 140):
    for br in blocks[index].xpath('.//w:br[@w:type="page"]'):
        br.getparent().remove(br)
    if blocks[index].tag == qn('w:p'):
        Paragraph(blocks[index], doc).paragraph_format.page_break_before = False
Paragraph(blocks[145], doc).paragraph_format.page_break_before = True

target.parent.mkdir(parents=True, exist_ok=True)
doc.save(target)
Path(__file__).with_name('changes.json').write_text(json.dumps(changes, ensure_ascii=False, indent=2), encoding='utf-8')
updated = Document(target)
all_text = '\n'.join(''.join(t.text or '' for t in block.iter(qn('w:t'))) for block in updated.element.body)
assert 'Đã dừng dịch tiếng Anh. Bạn muốn' not in all_text
assert 'Mình tiếp tục dịch tiếng Anh nhé.' not in all_text
assert 'MAIN hoặc AFTER_TRANSLATE_STOP' not in all_text
assert 'thoát dịch → AFTER_TRANSLATE_STOP' not in all_text
assert 'TRANSLATE_MAIN_AFTER_STOP' in all_text
assert len(flow.rows) == 8
assert len(qa.rows) == 24
print(f'Saved {target}; {len(changes)} changed paragraphs/cells; 7 translation states; 23 QA scenarios.')
