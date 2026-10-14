# Kiểm tra audio điều hướng sau khi bỏ Level

> Cập nhật sau kiểm tra: đã tích hợp ba MP3 người dùng cung cấp cho chọn 10 chủ đề,
> học lại khóa và nhắc chọn trong phạm vi 1–10. Câu nhắc phạm vi dùng chung cho
> hai nhánh chọn sai, nên cả bốn lời TTS mới nêu bên dưới đã có MP3 tương ứng.
> Các phát hiện khác bên dưới thuộc báo cáo kiểm tra ban đầu, chưa được sửa trong lần nhập audio này.

Ngày: 14/10/2026. Ba trợ lý kiểm tra độc lập UI, MAIN/giọng nói, hoàn thành/resume; trợ lý chính đối chiếu manifest và chạy kiểm thử.

**Kết luận: chưa phủ hết audio điều hướng.** Các luồng chính có MP3 hoặc TTS, nhưng còn bốn lời mới dùng TTS, một số nhánh lỗi chỉ hiện chữ, và hai nhánh MAIN dùng sai audio key có từ trước. Không tìm thấy lời Level hoạt động trong phạm vi đã kiểm tra.

Phạm vi: luồng Chủ đề của cả năm nhóm tuổi, chọn/học lại 10 chủ đề, chuyển bài, intro/resume, hoàn thành khóa, checkpoint Level cũ; các menu MAIN, retry/im lặng và chuyển module liên quan. Đây không phải chứng nhận mọi âm thanh của toàn bộ ứng dụng hoặc thiết bị thật. Lần kiểm tra này chỉ thêm bằng chứng trong output; không thay đổi mã sản phẩm hay sinh MP3.

## 1. Tình trạng từng phần

| Phần | Kết quả |
|---|---|
| Chọn 10 chủ đề | Có giọng đọc TTS; chưa có MP3 cho lời mới |
| Chọn số chủ đề không hợp lệ | Có TTS; chưa có MP3 cho lời mới |
| Học lại sau hoàn thành khóa, chọn sai số ở menu này | Có TTS; chưa có MP3 cho hai lời mới |
| Xác nhận học lại chủ đề 1–10 | Đủ 10 MP3, kiểm thử đường phát thật qua factory |
| Tiếp tục chủ đề đang học | Đủ 10 key/asset MP3 |
| Mở bài mới | Đủ 109 intro key/asset; 13 bài có hook tách phần dẫn thành TTS + hook MP3, 96 bài còn lại đi nhánh intro nguyên đoạn |
| Tiếp tục / học lại bài | Đủ 109 resume + 109 relearn key/asset, text khớp |
| Tiếp tục bài hát | Đủ 5 song-resume key/asset |
| Bài bị khóa theo thứ tự | Đủ 3 lời nhắc MP3 |
| Hoàn thành bài/chủ đề/còn một chủ đề/khóa học | MP3; kiểm thử các lời hoàn thành và mốc chủ đề 1–10 |
| Resume checkpoint `nextLevel` cũ | Tính lại theo toàn bộ nhóm chủ đề; không gọi audio Level |
| MAIN nhắc lại sau im lặng | Lặp lời hiện tại: menu mới vẫn TTS; lần im lặng thứ hai có MP3 tạm dừng |
| Đổi nhóm tuổi trong phần phụ huynh | Hiện SnackBar, không phát lại lời chọn 10 chủ đề |
| Lỗi micro/ASR/lựa chọn ở màn hình hoàn thành | Ba nhánh chỉ hiện chữ, chưa có phản hồi âm thanh |
| Một số lỗi tải nội dung / bài không tồn tại | Chỉ SnackBar |
| MAIN hỏi lại sau dừng dịch / học nội dung khác | Hai audio key gán ngược, cần sửa |

## 2. Bốn lời mới chưa có MP3

1. “Có 10 Chủ đề. Bạn chọn Chủ đề số mấy?” — key `assistant.topic.choose_10.vi` có ở nơi gọi nhưng chưa có trong manifest runtime.
2. “Nhóm tuổi này có 10 Chủ đề. Bạn chọn lại nhé.” — hiện không có key, chạy TTS.
3. “Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Chủ đề số mấy? Bạn chọn từ số 1 đến số 10.” — hiện không có key, chạy TTS.
4. “Bạn chọn Chủ đề 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 nhé.” — hiện không có key, chạy TTS.

Ba câu đầu đã có định nghĩa trong file nguồn sinh audio; định nghĩa nguồn chưa đồng nghĩa với MP3 đã được tích hợp. Câu thứ tư cũng cần được tính khi bổ sung audio. TTS ở đây phù hợp phương án dự phòng được cho phép trong yêu cầu bỏ Level trước đó; không phải mất toàn bộ tiếng nói.

Nguồn: [MAIN chọn chủ đề](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart:307), [xử lý số sai](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart:1531), [số sai khi học lại khóa](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart:1578).

## 3. Những chỗ chỉ hiện chữ

Ưu tiên bổ sung phản hồi âm thanh cho lựa chọn hoàn thành, vì trẻ đang dùng giọng nói có thể không biết cần chạm nút:

- [Không mở được micro](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_practice_screen.dart:3513): “Chưa mở được micro. Bạn chạm một nút để chọn nhé.”
- [Không hiểu lựa chọn](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_practice_screen.dart:3585): “HOMI chưa nghe rõ lựa chọn. Bạn có thể chạm một nút bên dưới.” Không phát lại hướng dẫn hoặc mở lượt nghe mới.
- [Lỗi nhận diện](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_practice_screen.dart:3629): “Chưa nhận diện được giọng nói. Bạn chạm một nút để chọn nhé.”

Các nhánh trên có thể chạy trong production trên Android/iOS. Kiểm thử iOS hiện hữu chỉ xác nhận nút chạm vẫn dùng được, chưa kiểm tra lời nhắc được đọc.

Các nhánh UI phụ cũng chỉ hiện chữ: [đổi nhóm tuổi](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/topic_listening_screen.dart:470), [lỗi tải bài hát](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/topic_listening_screen.dart:884), [lỗi tải bài học](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/topic_listening_screen.dart:1020), [bài không tồn tại](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/topic_lesson_list_screen.dart:517). Đổi tuổi là thao tác phụ huynh; mức ưu tiên thấp hơn lỗi trong lượt học của trẻ.

## 4. Hai lỗi audio key có sẵn trước khi bỏ Level

- **P2 — hỏi lại sau dừng dịch phát nhầm MP3.** `beginAfterTranslationStop()` rồi nhận lại chính lời hỏi trả text “Bạn muốn tiếp tục dịch, học Chủ đề hay Bộ từ vựng?” nhưng key lại là `assistant.main.choose_translation.vi`. Kiểm thử factory xác nhận MP3 đó được phát; nội dung bản thu là lời chọn “Dịch tiếng Anh”, khác lời tiếp tục dịch. [Nguồn](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart:885).
- **P2 — hỏi lại học nội dung khác dùng TTS dù có MP3 tương ứng.** Nhánh ngược lại gán `assistant.main.after_translation_stop.vi` cho câu “Bạn muốn Dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?”. Key/text không khớp nên rơi về TTS. [Nguồn](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart:847).

Đã đối chiếu HEAD: hai mapping này có trước thay đổi bỏ Level. Resolver chấp nhận key mà không kiểm tra text khi entry không có `sourceText`; entry `choose_translation` thuộc trường hợp này. Đây là lý do lỗi thứ nhất không tự rơi về TTS. [Resolver](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/core/audio/catalog/audio_prompt_resolver.dart:137).

## 5. Intro của 13 bài vẫn có phần TTS

[Nhánh intro có hook](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_intro_screen.dart:250) tách phần dẫn, hook và câu bắt đầu. Phần dẫn không có key/text khớp; tiếp tục tách tiếng Việt và tên bài tiếng Anh để TTS. Hook và “Bắt đầu nhé.” vẫn có MP3. Đây là hành vi có sẵn, không phát sinh do bỏ Level.

Danh sách bài: `c35-l1-t02-b03`, `c35-l2-t05-b01`, `c35-l3-t09-b02`, `c35-l3-t10-b02`, `c67-l1-t03-b02`, `c67-l3-t07-b02`, `c67-l3-t09-b02`, `c810-l1-t01-b01`, `c810-l1-t02-b02`, `c810-l2-t05-b01`, `c1112-l2-t06-b02`, `c1315-l3-t07-b02`, `c1315-l3-t08-b02`.

## 6. Bằng chứng kiểm tra

- 24 kiểm thử hiện hữu/diagnostic chạy đạt: GAP66, dịch vụ prompt, fixed prompt coverage và domain audit. Domain audit duyệt 263 ngữ cảnh, 31.658 chuyển trạng thái, 637 nhóm lời đầu ra; độ sâu hội thoại tối đa 4. Không có lời chứa “Level” trong các đầu ra scope `current` đã duyệt.
- Một kiểm thử bổ sung trong output chạy đạt, ghi nhận 40 lần yêu cầu phát qua `createVoicePromptService`: bốn lời mới đều gọi TTS; 34 lời replay/completion/milestone gọi authored audio; hai trường hợp còn lại tái hiện hai lỗi key trên. Native channel được giả lập nên không phải phép thử nghe thật.
- 567 entry đang bật trong ba manifest `assistant_core_audio`, `listening_common_audio`, `homi_gap66_audio`: không thiếu asset hoặc sai SHA-256. Cả 19 entry nhắc Level đã tắt.
- Việc có asset/key không chứng minh trải nghiệm nghe trên thiết bị. Chưa kiểm tra loa/tai nghe Bluetooth, ASR thật, âm lượng, độ trễ hoặc chất lượng giọng TTS.

Bằng chứng: [log 24 tests](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/no-level-verification/navigation-audio-tests.log), [40 kết quả phát](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/no-level-audio-audit/playback-results.json), [inventory](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/no-level-audio-audit/inventory.json), [domain outputs](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/output/no-level-audio-audit/domain-utterances.json).

Thứ tự xử lý đề xuất: sửa hai key MAIN; thêm lời đọc ở ba nhánh lỗi hoàn thành; bổ sung bốn MP3 cho luồng 10 chủ đề; sau đó hoàn thiện phần dẫn của 13 intro và các phản hồi UI phụ nếu mục tiêu là toàn bộ điều hướng dùng audio thu sẵn.
