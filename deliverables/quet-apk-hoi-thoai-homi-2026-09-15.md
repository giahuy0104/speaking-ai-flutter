# Báo cáo quét hội thoại APK HOMI

- APK mới nhất: `HOMI-1.0.8-production-legal.apk`
- Đường dẫn đã quét trực tiếp: `D:\Documents\ai-speaking-flutter-app\deliverables\HOMI-1.0.8-production-legal.apk`
- Kích thước: 159.91 MB
- Thời điểm APK: 2026-09-15 12:39:02
- Thời điểm quét lại từ APK mới nhất: 2026-09-15 15:54:12 +07:00
- SHA-256: `FEB618A659CD8B137BB47BC59EEC6E39F0C25771178576BFF939A84598D091F6`
- Bản `build/app/outputs/flutter-apk/app-release.apk` có cùng SHA-256, tức là giống hệt bản phát hành này theo từng byte.

## Kết quả nhanh

- 68 câu/khung câu HOMI trong kho hội thoại điều hướng.
- 500 mẫu câu người dùng, thuộc 21 nhóm ý định.
- 9 tình huống im lặng/không rõ và 8 chính sách ngoài phạm vi.
- Kho bài học riêng có 2435 mục âm thanh, 2156 nội dung chữ duy nhất, 109 bài, 601 câu luyện nói và 601 câu hỏi lựa chọn.
- Hai mã không xuất hiện trong chuỗi ID: `AI-021` và `AI-065`. Phần tổng quan trong catalog ghi 69 câu nhưng mảng thực tế chỉ có 68 câu.
- Các biến `{số chủ đề}`, `{số bài}`, `{tên bài}`… được thay bằng dữ liệu thật khi chạy.
- Báo cáo đã bỏ phân loại biên tập khỏi danh sách phản hồi. Các câu được trình bày chung theo từng ý định runtime để tránh gây hiểu nhầm.

## Đính chính quan trọng: dịch liên tục

### Câu HOMI thực sự phát khi bắt đầu

Runtime hiện tại ghép `AI-020` và `AI-022` thành **một lượt nói liên tục**:

> Mình cùng dịch sang tiếng Anh nha. Bạn cứ nói từng câu. Muốn dừng thì nói “dừng lại”.

Câu cũ vẫn được lưu trong trường đối chiếu `Câu gốc trong code` của catalog APK:

> Con nói từng câu nhé. Muốn dừng thì nói dừng lại.

Vì vậy báo cáo trước đã thiếu ngữ cảnh khi tách hai nửa câu thành hai hàng độc lập. Nếu thiết bị đang phát câu bắt đầu bằng “Con nói…”, thiết bị đó đang chạy lời thoại cũ; APK có SHA-256 ghi ở đầu báo cáo dùng câu mới bắt đầu bằng “Mình cùng dịch… Bạn cứ nói…”.

### Câu nào thật sự làm dừng

- Câu nên dùng, đúng với hướng dẫn TTS: **“Dừng lại”**.
- Tuy nhiên runtime của APK hiện tại không giới hạn ở đúng một câu. Trong lúc dịch liên tục, resolver so khớp **toàn bộ câu nói** với cả `INT-018` và `INT-001`; nếu khớp thì thoát phiên dịch.
- Riêng `INT-018` có 28 mẫu và cả 28 mẫu hiện đều được sinh vào map runtime.
- Các câu thuộc `INT-017`, ví dụ “Mình muốn học cái khác”, không dừng ngay như lệnh dừng. Chúng mở bước xác nhận chuyển sang hoạt động học khác.
- Nếu yêu cầu sản phẩm là **chỉ câu “Dừng lại” mới được dừng**, thì implementation hiện tại đang rộng hơn yêu cầu và cần thu hẹp resolver. Báo cáo này chỉ ghi nhận, chưa thay đổi code ứng dụng.

## Bản đồ HOMI nói → mình có thể trả lời

| ID | Ngữ cảnh | HOMI nói | Mình có thể trả lời/hành động |
|---|---|---|---|
| AI-001 | MAIN / Điều hướng gốc — Chọn chức năng | HOMI đây. Bạn muốn dịch sang tiếng Anh, học theo chủ đề hay học bộ từ vựng? | “Học theo chủ đề” / “Học từ mới” / “Dịch sang tiếng Anh” |
| AI-002 | MAIN / Im lặng — Không có tiếng nói lần 1 | Bạn có thể chọn: dịch sang tiếng Anh, học theo chủ đề hoặc học bộ từ vựng | “Học theo chủ đề” / “Học từ mới” / “Dịch sang tiếng Anh” |
| AI-003 | MAIN / Im lặng — Không có tiếng nói lần 2 | Khi sẵn sàng, bạn nhấn nút gọi HOMI nhé. | Không cần trả lời; khi muốn dùng lại, nhấn MAIN hoặc gọi “HOMI ơi”. |
| AI-004 | MAIN / Đổi hoạt động — Rời bài học | Được thôi. Bạn muốn dịch sang tiếng Anh, học theo chủ đề hay học bộ từ vựng? | “Học theo chủ đề” / “Học từ mới” / “Dịch sang tiếng Anh” |
| AI-005 | Luyện nghe / MAIN — Điều hướng trong bài | Bạn muốn nghe lại, học câu tiếp theo, học câu trước, hay dừng lại? | “Nghe lại” / “Câu tiếp theo” / “Câu trước” / “Dừng lại” |
| AI-006 | Luyện nghe / Rời bài — Chọn hoạt động thay thế | Bạn muốn dịch sang tiếng Anh hay học bộ từ vựng? | “Dịch sang tiếng Anh” / “Học từ mới” |
| AI-007 | Chủ đề — Hỏi tuổi | Bạn mấy tuổi? | Nói tuổi, ví dụ “6 tuổi” hoặc “Mình 6 tuổi”. |
| AI-008 | Chủ đề — Hỏi lại tuổi | Bạn mấy tuổi? Ví dụ bạn nói: 6 tuổi. | Nói tuổi, ví dụ “6 tuổi” hoặc “Mình 6 tuổi”. |
| AI-009 | Chủ đề — Tuổi ngoài phạm vi | HOMI có bài học cho các bạn từ {tuổi nhỏ nhất} đến {tuổi lớn nhất} tuổi. Bạn mấy tuổi? | Nói lại một tuổi hợp lệ, ví dụ “6 tuổi”. |
| AI-010 | Chủ đề — Chọn chủ đề | Có {số chủ đề} chủ đề. Bạn muốn học chủ đề số mấy? | Nói số chủ đề, ví dụ “Chủ đề số 3” hoặc “Mình chọn số 3”. |
| AI-011 | Chủ đề — Chủ đề không hợp lệ | Có {số chủ đề} chủ đề. Bạn chọn từ số 1 đến số {số chủ đề}. | Nói lại số trong khoảng HOMI vừa nêu, ví dụ “Chủ đề số 2”. |
| AI-012 | Chủ đề — Chủ đề trống | Chủ đề này chưa có bài học. Bạn chọn chủ đề khác nha. | Chọn chủ đề khác, ví dụ “Chủ đề số 2”. |
| AI-013 | Chủ đề — Chọn bài | Có {số bài} bài học. Bạn muốn học bài số mấy? | Nói số bài, ví dụ “Bài số 1” hoặc “Mình chọn bài thứ 1”. |
| AI-014 | Chủ đề — Bài không hợp lệ | Có {số bài} bài học. Bạn chọn từ số 1 đến số {số bài}. | Nói lại số trong khoảng HOMI vừa nêu, ví dụ “Bài số 1”. |
| AI-015 | Chủ đề — Xác nhận học lại | Bạn đã học chủ đề số {số chủ đề} rồi. Bạn muốn học lại không? | “Có” / “Không” |
| AI-016 | Chủ đề — Xác nhận chưa hợp lệ | Bạn muốn học lại chủ đề số {số chủ đề} không? Nói “có” hoặc “không”. | “Có” / “Không” |
| AI-017 | Chủ đề — Bắt đầu bài | Mình bắt đầu học thôi. | Không cần trả lời ngay; nghe mẫu rồi lặp lại câu tiếng Anh của bài. |
| AI-018 | Chủ đề / Lỗi — Không tải được bài | HOMI chưa tải được bài học. Bạn thử lại sau. | Không có câu trả lời cố định; thử lại sau hoặc nhấn MAIN. |
| AI-019 | Chủ đề / Lỗi — Mất trạng thái chủ đề | HOMI chưa chọn được chủ đề. Bạn thử lại. | Không có câu trả lời cố định; mở lại danh sách/chọn lại chủ đề. |
| AI-020 | Dịch tiếng Anh — Mở đầu dịch liên tục | Mình cùng dịch sang tiếng Anh nha. | Không chờ phản hồi riêng; HOMI nói tiếp ngay phần `AI-022`. |
| AI-022 | Dịch liên tục — Hướng dẫn thao tác | Câu runtime đầy đủ: “Mình cùng dịch sang tiếng Anh nha. Bạn cứ nói từng câu. Muốn dừng thì nói ‘dừng lại’.” Câu gốc/legacy: “Con nói từng câu nhé. Muốn dừng thì nói dừng lại.” | Nói câu tiếng Việt cần dịch. Cách dừng được hướng dẫn và nên dùng: “Dừng lại”. Runtime hiện còn nhận thêm các mẫu `INT-018`/`INT-001`. |
| RUNTIME-CT-AFTER-STOP | Dịch liên tục — Sau khi dừng | Con muốn học chủ đề, học bộ từ vựng hay dừng lại? | “Học chủ đề” / “Học bộ từ vựng” / “Dừng lại”. |
| AI-023 | Dịch liên tục / Im lặng — Không có tiếng lần 1 | HOMI chưa nghe thấy bạn nói. Bạn nói lại đi. | Nói lại câu tiếng Việt cần dịch, rõ và gần micro hơn. |
| AI-024 | Dịch liên tục / Im lặng — Không có tiếng lần 2 | Mình dừng ở đây. Khi cần, bạn nhấn nút gọi HOMI. | Không cần trả lời; nhấn MAIN khi muốn bắt đầu lại. |
| AI-025 | Dịch / Không rõ — ASR không có kết quả | HOMI chưa nghe thấy bạn nói. Bạn nói lại đi. | Nói lại câu vừa nói. |
| AI-026 | Dịch / Tiếng ồn — Môi trường ồn | Ở đây hơi ồn. Bạn đưa micro lại gần, tránh hướng quạt hoặc chuyển sang chỗ yên hơn rồi thử lại nhé. | Đưa micro gần hơn/chuyển chỗ yên rồi nói lại. |
| AI-027 | Dịch / Lỗi kỹ thuật — Web Batch không có transcript | HOMI chưa nghe rõ. Bạn thử nói lại nhé. | Nói lại câu vừa nói. |
| AI-028 | Từ vựng — Không tải được dữ liệu | HOMI chưa tải được từ vựng. Bạn thử lại sau nha. | Không có câu trả lời cố định; thử lại sau. |
| AI-029 | Từ vựng — Chọn bộ từ | Bạn muốn luyện tập lại hay xem bộ sưu tập ngôi sao? | “Luyện lại” / “Ngôi sao của mình” |
| AI-030 | Từ vựng — Mở bộ từ mới | Có từ mới rồi. Mình cùng học nha. | Không cần trả lời; nghe nội dung từ mới. |
| AI-031 | Từ vựng — Đọc từng mục | {từ tiếng Anh} → {nghĩa tiếng Việt} | Không bắt buộc trả lời; có thể nghe hoặc lặp lại từ tiếng Anh. |
| AI-032 | Từ vựng — Chuyển bộ từ | Mình qua phần luyện lại và ngôi sao nha. | Không cần trả lời; ứng dụng tự chuyển phần. |
| AI-033 | Từ vựng — Tiêu đề bộ luyện lại | Phần luyện lại. | Không cần trả lời; nghe phần luyện lại. |
| AI-034 | Từ vựng — Bộ luyện lại trống | Phần luyện lại chưa có từ nào. | Không cần trả lời. |
| AI-035 | Từ vựng — Tiêu đề bộ ngôi sao | Bộ sưu tập ngôi sao. | Không cần trả lời; nghe bộ ngôi sao. |
| AI-036 | Từ vựng — Bộ ngôi sao trống | Bộ sưu tập ngôi sao chưa có từ nào. | Không cần trả lời. |
| AI-037 | Từ vựng — Kết thúc | Mình đã học xong bộ từ vựng hôm nay rồi. | Không cần trả lời; có thể nhấn MAIN để chọn hoạt động khác. |
| AI-038 | Luyện nghe / MAIN — Tiếp tục | Mình học tiếp thôi. | Không cần trả lời; đây là câu xác nhận thao tác. |
| AI-039 | Luyện nghe / MAIN — Nghe lại hiện tại | Mình nghe lại câu này nhé. | Không cần trả lời; đây là câu xác nhận thao tác. |
| AI-040 | Luyện nghe / MAIN — Câu tiếp theo | Mình học câu tiếp theo thôi. | Không cần trả lời; đây là câu xác nhận thao tác. |
| AI-041 | Luyện nghe / MAIN — Câu trước | Mình quay lại câu trước nha. | Không cần trả lời; đây là câu xác nhận thao tác. |
| AI-042 | Luyện nghe / MAIN — Bài tiếp theo | Mình chuyển sang bài tiếp theo nào. | Không cần trả lời; đây là câu xác nhận thao tác. |
| AI-043 | Luyện nghe / MAIN — Bài trước | Mình quay lại bài trước nhé. | Không cần trả lời; đây là câu xác nhận thao tác. |
| AI-044 | Luyện nghe / MAIN — Học lại từ đầu | Mình học lại bài này từ đầu nha. | Không cần trả lời; đây là câu xác nhận thao tác. |
| AI-045 | MAIN / Dừng — Dừng hoạt động | Đã dừng. | Không cần trả lời; hoạt động đã dừng. |
| AI-046 | Luyện nghe / MAIN — Kết thúc bài | Mình kết thúc bài học ở đây nhé. | Không cần trả lời; bài học đã kết thúc. |
| AI-047 | Luyện nghe / Hướng dẫn — Bắt đầu luyện câu | Nghe HOMI trước, rồi bạn nói lại sau nha. | Chờ nghe mẫu, sau đó lặp lại câu tiếng Anh. |
| AI-048 | Luyện nghe / Hướng dẫn — Mời trẻ nói | Đến lượt bạn. Bạn nói lại đi. | Lặp lại đúng câu tiếng Anh vừa nghe. |
| AI-049 | Luyện nghe / Hoàn tất — Chọn sau bài | Bạn chọn “Luyện lại từ đầu” hay “Bài tiếp theo”? | “Học lại từ đầu” / “Bài tiếp theo” |
| AI-050 | Luyện nghe / Hoàn tất — Không hiểu lựa chọn | Bạn nói lại lựa chọn đi. | “Học lại từ đầu” / “Bài tiếp theo” |
| AI-051 | Luyện nghe / Hoàn tất — Hết chủ đề | Bạn đã học xong chủ đề này rồi. Chọn chủ đề mới nha. | Chọn chủ đề mới, ví dụ “Chủ đề số 2”. |
| AI-052 | Luyện nghe / Đánh giá — Phát âm đạt | Bạn làm tốt lắm. HOMI đã thêm câu này vào ngôi sao! | Không cần trả lời; đây là phản hồi đạt. |
| AI-053 | Luyện nghe / Không rõ — Không nghe rõ | HOMI chưa nghe rõ. Bạn nói lại đi. | Lặp lại câu tiếng Anh đang luyện. |
| AI-054 | Luyện nghe / Sai phạm vi — Câu ngoài nội dung | Bạn tập trung nhé. Mình quay lại câu đang học nào. | Quay lại và lặp câu tiếng Anh đang học. |
| AI-055 | Luyện nghe / Chuyển câu — Bỏ qua câu | Mình qua câu khác nha! | Không cần trả lời; ứng dụng tự chuyển câu. |
| AI-056 | Luyện nghe / Sửa phát âm — Gần đạt | Gần được rồi! Bạn nghe lại câu này nhé. | Nghe lại câu mẫu. |
| AI-057 | Luyện nghe / Sửa phát âm — Thử lần nữa | Bây giờ bạn thử nói lại lần nữa nè. | Lặp lại câu tiếng Anh thêm một lần. |
| AI-058 | Luyện nghe / Sửa phát âm — Chuyển sau nhiều lần | Bạn đã cố gắng tốt rồi! Mình sẽ luyện thêm sau. Giờ học câu tiếp nào. | Không cần trả lời; ứng dụng tự chuyển câu. |
| AI-059 | Luyện nghe / Mở bài — Lần đầu | Chào bạn! Mình là HOMI. Hôm nay mình học bài “{tên bài}”. Bạn nghe HOMI trước rồi nói lại. Muốn nghe lại hoặc dừng thì bấm nút MAIN. | Nghe HOMI, rồi lặp lại câu tiếng Anh; MAIN mở các lệnh điều hướng. |
| AI-060 | Luyện nghe / Mở bài — Bài mới | Hôm nay mình học bài “{tên bài}”. Bắt đầu thôi! | Không cần trả lời ngay; bắt đầu nghe bài. |
| AI-061 | Luyện nghe / Tiếp tục — Resume | Mình học tiếp bài “{tên bài}”. Bắt đầu từ chỗ lúc trước. | Không cần trả lời ngay; bài tiếp tục từ tiến độ cũ. |
| AI-062 | Luyện nghe / Kết bài — Hoàn tất bài | Giỏi lắm! Bạn đã học xong bài “{tên bài}”. Bạn muốn luyện lại từ đầu hay học bài tiếp theo? | “Học lại từ đầu” / “Bài tiếp theo” |
| AI-063 | Luyện nghe / Biên — Đang ở câu đầu | Bạn đang ở câu đầu tiên rồi. | Không cần trả lời; chọn “Câu tiếp theo” hoặc “Nghe lại”. |
| AI-064 | Luyện nghe / Biên — Đang ở bài đầu | Bạn đang ở bài đầu tiên rồi. | Không cần trả lời; chọn “Bài tiếp theo” hoặc tiếp tục bài hiện tại. |
| AI-066 | Luyện nghe / Tổng kết — Không có mục trước | Đây là phần tổng kết của bài học rồi. | Không cần trả lời; đây là thông báo vị trí hiện tại. |
| AI-067 | Luyện nghe / Tổng kết — Không có bài tiếp | HOMI chưa có bài tiếp theo. | Không cần trả lời; có thể chọn chủ đề/bài khác. |
| AI-068 | Bài hát — Lệnh không khả dụng | Mình học xong bài hát này trước rồi chuyển phần khác. | Không cần trả lời; chờ bài hát kết thúc. |
| AI-069 | Wake-word cũ — Xác nhận đánh thức | HOMI nghe đây. | Sau xác nhận, nói yêu cầu như “Học theo chủ đề”, “Học từ mới” hoặc “Dịch tiếng Anh”. |
| AI-070 | Lỗi thao tác — Module bận/lỗi | HOMI chưa thực hiện được. Bạn thử lại. | Nói lại yêu cầu hoặc nói “Giúp mình với”. |

## Toàn bộ 500 mẫu câu người dùng trong APK

Các câu dưới đây được nhóm theo ý định và trạng thái. Mẫu có `[số]` nhận giá trị số phù hợp với màn hình hiện tại.

### INT-001 — Dừng toàn cục

- Khi dùng: Mọi module
- Câu chuẩn: 
- Kết quả: Dừng/pause hoạt động hiện tại
- Số mẫu: 27
- Các câu runtime nhận: “Dừng lại”; “Dừng”; “Thôi”; “Không học nữa”; “Tạm dừng”; “Stop”; “Dừng đi”; “Thôi nha”; “Không muốn nữa”; “Mình không thích”; “Im lặng”; “Mình muốn nghỉ”; “Mình muốn dừng”; “Mình nghỉ một chút”; “Dừng giúp mình”; “Thôi mình nghỉ”; “Mình không muốn học nữa đâu”; “Nghỉ tí đi”; “Cho mình nghỉ đi”; “Mình nghỉ nha”; “Mình hông muốn học nữa”; “Mình hổng muốn học nữa”; “Thôi, mình nghỉ nghen”; “Mình nghỉ đây”; “Cho mình dừng một chút”; “Mình muốn tạm nghỉ”; “Thôi, dừng ở đây nha”

### INT-002 — Học chủ đề

- Khi dùng: Chọn chức năng
- Câu chuẩn: 
- Kết quả: Vào luồng chọn tuổi/chủ đề
- Số mẫu: 27
- Các câu runtime nhận: “Học theo chủ đề”; “Bắt đầu học”; “Mình muốn học”; “Học chủ đề”; “Học tình huống”; “Mình muốn học theo Chủ đề”; “Học đi”; “Mình học”; “Học cái này”; “Học bây giờ”; “Chủ đề”; “Mình muốn học bài”; “Cho mình học bài”; “Học bài đi”; “Mình muốn học bài này”; “Cho mình học chủ đề này”; “Mình muốn vào học”; “Cho mình học đi”; “Mình muốn học nè”; “Cho mình vô học”; “Mình học cái này nè”; “Học bài ni”; “Mình muốn học cái ni”; “Mình muốn học chủ đề này”; “Cho mình vào bài học”; “Mình học bài này nha”; “Bắt đầu chủ đề này đi”

### INT-003 — Học từ mới

- Khi dùng: Chọn chức năng
- Câu chuẩn: 
- Kết quả: Vào luồng từ vựng
- Số mẫu: 24
- Các câu runtime nhận: “Học từ mới”; “Mình muốn học từ”; “Học từ vựng”; “Luyện từ mới”; “Từ mới”; “Học từ”; “Học mới”; “Từ vựng”; “Mình muốn học từ mới”; “Cho mình học từ mới”; “Học mấy từ mới”; “Mình muốn học các từ mới”; “Học chữ mới”; “Mình học chữ”; “Cho mình học chữ mới”; “Học từ đi”; “Tớ muốn học từ mới”; “Học mấy chữ này nè”; “Mình muốn học chữ nè”; “Học chữ ni”; “Mình muốn học chữ mới”; “Cho mình học mấy từ mới”; “Học thêm từ mới nha”; “Mình muốn học từ vựng”

### INT-004 — Dịch tiếng Anh

- Khi dùng: Chọn chức năng
- Câu chuẩn: 
- Kết quả: Hỏi chế độ dịch
- Số mẫu: 29
- Các câu runtime nhận: “Dịch tiếng Anh”; “Dịch”; “Mình muốn dịch”; “Dịch giúp mình”; “Dịch tiếng Anh”; “Dịch cho mình”; “Dịch đi”; “Mình muốn nói tiếng Anh”; “Dịch câu này”; “Dịch cái này”; “Dịch từ này”; “Dịch cho mình sang tiếng Anh”; “Mình muốn dịch câu này sang tiếng Anh”; “Bạn dịch cái này sang tiếng Anh giúp mình”; “Nói tiếng Anh giúp mình”; “Dịch cái này ra tiếng Anh”; “Dịch câu này sang tiếng Anh giúp mình”; “Cậu dịch sang tiếng Anh giúp tớ”; “Bạn dịch câu này sang tiếng Anh giúp tớ”; “Dịch qua tiếng Anh giùm mình”; “Nói tiếng Anh”; “Tiếng Anh”; “Cái ni tiếng Anh”; “Câu ni tiếng Anh”; “Bạn dịch sang tiếng Anh giúp mình”; “Mình muốn dịch sang tiếng Anh”; “Dịch câu này sang tiếng Anh đi”; “Bạn giúp mình nói câu này bằng tiếng Anh”; “Mở phần dịch tiếng Anh giúp mình”

### INT-006 — Dịch liên tục

- Khi dùng: Chọn chế độ dịch
- Câu chuẩn: 
- Kết quả: Vào chế độ ghi âm liên tục
- Số mẫu: 23
- Các câu runtime nhận: “Dịch liên tục”; “Dịch nhiều”; “Dịch liên tiếp”; “Dịch tiếp đi”; “Mình nói liên tục”; “Dịch hoài”; “Dịch nhiều câu”; “Dịch tiếp”; “Nói tiếp”; “Dịch liên tục cho mình”; “Mình muốn dịch nhiều câu”; “Dịch từng câu liên tiếp”; “Dịch quài luôn”; “Dịch hết mấy câu mình nói”; “Dịch tiếp nhiều câu”; “Cậu bật dịch liên tục giúp tớ”; “Mở chế độ dịch liên tục giúp mình”; “Mình muốn dịch quài quài luôn”; “Dịch tiếp nghen”; “Cho mình bật dịch liên tục”; “Dịch liên tiếp giúp mình”; “Mình muốn dịch nhiều câu liền”; “Dịch nhiều câu luôn nha”

### INT-007 — Tiếp tục bài

- Khi dùng: Trong bài học
- Câu chuẩn: 
- Kết quả: Resume module
- Số mẫu: 18
- Các câu runtime nhận: “Tiếp tục học”; “Học tiếp”; “Tiếp tục bài này”; “Học tiếp đi”; “Mình muốn học nữa”; “Mình học nữa”; “Học tiếp bài này”; “Tiếp tục đi”; “Học nữa đi”; “Mình muốn tiếp tục”; “Cho mình học tiếp”; “Mình học nữa”; “Tớ muốn học tiếp”; “Học tiếp nha bạn”; “Học tiếp bài ni”; “Mình muốn học tiếp”; “Cho mình tiếp tục bài này”; “Học tiếp nha bạn”

### INT-008 — Câu tiếp theo

- Khi dùng: Trong bài học
- Câu chuẩn: 
- Kết quả: Sang câu tiếp
- Số mẫu: 22
- Các câu runtime nhận: “Câu tiếp theo”; “Qua câu tiếp”; “Câu sau”; “Nói câu khác”; “Câu nữa”; “Tiếp đi”; “Câu tiếp”; “Sang câu tiếp theo”; “Qua câu sau”; “Cho mình câu tiếp”; “Câu kế tiếp”; “Câu kế”; “Tiếp câu khác”; “Đổi câu đi”; “Cho mình câu khác”; “Câu sau đi”; “Sang câu mới”; “Cậu cho tớ câu tiếp theo”; “Qua câu kế”; “Cho mình sang câu sau”; “Qua câu kế đi”; “Mình muốn câu tiếp theo”

### INT-009 — Câu trước

- Khi dùng: Trong bài học
- Câu chuẩn: 
- Kết quả: Quay về câu trước
- Số mẫu: 20
- Các câu runtime nhận: “Câu trước”; “Quay lại câu trước”; “Lùi một câu”; “Câu hồi nãy”; “Quay lại”; “Về trước”; “Về câu trước”; “Cho mình câu trước”; “Quay lại câu vừa rồi”; “Câu vừa nãy”; “Câu lúc nãy”; “Câu ban nãy”; “Lùi lại”; “Quay lại một câu”; “Về câu cũ”; “Quay lại câu nãy nha”; “Tớ muốn quay lại câu trước”; “Cho mình quay lại câu trước”; “Về câu vừa rồi nha”; “Mình muốn về câu trước”

### INT-010 — Nghe lại câu

- Khi dùng: Trong bài học
- Câu chuẩn: 
- Kết quả: Phát lại câu hiện tại
- Số mẫu: 23
- Các câu runtime nhận: “Nghe lại”; “Nói lại”; “Đọc lại câu này”; “Cho mình nghe lại”; “Nghe nữa”; “Nói lại đi”; “Lặp lại”; “Lần nữa”; “Nghe lại câu này”; “Cho mình nghe lại câu này”; “Mở lại câu này”; “Phát lại đi”; “Phát lại câu này”; “Nghe lại một lần”; “Nghe thêm lần nữa”; “Bạn nói lại câu này”; “Nói lại cho mình nghe”; “Cậu nói lại cho tớ nghe”; “Nói lại nha bạn”; “Nghe lại câu ni”; “Bạn phát lại câu này đi”; “Mình muốn nghe lại lần nữa”; “Bạn nói lại cho mình nghe nha”

### INT-011 — Học lại từ đầu

- Khi dùng: Trong bài học
- Câu chuẩn: 
- Kết quả: Reset và học lại bài
- Số mẫu: 20
- Các câu runtime nhận: “Học lại từ đầu”; “Học từ đầu”; “Làm lại bài này”; “Học lại”; “Lại từ đầu”; “Làm lại từ đầu”; “Mình muốn học lại từ đầu”; “Bắt đầu lại từ đầu”; “Học lại cả bài”; “Cho mình học lại bài”; “Làm lại bài từ đầu”; “Học lại bài này từ đầu”; “Quay về đầu bài”; “Bắt đầu lại bài này”; “Cho mình làm lại từ đầu với”; “Học lại bài này nha”; “Học lại bài ni từ đầu”; “Mình muốn làm lại từ đầu”; “Cho mình bắt đầu lại bài này”; “Học lại từ câu đầu đi”

### INT-012 — Bài tiếp theo

- Khi dùng: Trong bài học
- Câu chuẩn: 
- Kết quả: Mở bài tiếp
- Số mẫu: 21
- Các câu runtime nhận: “Bài tiếp theo”; “Qua bài mới”; “Bài sau”; “Bài tiếp”; “Bài nữa”; “Học bài khác”; “Bài mới”; “Sang bài tiếp theo”; “Qua bài sau”; “Cho mình bài tiếp”; “Bài kế tiếp”; “Học bài sau”; “Chuyển bài sau”; “Qua bài tiếp”; “Cho mình học bài mới”; “Cậu cho tớ sang bài tiếp theo”; “Qua bài kế”; “Bài kế nha”; “Cho mình sang bài sau”; “Mình muốn học bài tiếp”; “Qua bài kế nha”

### INT-013 — Bài trước

- Khi dùng: Trong bài học
- Câu chuẩn: 
- Kết quả: Mở bài trước
- Số mẫu: 20
- Các câu runtime nhận: “Bài trước”; “Quay lại bài trước”; “Bài hồi nãy”; “Bài trước đó”; “Quay lại bài cũ”; “Bài lúc nãy”; “Sang bài trước”; “Về bài trước”; “Cho mình bài trước”; “Quay lại bài vừa rồi”; “Bài vừa nãy”; “Bài ban nãy”; “Về bài cũ”; “Quay lại một bài”; “Bạn cho tớ quay lại bài trước”; “Quay lại bài nãy nha”; “Về bài trước nha”; “Cho mình về bài trước”; “Mình muốn quay lại bài cũ”; “Mở lại bài trước đi”

### INT-014 — Luyện lại từ vựng

- Khi dùng: Từ vựng
- Câu chuẩn: 
- Kết quả: Đọc collection review
- Số mẫu: 23
- Các câu runtime nhận: “Luyện lại”; “Học lại phần chưa thuộc”; “Luyện từ khó”; “Nói lại”; “Học lại”; “Mấy câu khó”; “Luyện nữa”; “Mình muốn luyện lại”; “Cho mình luyện lại”; “Luyện mấy từ mình chưa thuộc”; “Học lại mấy từ khó”; “Ôn lại từ khó”; “Ôn lại mấy từ này”; “Luyện thêm”; “Mình muốn ôn lại”; “Học lại từ chưa nhớ”; “Luyện lại mấy chữ”; “Bạn cho tớ ôn lại”; “Ôn lại mấy chữ này nè”; “Luyện mấy chữ ni”; “Mình muốn ôn mấy từ khó”; “Cho mình luyện lại mấy từ khó”; “Ôn lại phần chưa nhớ nha”

### INT-015 — Ngôi sao từ vựng

- Khi dùng: Từ vựng
- Câu chuẩn: 
- Kết quả: Đọc collection star
- Số mẫu: 22
- Các câu runtime nhận: “Ngôi sao của mình”; “Xem ngôi sao”; “Học phần ngôi sao”; “Ngôi sao”; “Mình học ngôi sao”; “Xem sao”; “Muốn ngôi sao”; “Nhìn ngôi sao”; “Cho mình xem sao”; “Mình muốn xem ngôi sao”; “Xem sao của mình”; “Mình xem phần ngôi sao”; “Cho mình xem mình được mấy sao”; “Xem phần mình đã học được”; “Mở ngôi sao cho mình”; “Cậu cho tớ xem ngôi sao”; “Mình muốn coi sao”; “Coi ngôi sao”; “Cho mình coi sao với”; “Cho mình xem ngôi sao”; “Tớ muốn xem ngôi sao của mình”; “Mở phần ngôi sao đi”

### INT-016 — Trợ giúp

- Khi dùng: Toàn cục
- Câu chuẩn: 
- Kết quả: Mở trợ giúp/nhắc lại theo trạng thái
- Số mẫu: 26
- Các câu runtime nhận: “Giúp mình với”; “Mình không biết”; “Phải làm gì?”; “Nói lại đi”; “Giúp”; “Giúp mình”; “Không biết”; “Không hiểu”; “Sao đây?”; “Nói gì?”; “Bạn giúp mình”; “Giúp mình đi”; “Mình phải làm sao?”; “Giờ làm gì?”; “Tiếp theo làm gì?”; “Mình chưa biết làm”; “Chỉ mình với”; “Bạn chỉ mình đi”; “Làm sao bây giờ?”; “Cậu giúp tớ với”; “Bạn chỉ tớ với”; “Mình làm sao giờ?”; “Giờ mình làm cái chi?”; “Bạn giúp mình đi mà”; “Mình chưa biết làm gì”; “Bạn chỉ mình với”

### INT-017 — Rời luyện nói

- Khi dùng: Dịch liên tục
- Câu chuẩn: 
- Kết quả: Dừng dịch và gọi trợ lý MAIN
- Số mẫu: 26
- Các câu runtime nhận: “Mình muốn học cái khác”; “Cái gì khác để học”; “Gì khác để học”; “Có gì khác không”; “Học thử cái khác”; “Học môn khác”; “Học bài khác”; “Đổi sang học cái khác”; “Mình muốn chuyển sang học cái khác”; “Đổi sang phần khác giúp mình”; “Mình muốn làm cái khác”; “Đổi cái khác đi”; “Cho mình học cái khác”; “Chuyển sang chức năng khác đi”; “Mình muốn đổi bài”; “Đổi sang phần khác”; “Mình muốn học phần khác”; “Học cái khác nha”; “Qua cái khác đi”; “Đổi qua cái khác đi”; “Cho mình đổi cái khác với”; “Mình muốn học thứ khác”; “Mình muốn chuyển sang cái khác”; “Cho mình đổi sang phần khác”; “Mình muốn thử chức năng khác”; “Đổi qua cái khác nha”

### INT-018 — Dừng dịch

- Khi dùng: Dịch liên tục
- Câu chuẩn/khuyến nghị: “Dừng lại”
- Kết quả: Dừng phiên dịch
- Số mẫu: 28
- Hành vi runtime đã đối chiếu: cả 28 mẫu dưới đây đều đang được so khớp; đây là điểm lệch nếu đặc tả mong muốn chỉ nhận “Dừng lại”.
- Các câu runtime nhận: “Dừng lại”; “Mình muốn dừng”; “Dừng dịch”; “Dừng dịch liên tục”; “Ngừng”; “Mình muốn ngừng”; “Ngừng dịch”; “Thôi dừng lại”; “Không dịch nữa”; “Mình không muốn dịch nữa”; “Thoát dịch”; “Dừng dịch đi”; “Thôi dịch”; “Mình không dịch nữa”; “Nghỉ dịch”; “Dừng phần dịch”; “Thoát phần dịch”; “Không dịch nữa đâu”; “Thôi không dịch nữa”; “Dừng dịch giúp mình”; “Tớ không muốn dịch nữa”; “Dừng”; “Hổng dịch nữa”; “Mình hông muốn dịch nữa”; “Mình muốn dừng dịch”; “Thôi, không dịch nữa đâu”; “Dừng phần dịch giúp mình”; “Mình nghỉ dịch nha”

### INT-019 — Có

- Khi dùng: Xác nhận học lại
- Câu chuẩn: 
- Kết quả: Xác nhận học lại
- Số mẫu: 24
- Các câu runtime nhận: “Có”; “Ừ, học lại”; “Ừa, tớ muốn học lại”; “Mình có”; “Muốn học lại”; “Học lại”; “Ừ, mình muốn học lại”; “OK, được”; “Ừ”; “Được luôn”; “Ừ, tớ muốn”; “Tớ đồng ý học lại”; “OK”; “Cậu cho tớ học lại bài này”; “Ừa, mình học lại”; “Có chứ”; “Mình muốn”; “Mình muốn học lại”; “Oki luôn”; “Có nè”; “Ừm”; “Ừ, mình muốn”; “OK, học lại luôn”; “Ừ, học lại đi”

### INT-020 — Không

- Khi dùng: Xác nhận học lại
- Câu chuẩn: 
- Kết quả: Không học lại; quay về chọn chủ đề
- Số mẫu: 22
- Các câu runtime nhận: “Không”; “Không muốn học lại”; “Nô, tớ không muốn”; “Mình không”; “Không đâu”; “Không muốn”; “Không học”; “Thôi, mình không học lại”; “Thôi, không học lại”; “Tớ không học lại”; “Không cần”; “Không cần đâu”; “Mình thôi”; “Thôi mình không học”; “Mình muốn nghỉ rồi”; “Hông”; “Hông, mình không muốn”; “Hổng”; “Mình hổng muốn”; “Mình không muốn học lại”; “Thôi, bỏ qua đi”; “Không học lại đâu”

### INT-021 — Số tuổi/chủ đề/bài

- Khi dùng: Chọn bằng số
- Câu chuẩn: 
- Kết quả: Trích số cho tuổi/chủ đề/bài
- Số mẫu: 31
- Các câu runtime nhận: “Một đến mười lăm”; “1”; “2”; “3”; “4”; “5”; “6”; “7”; “8”; “9”; “10”; “11”; “12”; “13”; “14”; “15 và dạng chữ tiếng Việt”; “Mình [số] tuổi”; “[số] tuổi”; “Mình chọn [số]”; “Chọn số [số]”; “Số [số]”; “Bài số [số]”; “Mình chọn bài thứ [số]”; “Chủ đề số [số]”; “Mình chọn chủ đề [số]”; “Bốn / Tư”; “Mười bốn / Mười tư”; “Mười một / Mười mốt”; “Mình chọn số [số]”; “Cho mình bài số [số]”; “Mình muốn chủ đề số [số]”

### INT-022 — Wake word

- Khi dùng: Chế độ đánh thức cũ
- Câu chuẩn: 
- Kết quả: Mở trợ lý giọng nói
- Số mẫu: 24
- Các câu runtime nhận: “Hey HOMI”; “Hey HÔMI”; “Hey HAMI”; “Hay HOMIE”; “Hey HOMY”; “Hay HÔMY”; “Hey HO MI”; “Hay HO MIE”; “Hey HOMY”; “Hay HA MI”; “Hey HIMI”; “Hay HUMI”; “Ê HOMPI”; “Ê HOM ĐI”; “HOMI ơi”; “Bạn HOMI ơi”; “Ê HOMI”; “Hôm-mi ơi”; “Homi giúp mình”; “Bạn ơi”; “HOMI nghe mình nói không?”; “HOMI, mình muốn nói”; “HOMI có nghe không?”; “HOMI, mình cần bạn”

## Chuỗi điều khiển bổ sung ngoài kho 500

Các câu sau nằm trực tiếp trong bộ từ vựng điều khiển. Chúng không mặc nhiên khả dụng ở mọi màn hình; trạng thái hiện tại quyết định resolver nào được gọi:

- Nhánh legacy `Dịch một câu` vẫn có chuỗi trong `ControlledSpeechLexicon`, nhưng luồng MAIN hiện tại đi thẳng vào dịch liên tục; không xem đây là một lựa chọn có thể trả lời sau `AI-020`.
- Từ vựng ba mẹ đã thêm: “Ba mẹ đã thêm”; “Học Ba mẹ đã thêm”; “Nghe Ba mẹ đã thêm”; “Nội dung Ba mẹ đã thêm”.
- Mục mới nhất: “Nội dung mới nhất”; “Ngôi sao mới nhất”; “Mới nhất”.
- Nghe tất cả: “Nghe lại tất cả”; “Nghe tất cả”; “Tất cả”.
- Học phần khác: “Học nội dung khác”; “Nội dung khác”; “Học phần khác”.

## Im lặng, không rõ và tiếng ồn

| ID | Luồng/tình huống | HOMI nói | Sau đó |
|---|---|---|---|
| SIL-001 | Trợ lý MAIN — Không nói lần 1 (6 giây) | Bạn có thể chọn: dịch sang tiếng Anh, học theo chủ đề hoặc học bộ từ vựng. | Phát câu nhắc rồi tự mở mic lại |
| SIL-002 | Trợ lý MAIN — Không nói lần 2 (6 giây tiếp theo) | Khi sẵn sàng, bạn nhấn nút gọi HOMI nhé. | Kết thúc phiên MAIN và reset |
| SIL-003 | Dịch liên tục — Không nói/quá ngắn lần 1 (6 giây) | HOMI chưa nghe thấy bạn nói. Bạn nói lại đi. | Tự bắt đầu lượt ghi âm mới |
| SIL-004 | Dịch liên tục — Không nói/quá ngắn lần 2 (6 giây tiếp theo) | Mình dừng ở đây. Khi cần, bạn nhấn nút gọi HOMI nhé. | Kết thúc chế độ nói liên tục |
| SIL-005 | Ghi âm giao tiếp — ASR rỗng/không phát hiện tiếng (Mặc định 3 giây; có luồng truyền 6 hoặc 12 giây) | HOMI chưa nghe thấy bạn nói. Bạn nói lại đi. | Dừng lượt hiện tại; có thể phát lời nhắc tùy cấu hình |
| SIL-006 | Ghi âm giao tiếp — Môi trường bị đánh dấu ồn (Khi kết thúc lượt không có kết quả) | Ở đây hơi ồn. Bạn đưa micro lại gần, tránh hướng quạt hoặc chuyển sang chỗ yên hơn rồi thử lại nha. | Yêu cầu điều chỉnh vị trí rồi thử lại |
| SIL-007 | Luyện phát âm — Không nghe rõ bản ghi (Sau lượt ghi âm) | HOMI chưa nghe rõ. Bạn nói lại đi. | Mở lượt luyện lại |
| SIL-008 | Hoàn tất bài — Không hiểu Luyện lại/Bài tiếp (Sau khi trẻ trả lời) | Bạn nói lại lựa chọn nha. | Mở mic chờ lựa chọn lại |
| SIL-009 | Web Batch — Finalize không có transcript (Sau khi upload/finalize) | HOMI chưa nghe rõ. Bạn thử nói lại nhé. | Ném lỗi WEB_BATCH_NO_SPEECH cho tầng trên |

## Fallback ngoài phạm vi

> Đây là các chính sách/spec nằm trong APK; cột trạng thái cho biết mức triển khai hoặc phần cần test thêm, nên không nên hiểu tất cả là hành vi chắc chắn đã chạy.

| ID | Ngữ cảnh/điều kiện | Lần 1 | Lần 2/hành động cuối | Trạng thái |
|---|---|---|---|---|
| FB-001 | Chọn chức năng gốc — Câu không khớp học chủ đề / từ mới / dịch | Bạn có thể chọn: dịch sang tiếng Anh, học theo chủ đề hoặc học bộ từ vựng. → Mở mic lại | HOMI vẫn chưa hiểu. Khi sẵn sàng, bạn nhấn nút gọi HOMI nhé. → Kết thúc phiên, giữ trạng thái an toàn | Chưa có trong code |
| FB-004 | Chọn chủ đề — Không có số hoặc số ngoài phạm vi | Bạn nói số chủ đề, ví dụ “chủ đề số 3”. → Mở mic lại | HOMI chưa nhận được chủ đề. Bạn có thể chọn trên điện thoại nha. → Giữ màn danh sách chủ đề | Có thể phát triển nhận tên chủ đề ở giai đoạn sau |
| FB-005 | Chọn bài — Không có số hoặc số ngoài phạm vi | Bạn nói số bài, ví dụ “bài số 1”. → Mở mic lại | HOMI chưa nhận được bài. Bạn có thể chọn trên điện thoại nha. → Giữ màn chủ đề | Có thể phát triển nhận tên bài ở giai đoạn sau |
| FB-006 | Trong bài luyện nghe — Câu không khớp nghe lại/ câu tiếp/câu trước/dừng | HOMI chưa hiểu. Bạn có thể nói: nghe lại, câu tiếp, câu trước hoặc dừng lại. → Mở mic lại và giữ nguyên câu | HOMI vẫn chưa hiểu. Mình giữ nguyên câu hiện tại nhé. → Resume câu hiện tại; không tự chuyển sai | Đúng ví dụ người dùng nêu; tránh câu “Con tập trung học đi” quá cứng |
| FB-007 | Xác nhận học lại chủ đề — Không khớp Có/Không | Bạn nói “có” để học lại hoặc “không” để chọn chủ đề khác. → Mở mic lại | HOMI chưa nhận được câu trả lời. Bạn chọn “có” hoặc “không” nhé. → Quay về danh sách chủ đề | Mặc định an toàn sau 2 lần |
| FB-008 | Từ vựng: chọn luyện lại/ngôi sao — Không khớp hai bộ | Bạn nói “luyện lại” hoặc “ngôi sao”. → Mở mic lại | Mình tạm dừng học bộ từ vựng. Khi sẵn sàng, bạn nhấn nút gọi HOMI nhé. → Kết thúc luồng từ vựng | Fallback hai cấp |
| FB-009 | Dịch liên tục — Trẻ nói lệnh khác hoạt động hoặc dừng | Bạn muốn dừng dịch để học theo chủ đề hoặc học bộ từ vựng phải không? → Xác nhận chuyển luồng; không dịch câu lệnh | Bạn nói “dừng lại” để gọi HOMI nhé. → Giữ chế độ dịch hoặc dừng theo lựa chọn rõ | Cần test tránh dịch nhầm lệnh điều hướng thành câu tiếng Anh |
| FB-010 | Hoàn tất bài — Không khớp Luyện lại từ đầu/Bài tiếp theo | Bạn nói “luyện lại từ đầu” hoặc “bài tiếp theo”. → Mở mic lại | Mình dừng ở đây. Khi muốn học tiếp, bạn nhấn nút gọi HOMI nha. → Giữ tiến độ hoàn thành và thoát an toàn | Cần thêm giới hạn retry |

## Phạm vi nội dung bài học (giữ file nhẹ)

Báo cáo không bung toàn bộ 2.435 dòng âm thanh bài học. Quy tắc phản hồi là:

- `coreEnglish`: HOMI đọc câu tiếng Anh → người học lặp lại câu đó.
- `challengePrompt` / `missionPrompt`: HOMI hỏi dạng “A hay B?” → người học nói một trong hai lựa chọn.
- `rolePlayHomi`: HOMI nói vai của mình → người học đáp bằng câu `rolePlayChild` tương ứng.
- `coreVietnamese`, `hook`, `microObjective`, `systemPrompt`: phần giải nghĩa/hướng dẫn, thường không cần trả lời ngay.

| Loại nội dung | Số mục trong APK |
|---|---:|
| challengePrompt | 872 |
| coreEnglish | 601 |
| coreVietnamese | 601 |
| hook | 18 |
| microObjective | 91 |
| missionPrompt | 180 |
| rolePlayChild | 21 |
| rolePlayHomi | 17 |
| songReference | 5 |
| systemPrompt | 29 |

### Các câu hệ thống của bài học

- Bắt đầu Level [số].
- Chủ đề [số].
- Bài đầu tiên là [Tên Bài].
- Bài này là [Tên Bài].
- Bắt đầu nhé.
- Tiếp theo là một câu thử thách nhé.
- Tiếp theo là một câu thử thách. Xong rồi mình nghe bài hát [SONG_TITLE] nhé.
- Bây giờ cùng nghe [SONG_TITLE] nhé.
- Tiếp theo là Nhiệm vụ cuối Level. Bạn sẽ có bốn câu thử thách.
- Mình luyện nhanh vài phần rồi thử lại nhé.
- Xong rồi. Mình thử lại Nhiệm vụ cuối Level nhé.
- Mình học tiếp bài [Tên Bài] nhé.
- Mình tiếp tục đoạn hội thoại nhé.
- Mình làm lại phần thử thách nhé.
- Mình tiếp tục Nhiệm vụ cuối Level nhé.
- Bạn nói đầy đủ câu nhé.
- Bạn nói tiếng Anh nhé.
- Nói lại câu này.
- Bạn thử nói nhé.
- Đến lượt bạn.
- Bạn nói lại nhé.
- Bạn đã hoàn thành tất cả Chủ đề rồi!
- Bạn còn một Chủ đề chưa học. Bạn muốn học tiếp hay học lại?
- Bạn cần học xong Bài [PREVIOUS_LESSON] trước nhé.
- Chủ đề [TOPIC_NO] bạn đã học xong rồi. Bạn muốn học chủ đề khác hay học lại?
- Mình học tiếp Chủ đề [TOPIC_NO] nhé.
- Bạn cần hoàn thành Level [CURRENT_LEVEL] trước nhé.
- Bạn chọn học Chủ đề số mấy?
- Có [TOPIC_COUNT] Chủ đề. Bạn muốn học Chủ đề số mấy?

## Nguồn được đọc trực tiếp từ APK

- `assets/flutter_assets/assets/data/homi_ai_fallback_catalog_v1.json`
- `assets/flutter_assets/assets/data/listening_audio_manifest_v4.json`
- `assets/flutter_assets/assets/data/listening_lessons.json`

## Nguồn runtime đã đối chiếu

- `lib/features/voice_navigation/application/main_voice_assistant_flow.dart`: ghép `AI-020` + `AI-022` và đi thẳng vào dịch liên tục.
- `lib/features/voice_navigation/application/main_speaking_command_resolver.dart`: so khớp `INT-018`, `INT-001`, `INT-017` và trợ giúp.
- `lib/features/voice_navigation/application/main_speaking_fallback_flow.dart`: quyết định dừng, xác nhận chuyển hoạt động hoặc tiếp tục dịch.
- `lib/app/ai_speaking_app.dart`: chỉ kích hoạt resolver này khi phiên dịch liên tục đang hoạt động.

Đã chạy 44 kiểm thử liên quan đến resolver dừng dịch, fallback dịch liên tục và luồng MAIN; tất cả đều đạt.
