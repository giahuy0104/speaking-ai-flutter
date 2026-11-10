# Kế hoạch HOMI: dịch giữa các ngôn ngữ trên Android và iOS

Ngày lập: 10/11/2026. Trạng thái: kế hoạch, chưa triển khai.

Mốc mã nguồn dùng để đối chiếu (cập nhật 10/11/2026):

- FE: `origin/dev` @ `bc9a802a` (đã gồm PR #46 ML Kit offline 5 ngôn ngữ). Nhánh tính năng FE tạo từ `origin/dev`.
- BE: `origin/main` @ `8772e0a` (đã gồm `codex/multilingual-production-integration`). Nhánh tính năng BE tạo từ `origin/main`.
- Mọi số dòng bên dưới là theo hai mốc này; số dòng sẽ lệch khi `dev`/`main` tiếp tục thay đổi.

## 1. Phạm vi và tiêu chí hoàn thành

- Phạm vi đợt đầu: chọn ngôn ngữ nguồn và đích khác nhau trong 6 ngôn ngữ Việt (`vi`), Anh (`en`), Trung giản thể (`zh`), Nhật (`ja`), Hàn (`ko`), Pháp (`fr`); tổng cộng 30 chiều dịch. Mặc định cho người dùng hiện tại là Việt → Anh.
- Áp dụng cho luồng hội thoại/dịch giọng nói HOMI trên ứng dụng Flutter Android và iOS: ghi âm hoặc nhận dạng trực tiếp → bản chép lời → bản dịch → phát âm → lịch sử. Ngôn ngữ giao diện (`DisplayLanguage`) là cài đặt riêng, không quyết định ngôn ngữ dịch.
- Một lượt phải giữ cố định cặp nguồn–đích từ khi bắt đầu ghi âm đến khi lưu kết quả. Không cho chọn cặp giống nhau, không đổi cặp khi đang ghi âm/xử lý/hàng đợi câu đang chạy.
- Câu cũ và ứng dụng cũ tiếp tục đọc được: request thiếu `sourceLanguage` được hiểu là `vi`; lịch sử thiếu `sourceLanguage` được hiển thị như bản ghi tiếng Việt cũ. Không ghi đè dữ liệu lịch sử để suy diễn ngôn ngữ.
- Đợt đầu ưu tiên dịch trực tuyến. Offline chỉ báo “đã hỗ trợ” cho cặp có đủ ASR, mô hình dịch và TTS thực sự hoạt động trên thiết bị; không hứa offline cho cả 30 chiều. Trên `dev`, phần dịch offline (ML Kit) đã gần đủ; điểm nghẽn offline là **ASR** (Vosk chỉ có tiếng Việt).
- Chưa mở rộng nội dung bài học/từ vựng Việt–Anh hoặc hệ thống lệnh giọng nói HOMI sang 6 ngôn ngữ. Nếu sản phẩm muốn mở rộng hai phần đó, cần một hạng mục riêng vì dữ liệu và quy tắc hiện gắn với Việt–Anh. (Đã kiểm tra: module từ vựng có model riêng, không đọc lịch sử hội thoại.)

## 2. Hiện trạng đã xác minh

### Flutter FE (`ai-speaking-flutter-app`, `origin/dev`)

| Điểm hiện tại | Vị trí | Hệ quả khi đổi chiều |
|---|---|---|
| Chỉ có 5 đích `en/zh/ja/ko/fr` (`TranslationOutputLanguage`, có `speechLocale`), không có `vi`; `fromCode` mặc định `english` | `lib/features/conversation/domain/conversation_models.dart:16` | Cần một danh mục ngôn ngữ dùng cho cả nguồn và đích, gồm locale ASR/TTS tương ứng. |
| Màn hình chỉ có “Dịch sang”: mobile dùng menu, màn hình rộng dùng `DropdownButton` | `lib/features/conversation/presentation/conversation_screen.dart:157`, `:526` | Cần cập nhật cả hai bố cục và thêm nút đổi chiều. |
| Controller giữ `outputLanguage`; `setOutputLanguage` gọi `setTranslationTarget` lên repository; local exact/offline/preview/early-rule playback điều kiện theo đích Anh | `lib/features/conversation/presentation/conversation_controller.dart:511`, `:641`, `:858`, `:875`, `:933–939`, `:3409`, `:3438`, `:3864`, `:3978`, `:4002`, `:5377` | Các tối ưu Việt → Anh phải xét **cả nguồn `vi` và đích `en`**. |
| Repository giữ trạng thái mutable `_translationTarget`; direct upload, finalize và streaming text chỉ gửi `targetLanguage`; batch prefetch và preview tự tắt khi đích khác Anh | `lib/features/conversation/data/next_conversation_repository.dart:51–56`, `:179`, `:248`, `:363`, `:324`, `:515`, `:558` | Truyền cặp ngôn ngữ theo từng lời gọi (không dùng setter mutable); gửi đủ hai mã qua mọi transport. |
| `/api/conversation/prepare` (worker prepare) không gửi `targetLanguage` | `next_conversation_repository.dart:819` | Hiện chỉ dùng ở chế độ Worker ASR Pilot (không cho người dùng chọn). Khóa đường này ở `vi → en` hoặc gửi đủ cặp. |
| Model kết quả/lịch sử đọc `vietnameseText`, `englishText`, `translatedText` | `conversation_models.dart:171–239` (`ConversationResult`), `:272–352` (`ConversationHistoryItem`) | Cần `sourceLanguage`, `sourceText` và trường bản dịch chuẩn cho dữ liệu mới, vẫn đọc bản ghi cũ. |
| Result panel gắn nhãn “Câu tiếng Việt” | `lib/features/conversation/presentation/widgets/result_panel.dart:44` | Nhãn phải dựa trên cặp ngôn ngữ của **lượt kết quả**, không phải lựa chọn hiện thời. |
| Lịch sử: tìm kiếm, dòng tóm tắt, hộp thoại xóa, nhãn đọc màn hình dùng `vietnameseText` | `lib/features/settings/presentation/history_sheet.dart:94`, `:207`, `:330`, `:635`, `:661` | Đổi sang `sourceText` + nhãn ngôn ngữ của bản ghi. |
| Home shell theo dõi `outputLanguage` và dựng bản dịch từ `englishText`/`vietnameseText` | `lib/features/home/presentation/home_learning_shell.dart:170`, `:650`, `:767` | Theo dõi cả cặp; dùng trường chuẩn. |
| ML Kit offline: Việt → 5 đích, model tải sau khi đồng ý lúc setup; có interface Anh → Việt. `translateTo` cố định nguồn `TranslateLanguage.vietnamese` | `lib/features/conversation/application/offline_language_service.dart:120–161`, `:274` | ML Kit dịch qua tiếng Anh nên khi đủ 6 model có thể dịch offline 30 chiều: chỉ cần tham số hóa nguồn. |
| ASR offline Vosk chỉ `vi-VN` | `offline_language_service.dart:30–54` | Offline cho nguồn khác `vi` phụ thuộc ASR on-device của OS; không dùng Vosk. |
| Chuẩn bị ASR/offline lúc mở app cố định `vi-VN` (kể cả `prepareBackgroundLocale('vi-VN')` cho iOS) | `lib/app/ai_speaking_app.dart:605`, `:609`, `:621`, `:624`, `:671`, `:683`, `:729` | Khi người dùng chọn nguồn khác, phải chuẩn bị tài nguyên ASR cho locale đó trước lượt (đặc biệt iOS SpeechAnalyzer). |
| `StreamingSpeechInput.start()` **không có tham số locale**; hội thoại gọi `_streamingSpeechInput!.start()` | `lib/core/audio/streaming_speech_input.dart:122`, `:642`, `:1444`; `conversation_controller.dart:2769` | Đổi interface và mọi bản cài đặt (Android, iOS, HFP, web batch, BLE). iOS đã có `_startWithAudioRoute(localeIdentifier:)` (đang dùng `en-US` cho bài học) để tái sử dụng. |
| Native ASR Android nhận `locale` (mặc định theo bridge); iOS mặc định `vi-VN` và nhận `locale` lúc `speech.start` | `android/app/src/main/kotlin/com/innotrik/aispeaking/AndroidSpeechRecognizerBridge.kt:134`, `ios/Runner/IOSSpeechRecognizerBridge.swift:316`, `:362`, `:472` | FE phải truyền locale nguồn của lượt; kiểm tra khả năng model trên từng OS/thiết bị. |

### Next.js BE (`../BACK-END Flutter-Nextjs APP/speaking-ai-nextjs-backend`, `origin/main`)

| Điểm hiện tại | Vị trí | Hệ quả khi đổi chiều |
|---|---|---|
| `TargetLanguage` chỉ có `en/zh/ja/ko/fr`; `parseTargetLanguage` mặc định `en`, mã lạ trả 400 | `src/types/conversation.ts:3`, `src/lib/ai/targetLanguage.ts:4` | Thêm `vi` và bộ kiểm tra cặp nguồn–đích. |
| `/api/conversation` parse đích (JSON và multipart) và rẽ nhánh theo `targetLanguage === "en"` | `src/app/api/conversation/route.ts:40`, `:109`, `:152` | Nhật → Anh không được chạy pipeline Việt → Anh. |
| `/api/audio-sessions/[id]/finalize`: parse đích, đường tắt cho đích khác Anh ở `browser_streaming`, rẽ nhánh đích khác Anh, và pipeline prefetch/hedged ASR gán cứng `targetLanguage: "en"` | `src/app/api/audio-sessions/[audioSessionId]/finalize/route.ts:132`, `:232`, `:313`, `:625` | Thêm nguồn trong body; đường prefetch/hedged chỉ dùng khi `vi → en`. |
| Audio-session preview gán cứng `targetLanguage: "en"`; `/api/conversation/prepare`, `/prepare/finalize`, `/prepare/commit`, `/api/conversation/preview` không nhận cặp ngôn ngữ | `src/app/api/audio-sessions/[audioSessionId]/preview/route.ts:133`, `src/app/api/conversation/prepare/**`, `src/app/api/conversation/preview` | Khóa các đường này ở `vi → en`, trả lỗi/bỏ qua cho cặp khác. |
| Pipeline đích khác Anh gọi `transcribeVietnamese` rồi dịch câu Việt; `prepareConversationPipeline` và `runConversationPipeline` là đường Việt → Anh | `src/lib/ai/pipeline.ts:64–72`, `:143`, `:215`, `:324` | Cần pipeline tổng quát cho nguồn khác `vi`; giữ đường Việt → Anh đã tối ưu. |
| `transcribeVietnamese` chạy `assertVietnameseTranscript` **cả với text từ thiết bị** và sửa câu trẻ em tiếng Việt; Whisper gọi `language: "vi"` kèm `initial_prompt` tiếng Việt | `src/lib/ai/asr.ts:93`, `:108–131`; `src/lib/ai/aiProvider.ts:274–277`; `src/lib/ai/cloudflareWorkersAi.ts:414–418` | Câu Nhật gửi lên sẽ bị chặn bởi kiểm tra tiếng Việt. Chỉ chạy kiểm tra/sửa tiếng Việt khi nguồn `vi`; truyền ngôn ngữ nguồn cho Whisper (`whisper-large-v3-turbo` hỗ trợ cả 6). |
| Đã có `translateAudioToEnglish(audio, sourceLanguage)` dịch nguồn bất kỳ → Anh, cache/checkpoint phân biệt nguồn | `src/lib/ai/cloudflareWorkersAi.ts:117–135`, `src/lib/ai/audioTranslationRoute.ts:135`, `:204` | Tham khảo/tái sử dụng cho X → Anh; endpoint `/api/audio/translate` vẫn chỉ ra Anh, không phải API hội thoại 30 chiều. |
| Prompt đích khác Anh nói rõ “child's Vietnamese utterance”; `buildTargetLanguageInstruction` nhận `Exclude<TargetLanguage, "en">` | `src/lib/ai/prompts.ts:17–28`, `src/lib/ai/targetTranslation.ts:64–68` | Prompt phải theo đúng cặp; hàm dịch `translateVietnameseWithCloudflare` cần đổi thành dịch tổng quát. |
| TTS: đích Anh dùng `@cf/deepgram/aura-1`; đích khác dùng `xai/grok-tts` với `TargetSpeechLanguage = zh/ja/ko/fr` | `src/lib/ai/aiProvider.ts:12–17`, `:307–350` | Đích `vi` chưa có giọng backend: kiểm tra grok-tts có `vi`, nếu không thì trả `device_tts` `vi-VN`. |
| Lịch sử lưu nguyên object kết quả (namespace `conversation_history`); học/rule/feedback coi bản ghi thiếu `targetLanguage` hoặc đích `en` là đủ điều kiện | `src/lib/history.ts:40`, `:198–212`, `src/lib/ai/postResponseTasks.ts:64`, `src/app/api/history/route.ts:198` | Điều kiện học phải là **nguồn Việt (hoặc thiếu) + đích Anh (hoặc thiếu)**; không phải mọi câu có đích Anh. |

## 3. Hợp đồng dữ liệu đề xuất

Áp dụng cho request `/api/conversation` (JSON và multipart), `/api/audio-sessions/[id]/finalize`, và mọi request prepare/preview dùng cho hội thoại:

```json
{
  "sourceLanguage": "ja",
  "targetLanguage": "ko",
  "sourceText": "... hoặc audio theo transport hiện có",
  "context": "home"
}
```

- BE chấp nhận đúng 6 mã ngôn ngữ, từ chối mã lạ hoặc cặp trùng nhau bằng lỗi 400 có mã lỗi ổn định. Request từ app cũ thiếu `sourceLanguage` mặc định `vi`; mặc định `targetLanguage` vẫn là `en`.
- Response mới luôn có `sourceLanguage`, `targetLanguage`, `sourceText` (bản chép lời) và `translatedText` (bản dịch cuối). Các trường cũ `vietnameseText`/`englishText` được giữ cho response và lịch sử cũ; chỉ điền theo đúng ý nghĩa ngôn ngữ của chúng, không nhét câu Nhật vào `vietnameseText` hay câu Hàn vào `englishText`.
- Lưu cặp ngôn ngữ cùng kết quả và lịch sử. Các key cache kết quả dịch, bản chuẩn bị, prefetch, idempotency/checkpoint phải phân biệt nguồn, đích và nội dung; cache âm thanh tiếp tục phân biệt locale/voice/model. Không tái sử dụng bản dịch hoặc audio của cặp khác.
- Nếu cần duy trì API cũ cho client đang phát hành, có thể trả song song các trường chuẩn mới và trường cũ ở đường Việt → các đích hiện hành. Trước khi bỏ trường cũ cần thống kê phiên bản client còn dùng.
- Lưu ý: app hiện tại đọc `vietnameseText` bằng `?? ''`. Với lượt nguồn khác `vi`, app cũ sẽ không gặp (app cũ chỉ gửi nguồn `vi`), nhưng lịch sử dùng chung giữa app cũ và mới cần kiểm tra: app cũ đọc bản ghi Nhật → Hàn sẽ thấy câu gốc trống.

## 4. Các bước triển khai theo thứ tự

### Bước 0 — Nhánh và môi trường test

1. FE: tạo nhánh từ `origin/dev`. BE: tạo nhánh từ `origin/main`.
2. BE deploy hiện chỉ chạy khi push lên `can-bang-tai` (`.github/workflows/deploy.yml:7`), nên nhánh tính năng không tự deploy. Chạy BE local hoặc dựng staging riêng, rồi build app với `--dart-define` trỏ backend sang đó (mặc định là `https://api.hoamytech.com` tại `lib/config/app_config.dart:4`).

### Bước 1 — Chốt ma trận năng lực và hợp đồng BE/FE

1. Liệt kê locale ASR/TTS cho 6 ngôn ngữ và kiểm tra provider trên Android, iOS, backend. Xác nhận biến thể tiếng Trung là giản thể và locale dự kiến cho từng ngôn ngữ.
2. Chốt schema request/response ở mục 3, quy tắc `vi` mặc định, lỗi cặp trùng, lỗi ASR/TTS thiếu hỗ trợ, cùng quy tắc đọc lịch sử cũ.
3. Chốt phạm vi preview/offline: đợt đầu giữ preview nhanh, prefetch, worker prepare cho Việt → Anh; các cặp còn lại dùng đường chuẩn và hiển thị trạng thái thực tế.

**Đầu ra:** hợp đồng có ví dụ cho Việt → Anh, Nhật → Hàn, Pháp → Việt và app cũ không gửi nguồn.

### Bước 2 — BE: dữ liệu và pipeline tổng quát

1. Thêm `SourceLanguage` và `vi` cho đích trong `src/types/conversation.ts`; thêm parser/validator nguồn và cặp trong `src/lib/ai/targetLanguage.ts` (có thể đổi tên module khi triển khai).
2. Giữ `runConversationPipeline` hiện tại cho `vi → en`. Cho `vi → zh/ja/ko/fr` đi đường `runTargetLanguageConversationPipeline` hiện có. Tạo đường tổng quát cho nguồn khác `vi`, bao gồm đích `en` và `vi`; **không** dựa riêng vào điều kiện đích Anh. Với X → Anh có thể tái sử dụng logic của `translateAudioToEnglish`.
3. Tách bản chép lời tổng quát khỏi `transcribeVietnamese` trong `src/lib/ai/asr.ts`. Chỉ chạy `assertVietnameseTranscript`, sửa câu trẻ em và `initial_prompt` tiếng Việt khi nguồn `vi`; giữ chính sách VAD phù hợp với cách thu âm. Truyền ngôn ngữ nguồn cho Whisper (`aiProvider.ts:274`, `cloudflareWorkersAi.ts:418`) và phản hồi lỗi rõ ràng nếu không hỗ trợ.
4. Sửa prompt trong `src/lib/ai/prompts.ts`/`targetTranslation.ts` để mô tả đúng ngôn ngữ nguồn và đích, giữ yêu cầu dịch trung thành; kiểm tra đầu ra theo chữ viết/ngôn ngữ đích thay vì dùng luật tiếng Việt cho mọi nguồn.
5. Mở rộng TTS trong `src/lib/ai/aiProvider.ts`: đích `en` giữ aura-1; thử `xai/grok-tts` với `vi`. Nếu không có giọng hoặc tạo audio thất bại, trả `device_tts` cùng locale đích chính xác, không trả audio của ngôn ngữ khác.

**Cổng nghiệm thu:** gọi pipeline bằng text cho ít nhất Việt → Anh, Nhật → Anh, Anh → Việt, Trung → Pháp; response và audio đều có cặp đúng, request sai trả 400.

### Bước 3 — BE: cập nhật đủ các entry point và dữ liệu tồn tại

1. Cập nhật `/api/conversation` cho JSON và multipart; cập nhật finalize của audio session (gồm cả `pipelineInput` đang gán cứng `"en"` ở `:625`). Giữ xác thực `requireInstallationAccess` và `authorizeAudioSessionRequest` như hiện tại.
2. Rà `/api/conversation/prepare`, `/prepare/finalize`, `/prepare/commit`, `/api/conversation/preview`, audio-session preview/prefetch: nơi nào vẫn là đường nhanh Việt → Anh thì khóa bằng điều kiện `sourceLanguage === "vi" && targetLanguage === "en"`; nơi nào hỗ trợ cặp khác thì truyền và kiểm tra cặp qua toàn bộ vòng đời. Không trả preview tiếng Anh cho lượt có đích khác.
3. Thêm trường mới vào response và lịch sử tại `src/lib/history.ts`; reader `/api/history` trả đúng trường mới, dữ liệu cũ được đọc như nguồn Việt mà không viết lại. Storage hiện lưu object JSON nên dự kiến không cần migration bảng; vẫn phải kiểm tra mọi index/query và export liên quan trước khi chốt.
4. Đổi guard học/rule/feedback ở `history.ts:207–210`, `postResponseTasks.ts:64`, `/api/history:198`, admin review và các consumer `vietnameseText`/`englishText` (khoảng 17 file) sang xét đúng cặp `vi → en`. Phân biệt thao tác đánh giá chất lượng bản dịch với thao tác học rule; các cặp khác không được tạo rule Việt–Anh từ nội dung ngôn ngữ khác.
5. Thêm cặp ngôn ngữ vào log/telemetry không chứa nội dung câu, để theo dõi lỗi và độ trễ theo chiều dịch.

**Cổng nghiệm thu:** đọc lại lịch sử vừa ghi và lịch sử cũ; không có phản hồi Nhật → Anh nào được đưa vào học Việt–Anh; retry/finalize cùng request trả cùng cặp và kết quả.

### Bước 4 — Flutter FE: chọn cặp và truyền xuyên suốt lượt

1. Tạo model ngôn ngữ chung trong `conversation_models.dart` với mã API, tên hiển thị, locale ASR/TTS (mở rộng từ `TranslationOutputLanguage` và thêm `vi`). Tách khỏi `DisplayLanguage` (ngôn ngữ giao diện).
2. Trong `conversation_controller.dart`, giữ `sourceLanguage` và `targetLanguage`, mặc định `vi → en`; thêm chọn nguồn, chọn đích, đổi chiều. Snapshot cặp khi bắt đầu lượt/hàng đợi để response đến muộn không bị gán nhãn theo lựa chọn mới. Thay các điều kiện `outputLanguage == english` liệt kê ở mục 2 bằng điều kiện cặp `vi → en`.
3. Thay interface `TranslationTargetRepository` (`domain/conversation_repository.dart:74`) bằng hợp đồng cặp nguồn–đích truyền theo từng lời gọi; cập nhật `next_conversation_repository.dart` ở direct upload, streaming text, chunk finalize, batch prefetch, worker prepare và preview. Bỏ trạng thái mutable `_translationTarget`.
4. Cập nhật menu mobile và dropdown màn hình rộng trong `conversation_screen.dart`: hai bộ chọn, nút đổi chiều, disable theo cùng guard controller; chỉ hiện trạng thái offline khi cặp thực sự có thể dùng offline.
5. Đọc response và lịch sử mới/cũ trong `conversation_models.dart`; sửa result panel, `history_sheet.dart`, `home_learning_shell.dart`, phát lại để lấy nhãn và TTS locale từ **bản ghi**. Khi đang xem kết quả cũ rồi chọn cặp mới, kết quả cũ không đổi ngôn ngữ hoặc nhãn.

**Cổng nghiệm thu:** cả Android/iOS chọn và đổi chiều được; gửi ra đủ hai mã; kết quả cũ, kết quả mới và audio replay đúng cặp.

### Bước 5 — Native ASR và offline theo năng lực thực tế

1. Thêm tham số locale cho `StreamingSpeechInput.start()` và mọi bản cài đặt; truyền locale nguồn tới `speech.start` ở Android/iOS. Chuẩn bị tài nguyên ASR cho locale nguồn khi người dùng chọn cặp (thay cho chỉ `vi-VN` ở `ai_speaking_app.dart`). Kiểm tra một lượt trên mic điện thoại và đường mic HOMI; tách locale của lệnh điều khiển HOMI (`startCommandRecognition`, giữ `vi-VN`) khỏi locale nội dung cần dịch.
2. Kiểm tra model ASR theo thiết bị và OS. Nếu model/locale chưa sẵn sàng, báo đúng nguyên nhân và dùng phương án online đã được kiểm chứng; không tự ghi câu ngôn ngữ này như ngôn ngữ khác.
3. Giữ ML Kit/Vosk/Apple Speech offline hiện có theo cặp được hỗ trợ. Tham số hóa nguồn trong `translateTo` của ML Kit để dùng lại các model đã tải lúc setup; chỉ bật offline cho cặp khi ASR on-device của nguồn và TTS của đích đều sẵn sàng. Không tải thêm model khi mở app ngoài những gì setup hiện đã tải.

**Cổng nghiệm thu:** cùng một cặp được nói, dịch, phát lại trên ít nhất một Android và một iPhone thật; mất mạng tạo thông báo đúng cho cặp không hỗ trợ offline.

### Bước 6 — Kiểm thử và phát hành

| Ca bắt buộc | Kết quả mong đợi | Bằng chứng |
|---|---|---|
| App cũ: request thiếu nguồn, đích Anh | Tiếp tục Việt → Anh, rule/cache cũ vẫn dùng | BE API test + read-back lịch sử |
| Việt → Trung và Việt → Anh | Hai đường cũ không đổi nghĩa, giọng đọc đúng | BE test + Android/iOS smoke |
| Nhật → Anh | Không chạy kiểm tra/sửa transcript, rule, học tiếng Việt; không đi đường prefetch/preview Việt → Anh | BE pipeline test + lịch sử/feedback |
| Anh → Việt, Pháp → Hàn | Bản chép lời đúng nguồn, dịch/giọng đọc đúng đích (Việt dùng giọng backend hoặc `device_tts vi-VN`) | API integration + thiết bị thật |
| Chọn cùng ngôn ngữ, mã lạ, model ASR thiếu | Guard UI và lỗi BE thống nhất; không lưu lượt sai | Unit/API/UI test |
| Đổi chiều trước lượt; cố đổi khi ghi âm; response đến muộn | Mỗi lượt giữ cặp đã snapshot | Controller/widget test |
| Preview, chunk finalize, retry, mất mạng sau upload | Không lẫn cặp/cache; lỗi có thể thử lại; không tạo lịch sử sai | BE integration + FE repository test |
| Lịch sử trước nâng cấp và sau nâng cấp | Câu gốc/bản dịch, nhãn, audio replay đúng; không sửa bản ghi cũ | API read-back + widget test |
| Lệnh HOMI khi đang chọn nguồn khác `vi` | Lệnh điều khiển vẫn nhận dạng tiếng Việt | Thiết bị thật Android/iOS |

Chạy typecheck/lint/test tập trung ở cả hai repo (`npx tsc --noEmit`, `npm run lint`, test BE liên quan; `flutter analyze`, `flutter test` các test conversation), rồi kiểm thử thủ công trên Android và iOS thật. Chỉ công bố hỗ trợ cặp ngôn ngữ sau khi đã kiểm tra ASR, dịch và TTS của cặp đó trên môi trường triển khai.

## 5. Thứ tự phát hành và điểm cần quyết định

1. Phát hành BE tương thích ngược trước; app cũ vẫn gửi mặc định Việt → Anh hoặc Việt → 4 đích hiện có.
2. Bật FE mới sau khi BE và provider đã qua ma trận kiểm thử. Nên có cấu hình/feature flag cho danh sách cặp đã xác minh để có thể tắt một cặp lỗi mà không chặn các cặp khác.
3. Theo dõi lỗi ASR, lỗi dịch, TTS fallback, thời gian xử lý, tỷ lệ đọc lại lịch sử theo cặp; rollback bằng cách ẩn chọn nguồn mới, vẫn giữ BE đọc được trường mới.
4. Cần chủ sản phẩm xác nhận: 6 ngôn ngữ hiện có có đúng là phạm vi đợt đầu không; tiếng Trung dùng `zh-CN`/giản thể; tính năng “học rule từ phản hồi” có giữ riêng cho Việt → Anh không; có yêu cầu offline cho cặp nào ngoài Việt → 5 đích hiện có không. Các quyết định này không cản trở việc thiết kế API tương thích ngược.

## 6. Những gì chưa được xác minh trong bản kế hoạch

- Chưa chạy ứng dụng, test hoặc gọi provider thật; chưa chứng minh ASR/TTS của tất cả 6 ngôn ngữ trên mọi bản Android/iOS. Đây là cổng kỹ thuật của bước 1 và bước 5.
- Chưa thử `xai/grok-tts` với tiếng Việt; chưa thử Whisper trên Cloudflare với nguồn `ja/ko/zh/fr` trong luồng hội thoại.
- Chưa rà toàn bộ cấu hình production, dữ liệu lịch sử thực tế và mọi consumer admin/export; bước 3 yêu cầu kiểm tra trước khi khẳng định không cần migration hoặc trước khi phát hành.
- Chưa thay đổi mã nguồn FE/BE.

## 7. Trạng thái triển khai (nhánh `feat/homi-multilingual-pairs`)

Cập nhật 10/11/2026. FE tạo từ `origin/dev` @ `bc9a802a`, BE tạo từ `origin/main` @ `8772e0a`. Chưa commit, chưa merge.

### BE (`speaking-ai-nextjs-backend-multilingual-pairs`)

- `src/lib/ai/targetLanguage.ts`: `parseLanguagePair` (thiếu nguồn → `vi`, thiếu đích → `en`, cặp trùng/mã lạ → 400 có `reason`), `isVietnameseToEnglish`, `withConversationLanguageFields` (điền trường mới khi trả về, không ghi lại bản ghi cũ).
- Định tuyến: `vi → en` giữ `runConversationPipeline`; mọi cặp khác đi `runTargetLanguageConversationPipeline` (đã tổng quát hóa). `/api/conversation` và finalize audio-session dùng cùng điều kiện; prefetch/hedged ASR chỉ chạy cho `vi → en`.
- ASR: `transcribeSourceLanguage` — nguồn `vi` giữ nguyên kiểm tra/sửa câu trẻ em; nguồn khác bỏ qua các lớp tiếng Việt, gọi Whisper với ngôn ngữ nguồn.
- Prompt/kiểm tra đầu ra: prompt `vi → X` không đổi; nguồn khác dùng tên ngôn ngữ đúng; đích `en/fr/vi` phải có chữ Latin.
- TTS: grok-tts nhận cả `vi`/`en`; lỗi thì trả `device_tts` đúng locale đích.
- Preview, batch prefetch, worker prepare: cặp khác `vi → en` trả `matched:false` / `eligible:false` / 400.
- Học rule, feedback, admin review, promote rule: chỉ cho `vi → en` (bản ghi cũ thiếu trường vẫn đủ điều kiện).
- Test: `src/lib/ai/languagePair.test.mjs` (9 test). Toàn bộ unit test: 414/416 pass; 2 test lỗi (`deadline.test.ts`, `upload.test.ts`) cũng lỗi y hệt trên `main` sạch.

### FE (`ai-speaking-flutter-app-multilingual`)

- `TranslationOutputLanguage` thêm `vietnamese`; `sourceFromCode` mặc định `vi`; `isVietnameseToEnglishPair`.
- `ConversationResult`/`ConversationHistoryItem`: `sourceLanguage`, `sourceText`, `displayedSource`, `isVietnameseToEnglish`.
- Repository: interface mới `TranslationSourceRepository`; gửi `sourceLanguage` ở upload, finalize, streaming text; preview/prefetch/worker prepare chỉ `vi → en`.
- Controller: `sourceLanguage`, `setSourceLanguage`, `swapTranslationLanguages`, chọn trùng thì tự đổi chiều; khóa khi đang ghi âm/xử lý/hàng đợi; các tối ưu Việt → Anh và offline chỉ chạy cho nguồn `vi`; thông báo offline riêng cho cặp không hỗ trợ.
- ASR native: interface `ConversationLocaleSpeechInput`; locale nguồn chỉ được đặt trong lúc bắt đầu lượt hội thoại rồi xóa, nên bài học và lệnh HOMI giữ locale riêng. Không cần sửa Kotlin/Swift.
- UI: bộ chọn “Nói bằng” + nút đổi chiều + “Dịch sang” (mobile và màn hình rộng); result panel và lịch sử lấy nhãn/câu gốc từ bản ghi. Khi repository không hỗ trợ chọn nguồn, “Tiếng Việt” không xuất hiện trong danh sách đích.
- Bộ sửa transcript tiếng Việt phía client và luật tách câu hỏi tiếng Việt (`splitFinalSentences`) chỉ chạy khi nguồn là `vi`.
- Báo “sẵn sàng offline” (`ai_speaking_app.dart`) luôn là chưa sẵn sàng cho nguồn khác `vi`.
- Test mới: `language_pair_controller_test.dart`, thêm ca trong `conversation_models_test.dart`, `next_conversation_repository_test.dart`, `sentence_queue_test.dart`; cập nhật kỳ vọng trong `home_learning_shell_golden_test.dart` (ảnh golden không đổi).

### Sửa sau review (flutter-reviewer + review BE)

- BE: `migrateApprovedHistoryLearning` (warmup) chỉ học từ bản ghi `vi → en` — trước đó một lượt Nhật → Anh được duyệt có thể làm warmup lỗi mãi (`Rule text is empty`). AI review của admin cũng chỉ cho `vi → en`.
- BE: `/api/conversation` lưu lịch sử bằng kết quả gốc của pipeline (giống finalize); khi đọc, `translatedText` của đích Anh lấy từ `englishText` để hiện đúng câu admin đã sửa. PATCH `/api/history` trả về đủ trường mới.
- BE: nguồn khác `vi` từ chối các câu “ảo giác” quen thuộc của Whisper khi im lặng; kiểm tra chữ Latin bỏ qua đầu ra không có chữ cái (ví dụ “5”).
- FE: Worker ASR pilot và đường BLE hybrid (intent tiếng Việt offline) chỉ chạy khi nguồn `vi`; lệnh MAIN trên web dùng repository riêng cố định Việt → Anh; lệnh giọng nói tiếng Việt chỉ khớp khi nguồn `vi`.
- FE: hàng đợi câu, banner offline (“cặp này chỉ dịch khi có mạng”), `displayedSource` khi `sourceText` rỗng, bố cục màn hình rộng giữ nhãn cạnh dropdown.
- Test thêm: khóa bộ chọn khi đang xử lý, nhãn result panel theo bản ghi, locale gửi xuống `speech.start` (lệnh MAIN không nhận locale hội thoại), các ca BE mới.
- Còn để sau (thấp): golden cho mobile có 2 bộ chọn ở cỡ chữ 200%; text hướng dẫn onboarding và gợi ý tìm kiếm lịch sử (“Tìm câu tiếng Việt hoặc tiếng Anh”) vẫn mô tả Việt → Anh, giữ nguyên để không lệch ảnh golden (cần sinh lại golden trên CI nếu đổi).

### Còn lại trước khi merge

- Test trên Android và iPhone thật cho từng ngôn ngữ nguồn (ASR thiết bị, mic HOMI/HFP).
- Kiểm tra `xai/grok-tts` có giọng `vi`; Whisper với nguồn `ja/ko/zh/fr` trên Cloudflare thật.
- Chạy BE nhánh này ở local/staging và build app với `--dart-define` trỏ tới đó.
