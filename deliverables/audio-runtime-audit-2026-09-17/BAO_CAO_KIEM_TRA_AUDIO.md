# Kiểm tra audio HOMI — 17/09/2026

## Kết luận

Ứng dụng còn sử dụng TTS cũ. Có **66 câu cố định thiếu audio khớp nguyên văn** trong bộ kịch bản hiện tại. Bộ phát thật của Flutter đã rơi về native TTS ở cả 3 đường phát cho các câu này (198 lần). Có **3 câu khác nhau được ghi nhận trực tiếp trên điện thoại**, không chỉ suy luận từ tìm kiếm mã.

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

- 2026-09-17T20:57:53.054086: Bắt đầu Level 1. Có 3 Chủ đề. Bạn chọn Chủ đề số mấy? (25-review-playing-events.json)
- 2026-09-17T20:58:08.078071: Mình chưa hiểu. Có 3 Chủ đề. Bạn chọn Chủ đề số mấy? (25-review-playing-events.json)
- 2026-09-17T21:00:11.778793: Bạn muốn nghe lại, học câu tiếp theo, học câu trước hay dừng lại? (35-history-replay-events.json)

## Phạm vi kiểm thử tự động

- Domain hiện tại: 313 ngữ cảnh, 71774 chuyển trạng thái; thêm 35 ngữ cảnh MAIN do màn hình cung cấp. Độ sâu thăm dò hội thoại giới hạn 4; không phải chứng minh toàn bộ không gian trạng thái.
- Kho hiện tại: 2109 cặp câu/locale cố định, 2043 có audio khớp, 66 thiếu.
- Resolver: 2329 câu hiện tại/điều kiện × 3 đường (thường, đầu ra đang chọn, loa điện thoại) = 6987 lượt. Native channel và vận chuyển CDN được mock; dùng bộ phân giải/manifest thật.
- 3.077 URL tải thực từ mạng máy tính: 3077 HTTP 200, 3077 checksum khớp, không URL nào vượt 8 giây trong lượt thử. Không suy ra mạng điện thoại luôn tốt.
- 1.311 link trực tiếp trong nội dung học đều khớp transcript/locale khai báo. Checksum không thay thế việc nghe từng file.
- Bộ regression chọn lọc: 338 pass, 5 fail (2 kiểm tra UI từ vựng, 2 golden, 1 timeout test Back/Today). Không báo toàn bộ suite pass. Chi tiết: flow-tests.log.
- Test “không được fallback TTS” cố ý thất bại vì đã đo được 198 lần fallback. Đây là phát hiện cần xử lý, không phải file audio đã được sửa.

## Thiếu theo nhóm

| Nhóm | Số câu |
|---|---:|
| MAIN theo màn hình | 4 |
| Chọn Level / Chủ đề | 5 |
| Học lại Chủ đề đã hoàn thành | 20 |
| Không hiểu lệnh / menu / hoàn thành | 37 |

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

1. Bạn chọn một trong các lựa chọn trên màn hình nhé.
2. Bạn muốn nghe lại, học câu tiếp theo, học câu trước hay dừng lại? **[Đã xác nhận trên điện thoại]**
3. Bạn muốn nghe lại, nghe câu trước hay dừng lại?
4. Bạn muốn nghe lại, nghe câu trước, câu tiếp theo hay dừng lại?
5. Bắt đầu Level 1. Có 3 Chủ đề. Bạn chọn Chủ đề số mấy? **[Đã xác nhận trên điện thoại]**
6. Bắt đầu Level 2. Có 3 Chủ đề. Bạn chọn Chủ đề số mấy?
7. Bắt đầu Level 3. Có 4 Chủ đề. Bạn chọn Chủ đề số mấy?
8. Chủ đề 1 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 1?
9. Chủ đề 10 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 10?
10. Chủ đề 2 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 2?
11. Chủ đề 3 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 3?
12. Chủ đề 4 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 4?
13. Chủ đề 5 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 5?
14. Chủ đề 6 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 6?
15. Chủ đề 7 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 7?
16. Chủ đề 8 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 8?
17. Chủ đề 9 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 9?
18. Mình chưa hiểu.
19. Mình chưa hiểu. Bạn chọn một trong các lựa chọn trên màn hình nhé.
20. Mình chưa hiểu. Bạn chưa có Ngôi sao nào. Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?
21. Mình chưa hiểu. Bạn còn một Chủ đề chưa học. Bạn muốn học tiếp hay học lại?
22. Mình chưa hiểu. Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Level số mấy?
23. Mình chưa hiểu. Bạn đã nghe hết Ngôi sao rồi. Bạn muốn học nội dung khác hay học lại?
24. Mình chưa hiểu. Bạn đã nghe hết rồi. Bạn muốn học nội dung khác hay học lại?
25. Mình chưa hiểu. Bạn muốn bắt đầu Level 2 hay dừng lại?
26. Mình chưa hiểu. Bạn muốn bắt đầu Level 3 hay dừng lại?
27. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 1?
28. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 10?
29. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 2?
30. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 3?
31. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 4?
32. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 5?
33. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 6?
34. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 7?
35. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 8?
36. Mình chưa hiểu. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 9?
37. Mình chưa hiểu. Bạn muốn dịch sang tiếng Anh hay học bộ từ vựng?
38. Mình chưa hiểu. Bạn muốn học Bài 2 hay học lại Bài 1?
39. Mình chưa hiểu. Bạn muốn học Bài 3 hay học lại Bài 2?
40. Mình chưa hiểu. Bạn muốn học Ngôi sao hay Luyện lại?
41. Mình chưa hiểu. Bạn muốn học nội dung khác hay học lại?
42. Mình chưa hiểu. Bạn muốn học nội dung khác hay học tiếp?
43. Mình chưa hiểu. Bạn muốn học phần Ba mẹ đã thêm hay Luyện lại?
44. Mình chưa hiểu. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?
45. Mình chưa hiểu. Bạn muốn học phần Ba mẹ đã thêm, Ngôi sao hay Luyện lại?
46. Mình chưa hiểu. Bạn muốn nghe lại, học câu tiếp theo, học câu trước hay dừng lại?
47. Mình chưa hiểu. Bạn muốn nghe lại, học câu tiếp theo, học câu trước, hay dừng lại?
48. Mình chưa hiểu. Bạn muốn nghe lại, nghe câu trước hay dừng lại?
49. Mình chưa hiểu. Bạn muốn nghe lại, nghe câu trước, câu tiếp theo hay dừng lại?
50. Mình chưa hiểu. Bạn muốn tiếp tục dịch, học Chủ đề hay Bộ từ vựng?
51. Mình chưa hiểu. Chủ đề 1 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 1?
52. Mình chưa hiểu. Chủ đề 10 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 10?
53. Mình chưa hiểu. Chủ đề 2 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 2?
54. Mình chưa hiểu. Chủ đề 3 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 3?
55. Mình chưa hiểu. Chủ đề 4 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 4?
56. Mình chưa hiểu. Chủ đề 5 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 5?
57. Mình chưa hiểu. Chủ đề 6 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 6?
58. Mình chưa hiểu. Chủ đề 7 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 7?
59. Mình chưa hiểu. Chủ đề 8 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 8?
60. Mình chưa hiểu. Chủ đề 9 bạn đã học xong rồi. Bạn muốn chọn Chủ đề khác hay học lại Chủ đề 9?
61. Mình chưa hiểu. Chưa có nội dung ở phần này. Bạn muốn học Ngôi sao hay Luyện lại?
62. Mình chưa hiểu. Có 3 Chủ đề. Bạn chọn Chủ đề số mấy? **[Đã xác nhận trên điện thoại]**
63. Mình chưa hiểu. Có 4 Chủ đề. Bạn chọn Chủ đề số mấy?
64. Mình chưa hiểu. HOMI đây. Bạn muốn dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?
65. Mình chưa hiểu. Không có nội dung cần luyện lại. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?
66. Mình chưa hiểu. Mình đã luyện xong rồi. Bạn muốn học phần Ba mẹ đã thêm hay Ngôi sao?

## Bằng chứng có thể chạy lại

- missing-audio.csv / missing-audio.json: danh sách gọn, nhóm, câu đã thấy trên máy, ba đường TTS.
- phone-timeline.json và các *-events.json: log theo thời gian, SHA256 → id/text MP3.
- final-resolver-execution.json, final-resolver-test.log: kết quả chạy resolver.
- fresh-domain-audit.json, context-domain-audit.json: dữ liệu sinh từ code hiện tại.
- remote-audio-results.json: HTTP/checksum từng URL.
- slow-manifest-reproduction.json: kịch bản manifest chậm tái hiện độc lập.

Ưu tiên xử lý tiếp theo: bổ sung/ánh xạ các câu MAIN cố định theo từng nhóm, rồi chạy lại đúng bộ test này. TTS động và lỗi mạng cần chiến lược riêng; không thay logic học, ghi âm, chấm điểm hoặc lưu tiến độ.
