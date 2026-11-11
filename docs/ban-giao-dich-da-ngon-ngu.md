# Bàn giao: HOMI dịch qua lại giữa 6 ngôn ngữ

Tài liệu này gom lại toàn bộ phần đã làm để áp dụng sau này: dịch qua lại giữa
tiếng Việt, Anh, Trung, Nhật, Hàn, Pháp (30 cặp, mặc định Việt → Anh). Kế
hoạch gốc: [ke-hoach-homi-dich-da-ngon-ngu-android-ios.md](ke-hoach-homi-dich-da-ngon-ngu-android-ios.md).
Mục cuối là đề xuất phần chọn giọng đọc.

## 1. Nhánh và commit

| | FE (Flutter) | BE (Next.js) |
|---|---|---|
| Repo | `giahuy0104/speaking-ai-flutter` | `giahuy0104/speaking-ai-nextjs-backend` |
| Nhánh | `feat/homi-multilingual-pairs` | `feat/homi-multilingual-pairs` |
| Tách từ | `origin/dev` | `origin/main` |
| Commit | `3460f648` chọn ngôn ngữ nguồn và đích | `c440bda` dịch giữa mọi cặp vi/en/zh/ja/ko/fr |
| | (+ commit tài liệu này) | `b55ce0a` cho phép chạy CI verify thủ công |
| | | `07438bb` tăng tốc giọng đọc, sửa chất lượng dịch |
| Đã push | Có (trừ commit tài liệu này) | `c440bda`, `b55ce0a` đã push; `07438bb` chưa push |

Ghép thử (ngày 2026-11-11):

- **FE → `dev`:** ghép sạch, không xung đột (`dev` có thêm 2 commit mới).
- **BE → `can-bang-tai`** (nhánh BE đang chạy thật): chỉ xung đột 2 file cấu
  hình, `.env.example` và `.github/workflows/verify.yml`. Giữ cả hai phía là
  được, code không xung đột.

## 2. Thứ tự áp dụng

1. **Deploy BE trước.** App mới luôn gửi `sourceLanguage`; BE cũ không hiểu cặp
   như Trung → Việt và trả lỗi "Ngôn ngữ dịch không được hỗ trợ" (đã gặp trên
   iPhone khi app mới gọi BE cũ).
2. Đặt biến môi trường trên BE (mục 5), nhất là `TARGET_TTS_ENABLED`.
3. Ghép FE vào `dev`, build app.

App cũ (không gửi `sourceLanguage`) vẫn chạy bình thường: BE hiểu là tiếng Việt
và giữ nguyên luồng cũ.

## 3. Đã làm ở BE

**Cặp ngôn ngữ**

- `src/types/conversation.ts`: kiểu `ConversationLanguage` gồm 6 mã. Request có
  `sourceLanguage?`; response có `sourceLanguage` và `sourceText`.
- `src/lib/ai/targetLanguage.ts`
  - `parseLanguagePair`: nguồn mặc định `vi`, đích mặc định `en`.
  - Cặp sai trả 400 với `details.reason`: `same_source_and_target_language`,
    `unsupported_source_language`, `unsupported_target_language`.
  - `isVietnameseToEnglish`: bản ghi cũ thiếu trường được coi là Việt → Anh.
  - `withConversationLanguageFields`: đọc bản ghi cũ theo định dạng mới.

**Luồng xử lý**

- Việt → Anh giữ nguyên `runConversationPipeline`: luật, cache, học từ lịch sử,
  preview, prefetch, hedged request.
- Mọi cặp khác đi qua `runTargetLanguageConversationPipeline` (`pipeline.ts`),
  gồm ba bước:
  1. Nhận diện giọng nói: `transcribeSourceLanguage`. Nguồn không phải tiếng
     Việt thì bỏ qua bước kiểm tra/sửa tiếng Việt.
  2. Dịch trực tiếp bằng LLM.
  3. Đọc kết quả: `xai/grok-tts`, nếu không được thì dùng giọng điện thoại.
- `vietnameseText` chỉ điền khi nguồn là tiếng Việt; `englishText` chỉ điền khi
  đích là tiếng Anh.
- Các chức năng chỉ chạy cho Việt → Anh: học luật, admin review, ai-review,
  promote rule, migrate lịch sử, preview/prepare.

**Nhận diện giọng nói (`asr.ts`, `cloudflareWorkersAi.ts`)**

- Whisper nhận mã ngôn ngữ của nguồn.
- Loại các câu Whisper hay bịa ra khi im lặng ("ご視聴ありがとうございました",
  "Thanks for watching"…), nhưng không loại "Thank you".

**Dịch (`prompts.ts`, `targetTranslation.ts`)**

- `buildTargetLanguageInstruction(language, context, childAge, sourceLanguage)`.
  Prompt Việt → X giữ nguyên chữ như cũ.
- Prompt X → Việt có luật ngôi xưng kèm ví dụ: "I/我" dịch là "con", "you/你"
  dịch là "bạn" hoặc mẹ/bố…, không bao giờ dịch "you" thành "con".
- Nguồn không phải tiếng Việt: cho phép xử lý từ bị nghe nhầm, nhưng cấm thêm
  chi tiết không có trong câu.
- Kiểm tra chữ viết của bản dịch:
  - Đích zh/ja/ko phải có chữ của ngôn ngữ đó.
  - Đích vi/en/fr bị sót chữ Hán/Nhật/Hàn thì dịch lại 1 lần, kèm lời nhắc
    (lỗi kiểu "Anh Huy quá帅 rồi").
  - Bản dịch sai hoàn toàn chữ viết thì báo lỗi ngay, không dịch lại.

**Giọng đọc (`pipeline.ts`)**

- `TARGET_TTS_ENABLED=false`: luôn dùng giọng điện thoại, không gọi `grok-tts`.
- Khi `grok-tts` trả 401/402/403/429, BE bỏ qua nó trong
  `TARGET_TTS_FAILURE_COOLDOWN_MS` (mặc định 5 phút) rồi mới thử lại.

**Test:** `src/lib/ai/languagePair.test.mjs`, 34 test cho phần dịch đều đạt.
Toàn bộ BE đạt 448/453; 2 test lỗi (`deadline.test.ts`, `upload.test.ts`) đã
lỗi từ trước trên `main`, không do nhánh này.

## 4. Đã làm ở FE

- **Model** (`conversation_models.dart`)
  - Enum `TranslationOutputLanguage` thêm `vietnamese`, dùng cho cả nguồn và đích.
  - `sourceFromCode` mặc định trả `vi`; thêm `isVietnameseToEnglishPair`.
  - `ConversationResult` và `ConversationHistoryItem` có `sourceLanguage`,
    `sourceText`, `displayedSource`. `displayedSource` lấy `vietnameseText` nếu
    `sourceText` rỗng.
- **Repository**
  - Interface mới `TranslationSourceRepository`.
  - `NextConversationRepository` gửi `sourceLanguage` trong mọi request.
  - Prefetch, preview và worker prepare chỉ chạy cho Việt → Anh.
- **Controller** (`conversation_controller.dart`)
  - Chọn ngôn ngữ: `setSourceLanguage`, `swapTranslationLanguages`. Chọn trùng
    ngôn ngữ ở hai bên thì tự đảo cặp. Không đổi được khi đang xử lý một lượt.
  - Chỉ chạy cho Việt → Anh: dịch offline, luật chính xác, preview, phát sớm,
    sửa lỗi tiếng Việt, lệnh giọng nói tiếng Việt.
  - Nguồn khác tiếng Việt khi đi qua BLE thì ghi âm theo lô.
  - Mã lỗi mới `OFFLINE_PAIR_UNAVAILABLE`.
- **Nhận diện giọng nói** (`streaming_speech_input.dart`)
  - Interface `ConversationLocaleSpeechInput`, có ở Android, iOS và NativeFirst.
  - Locale chỉ đặt cho lượt hội thoại; lệnh MAIN và bài học giữ locale riêng.
- **Giao diện**
  - `_LanguagePairBar`: chọn nguồn, nút đảo cặp, chọn đích.
  - Thông báo offline khi nguồn không phải tiếng Việt.
  - `ResultPanel` và lịch sử ghi nhãn theo cặp của chính kết quả đó, không theo
    cặp đang chọn.
- **Offline:** `OfflineLanguageService` chỉ dịch từ tiếng Việt sang ngôn ngữ khác.
- **Test**
  - Mới: `language_pair_controller_test.dart`,
    `core_audio_conversation_locale_test.dart`.
  - Cập nhật: test model, repository, sentence queue và golden.
  - Test `test/app/*` (bluetooth) và test accessibility đã lỗi sẵn trên `dev`.

## 5. Biến môi trường BE

| Biến | Giá trị đề xuất | Ghi chú |
|---|---|---|
| `TARGET_TTS_ENABLED` | `false` | Tài khoản Cloudflare hiện tại trả 402 cho `xai/grok-tts`. Đặt `true` (hoặc xoá dòng) khi tài khoản dùng được. |
| `TARGET_TTS_FAILURE_COOLDOWN_MS` | `300000` | Chỉ có tác dụng khi `TARGET_TTS_ENABLED` bật. |
| `CLOUDFLARE_TEXT_TIMEOUT_MS` | `6000` | Để 2500 thì cặp Trung → Việt từng bị hết giờ. |

Việt → Anh dùng giọng `CLOUDFLARE_TTS_MODEL` (`aura`), không bị ảnh hưởng bởi
các biến trên.

## 6. Kết quả test thật (Android, BE local, 2026-11-11)

- Đã thử chạy được: Anh → Việt, Trung → Việt, Trung → Anh.
- **Tốc độ** (từ lúc BE nhận câu đến lúc có tiếng đọc, trung vị):

  | | Số lượt | Trung vị |
  |---|---|---|
  | Trước khi sửa | 19 | 2,52 s |
  | Sau khi tắt `grok-tts` | 18 | 0,79 s |

  Lượt chậm nhất sau khi sửa là 4,6 s, do Cloudflare chậm ở bước dịch.
- **Chất lượng sau khi sửa**
  - Ngôi xưng đúng: "你吃饭了吗 → Bạn ăn cơm chưa?".
  - Không còn sót chữ Hán.
  - Khi điện thoại nghe sai cả câu, đôi khi mô hình vẫn thêm vài chữ.

## 7. Việc còn lại

1. **Nhận diện giọng nói cho nguồn không phải tiếng Việt.** Điện thoại hay nghe
   sai hoặc cắt giữa câu. Phương án: dùng Whisper trên server cho các nguồn này.
   Mỗi lượt chậm thêm khoảng 1 giây; cần sửa cả FE và BE.
2. **Gửi lại yêu cầu dịch khi Cloudflare chậm.** Nếu sau khoảng 2 giây chưa có
   kết quả thì gửi thêm một yêu cầu song song. Cắt được các lượt 4–5 giây nhưng
   tốn thêm lượt gọi.
3. **Đổi mật khẩu và khoá bí mật của BE chính:** admin, Neon, Cloudinary,
   Redis, `INSTALLATION_AUTH_SECRET`. Một file `.env` chứa các giá trị này đã bị
   chia sẻ ra ngoài trong lúc test.
4. Chưa thử trên iOS và chưa thử các cặp ja/ko/fr trên máy thật.
5. Sửa giọng đọc của điện thoại; xem mục 8.

## 8. Đề xuất phần chọn giọng

### Hiện trạng

- Mọi cặp khác Việt → Anh đều đọc bằng giọng điện thoại, qua `VoicePromptBridge`:
  Android dùng `TextToSpeech.setLanguage`, iOS dùng
  `AVSpeechSynthesisVoice(language:)`.
- App chỉ truyền locale (ví dụ `ja-JP`), không chọn giọng cụ thể, nên mỗi máy
  đọc một kiểu.
- **Lỗi cần sửa trước:** khi máy thiếu giọng của ngôn ngữ đích, cả Android
  (`VoicePromptBridge.kt`) và iOS (`VoicePromptBridge.swift`) đều quay về giọng
  `vi-VN`. Hậu quả là giọng tiếng Việt đọc câu tiếng Nhật, Hàn hay Pháp, nghe rất
  sai. Nên báo "Máy chưa có giọng tiếng Nhật" và gợi ý tải giọng, thay vì đọc
  bằng giọng Việt.

### Bước 1: chọn giọng của điện thoại (miễn phí, làm được ngay)

**Native**

- Thêm method `voices.list(locale)`, trả về danh sách `{id, name, locale,
  quality, needsNetwork, gender?}`:
  - Android: `TextToSpeech.getVoices()`; `Voice` có `name`, `locale`,
    `quality`, `isNetworkConnectionRequired`.
  - iOS: `AVSpeechSynthesisVoice.speechVoices()`; có `identifier`, `language`,
    `quality` (`.default`/`.enhanced`/`.premium`), `gender`.
- `speak` nhận thêm `voiceId`. Không tìm thấy giọng đó thì dùng giọng tốt nhất
  của cùng locale; không có giọng nào của locale đó thì báo lỗi, không đọc bằng
  `vi-VN`.
- Android có thể mở màn hình tải giọng bằng
  `TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA`.

**Giao diện** (Cài đặt → Giọng đọc)

- Mỗi ngôn ngữ một dòng: tên giọng đang dùng, nút "Nghe thử", và thanh tốc độ.
  Tốc độ mặc định khoảng 0,9 để trẻ dễ nghe.
- Mỗi ngôn ngữ chỉ hiện tối đa 3–4 giọng tốt nhất. Ưu tiên giọng chạy offline
  và giọng chất lượng cao, ẩn các giọng trùng nhau.
- Ngôn ngữ chưa có giọng trên máy: hiện nút "Tải giọng".

**Lưu cài đặt**

- Lưu `{language: voiceId, rate}` vào SharedPreferences.
- `voiceId` khác nhau giữa các máy, nên khi lưu không tìm thấy giọng đã chọn thì
  tự dùng giọng tốt nhất của locale đó.

### Bước 2: giọng từ server (khi tài khoản có model đọc đa ngôn ngữ)

- BE nhận thêm `voice` trong request. Mỗi ngôn ngữ có một danh sách giọng cho
  phép; giọng không có trong danh sách thì dùng giọng mặc định.
- `voice` đã nằm trong khoá cache audio (`descriptor.voice`), nên giọng khác
  nhau không bị trộn cache.
- Hiện `grok-tts` dùng cố định `voice_id: "ara"` (`aiProvider.ts`). Cần xem
  model hỗ trợ những giọng nào và có tiếng Việt không trước khi đưa vào giao diện.
- Model khác nên xem xét: cần kiểm tra danh mục Cloudflare Workers AI hiện có
  model nào đọc đủ 6 ngôn ngữ, nhất là tiếng Việt. `aura` chỉ hỗ trợ tiếng Anh.

### Giao diện đơn giản cho phụ huynh và trẻ

- Thay vì hiện tên kỹ thuật, cho chọn "Giọng nữ / Giọng nam / Giọng chậm".
- App tự ánh xạ lựa chọn đó sang giọng cụ thể theo từng nền tảng và ngôn ngữ, và
  thêm "Nâng cao" cho người muốn chọn đúng tên giọng.
- Cùng một lựa chọn dùng chung cho giọng điện thoại và giọng server, để khi bật
  lại giọng server thì người dùng không phải chọn lại.

### Thứ tự đề xuất

1. Sửa lỗi quay về giọng `vi-VN` (nhỏ, nên làm ngay).
2. Bước 1: chọn giọng điện thoại theo từng ngôn ngữ, có nút nghe thử.
3. Bước 2: chỉ làm khi đã có model đọc server hỗ trợ đủ ngôn ngữ.
