# HOMI Speaking — Roadmap sửa lỗi audio, micro và điều hướng

Nguồn: [bảng task QA](https://docs.google.com/spreadsheets/d/1WF9T705T7U-MH2nqkTAv-i0TegaxzfhNAqBqBz7QUFE/edit?gid=0#gid=0)
(6 dòng) + rà soát mã nguồn + log runtime trên iPhone thật + nhiều vòng agent
review đối kháng.

Nhánh `self-small-fixes-audio-nav-next`. Cập nhật 2026-09-29.

---

## 1. Trạng thái theo đúng thứ tự sheet QA

| Hàng | Dòng trong sheet | Trạng thái |
|---|---|---|
| 3 | Ghi âm rè, ngắt quãng, mở mic chậm | **3/4** — còn "mở mic chậm" |
| 4 | Chủ đề: điều hướng chậm | ✅ **3/3** — Đầu, Cuối, chấm điểm |
| 5 | Mic Challenge chưa ổn định | ✅ **xong** |
| 6 | Bộ từ vựng: audio ngắt giữa chừng | ❌ **chưa làm** |
| 7 | Âm lượng không đồng đều | **2/3** — còn `gainDb` cho TTS iOS |
| 8 | Giọng AI không đồng bộ | ✅ **xong** |

**Định nghĩa "xong":** code xong, có test, toàn bộ kiểm tra tự động xanh, đã
commit. **Chưa bao gồm** xác nhận bằng tai người trên thiết bị thật.

### Commit trên nhánh này

```
d514b601 fix(audio): stop the manifest cooldown from silencing a cold start…
f32fc15d fix(ios): serialise the diagnostic trace buffer
4e554c7e fix(main): stop reporting navigation as a failed manifest…
ac5bb64f test(android): make the gain cap test exercise the cap
17a5d25e fix(ios): let the capture lease go before flushing the recording
c2f0d59a fix(audio): level the authored catalogue on iOS as well as Android
665a35ae fix(network): bound every response body read and release the connection
9ea1ecab perf(listening): stop re-reading the progress file on entry and on every write
bf43ec89 fix(audio): stop stale speech turns, clipped lesson recordings…
```

### Kiểm tra tự động

```
dart    : 1263/1263 pass
kotlin  : 42/42 pass          ← lần đầu tiên được chạy; CI vẫn không chạy chúng
analyze : No issues found
boundary: OK
swift   : CHƯA BAO GIỜ ĐƯỢC BIÊN DỊCH — xem mục 5
```

---

## 2. Việc còn lại, kèm lý do chưa làm

### Chặn vì thiếu bằng chứng

**Hàng 6 — Bộ từ vựng ngắt audio.** Ba cơ chế đều gây đúng triệu chứng, **hai
nằm ở code dùng chung với phần Chủ đề**, nên sửa mò có thể làm hỏng Chủ đề đang
chạy được.

| # | Cơ chế | Vị trí | Điều kiện |
|---|---|---|---|
| A | `statusChanges` là stream dùng chung, không theo scope | `hfp_audio_route_coordinator.dart:242` · `coordinated_voice_prompt_service.dart:255` | Chỉ khi có H20 |
| B | Completion đến muộn giải phóng lease của clip **mới** | `audio_playback_service.dart` | Nhiều khả năng trên web |
| C | Màn Luyện tập không huỷ service dùng chung khi dispose | `vocabulary_practice_screen.dart:182` | Khi rời màn |

**Đã kiểm C và KHÔNG sửa:** `dispose()` có xử lý service dùng chung
(`_ownsVoicePromptService ? dispose() : stop()`), lỗ hổng duy nhất là khi
`_exiting == true`. Nhưng `_exiting` xuất hiện nhất quán ở **4 chỗ** như một mẫu
có chủ đích — *"đang bàn giao có kế hoạch, đừng phá audio giữa chừng"*. Không có
test nào ghim nó. Đây đúng kiểu "hành vi có chủ đích trông như bug" mà mục 6 ghi
lại 4 lần. **Không đụng khi chưa có bằng chứng.**

**Cần một trong hai:**
- Trả lời 4 câu: lúc đứt **có cắm H20 không**? **web/PWA hay native**? **đứng yên
  trong màn hay vừa chuyển màn**? log có `audio_session_owner_released` nào
  **không đi kèm thao tác người dùng** không?
- Hoặc một **log máy thật** quay đúng lúc audio đứt.

### Chặn vì thiếu Xcode

Xem mục 5. Tất cả các mục dưới đây là Swift:

| Mục | Việc |
|---|---|
| **Hàng 3** | "mở mic chậm" — cần chọn hướng, xem mục 3 |
| **Hàng 7** | `gainDb` cho **TTS iOS** (phần MP3 dựng sẵn đã xong) |
| **M8/M9** | Gain đọc `requestedAudioSource` từ tap thread, keyed theo nguồn *yêu cầu* chứ không phải route *đã xác nhận* |
| **M10** | `recordingWriteQueue` không có backpressure — buffer giữ vô hạn nếu đĩa chậm (~190 KB/s) |
| **M13** | Normalizer iOS nới lên 60s nạp cả file vào một buffer: 60s @ 48kHz stereo float32 ≈ 23 MB |

### Chặn vì cần chạy app

**§5 cũ — màn đỏ ở lesson intro.** Bấm vào chủ đề → Bắt đầu, màn intro bị phủ
lớp đỏ, UI vẫn hoạt động dưới lớp đó. Đã loại trừ: không phải layout, không phải
màu từ code (`lib/` không có `Colors.red`, không `ColorFiltered`/`BlendMode`),
ảnh nền bình thường, không phải crash. `lesson_intro_screen.dart` có
`Scaffold(backgroundColor: Colors.transparent)` nên màu đến **từ phía sau**; hình
dạng lớp đỏ khớp với `ErrorWidget` thay thế một subtree.

**Cách chốt nhanh nhất:** chạy debug build, vào đúng màn đó, đọc khối
`══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞══` trong console. Máy hiện tại không
chạy được iOS (không Xcode) và không có emulator/thiết bị Android gắn sẵn.

---

## 3. Quyết định sản phẩm đang treo

| # | Quyết định | Vì sao cần người quyết |
|---|---|---|
| 1 | **Hàng 3** — có đổi nghĩa tiếng báo từ *"sắp mở mic"* thành *"mic đang nghe"* không? | Đây là đổi hành vi **trẻ nghe thấy trực tiếp**, không phải sửa nội bộ. Hướng còn lại (giữ session qua đoạn chuyển giao) an toàn hơn về trải nghiệm nhưng rủi ro kỹ thuật cao hơn: rò lease là kẹt SCO, chặn H20 reconnect |
| 2 | **2a-ii** — trần thời gian chấm điểm | Đo được rồi: **~135 giây** xấu nhất (75s thang retry + tới 30s xác thực cài đặt + 15s tải blob trên web). Trước đây là **vô hạn**. Bao nhiêu giây là chấp nhận được cho trẻ? |
| 3 | **2a-iii** — 401/403 có chuyển sang chấm trên máy không? | Comment tại `lesson_attempt_evaluator.dart` nói rõ *"online API failures must not silently switch scoring to the offline recognizer"*. Đề xuất này **mâu thuẫn thiết kế có chủ đích** |
| 4 | **Chuẩn hoá audio ở khâu sinh** | Xem mục 4 — đã cân mức lúc *phát*, nhưng `tool/*.mjs` vẫn sinh ra file lệch nhau. Clip mới vẫn lệch và phải chạy lại manifest thủ công |

---

## 4. Phát hiện quan trọng: bộ audio tự nó lệch nhau

Đo 356 file bằng `afconvert` (có sẵn trong macOS, **không cần ffmpeg**):

| Nhóm | n | Trung vị | p10 | p90 |
|---|---|---|---|---|
| `.en.mp3` | 165 | **−12.8 dBFS** | −15.9 | −10.8 |
| `.vi.mp3` | 222 | **−8.7 dBFS** | −10.6 | −7.6 |

**Tiếng Việt to hơn tiếng Anh 4.1 dB**, hai dải gần như không chồng nhau. Cả bộ
trải **18.4 dB**. Trẻ nghe câu dẫn tiếng Việt xong tới câu tiếng Anh là tụt 4 dB.

Điều này đổi hình dạng hàng 7: nó có **ba** nguyên nhân chứ không phải một.

1. `speechRate`/`pitch` iOS không đọc — ✅ xong (commit trước).
2. `gainDb` TTS iOS — ❌ còn.
3. Bộ MP3 lệch nhau — ✅ xong, và đây mới là nguyên nhân giải thích *"trong tất
   cả các phần"* trong sheet.

**Cách sửa đã chọn.** Android vốn đã đo từng clip lúc phát (`AndroidPlaybackLoudness`,
đích −21 dBFS gated RMS); iOS không đo gì cả. Nhưng mở cổng đo cho iOS sẽ thêm
một lần giải mã trước **mỗi** clip, đúng trên đường điều hướng đang bị than chậm
(hàng 4). Bộ audio là tài sản cố định giữa các bản build, nên đo sẵn lúc build:

- `tool/measure_audio_loudness.py` — port đúng chính sách `PcmPlaybackLevelMeter`.
- `assets/data/audio_loudness.json` — 2865/2867 clip, 260 KB.
- Cả hai nền tảng tra bảng: không giải mã, không chờ, cùng một con số.

**Mọi gain đo được đều âm** (≤ +0.7 dB) → chỉ cần *giảm* âm lượng →
`AVAudioPlayer.volume` đủ. **Bế tắc `gainDb` của roadmap cũ phần lớn do trước giờ
nghĩ phải khuếch đại — không phải vậy.**

### Còn nợ ở phần này

- **Android chỉ dùng manifest ở lần phát đầu**, từ lần 2 lấy số đo runtime (lệch
  ≤0.91 dB). Mâu thuẫn với doc comment trong `audio_loudness_manifest.dart`.
- `preload()` vẫn giải mã đo mức cho asset đã có trong manifest — việc thừa.
- `_applySourceLevel` **không test nào phủ** nhánh asset/iOS — đây là sửa đổi
  rủi ro nhất trong nhóm.
- `measure_audio_loudness.py --check` **chưa nối vào CI** → manifest mốc mà không
  ai biết. Chạy lại mất ~2 phút nên không bỏ thẳng vào `flutter test` được.
- Test chống trôi chỉ so 3/~8 tham số chính sách; kích thước cửa sổ,
  `MAX_DURATION_MS` và hai hằng số gate chưa được so.

---

## 5. Ràng buộc môi trường — đọc trước khi tiếp tục

| | |
|---|---|
| **KHÔNG CÓ XCODE** | Chỉ có Command Line Tools, không có iOS SDK. `flutter doctor`: *"Xcode installation is incomplete"*. **5 thay đổi Swift trên nhánh này chưa từng qua trình biên dịch.** Codemagic sẽ là nơi đầu tiên biết |
| **`swiftc -parse` là bảo đảm yếu** | Nó chỉ bắt cú pháp. Một hàm **khai báo trùng** đã lọt qua và làm hỏng toàn bộ test target iOS. Đã viết kiểm tra riêng vào `tool/check_architecture_boundaries.dart` (CI chạy sẵn công cụ này) để chặn đúng lớp lỗi đó |
| **Không có CI cho Android** | `codemagic.yaml` chỉ có 2 workflow iOS. Test Kotlin chạy được ở máy (`cd android && sh gradlew :app:testDebugUnitTest`) nhưng **CI không chạy** |
| **Golden test không verify được trên Mac** | Baseline duyệt trên Windows; cả hai workflow Codemagic loại chúng ra |
| **Đoạn lệnh test của CI không chạy trên zsh** | zsh không word-split biến, cả danh sách 136 file thành **một** tham số. Phải `bash -c` hoặc `${=VAR}` |
| **Toolchain lệch** | CI pin Flutter 3.44.6 / Xcode 26.6; máy dev 3.47.5 và **không có Xcode** |
| **Dev build thiếu dart-define thì khoá giọng nói** | `dart_defines.example.json` **thiếu cả 5 key pháp lý**. Làm đúng README vẫn bị khoá. Dùng `dart_defines.production.json` |
| **Working tree luôn bẩn** | `ios/Flutter/ephemeral/` bị track dù `ios/.gitignore` đã loại trừ. Sửa: `git rm -r --cached ios/Flutter/ephemeral/` |
| **`analysis_options.yaml`** | Đang loại `android/**`, `ios/**`, `web/**` khỏi analyze → Dart dưới `web/` không được phân tích |
| **Thư mục Desktop được sync** | Giữa lúc sửa nó đẻ ra file `... 2.dart` trong `lib/` làm analyze đỏ. Sẽ tái diễn |
| **Push bị chặn** | Keychain dùng `dacerlary`, chưa có quyền ghi vào `giahuy0104/speaking-ai-flutter` (403) |

---

## 6. Bài học — lặp lại suốt hai phiên

**Quy tắc 1: luôn `grep` test trước khi sửa.** Bốn lần phát hiện từ đọc code mà
không đối chiếu test hiện có đều sai — hành vi tưởng là bug hoá ra có chủ đích và
đã có test đặc tả.

**Quy tắc 2: xác minh *đường nào thật sự chạy*, không chỉ cơ chế.** Hai lần trong
phiên này một bản sửa đúng về cơ chế nhưng đặt sai đường:

- **H4** đặt finalize sau `releaseCapture` ở 3 đường, nhưng bỏ sót `stop()` —
  đường kết thúc **phần lớn** bản ghi bài học. Sửa gần như vô tác dụng.
- **Loudness** nối manifest vào `MainAssistantAudioPromptService`, nhưng
  `VoicePromptAudioRegistryAdapter` mới là service ngoài cùng → chỉ với tới
  ~66/2865 clip.

**Quy tắc 3: agent review bắt được thứ 1263 test không bắt được.** Trong phiên
này review tìm ra: mất tiến độ học của trẻ, xoá sạch file tiến độ, rò socket, test
tautology, hàm khai báo trùng làm hỏng build, và **một hồi quy tệ hơn lỗi nó định
sửa** (cooldown manifest đếm cả timeout → trẻ mở app trên máy chậm mất sạch audio
dựng sẵn 30 giây đầu).

**Quy tắc 4: test phải chứng minh được là bắt được lỗi.** Mọi test hồi quy trong
phiên này đều đã dựng lại hành vi cũ và xác nhận nó **đỏ**. Một test không làm
được điều đó thì hoặc là tautology, hoặc chỉ canh code mới.

---

## 7. Thứ tự đề xuất khi quay lại

1. **Cấp quyền ghi repo cho `dacerlary`** → 8 commit mới rời khỏi máy.
2. **Cài Xcode** → biên dịch 5 thay đổi Swift đang treo, rồi mở khoá hàng 3,
   hàng 7-TTS, M8/M9, M10, M13.
3. **Chạy thử trên iPhone thật** — ba thứ chỉ tai người xác nhận được: hết rè
   chưa, mic Challenge mở được chưa, âm lượng đều chưa.
4. **Một log máy thật lúc audio từ vựng đứt** → mở khoá hàng 6.
5. **Chạy debug build vào lesson intro** → chốt nguyên nhân màn đỏ.
6. Trả lời 3 quyết định sản phẩm ở mục 3.

---

## 8. Test case cho tester — hàng 3

Vừa là kịch bản test vừa là cách thu đúng dữ liệu đang thiếu.

**Chuẩn bị.** Build **phải** có dart-define pháp lý, nếu không onboarding khoá
chế độ giọng nói:

```bash
flutter run -d <device-id> --dart-define-from-file=dart_defines.production.json
```

| Mã | Tên | Thao tác | Mở khoá việc gì |
|---|---|---|---|
| TC-01 | Đo độ trễ mở mic | Bấm ghi âm, **không nói gì**, chờ tự dừng — 10 lần liên tiếp + 3 lần sau khi mở lại app | Lấy `listeningReadyMs` → sửa "mất phần đầu" |
| TC-02 | Bản ghi lúc có lúc không | Nói một từ ngắn / câu dài liền mạch / câu có ngắt giữa chừng, mỗi loại 5 lần | Cần giả thuyết mới |
| TC-03 | Âm lượng theo độ dài | Ghi câu **dưới 5 giây** và câu **trên 12 giây**, chấm to/nhỏ thang 1-5, cả iOS và Android | Xác nhận nguyên nhân giới hạn 12s |
| TC-04 | Lấy file ghi âm bị rè | Ghi tới khi nghe thấy rè, kéo file ra khỏi máy, **nghe trên máy tính** | Sửa "rè, giựt" |
| TC-05 | Hồi quy | Chạy lại TC-01 và TC-03, so mốc. Thêm: ghi âm ở Chủ đề / Thử thách / Luyện lại / Bộ từ vựng | Sau khi có fix |

**TC-04 làm trước** — một thao tác chia đôi không gian tìm kiếm:

| Nghe trên máy tính | Kết luận |
|---|---|
| File **cũng rè** | Lỗi ở đường **ghi** — AGC hoặc encoder |
| File **sạch** | Lỗi ở đường **phát lại** |

**Lấy file từ iPhone:** Xcode → Window → Devices and Simulators → chọn máy →
Installed Apps → HOMI → bánh răng → **Download Container** → mở gói `.xcappdata`
→ `AppData/Documents/`.

**Lấy file từ Android:**
```bash
adb exec-out run-as com.innotrik.aispeaking tar c files/ | tar x
```

**Lọc log nhanh:**
```bash
grep -E 'listeningReadyMs|audio_tap_installed|first_audio_buffer' homi-qa-*.log
grep -i 'normalization skipped' homi-qa-*.log
```

---

## 9. Lệnh hay dùng

```bash
# Suite Dart đúng như CI (zsh KHÔNG chạy được đoạn này, phải qua bash)
bash -c 'NON_GOLDEN="$(find test -type f -name "*_test.dart" ! -name "*golden*.dart" -print |
  while IFS= read -r f; do grep -q matchesGoldenFile "$f" || printf "%s\n" "$f"; done)"
  flutter test $NON_GOLDEN'

dart run tool/check_architecture_boundaries.dart   # gồm cả kiểm trùng khai báo Swift
flutter analyze

cd android && sh gradlew :app:testDebugUnitTest    # 42 test Kotlin, CI không chạy

python3 tool/measure_audio_loudness.py             # sinh lại manifest âm lượng
python3 tool/measure_audio_loudness.py --check     # fail nếu manifest đã mốc
```
