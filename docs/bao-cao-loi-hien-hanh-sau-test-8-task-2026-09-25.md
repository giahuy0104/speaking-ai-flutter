# Báo cáo lỗi hiện hành sau kiểm thử 8 task

Ngày rà soát: 2026-09-25  
Nhánh được đối chiếu: `self-fix-audio-vocabulary`  
Mốc mã nguồn: `e8ac9cbc`

## 1. Phạm vi và cách đọc kết quả

Báo cáo này tổng hợp và đối chiếu các nguồn sau:

- Biên bản kiểm thử `saukhitest8loi.docx`.
- Ảnh iOS có lỗi Apple Speech `com.apple.coreaudio.avfaudio:2003329396` sau khi tắt màn hình.
- Ảnh Android có lỗi `Không thể chuẩn bị âm thanh trong thời gian cho phép`.
- Kế hoạch cũ trong `phienbantusua.md`.
- Hai tài liệu về lifecycle ghi âm và HFP disconnect/reconnect.
- Mã nguồn hiện tại và `docs/self-fix-deep-audit.md`.

Nội dung trong Word và ảnh chỉ được dùng như **kết quả kiểm thử**, không được coi
là chỉ dẫn tự động sửa code. Báo cáo này chưa thay đổi source, chưa build/phát
hành, không sửa secret và không thay đổi cấu hình production.

Quy ước trạng thái:

- **Còn lỗi**: đã có bằng chứng tái hiện trên thiết bị.
- **Bị chặn**: chưa kiểm thử được vì một lỗi xảy ra sớm hơn trong luồng.
- **Chỉ cần kiểm chứng**: chưa có bằng chứng source đang sai; không được sửa trước
  khi tái hiện được.
- **Đóng băng**: đã DONE và phải giữ nguyên trừ khi có log mới chứng minh hồi quy.

## 2. Kết luận ngắn

Không phải cả 8 task đều còn lỗi. Phần lớn task giao diện và các chỉnh sửa audio
trước đó đã đạt. Hiện còn bốn cụm cần xử lý thực sự:

1. State chung của `Dừng -> MAIN hỏi -> Tiếp tục` và chuyển stage cuối bài chưa
   được hoàn tất. Đây chính là Task 8 và Task 9 từng được chủ động để lại.
2. iOS mất khả năng mở Apple Speech khi chuyển từ màn hình sáng sang nền/tắt màn
   hình; lỗi này chặn chấm điểm và chặn kiểm thử Challenge nền.
3. Android thỉnh thoảng timeout ở bước chuẩn bị/phát audio; thông báo trong ảnh
   đến từ lớp playback chung, chưa phải bằng chứng HFP native bị timeout.
4. Bộ từ vựng có lỗi tính nguyên tử của một entry: checkpoint có thể được tăng dù
   audio của entry thất bại, và lỗi phát bản ghi Stars đang bị nuốt rồi bỏ qua.

Không nên gộp bốn cụm này thành một commit. Mỗi cụm phải có log/test tái hiện,
sửa tối thiểu đúng tầng, rồi kiểm thử thiết bị trước khi sang cụm kế tiếp.

## 3. Ma trận Android/iOS sau kiểm thử

| ID | Hiện tượng | Android | iOS | Kết luận hiện tại |
| --- | --- | --- | --- | --- |
| HH-01 | Sau Dừng, MAIN đôi lúc không hỏi lại; khi nói tiếp tục thiếu câu dẫn `Mình tiếp tục nhé` | **Còn lỗi** | **Còn lỗi** | Shared Dart Task 8 chưa hoàn tất |
| HH-02 | Cuối bài có lúc không đi tiếp hoặc owner/prompt Challenge cũ còn tồn tại | **Còn lỗi chung**; trường hợp Challenge tắt màn hình cũ đã được tester ghi DONE | **Chưa kiểm thử hết** vì bị HH-03 chặn | Shared Dart Task 9 chưa hoàn tất |
| HH-03 | Tắt màn hình rồi đến lượt chấm điểm: Apple Speech không khởi động, mã `2003329396` | Không áp dụng | **Còn lỗi, blocker** | Lỗi iOS native ở ranh giới background handoff/capture |
| HH-04 | Nút MAIN vật lý không dùng được khi đang học Chủ đề | Không được báo lỗi | **Còn lỗi, blocker** | Cần trace BLE -> native -> Dart -> active owner trước khi sửa |
| HH-05 | Màn `Thử lại` báo không chuẩn bị audio kịp | **Còn lỗi không ổn định** | Chưa có báo cáo | Timeout playback chung; chưa đủ bằng chứng để sửa HFP native |
| HH-06 | Nói `học tiếp`: nhận lệnh nhưng chờ lâu, có cuộn mà không phát từ/bản ghi | **Còn lỗi** | Chưa có báo cáo | Resume/cleanup/playback ownership của Vocabulary chưa nguyên tử |
| HH-07 | Stars phát Anh + Việt nhưng bỏ qua giọng trẻ | **Còn lỗi** | Chưa có báo cáo | Code hiện tại nuốt lỗi bản ghi và vẫn tăng checkpoint |
| KT-01 | Câu trước/Câu sau ở biên đầu/cuối | **DONE trên thiết bị** | **Chỉ cần kiểm chứng** | Không sửa source nếu iOS chưa tái hiện lỗi |
| KT-02 | Âm lượng bản ghi Challenge | **Không có lỗi mới** | **DONE khi sáng màn hình**; nền bị HH-03 chặn | Giữ nguyên normalizer/gain hiện tại |
| DB-01 | Pháo hoa và khung ghi âm Luyện lại | **DONE** | **DONE theo biên bản** | Đóng băng |
| DB-02 | Auto-scroll danh sách Bộ từ vựng | **DONE** | **DONE theo biên bản** | Đóng băng; HH-06/07 là audio/checkpoint, không phải scroll |
| DB-03 | Bài hát xuất hiện tại màn chọn Chủ đề | **DONE** | **DONE theo biên bản** | Đóng băng |

## 4. Phân tích nguyên nhân theo bằng chứng

### HH-01 - MAIN tự tiếp tục hoặc thiếu câu dẫn tiếp tục

**Bằng chứng thiết bị**

- Biên bản ghi nhận cả Android và iOS đều không nói lại câu dẫn tiếp tục mà tự
  động tiếp tục.
- Có lúc MAIN không hỏi lại sau khi module đã dừng.

**Bằng chứng code**

- `AivoControlDispatcher` vẫn có nhánh `assistantOrResume` gọi thẳng
  `registry.execute(ActiveLearningCommand.resume)` khi module đang paused.
- `AppFlowCoordinator.resumeAfterMainAssistant()` cũng có đường gọi resume sau
  phiên MAIN.
- Vì resume có thể xảy ra trước khi AI hỏi và trước khi resolver nhận lệnh của
  người dùng, module có thể chạy lại ngay hoặc bỏ qua câu dẫn riêng của module.

**Kết luận**

Đây không phải lỗi TTS đơn lẻ. Gốc là contract state/ownership: trạng thái paused
đang bị dùng như quyết định tự resume, trong khi nó chỉ nên cung cấp context cho
MAIN hỏi. Chỉ dispatch `resume` sau khi người dùng thực sự chọn/nói tiếp tục.

### HH-02 - Challenge/cuối bài không chuyển stage ổn định

**Bằng chứng thiết bị và tài liệu cũ**

- Biên bản mới vẫn ghi nhận cuối bài đôi lúc không chuyển sang bước kế tiếp.
- Trường hợp Android tắt màn hình trước đây bị lặp câu cũ/đứng sau Challenge đã
  được tester ghi **DONE Android**. Không được coi điều đó là Task 9 đã hoàn tất
  cho cả hai nền tảng.
- iOS chưa thể kiểm thử Challenge nền vì HH-03 xảy ra trước lúc chấm điểm.

**Bằng chứng code/audit**

- `docs/self-fix-deep-audit.md` xác nhận Task 9 chưa làm có chủ đích.
- Kết thúc Challenge, ghi progress, pop route, phát prompt cuối và mở completion
  choice vẫn là nhiều thao tác có thể bị MAIN/lifecycle chen giữa.
- Active module registry ưu tiên controller đăng ký sau cùng. Một MAIN turn đang
  chuẩn bị có thể giữ context của Challenge trong lúc route đã pop về màn cha.

**Kết luận**

Cần một kết quả Challenge typed, commit progress idempotent và owner generation.
Không sửa riêng `replayCurrent` để che biểu hiện, vì replay hiện tại không chủ ý
đọc intro; nếu intro bị phát lại thì command/owner/stage đã bị resolve sai.

### HH-03 - iOS Apple Speech lỗi `2003329396` khi tắt màn hình

**Điều chắc chắn**

- Chuỗi lỗi trên ảnh được tạo tại `IOSSpeechRecognizerBridge` khi
  `AVAudioEngine.start()` thất bại và được bọc thành
  `AUDIO_ENGINE_START_FAILED`.
- Mã thập phân `2003329396` tương ứng four-char code `what`, tức AVFAudio từ
  chối khởi động graph ở state hiện tại.
- Native bridge chỉ tái sử dụng engine nền khi phase là `armed`, source/route
  khớp, engine còn chạy, tap còn gắn và coordinator xác nhận engine chạy.
- Nếu điều kiện này không còn đúng, code rebuild rồi start engine mới. Việc start
  mới sau khi app đã inactive/background là điểm có nguy cơ cao.

**Giả thuyết cần log xác nhận**

Race có khả năng xảy ra ở ranh giới `arming -> armed -> capturing`: lượt speech
thật thay thế một pre-arm đang chạy, teardown graph cũ, rồi cố start graph mới khi
app đã background. Ảnh phù hợp với giả thuyết này nhưng chưa đủ để kết luận chỉ
từ một screenshot.

**Không được làm**

- Không tăng retry/delay tùy ý.
- Không fallback sang file ghi âm hoặc cloud upload ngoài contract hiện tại.
- Không thay normalizer/gain Challenge đang tốt khi màn hình sáng.
- Không sửa HFP disconnect/reconnect coordinator nếu trace không chỉ ra lỗi ở đó.

### HH-04 - iOS không nhận MAIN trong lúc học Chủ đề

Code hiện tại đã cố giữ BLE MAIN độc lập với HFP/SCO và có trace tại
`Aiv0BleControlBridge`, `IOSAudioSessionCoordinator.notePhysicalMain` và Dart.
Tuy vậy biên bản thiết bị nói nút không dùng được trong Topic.

Chưa thể kết luận lỗi nằm ở BLE, event sink, dispatcher hay active module. Cần
đọc một timeline duy nhất qua các mốc:

1. Packet BLE thật được nhận và qua duplicate filter.
2. Native gọi `notePhysicalMain`.
3. Event được gửi qua event sink hoặc được giữ trong pending buffer.
4. Dart nhận action và `MainButtonCoordinator` dispatch.
5. Registry xác nhận controller/node đang active.
6. MAIN pause module và bắt đầu prompt/micro.

Nếu packet không đến khi SCO đang hoạt động thì đó là ranh giới native/firmware;
không được sửa Dart. Nếu Dart nhận action nhưng không xử lý thì mới sửa registry
owner/generation cùng HH-01.

### HH-05 - Android timeout chuẩn bị audio

Thông báo trong ảnh khớp chính xác với
`ConversationController._preparePlaybackWithTimeout()` và
`_awaitPlaybackStartWithTimeout()`. Cả hai dùng timeout 8 giây và trả cùng một
chuỗi lỗi. Chuỗi lỗi HFP-specific trong code là chuỗi khác, vì vậy ảnh **không
chứng minh** native HFP negotiation bị timeout.

Một lượt chuẩn bị/phát cũ có thể giữ player hoặc route trong lúc lượt mới đã bắt
đầu. Hiện lỗi chưa cho biết timeout ở bước nào: cấu hình audio session, resolve
URI/cache, set source, đo loudness hay đợi player thực sự phát.

Sửa bằng cách chỉ tăng 8 giây sẽ che race, làm người dùng chờ lâu hơn và vẫn có
thể thất bại. Cần operation token, stage timing và cleanup có thể await/cancel.

### HH-06 và HH-07 - Vocabulary cuộn nhưng mất audio/bản ghi

**Lỗi code xác định được**

- `_playQueue()` lưu checkpoint `index + 1` trước khi kiểm tra `played == false`.
  Vì vậy entry phát lỗi vẫn có thể bị coi là đã đi qua.
- `_speakVocabularyEntry()` bắt lỗi phát bản ghi Stars, log
  `VOCABULARY_STAR_AUDIO_FAILED` rồi trả `false`; vòng lặp tiếp tục sang entry
  khác sau khi checkpoint đã tăng.
- Store chỉ lọc path rỗng, chưa chứng minh file tại path còn tồn tại ngay lúc phát.
- Auto-scroll/highlight xảy ra trước khi toàn bộ EN -> VI -> bản ghi hoàn tất. Do
  đó ảnh hưởng audio có thể trông giống lỗi scroll dù auto-follow đã đúng.
- `_resumePlayback()` còn chờ settle bằng polling hữu hạn; cleanup cũ đến muộn có
  thể va với route/player của lượt mới.

**Kết luận**

Một entry Stars phải là thao tác nguyên tử: chỉ tăng checkpoint sau khi chuỗi bắt
buộc hoàn thành. File mất và route/player lỗi phải là hai nhánh recovery khác
nhau; không được nuốt lỗi rồi bỏ qua giọng trẻ.

## 5. Phần đã DONE phải đóng băng

Các phần sau không thuộc phạm vi sửa hiện hành:

- Fireworks Review và cleanup khi MAIN takeover.
- Trạng thái/khung ghi âm Review, khóa feedback và dọn failed recording.
- iOS Challenge normalization/gain khi màn hình sáng.
- Logic Câu trước/Câu sau và thứ tự prompt/mic đã được xác nhận trên Android.
- Auto-follow, stable entry id, giữ scroll người dùng và dọn stale highlight.
- Bài hát tại Topic, level/sequential lock, đường Back và progress invariant.
- HFP disconnect/reconnect coordinator, generation và route revalidation đã có.
- Recording lifecycle start/stop/cancel/dispose và stale-start protection đã có.
- Trường hợp Android Challenge tắt màn hình từng lặp câu/đứng đã được biên bản mới
  đánh dấu DONE.

Guardrail chung: không đổi scoring, nội dung bài học, rotation Challenge, sentence
index, authored audio, privacy/upload policy, BLE protocol, gain cap hoặc UI đã
được tester xác nhận tốt nếu task hiện tại không có bằng chứng trực tiếp liên quan.

## 6. Prompt triển khai dứt điểm

Mỗi prompt dưới đây là một task độc lập. Sau mỗi task phải commit riêng, chạy test
tự động và dừng để chủ sản phẩm kiểm thử thiết bị. Không triển khai task kế tiếp
trước khi task hiện tại được xác nhận.

### Prompt A - Tạo bộ trace tái hiện, chưa đổi hành vi

```text
Hãy thêm diagnostics có cấu trúc để tái hiện các lỗi HH-01 đến HH-07, nhưng chưa
thay đổi hành vi sản phẩm.

Yêu cầu:
- Dùng operation/generation id thống nhất cho MAIN turn, active module owner,
  speech capture, playback prepare/start và Vocabulary entry.
- Log timestamp monotonic, platform, lifecycle, owner/controller identity, node,
  command, route/source, phase và kết quả. Không log transcript, giọng nói, đường
  dẫn chứa dữ liệu người dùng hoặc dữ liệu trẻ em.
- iOS: nối timeline BLE packet -> duplicate filter -> notePhysicalMain -> eventSink
  -> Dart; và background handoff idle/arming/armed/capturing -> engine start.
- Android: tách thời gian playback thành audio-session/route prepare, URI/cache,
  set source, loudness/preprocess, play requested và first-playing event.
- Vocabulary: log entry stable id, checkpoint trước/sau, file-exists, EN/VI/child
  recording stage, route generation và cancellation reason.
- MAIN/Challenge: log main_question_started, resolved command, resume_lead_started,
  owner generation, route pop, typed/untyped result hiện tại và progress commit.
- Diagnostics phải tắt được trong release hoặc bị giới hạn theo cơ chế log hiện có.
- Thêm unit/widget/native tests cho schema và redaction; không tăng timeout, không
  thêm delay, không sửa scoring/progress/UI/audio policy trong commit này.

Commit đề xuất:
test: add cross-layer audio and MAIN lifecycle diagnostics
```

### Prompt B - Sửa iOS background Apple Speech handoff

```text
Hãy dùng trace của Prompt A để tái hiện và sửa dứt điểm lỗi iOS
AUDIO_ENGINE_START_FAILED / AVFAudio 2003329396 khi màn hình tắt ngay trước lượt
chấm điểm. Không sửa Dart state MAIN/Challenge trong task này.

Invariant bắt buộc:
- Chỉ có một operation sở hữu quá trình background handoff từ
  idle -> arming -> armed -> capturing hoặc failed.
- Speech start đến khi pre-arm đang arming phải await/adopt đúng operation hiện
  tại; không tăng generation rồi teardown engine hợp lệ để start lại trong nền.
- Nếu app đã inactive/background và không có engine armed hợp lệ, không được cố
  rebuild/start AVAudioEngine mới theo vòng retry. Trả trạng thái recoverable,
  giữ checkpoint và tiếp tục đúng lượt khi foreground hoặc theo contract
  background đã được chứng minh là hợp lệ.
- Mọi completion cũ phải kiểm tra generation, requested source, route snapshot và
  lifecycle trước khi đổi phase hay teardown graph.
- Route change hoặc HFP disconnect phải invalid operation cũ mà không đóng engine
  của owner mới.
- Giữ nguyên Apple Speech privacy policy, screen-on Challenge normalization/gain,
  scoring, HFP coordinator và authored prompt.

Test bắt buộc:
- Native XCTest cho screen-off tại từng biên: trước arming, đang arming, vừa armed,
  trước capture và trong capture.
- Stale arm completion sau một start mới; route built-in <-> HFP trong handoff;
  cancel/dispose/foreground recovery; engine start trả lỗi 2003329396.
- Flutter integration/static contract xác nhận lỗi recoverable không tự tăng
  checkpoint, không tự chấm điểm và không mở hai mic.
- Kiểm thử iPhone thật với H20: màn hình sáng, khóa màn hình trước lượt ghi,
  khóa đúng lúc chuyển prompt -> mic, mở lại, rồi đi đến Challenge.

Không chấp nhận nghiệm thu nếu cách sửa chỉ tăng số lần retry hoặc thêm sleep.

Commit đề xuất:
fix(ios): make background speech handoff single-owner
```

### Prompt C - Sửa MAIN vật lý iOS trong Topic dựa trên trace

```text
Hãy sửa lỗi nút MAIN vật lý không hoạt động trên iOS khi đang học Topic. Chỉ sửa
tầng mà trace Prompt A chứng minh bị mất event.

Quy trình bắt buộc:
1. Xác định packet BLE có đến không khi idle playback, đang phát prompt, đang HFP
   capture, đang scoring feedback và giữa hai câu.
2. Nếu packet không đến: xử lý state notify/recovery của Aiv0BleControlBridge hoặc
   nêu rõ giới hạn firmware; không thay dispatcher Dart để giả tạo MAIN event.
3. Nếu packet đến nhưng eventSink không giao: sửa pending/deferred delivery bằng
   generation, đảm bảo mỗi physical press giao đúng một action.
4. Nếu Dart đã nhận nhưng registry từ chối/sai owner: sửa ở shared owner contract
   cùng Task 8, không vá riêng Topic.
5. Không duy trì SCO chỉ để chờ MAIN nếu điều đó làm mất BLE control; không đổi
   protocol packet, duplicate-window hoặc HFP route policy khi chưa có trace.

Test bắt buộc:
- Native test notify disable/enable, eventSink detach/reattach, deferred recovery,
  capture end, disconnect/reconnect và duplicate burst.
- Dart test một packet -> một MAIN turn; event cũ không điều khiển owner mới.
- Device test iPhone + H20 tại năm state nêu trên và sau khóa/mở màn hình.

Commit đề xuất:
fix(ios): preserve physical MAIN delivery during topic audio
```

### Prompt D - Sửa Android playback preparation timeout

```text
Hãy sửa lỗi Android không ổn định với thông báo "Không thể chuẩn bị âm thanh
trong thời gian cho phép". Dùng stage timing từ Prompt A; không mặc định lỗi nằm
ở HFP native và không tăng _audioPreparationTimeout để che triệu chứng.

Yêu cầu:
- Mỗi prepare/play có operation token gắn với conversation turn và output-route
  generation. Sau mọi await phải kiểm tra operation còn là owner hiện tại.
- Stop/cancel/dispose/MAIN turn mới phải vô hiệu hóa prepare cũ và await cleanup
  hữu hạn trước khi tái dùng player; completion cũ không được stop player mới.
- Phân biệt timeout ở route/session, source/cache, preprocessing và first-playing.
- Chỉ recreate player hoặc retry đúng một lần khi trace chứng minh player/source
  operation hiện tại bị kẹt; retry phải dùng cùng URI/checksum và route generation.
- Nếu route/HFP không sẵn sàng, trả lỗi route cụ thể. Không dùng chung chuỗi lỗi
  preparation để che mọi nguyên nhân.
- Giữ nguyên backend result, command matching, privacy, checksum verification,
  HFP coordinator và luồng đang phát tốt.

Test bắt buộc:
- Prepare cũ hoàn tất sau turn mới; stop cũ đến muộn; source load treo; first-play
  event không tới; HFP route đổi giữa prepare/play; retry thành công/thất bại.
- Khẳng định turn cũ không phát audio, không dừng turn mới và chỉ một player owner.
- Device test Android + H20 ít nhất 20 vòng: nói -> chấm -> assistant phát -> Thử
  lại, bao gồm MAIN chen giữa và disconnect/reconnect.

Commit đề xuất:
fix(android): serialize conversation playback preparation
```

### Prompt E - Sửa Vocabulary resume và Stars recording theo transaction entry

```text
Hãy sửa HH-06/HH-07 trong Vocabulary mà không thay đổi auto-scroll đã DONE.

Contract của một entry Stars:
route ready -> English hoàn tất -> Vietnamese hoàn tất -> child recording hoàn
tất -> checkpoint tăng đúng một lần. Nếu một bước bắt buộc thất bại, checkpoint
không tăng và entry hiện tại phải còn khả năng retry.

Yêu cầu:
- Chuyển savePlaybackCheckpoint(index + 1) xuống sau khi entry trả kết quả success.
- Không catch VOCABULARY_STAR_AUDIO_FAILED rồi continue sang từ kế tiếp.
- Kiểm tra file tồn tại/đọc được ngay trước phát. Phân biệt:
  a) stale/missing path: áp dụng data-repair theo contract store, không giả vờ đã
     phát giọng trẻ;
  b) route/player failure: giữ cùng index, reacquire output route hiện tại và cho
     retry có kiểm soát.
- Resume không polling chờ cleanup bằng delay. Dùng Future/queue hoàn tất rõ ràng
  và operation generation cho command, route prepare, active entry và media play.
- Nếu route prepare hoặc media start thất bại sau khi đã cuộn/highlight, rollback
  state phát phù hợp nhưng không can thiệp cơ chế auto-follow/user-drag đã DONE.
- MAIN/Back/module switch phải invalid operation cũ; callback cũ không được phát
  tiếp, tăng checkpoint hoặc xóa file được owner mới dùng.
- Giữ nguyên thứ tự EN -> VI -> child recording, nội dung prompt và retained file
  policy hiện có.

Test bắt buộc:
- File tồn tại: đủ EN, VI, child recording rồi mới tăng checkpoint.
- Missing file, unreadable file, player failure, route failure và retry cùng entry.
- Failure không nhảy entry; stale completion không tăng checkpoint.
- MAIN Dừng -> học tiếp khi cleanup cũ còn pending; không chờ polling, không chỉ
  cuộn mà im tiếng.
- Path Windows/Android và normalized WAV iOS; retained successful recording không
  bị xóa.

Commit đề xuất:
fix: make vocabulary entry playback and checkpoint atomic
```

### Prompt F - Hoàn tất Task 8: contract MAIN resume/replay theo module

```text
Hãy hoàn tất shared Dart Task 8 cho cả Android và iOS:
Dừng -> MAIN hỏi theo owner/node hiện tại -> người dùng nói/chọn Tiếp tục -> module
phát câu dẫn tiếp tục đúng một lần -> tiếp tục đúng media/cue/mic sequence.

Yêu cầu bắt buộc:
- Xóa hành vi tự registry.execute(resume) chỉ vì module đang paused trong nhánh
  assistantOrResume. Paused chỉ chọn context/prompt; resume chỉ được dispatch sau
  khi resolver trả ActiveLearningCommand.resume từ lựa chọn thật của người dùng.
- Tạo contract typed nhỏ cho resume/replay. Mỗi module tự mô tả nội dung nhưng
  dùng chung operation token, owner generation và cancellation rule.
- MAIN phải refresh/validate active context ngay trước resolve và trước dispatch.
  Controller được pause, context được đọc và command được dispatch phải cùng một
  owner generation.
- MAIN lần hai, Back, pop hoặc module switch invalid operation cũ. Trước mỗi audio
  và mic, kiểm tra mounted, token và active owner.
- Core V4: resume lead một lần -> English -> Vietnamese -> cue -> mic một lần.
- Core legacy: resume lead một lần rồi đúng contract legacy, không mở thẳng mic.
- Challenge: resume lead một lần -> câu hỏi/đáp án -> cue -> mic một lần.
- Review: tái sử dụng reviewResume hiện có; không thêm lead thứ hai, không nhảy
  item, không nhân feedback/mic.
- Song: resume lead theo contract hiện có rồi tiếp tục bài hát; không câu mẫu/mic.
- replayCurrent chỉ replay state hiện tại. Challenge replay không intro và không
  resume lead.
- Không đổi scoring, progress, rotation, sentence index, native audio hay các UI
  đã đóng băng.

Test bắt buộc:
- Module paused + nhấn MAIN: AI hỏi trước; chưa nói Tiếp tục thì module không chạy.
- Core câu đầu/giữa, có/không bản ghi cũ; thứ tự đúng và mic đúng một lần.
- Challenge resume và replay khác nhau; Review không nhân lead/feedback; Song
  không mở mic.
- Owner đổi trong lúc chuẩn bị MAIN; stale callback; MAIN hai lần; Back/pop.
- Chạy cùng shared test suite với Android và iOS target platform.

Chia commit:
1. test: reproduce MAIN resume ownership races
2. refactor: add typed module resume and replay contract
3. fix: dispatch resume only after resolved user intent
```

### Prompt G - Hoàn tất Task 9: Challenge và stage cuối bài

```text
Hãy hoàn tất shared Dart Task 9 cho luồng
Challenge -> Song/Completed/WaitingForChoice. Không sửa native audio trong task
này nếu log chưa chứng minh native là nguyên nhân.

Yêu cầu bắt buộc:
- Thay tín hiệu rời kiểu Navigator.pop(true) + callback cục bộ bằng một kết quả
  typed duy nhất, ví dụ ChallengeCompletionResult, có challenge id/index, target
  id, outcome và operation id. Route con hoàn thành đúng một lần.
- Tạo API progress-store idempotent và serialize read-modify-write. Commit outcome
  và resumeStage kế tiếp trong một thao tác logic trước audio/modal cuối bài.
- Gọi lại cùng challenge/operation id không được tăng rotation/progress hai lần.
- Nếu route bị gián đoạn trước kết quả hợp lệ, giữ stage challenge làm checkpoint
  phục hồi và log interrupted. Nếu đã có typed result, phải commit stage kế tiếp
  trước prompt/modal.
- Bài có Song -> song; không có Song -> completed hoặc waitingForChoice theo
  contract hiện tại.
- Sau pop chỉ phát prompt/mic cuối bài khi parent owner generation đã ổn định.
  Completion choice phải khôi phục được từ persistence sau inactive/background.
- MAIN refresh context ngay trước resolve. Context Challenge cũ không được replay
  sau khi owner đã chuyển về LessonPractice/CompletionChoice.
- Challenge replay chỉ câu hỏi + đáp án + cue, không intro/resume lead.
- Giữ nguyên scoring, câu hỏi, rotation, screen-on normalization, zero-duration
  background-safe route và phần Android screen-off đã được tester xác nhận tốt.

Test bắt buộc:
- Inactive tại feedback, trước pop, giữa commit và sau pop; restore đúng stage.
- MAIN chen lúc child -> parent; AI phản ánh owner mới đúng một lần.
- Pop không result, typed result đúng lúc và stale result tới muộn.
- Khôi phục từng stage challenge/song/completed/waitingForChoice.
- Replay nhiều lần không intro; idempotency khi callback/lifecycle lặp.
- Shared Android/iOS tests. Sau khi HH-03 được sửa, device test iOS screen-off;
  Android phải re-test để bảo vệ phần đã DONE.

Chia commit:
1. test: reproduce Challenge completion ownership races
2. refactor: return typed Challenge completion result
3. fix: commit Challenge progress idempotently
4. fix: refresh MAIN owner context after Challenge pop
```

## 7. Kiểm thử chỉ xác nhận, không sửa trước

### KT-01 - Câu trước/Câu sau trên iOS

Sau khi HH-03 và HH-04 không còn chặn, chạy smoke test iOS:

- Câu trước tại câu đầu: không underflow, thứ tự prompt/mic đúng.
- Câu sau tại câu cuối: sang đúng Challenge/Review/Song theo stage.
- MAIN chen trong lúc chuyển biên: callback cũ không mở mic.

Nếu tất cả đạt, đánh dấu DONE iOS và không tạo commit. Chỉ mở task source mới khi
có log và bước tái hiện riêng trên iOS.

### KT-02 - Âm lượng Challenge iOS khi tắt màn hình

Chỉ kiểm thử sau khi HH-03 đã sửa:

- So sánh cùng người nói, cùng H20, cùng khoảng cách ở màn hình sáng và khóa màn.
- Xác nhận peak/RMS nằm trong gate/cap hiện tại và không clipping.
- Nếu background recording đã tạo file hợp lệ và mức âm tương đương thì DONE;
  không chỉnh gain thêm.
- Nếu khác, thu diagnostics đầu vào trước/sau normalize rồi mới mở task riêng.

## 8. Thứ tự thực hiện và điểm dừng

1. Prompt A - trace tái hiện, không đổi hành vi.
2. Prompt B - iOS background Apple Speech blocker.
3. Prompt C - iOS physical MAIN trong Topic, chỉ theo tầng trace chỉ ra.
4. Prompt D - Android playback preparation timeout.
5. Prompt E - Vocabulary entry/checkpoint/recording.
6. Prompt F - shared MAIN resume/replay Task 8.
7. Prompt G - shared Challenge completion Task 9.
8. Chạy KT-01 và KT-02; không sửa nếu không tái hiện.

Sau **mỗi** prompt:

- Chạy test phạm vi task và test hồi quy liên quan.
- Chạy static analysis/dry-run an toàn; không publish, upload hay đổi secrets.
- Commit riêng với message rõ nghĩa.
- Ghi lại SHA, test đã chạy và kết quả thiết bị Android/iOS.
- Dừng để chủ sản phẩm xác nhận rồi mới sang prompt kế tiếp.

## 9. Tiêu chí đóng toàn bộ đợt lỗi

Chỉ coi đợt này hoàn tất khi:

- Android và iOS đều thực hiện đúng `Dừng -> MAIN hỏi -> Tiếp tục -> resume lead`
  và không tự chạy trước lựa chọn của người dùng.
- iOS khóa màn hình vẫn đi qua ghi âm/chấm điểm đến Challenge hoặc phục hồi đúng
  checkpoint, không còn `2003329396`.
- MAIN vật lý iOS dùng được trong Topic qua các state playback/capture/feedback.
- Android không còn preparation timeout trong bài test lặp; nếu lỗi ngoại vi xảy
  ra, thông báo chỉ đúng stage/nguyên nhân và retry không làm hỏng owner mới.
- Vocabulary không tăng checkpoint khi entry phát lỗi và không bỏ qua child
  recording của Stars.
- Challenge kết thúc commit đúng một lần và phục hồi đúng stage trên cả hai nền
  tảng.
- Tất cả mục đóng băng ở phần 5 vẫn giữ nguyên hành vi tốt hiện tại.
