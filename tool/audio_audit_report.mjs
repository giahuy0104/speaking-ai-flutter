// Consolidates diagnostics already collected. No network, synthesis or app writes.
import {readFileSync,writeFileSync,readdirSync} from 'node:fs';
const dir='deliverables/audio-runtime-audit-2026-09-17';
const read=name=>JSON.parse(readFileSync(`${dir}/${name}`,'utf8'));
const summary=read('homi-speech-audit-summary.json');
const resolver=read('final-resolver-execution.json');
const remote=read('remote-audio-results.json').summary;
const prompts=['main_assistant_audio','curriculum_audio'].flatMap(n=>JSON.parse(readFileSync(`assets/data/${n}.json`,'utf8')).prompts);
const hashes=new Map(prompts.map(p=>[p.sha256,p]));
const all=new Map();
for(const file of readdirSync(dir).filter(n=>/\d.*-events\.json$/.test(n))) {
  for(const e of read(file)) {
    const key=[e.at,e.sequence,e.channel,e.event].join('|');
    const p=hashes.get(e.sha256);
    all.set(key,{...e,...(p?{id:p.id,text:p.text,locale:p.locale}:{}),evidence:file});
  }
}
const timeline=[...all.values()].sort((a,b)=>a.at.localeCompare(b.at));
const native=timeline.filter(e=>e.event==='request'&&e.source==='native_tts');
const nativeTexts=new Set(native.map(e=>e.text.trim()));
const group=text=>text.includes('Có 3 Chủ đề')||text.includes('Có 4 Chủ đề')?'Chọn Level / Chủ đề':
  /Chủ đề \d+ bạn đã học xong rồi/.test(text)?'Học lại Chủ đề đã hoàn thành':
  !text.startsWith('Mình chưa hiểu.')?'MAIN theo màn hình':'Không hiểu lệnh / menu / hoàn thành';
const missing=summary.currentMissing.map(r=>({...r,group:group(r.text),
  phoneConfirmed:nativeTexts.has(r.text),
  resolverRoutes:resolver.fallbacks.filter(x=>x.text===r.text&&x.locale===r.locale).map(x=>x.route)}));
const counts=Object.fromEntries([...new Set(missing.map(x=>x.group))].map(g=>[g,missing.filter(x=>x.group===g).length]));
const metrics={currentFixedTexts:summary.currentUniqueTextLocale,ready:summary.currentReady,
  missing:missing.length,resolverUtterances:resolver.utterances,resolverExecutions:resolver.executions,
  resolverTtsExecutions:resolver.fallbacks.length,phoneNativeCalls:native.length,
  phoneNativeDistinct:nativeTexts.size,groups:counts,remote};
writeFileSync(`${dir}/phone-timeline.json`,JSON.stringify(timeline,null,2));
writeFileSync(`${dir}/missing-audio.json`,JSON.stringify({metrics,missing},null,2));
const csv=v=>`"${String(v??'').replaceAll('"','""')}"`;
writeFileSync(`${dir}/missing-audio.csv`,'\uFEFF'+[
  ['nhom','cau_thieu_audio','locale','xac_nhan_tren_dien_thoai','duong_phat_TTS','nguon'],
  ...missing.map(x=>[x.group,x.text,x.locale,x.phoneConfirmed?'Có':'Chưa',x.resolverRoutes.join(';'),
    [...new Set(x.evidence.map(e=>e.source))].join(';')]),
].map(r=>r.map(csv).join(',')).join('\r\n'));
const phoneList=native.map(e=>`- ${e.at}: ${e.text} (${e.evidence})`).join('\n');
const groupsTable=Object.entries(counts).map(([g,n])=>`| ${g} | ${n} |`).join('\n');
const allMissing=missing.map((r,i)=>`${i+1}. ${r.text}${r.phoneConfirmed?' **[Đã xác nhận trên điện thoại]**':''}`).join('\n');
const report=`# Kiểm tra audio HOMI — 17/09/2026

## Kết luận

Ứng dụng còn sử dụng TTS cũ. Có **${missing.length} câu cố định thiếu audio khớp nguyên văn** trong bộ kịch bản hiện tại. Bộ phát thật của Flutter đã rơi về native TTS ở cả 3 đường phát cho các câu này (${resolver.fallbacks.length} lần). Có **${nativeTexts.size} câu khác nhau được ghi nhận trực tiếp trên điện thoại**, không chỉ suy luận từ tìm kiếm mã.

Không thể tuyên bố đã bấm hết mọi nhánh của 109 bài trên điện thoại. Báo cáo tách rõ: thao tác thật, thực thi domain/resolver có mock I/O, và đọc mã. 66 là số tìm được trong phạm vi kịch bản, không phải chứng minh không còn câu thiếu nào khác.

## Đã thử từng bước trên điện thoại

| Bước | Thao tác | Quan sát nguồn audio |
|---|---|---|
| 1 | Mở Chủ đề, vào chọn Level 1 | TTS: “Bắt đầu Level 1. Có 3 Chủ đề. Bạn chọn Chủ đề số mấy?” |
| 2 | Chờ nhánh không hiểu ở chọn Chủ đề | TTS: “Mình chưa hiểu. Có 3 Chủ đề. Bạn chọn Chủ đề số mấy?” |
| 3 | Tiếp tục Chủ đề 1 / Alphabet | Lời dẫn tiếp tục dùng MP3 |
| 4 | Học mẫu J. Juice., nghĩa tiếng Việt, chuyển K. Kite. | Audio mẫu dùng URI/cache; lời nhắc dùng MP3 |
| 5 | Chờ lượt ghi âm / thử lại và nghe bản ghi | MP3 nhắc nói lại; bản ghi người dùng là WAV, không tính là TTS trợ lý |
| 6 | Gọi MAIN trong bài học | TTS: “Bạn muốn nghe lại, học câu tiếp theo, học câu trước hay dừng lại?” |
| 7 | Ôn lại bài Alphabet 1, A. Apple. | Mẫu EN/VI dùng URI/cache; không thấy native TTS ở đoạn mẫu |
| 8 | Mở Từ vựng, Ba mẹ đã thêm | Danh sách hiện có 0 mục; không thể xác minh phát nội dung phụ huynh bằng dữ liệu hiện có |
| 9 | Ngôi sao, Bắt đầu nghe / nút nghe | Xác nhận lời tiếp tục là MP3; chưa đủ log kết luận toàn bộ vòng nghe 6 mục đã hoàn tất |
| 10 | Luyện lại, Bắt đầu luyện | MP3 cho lời mở đầu, “B. Ball.”, “Quả bóng.”, “Bạn nói lại nhé.”; đi tới lượt mic |
| 11 | Trang chủ, Bắt đầu nói, nhận kết quả dịch | Log thấy phát URI /api/audio/stream của backend; chưa xác minh provider/model phía backend |
| 12 | Phát lại tiếng Anh, mở Lịch sử và phát lại | Xem snapshot/log 31–35; đây là audio kết quả backend/cache, không chứng minh Eleven v3 |

Trong lúc thử mic, hệ thống nhận lại một phần lời nhắc từ môi trường rồi dịch và lưu một lượt thử. Test thực tế cũng có thể tạo bản ghi/lưu vị trí học theo hành vi bình thường. Không xóa dữ liệu, không giả lập hoàn thành bài, không sửa logic lưu tiến độ.

### Native TTS ghi nhận trực tiếp

${phoneList}

## Phạm vi kiểm thử tự động

- Domain hiện tại: ${summary.domainScenarios} ngữ cảnh, ${summary.domainTransitions} chuyển trạng thái; thêm 35 ngữ cảnh MAIN do màn hình cung cấp. Độ sâu thăm dò hội thoại giới hạn 4; không phải chứng minh toàn bộ không gian trạng thái.
- Kho hiện tại: ${summary.currentUniqueTextLocale} cặp câu/locale cố định, ${summary.currentReady} có audio khớp, ${missing.length} thiếu.
- Resolver: ${resolver.utterances} câu hiện tại/điều kiện × 3 đường (thường, đầu ra đang chọn, loa điện thoại) = ${resolver.executions} lượt. Native channel và vận chuyển CDN được mock; dùng bộ phân giải/manifest thật.
- 3.077 URL tải thực từ mạng máy tính: ${remote.http200} HTTP 200, ${remote.checksumVerified} checksum khớp, không URL nào vượt 8 giây trong lượt thử. Không suy ra mạng điện thoại luôn tốt.
- 1.311 link trực tiếp trong nội dung học đều khớp transcript/locale khai báo. Checksum không thay thế việc nghe từng file.
- Bộ regression chọn lọc: 338 pass, 5 fail (2 kiểm tra UI từ vựng, 2 golden, 1 timeout test Back/Today). Không báo toàn bộ suite pass. Chi tiết: flow-tests.log.
- Test “không được fallback TTS” cố ý thất bại vì đã đo được ${resolver.fallbacks.length} lần fallback. Đây là phát hiện cần xử lý, không phải file audio đã được sửa.

## Thiếu theo nhóm

| Nhóm | Số câu |
|---|---:|
${groupsTable}

## Nguyên nhân

1. Câu trong code hiện tại khác câu đã tạo: “Bạn chọn Chủ đề…” so với “Bạn muốn học Chủ đề…”. Resolver chỉ trim đầu/cuối rồi khớp đúng chuỗi/alias và locale; dấu phẩy khác cũng làm trượt.
2. MAIN lấy mainVoicePrompt từ màn hình bài học/từ vựng, khác lời nhắc mặc định của MainVoiceAssistantFlow. Bộ audit cũ chỉ truyền kind, không truyền voiceContext nên bỏ sót.
3. Nhánh không hiểu nối “Mình chưa hiểu. ” với câu menu động (main_voice_assistant_flow.dart:1489). Câu gốc có MP3 không đồng nghĩa câu ghép có MP3.
4. Báo cáo cũ dùng dữ liệu domain cũ. Script domain còn truyền tham số không còn tương thích với LessonGuideFlowV2 nên không chạy lại được. Đã sửa riêng công cụ kiểm tra, không sửa luồng ứng dụng.
5. Một rủi ro độc lập đã tái hiện: lần nạp manifest đầu mất 650 ms, quá ngưỡng 500 ms, lỗi được giữ trong Future cache; lần tiếp theo vẫn TTS dù storage đã nhanh. Trên điện thoại lần này manifest nạp 0–15 ms, nên chưa có bằng chứng đây là nguyên nhân của các câu thiếu ghi nhận.

## TTS động vẫn tồn tại ngoài 66 câu

- Dịch offline Android: conversation_controller.dart:3724 gọi speakAndWaitStyled; wrapper chuyển trực tiếp tới native TTS. Chưa thực hiện end-to-end offline trên điện thoại trong lượt này.
- Nội dung phụ huynh nhập: vocabulary_audio_service.dart:64 ưu tiên dịch vụ dictionary /api/v1/tts và cache; khi lỗi/timeout 3 giây, gọi fallback. Áp dụng cả khi nội dung đó xuất hiện ở Today/Luyện lại/Ngôi sao. Danh sách phụ huynh trên điện thoại hiện rỗng; kết luận này từ code/test, không phải phát mẫu thực tế.
- Dịch online/lịch sử: phát audio backend/trước đó. Frontend không xác nhận backend đã dùng Eleven v3; không gộp thành audio Eleven chỉ vì đuôi MP3.
- Fallback khi tắt nhóm audio, mạng lỗi, checksum lỗi, timeout hoặc phát thất bại vẫn còn theo thiết kế quay lại TTS cũ. Không nên loại bỏ fallback chỉ để tránh nghe giọng cũ.

## Giới hạn và thay đổi trong lượt này

- Không tự đọc API key, không gọi ElevenLabs, không tạo audio và không sửa code production.
- Chỉ bổ sung/sửa công cụ chẩn đoán ở tool/ và bằng chứng trong thư mục này. Bản APK chẩn đoán ghi nguồn phát, không thay đổi câu thoại hay logic học/ghi âm/chấm điểm.
- Chưa đi hết 109 bài trên điện thoại, chưa kiểm tra vật lý mọi nhánh Challenge/Song/hoàn tất khóa học, mọi lệnh qua BLE/thiết bị ngoài, iOS/web, mạng mất và nội dung phụ huynh tự nhập. Các phần này có mức bằng chứng thấp hơn đã ghi rõ.
- 456 câu thuộc compatibility/luồng cũ thiếu trong audit tĩnh được để riêng, không cộng vào 66 câu của kịch bản hiện tại.
- Việc khôi phục APK gốc được ghi riêng trong restore-result.txt; chỉ kết luận đã khôi phục nếu tệp đó xác nhận install Success và checksum APK gốc.

## Danh sách câu cần bổ sung hoặc ánh xạ audio

${allMissing}

## Bằng chứng có thể chạy lại

- missing-audio.csv / missing-audio.json: danh sách gọn, nhóm, câu đã thấy trên máy, ba đường TTS.
- phone-timeline.json và các *-events.json: log theo thời gian, SHA256 → id/text MP3.
- final-resolver-execution.json, final-resolver-test.log: kết quả chạy resolver.
- fresh-domain-audit.json, context-domain-audit.json: dữ liệu sinh từ code hiện tại.
- remote-audio-results.json: HTTP/checksum từng URL.
- slow-manifest-reproduction.json: kịch bản manifest chậm tái hiện độc lập.

Ưu tiên xử lý tiếp theo: bổ sung/ánh xạ các câu MAIN cố định theo từng nhóm, rồi chạy lại đúng bộ test này. TTS động và lỗi mạng cần chiến lược riêng; không thay logic học, ghi âm, chấm điểm hoặc lưu tiến độ.
`;
writeFileSync(`${dir}/BAO_CAO_KIEM_TRA_AUDIO.md`,report);
console.log(JSON.stringify(metrics,null,2));
