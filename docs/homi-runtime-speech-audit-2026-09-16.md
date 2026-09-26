# Rà soát câu HOMI thực sự có thể phát — 16/09/2026

> Cập nhật sau rà soát: 28/28 câu thiếu bên dưới đã được tạo bằng Eleven v3 và bật trong manifest. Kho MAIN + CURRICULUM hiện có 2.860 file; kiểm kê hữu hạn đạt 2.062/2.062 mục có audio khớp, còn 0 thiếu. Phần dưới giữ lại kết quả **trước khi bổ sung** để làm bằng chứng; các tệp CSV/JSON liên kết đã được cập nhật sang trạng thái sau bổ sung. Xem [báo cáo đợt 28 câu](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/docs/homi-gap28-elevenlabs-2026-09-16.md). Các hạn chế về câu động và chọn clip intro vẫn còn nguyên.

## Kết luận

**Chưa thể kết luận mọi lời HOMI nói đều đã dùng audio ElevenLabs.** Rà theo đường gọi phát hiện tại xác nhận **28 câu/biến thể tiếng Việt chưa có audio khớp chính xác**. Ngoài ra, dịch tự do và nội dung ba mẹ thêm là các tập mở, không thể liệt kê hết trước bằng một số lượng file cố định.

Trong phần hữu hạn đã tái dựng từ code và giáo trình hiện tại:

- **2.062 cặp nội dung–locale** được ghi nhận trong các nhánh hiện hành, kể cả lời báo lỗi có điều kiện.
- **2.034 cặp có audio khớp**, **28 cặp chưa có**. Đây là kết quả kiểm kê theo phạm vi bên dưới, không phải chứng minh mọi chuỗi tương tác vô hạn đều đã được chạy.
- **2.832 file MAIN + CURRICULUM** đều tồn tại, khớp SHA-256, nằm trong khai báo assets và đạt giới hạn dung lượng/thời lượng của bộ phát.
- **1.311 liên kết audio trực tiếp** trong giáo trình được kiểm tra: 1.202 mẫu Core Anh/Việt và 109 intro. Không phát hiện link thiếu file, thiếu khai báo đóng gói hoặc sai text/locale so với manifest.
- Không sửa luồng app, không tạo audio, không gọi ElevenLabs, không sử dụng API key trong lượt rà soát này.

Phạm vi là **working tree hiện tại**, không phải xác nhận bản APK đang cài trên điện thoại. “Có audio khớp” là kiểm tra dữ liệu/file, không đồng nghĩa đã nghe kiểm định từng bản ghi hoặc đảm bảo không bao giờ fallback trên thiết bị.

## 1. Danh sách 28 câu còn thiếu

Các dấu câu và cách viết dưới đây được giữ theo runtime. `N` phải được thay bằng từng số trong miền nêu rõ; không được tạo giọng đọc nguyên ký hiệu `N`.

| Nhóm | Nội dung thực sự đưa vào bộ phát | Biến thể | Số câu thiếu |
|---|---|---|---:|
| Học tiếp chủ đề | `Mình học tiếp Chủ đề N nhé.` | N = 1…10 | 10 |
| Chọn chủ đề đã hoàn thành | `Chủ đề N bạn đã học xong rồi. Bạn muốn học chủ đề khác hay học lại?` | N = 1…10 | 10 |
| Chọn chủ đề, không đọc lại lời mở Level | `Có K Chủ đề. Bạn muốn học Chủ đề số mấy?` | K = 3, 4 | 2 |
| Chưa mở khóa Level tiếp theo | `Bạn cần hoàn thành Level N trước nhé.` | N = 1, 2 | 2 |
| Chọn sai Level khi học lại khóa học | `Bạn chọn Level 1, 2, 3 nhé.` | Câu cố định | 1 |
| Tuổi ngoài phạm vi khi trợ lý đang hỏi tuổi | `Bi cô có bài học cho các bạn từ 3 đến 15 tuổi. Con mấy tuổi` | Không có dấu chấm cuối | 1 |
| Lệnh điều khiển module phát sinh lỗi | `Bi cô chưa thực hiện được. Con thử lại nhé.` | Câu cố định | 1 |
| Không mở được micro dịch liên tục | `Cô chưa mở được micro để dịch liên tục. Con kiểm tra quyền micro rồi thử lại nhé.` | Câu cố định | 1 |
| **Tổng** | | | **28** |

Nguồn chính:

- [TopicListeningScreen](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/features/listening/presentation/topic_listening_screen.dart:678): chọn chủ đề, khóa Level, tiếp tục/học lại chủ đề.
- [MainVoiceAssistantFlow](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart:913): hội thoại chọn chủ đề/học lại và kiểm tra Level.
- [Thông báo tuổi](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart:807).
- [Lỗi điều phối](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/core/session/app_flow_coordinator.dart:65).
- [Lỗi micro](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/app/ai_speaking_app.dart:1696).

Hai câu còn dùng tên “Bi cô” cần được duyệt cách xưng hô trước khi tạo audio mới. Báo cáo giữ nguyên câu đang có để tránh nhầm câu dự kiến sửa với câu runtime.

### Vì sao có file gần giống nhưng vẫn thiếu?

Bộ phát so sánh **toàn bộ text sau trim và locale**; nó không tự cắt hoặc ghép một phần file khác. Ví dụ đã có “Bắt đầu Level 1. Có 3 Chủ đề…” không làm cho câu riêng “Có 3 Chủ đề…” tự có audio. Metadata `aliases` không phải cơ chế thay thế text.

Xem [điều kiện khớp](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/core/audio/main_assistant_audio_prompt_service.dart:47). Thiếu khớp, lỗi file, timeout, tắt cờ authored-audio hoặc bộ phát không hỗ trợ đều có thể dẫn tới TTS dự phòng.

## 2. Các nhóm nội dung hiện hành đã kiểm kê

Các hàng sau **có thể trùng câu với nhau**; không cộng tổng từng hàng để suy ra số file cần tạo.

| Nhóm | Phạm vi đã rà | Kết quả |
|---|---|---|
| Trợ lý MAIN | Mở menu, đổi hoạt động, dừng, dịch, hỏi tuổi, trợ giúp, chọn Level/chủ đề, fallback, lỗi tải giáo trình | 48 text–locale trong bộ kiểm tra domain; 14 còn thiếu, đã nằm trong bảng 28 |
| Mẫu Core | 601 target trong 109 bài, mỗi target Anh + Việt | 1.202 vị trí phát; 548 text EN và 528 text VI riêng biệt; đầy đủ audio |
| Challenge | 601 câu hỏi; xác nhận từng câu đều được bộ chọn chọn ra khi target tương ứng là câu yếu | 589 câu hỏi riêng biệt và 532 đáp án EN riêng biệt; đầy đủ audio |
| Hướng dẫn nói lại | 5 cue Core luân phiên | Đầy đủ audio |
| Khen, thử lại, nói mẫu, im lặng, nghe không rõ, bỏ qua | Tất cả 6 loại phản hồi × 5 nhóm tuổi, gồm mọi lựa chọn luân phiên | 25 câu riêng biệt; đầy đủ audio |
| Intro bài | 109 vị trí intro phát từ URI | 69 nội dung riêng biệt; đầy đủ audio |
| Học lại | Tên bài theo giáo trình | 106 câu riêng biệt; đầy đủ audio |
| Ngôi sao còn thiếu | Số sao trong phạm vi Core thực tế, hai cách nói theo nhóm tuổi | 16 câu riêng biệt; đầy đủ audio |
| Hoàn thành/chọn bước kế tiếp | Bài, chủ đề, Level, toàn khóa, một chủ đề còn lại | Các biến thể hữu hạn đã ghi trong inventory có audio |
| Hướng dẫn bộ từ vựng | Hôm nay, Ba mẹ thêm, Luyện lại, Ngôi sao, tiếp tục, hết danh sách, thiếu dữ liệu | 22 câu riêng biệt được dùng trong luồng; đầy đủ audio |
| Dẫn vào bài hát | 5 tên bài hát | 5 câu có audio; nhạc được phát bằng file bài hát riêng |
| Lời lỗi/ngữ cảnh | Micro, chưa nghe thấy trẻ, dữ liệu Challenge sai, yêu cầu điều khiển không hợp lệ | Có kiểm kê; 2 lỗi micro/điều phối còn thiếu đã liệt kê |

Điểm cần phân biệt:

- Một lượt học chỉ chọn một Challenge theo tiến độ/rotation, không đọc cả 601 câu trong một lần. Rà soát phải tính toàn bộ ngân hàng vì các lượt học lại có thể chọn câu khác.
- `correctVietnamese` của Challenge không được màn Challenge hiện tại đọc trực tiếp. Nhánh tổng kết hiện tại đưa Core tương ứng vào Luyện lại; không được tự tính mọi đáp án VI của Challenge thành một câu bắt buộc đọc ở màn này.
- Hướng dẫn từ vựng có 23 text khai báo riêng biệt nếu tính cả `startPlayback = 'Bắt đầu nào.'`, nhưng hằng này không có nơi sử dụng trong luồng hiện tại. Vì vậy 22 câu được tính là hiện hành. Cả câu không dùng đó cũng đã có audio.
- 7 câu phản hồi tiếng Anh được một số nơi gọi với locale `vi-VN`; manifest có `lookupLocales` để chọn đúng audio tiếng Anh. Kiểm tra đã áp dụng quy tắc này, không báo thiếu nhầm.

## 3. Nội dung động: không thể đóng danh sách bằng audio tạo sẵn

### Ba mẹ thêm từ/câu và các câu gợi ý

Nội dung `VocabularyEntry.word` và `meaning` phụ thuộc dữ liệu người dùng lưu. Các mẫu như “I can {word}.”, “This is my {word}.”, “It is {color}.” cũng chỉ trở thành nội dung học sau khi được chọn/lưu.

Với entry có nguồn ba mẹ thêm, [đường phát từ vựng](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/features/vocabulary/presentation/vocabulary_home_screen.dart:1989) hiện ưu tiên dịch vụ audio từ điển và cache, **không kiểm tra kho ElevenLabs trước**. Khi thất bại mới gọi callback vào bộ phát chung; lúc đó text khớp có thể dùng audio đã tạo, còn không thì TTS thiết bị. Nguồn entry này vẫn giữ cách phát đó khi đi vào Hôm nay/Luyện lại/Ngôi sao. Một số lần nói lại đáp án trong Practice gọi thẳng bộ phát chung.

Endpoint TTS mặc định của từ điển được xác định trong [MinhqndDictionaryProvider](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/features/vocabulary/data/minhqnd_dictionary_provider.dart:91). Lượt rà soát không gọi endpoint này.

Không đọc dữ liệu trên điện thoại; do đó không đưa ra số lượng câu ba mẹ đã thêm thực tế. Store nằm trong SharedPreferences, key `innotrik.vocabulary.v1`.

### Dịch offline

Kết quả dịch là text mở. Trên Android, [nhánh dịch offline](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/features/conversation/presentation/conversation_controller.dart:3714) gọi `speakAndWaitStyled`; [wrapper](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/core/audio/main_assistant_audio_prompt_service.dart:244) chuyển thẳng sang bộ đọc thiết bị, không lookup audio tạo sẵn. Ở nhánh khác dùng lời gọi thông thường, text khớp mới có thể dùng asset.

### Dịch online và lịch sử

App phát `preferredPlaybackUri`/`result.audioUri` do luồng dịch hoặc rule cung cấp. Đây là đường phát riêng, không tự đổi sang Eleven v3 chỉ vì đã bổ sung MAIN/CURRICULUM. Chưa xác minh nhà cung cấp TTS/model đang chạy ở backend production. Lịch sử phát lại URI đã lưu.

### Giọng của trẻ

Ghi âm trẻ trong Ngôi sao, bài học và lịch sử là dữ liệu thu âm, **không phải câu HOMI cần tạo TTS**. Không được thay các file này bằng giọng HOMI.

## 4. Những nội dung không nên cộng nhầm vào số audio còn thiếu

### Biến thể nhận diện không phải biến thể đầu ra

Giáo trình có **727 mục recognitionVariants** — bao gồm cả những mục lặp lại câu chuẩn. Chúng giúp nhận diện/chấm câu trẻ nói, không phải lệnh để HOMI đọc mọi mục đó. Tương tự, bộ 488 câu trẻ nói và 12 mẫu số thuộc phía nhận lệnh, không phải 500 audio đầu ra.

Ví dụ target “A. Apple.” chấp nhận “Apple.”: HOMI đọc mẫu target; “Apple.” chỉ cần audio riêng nếu một đường khác thực sự đọc nó, như đáp án Challenge. Rà soát đã tách hai vai trò này.

### Nhánh chọn bài/hướng dẫn cũ

`beginLessonSelectionForTopic` vẫn có ở controller và được truyền qua callback, nhưng trong TopicListeningScreen hiện tại callback chỉ được khai báo/nhận, không được gọi. Các biến thể tên chủ đề + tập bài đã xong của nhánh đó được xếp **compatibility**, không tính vào 28 câu thiếu hiện hành.

Tất cả 109 bài hiện tại dùng V4. Intro/ending kiểu LessonGuideV2, tổng kết và karaoke đời cũ được tách riêng. Inventory có **684 text–locale tương thích**, trong đó **673 chưa có audio khớp**; đây **không phải đề nghị tạo thêm 673 file**. Nếu bật lại các luồng này phải kiểm kê lại điều kiện truy cập và dữ liệu lúc đó.

Không tính thêm “Bạn cần hoàn thành Level 3 trước nhé.”: giáo trình chỉ có ba Level, nên không có Level 4 bị khóa để đi vào nhánh ấy. Cũng không tính 10 câu retry cũ “Con có muốn học lại chủ đề số N không?…” thành câu hiện hành: các đường hiện tại được xử lý bởi nhánh có/không, echo hoặc FB-007 trước đó.

### Nội dung chỉ có trong catalog hoặc kho audio

Role-play, Mission, một số system prompt, câu gợi ý và file đã chuẩn bị có thể tồn tại mà chưa được luồng hiện hành gọi để đọc. Inventory giữ chúng với nhãn `catalog_only` hoặc `audio_catalog_only`, không xóa và không đánh đồng với câu đang chạy.

Kho cũ ngoài MAIN/CURRICULUM có 217 file media. Có 5 bài hát được giáo trình hiện tại tham chiếu trực tiếp; cả 5 file tồn tại và được khai báo đóng gói. Chưa nghe/chép lại lời của các bài hát hoặc cue MP3 cũ; không suy đoán nội dung từ tên file, và không tính nhạc thành câu TTS mới. Không tìm thấy file cũ trùng basename các mã cue đã kiểm tra để ghi đè lời hiện hành.

## 5. Một điểm lệch giữa chữ và tiếng cần lưu ý

Ở [LessonIntroScreen](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/lib/features/listening/presentation/lesson_intro_screen.dart:141), app ưu tiên `introAudioUri` khi không phải `relearnFromBeginning`. `_guideText` lại có thể là “Mình học tiếp bài…”, “Mình tiếp tục câu thử thách…” hoặc một intro ghép tên chủ đề/bài.

Vì vậy ở các trạng thái này, **text hướng dẫn đã đổi nhưng âm thanh có thể vẫn là clip intro ban đầu**. Tạo thêm file cho `_guideText` không đủ để đổi điều đó nếu đường chọn URI vẫn giữ nguyên. Rà soát tách các câu bị URI ưu tiên thành `conditional`, không báo chúng như câu luôn thực sự được đọc. Cần kiểm thử luồng resume/relearn trên thiết bị trước khi đổi cách chọn clip. Lượt này chưa sửa.

## 6. Bằng chứng, cách tái chạy và giới hạn

Đã thực hiện:

- Dò toàn bộ `lib` để lập danh sách điểm gọi giọng, các adapter trung gian và đường phát URI; lần theo nơi tạo nội dung thay vì đếm mọi chuỗi giao diện.
- Chạy **313 cấu hình, 79.798 lượt chuyển trạng thái** qua chính MainVoiceAssistantFlow, bao gồm 5 nhóm tuổi, tiến độ Level/chủ đề, học lại, trợ giúp, echo, fallback lặp lại và lỗi tải nội dung được mô phỏng cục bộ.
- Với nhánh tương thích chọn bài: sinh các tập con hoàn thành bài trong từng chủ đề. Không gán các câu đó vào nhánh hiện hành.
- Gọi thư viện phản hồi theo tuổi và hàm câu hoàn thành thật; đối chiếu thêm template trong UI với dữ liệu giáo trình hiện tại.
- Xác nhận cả 601 Challenge đều có thể được selector chọn cho target tương ứng.
- Kiểm tra exact text + locale + lookupLocales, số lượng match, file, SHA-256, khai báo assets và giới hạn bộ phát.
- **65 test hiện có liên quan đến MAIN, audio wrapper, từ vựng đã pass**; test audit domain riêng cũng pass.

Chưa thực hiện: kiểm thử phát thật Android/iOS/web, thao tác nút MAIN/BLE trên máy, nghe kiểm định mọi MP3, trích dữ liệu người dùng hay kiểm chứng backend production. Bộ thử hội thoại giới hạn chiều sâu và gộp nhánh theo trạng thái/output; kết quả kết hợp kiểm tra code, không phải chứng minh hình thức về mọi input/trạng thái hỏng có thể tưởng tượng.

Hai lệnh tái chạy từ thư mục dự án, không dùng API và chỉ xuất dữ liệu kiểm kê:

```powershell
flutter test tool/audit_homi_utterances_test.dart
node tool/audit_homi_audio.mjs
```

Các tệp kết quả:

- [Danh sách đầy đủ dạng CSV](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-inventory.csv): 3.540 hàng bao gồm mọi phạm vi; lọc `scopes` có `current` để xem 2.062 cặp hiện hành đã kiểm kê, sau đó lọc `audio_status = missing_exact_audio` để xem 28 câu.
- [Inventory JSON có nguồn và ngữ cảnh](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-inventory.json).
- [Tổng hợp số liệu](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-audit-summary.json).
- [Điểm gọi phát](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-callsites.json).
- [File, link trực tiếp và media cũ](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-assets.json).
- [Các nhóm nội dung động](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-dynamic-families.json).
- [Kết quả chạy domain](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-runtime-domain-audit.json) và [hash nguồn kiểm kê](D:/Code/HuaMei/App_noi/flutter/18_16th9/speaking-ai-flutter/deliverables/homi-speech-provenance.json).

## 7. Thứ tự xử lý đề xuất sau kiểm kê

1. Duyệt cách xưng hô của các câu lỗi, rồi bổ sung **28 câu hiện hành còn thiếu** bằng cơ chế asset-first hiện có. Không thay logic học tập chỉ để bổ sung giọng.
2. Kiểm thử riêng việc chọn clip intro/resume/relearn; đây là vấn đề chọn nội dung phát, không chỉ thiếu file.
3. Nếu yêu cầu cả câu mới cũng dùng ElevenLabs: thiết kế luồng sinh audio động và cache riêng cho dữ liệu ba mẹ/dịch, có giới hạn chi phí, chống tạo trùng và fallback an toàn. Không thể giải quyết bằng cách tạo trước một danh sách hữu hạn.
4. Giữ TTS dự phòng cho lỗi tải/phát và tình huống chưa có file; đo lại lý do fallback trên thiết bị trước khi cân nhắc tắt.

Các bước trên là đề xuất, chưa được thực hiện trong lượt rà soát.
