# Phân tích 29 test thất bại — 2026-10-21

## Kết luận

29 test thất bại không tương đương 29 lỗi chức năng của app. Phân loại: 6 test BLE dùng nhãn CTA cũ; 1 test accessibility dùng cấu trúc Settings cũ và chưa chờ mở trang hoàn tất; 1 test khoảng nghỉ song ngữ chưa cập nhật sau thay đổi nghiệp vụ; 21 test so ảnh khác pixel với golden.

Không tìm được lỗi chức năng mới từ 29 failure này trong phạm vi điều tra. Chưa kiểm nghiệm thiết bị HOMI thật, nên không suy ra toàn bộ BLE/phần cứng đã an toàn. Golden mismatch cũng cần review trước khi chấp nhận, không tự cập nhật toàn bộ hoặc tăng ngưỡng để làm xanh test.

## 1. Sáu test kết nối — kỳ vọng nút cũ, đã kiểm chứng

Nguồn: `test/app/device_connection_action_app_test.dart:254`. `_tapSpeak` tìm text `Bắt đầu nói`, nhưng các tình huống chưa sẵn sàng hiện nút `Kết nối HOMI`, đúng yêu cầu UI đã chốt. Tất cả sáu failure dừng ở finder trước khi kiểm hành vi BLE:

1. Home quan sát native retry lỗi và Hủy gọi xuống native.
2. Thử lại bắt đầu scan mới, không tìm được thiết bị thì hiện hướng dẫn.
3. Hủy bỏ kết quả scan đến trễ, cho phép thử lại ngay.
4. Scan treo phải nhả nút Thử lại sau deadline 45 giây.
5. Hủy lượt hiện tại vẫn giữ retry HFP nền theo tick 15 giây.
6. Chỉ có BLE nhưng thiếu HFP không được bắt đầu nói.

Chẩn đoán: sao chép test tạm, chỉ thay finder thành `Kết nối HOMI`, giữ nguyên toàn bộ assertions, chạy cùng privacy defines như regression. Cả **7/7 test trong file đạt** (gồm sáu lỗi và một test Topic/HFP vốn đạt). Không sửa code app/BLE. Điều này xác nhận lỗi finder; không phải bằng chứng radio/firmware hoạt động đúng trên thiết bị thật.

Đề xuất: thêm Key ổn định cho primary action hoặc tìm InkWell trong SpeakActionBar; dùng key cho test nghiệp vụ và test riêng nhãn theo readiness. Ưu tiên cao vì sáu case quan trọng hiện bị mất khả năng bảo vệ hồi quy.

## 2. Một test accessibility — cấu trúc Settings cũ, đã kiểm chứng

Nguồn: `test/accessibility_resilience_test.dart:81`. Test vẫn tìm `Dữ liệu và quyền riêng tư` và `Xem lịch sử gần đây` sau khi mở Settings; màn mới đã nhóm `Thông tin & hỗ trợ`, có Chính sách quyền riêng tư và Điều khoản riêng. Test cũng chỉ pump một frame sau thao tác mở trang async.

Chẩn đoán tạm: chờ mở trang xong, kiểm nhóm hiện tại, các key privacy/terms, cuộn đến Điều khoản và xác nhận hit-testable; giữ viewport 320×568, text scale 200% và reduced motion. **1/1 đạt, không phát hiện overflow/exception trong luồng đã test**. Tổng hai file probe **8/8 đạt**.

Đề xuất: cập nhật assertions theo UI đã duyệt, giữ kiểm cỡ chữ lớn/khả năng cuộn và tương tác; thêm TalkBack/VoiceOver thủ công khi nghiệm thu. Không nên suy ra mọi màn đều đạt accessibility từ một test này.

## 3. Một test audio — khoảng nghỉ 2 giây so với 0 giây

Nguồn: `test/features/listening/lesson_guide_flow_v2_test.dart:11` đòi `englishToVietnamesePause == 2s`, trong khi `lib/features/listening/domain/lesson_guide_flow.dart:256` là `0s`.

Git cho thấy commit `d500904e` ngày 15/10/2026 đổi 2s → 0s; `4d89b5c7` ngày 16/10 sửa comment thành zero-second. Đây là thay đổi có chủ ý trong lịch sử source, test chưa đi theo.

Ảnh hưởng thực tế: câu nghĩa tiếng Việt bắt đầu ngay sau khi câu tiếng Anh kết thúc thay vì nghỉ thêm 2 giây. `_playBilingualSentenceSample` await `_playEnglishSentenceSample` trước khi chờ gap và phát tiếng Việt; nhánh authored audio dùng await playToCompletion, prompt dùng speakAndWait. Gap 0 không tự đồng nghĩa hai đoạn phát chồng nhau. Chưa đo đường âm thanh trên phần cứng.

Đề xuất: giữ 0s theo behavior đã ghi nhận và cập nhật test nếu đó vẫn là yêu cầu hiện hành. Bổ sung/giữ test thứ tự English hoàn tất → Vietnamese bắt đầu; không tự đổi lại 2s chỉ để làm test xanh. Nếu muốn trẻ có thời gian tiếp thu thêm thì đó là quyết định UX/audio riêng.

## 4. Hai mươi mốt test golden — sai khác ảnh tham chiếu

Phân bố: Home 5, luồng Chủ đề/bài học 9, Karaoke 1, Từ vựng 5, Lịch sử 1. Có 20 ảnh tham chiếu khác nhau vì hai test Home dark dùng chung một golden. Không nhầm với 24 file testImage còn trong thư mục failures từ các lượt kiểm tra khác.

Đã đọc log từng failure, tính độ lệch pixel cho cả 20 ảnh tham chiếu và xem trực tiếp một số cặp master/test và isolated diff (Home, hành trình bài học, Lịch sử, Karaoke). Các mẫu khác chủ yếu ở chữ, nét glyph/icon; bố cục và nội dung chính không thay đổi rõ rệt. Điều này gợi ý vấn đề typography/rendering hoặc baseline không đồng bộ, chưa đủ để quy mọi lỗi cho một nguyên nhân font duy nhất.

- Home: khoảng 0.25–0.41% pixel lệch, mẫu Home tập trung ở chữ hai nút Từ vựng/Chủ đề.
- Bài học: khoảng 0.69–3.10%; mẫu hành trình tập trung ở viền chữ/icon.
- Từ vựng: khoảng 1.42–2.84%.
- Lịch sử: 1.38%; ảnh có kích thước 1170×2532 dù tên ghi390×844 (DPR3), hợp lệ về logic pixels nhưng harness cần quy định DPR rõ ràng.
- Karaoke: 12.69% pixel khác, nhưng chỉ 2.38% tổng pixel lệch trên10 mức màu; nhiều sai khác nhỏ, không phải12.69% UI bị hỏng. Hai ảnh nhìn cùng bố cục/nội dung. Không dùng số liệu này để tự cho qua so ảnh.

Môi trường điều tra Flutter3.44.6, Dart3.12.2; `.metadata` khớp revision SDK này, không tìm thấy `.fvmrc` ở root repo. Một số harness chỉ load Roboto-Regular và MaterialIcons, trong khi pubspec khai báo cả Roboto Medium/Bold. Đây là điểm cần chuẩn hóa, chưa chứng minh là nguyên nhân duy nhất.

Ảnh hưởng thực tế: hiện chỉ xác nhận khác hình ảnh, không có crash/chức năng hỏng được chứng minh bởi21 test này. Có thể ảnh hưởng độ đậm/chữ/spacing; cần kiểm render có chủ đích trước khi chốt golden.

Đề xuất theo thứ tự:

1. Pin SDK thực dùng, chuẩn hóa viewport logic + DPR + text scale + locale + font assets/weights trong một helper golden chung.
2. Chạy lại trước khi đổi ảnh; review master/test/diff theo từng màn, ưu tiên Karaoke và chữ lớn.
3. Nếu UI hiện tại đúng bản duyệt, cập nhật đúng các golden liên quan; nếu không, sửa UI trước.
4. Giữ pixel comparison nghiêm ngặt, không nâng tolerance hàng loạt. Tách test tương tác khỏi test ảnh để pixel fail không làm mất thông tin hành vi.

### Danh sách đủ 21 golden tests

- `test/features/home/home_learning_shell_golden_test.dart: dark communication matches the approved rail treatment`
- `test/features/home/home_learning_shell_golden_test.dart: dark home keeps the approved option two composition`
- `test/features/home/home_learning_shell_golden_test.dart: disconnected home matches the approved navy tabs`
- `test/features/home/home_learning_shell_golden_test.dart: home communication matches image one`
- `test/features/home/home_learning_shell_golden_test.dart: small disconnected home keeps both tabs readable with large text`
- `test/features/listening/lesson_flow_golden_test.dart: English-only lesson review matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: V4 completion opens an authored voice challenge`
- `test/features/listening/lesson_flow_golden_test.dart: favorite food journey matches the selected HOMI direction`
- `test/features/listening/lesson_flow_golden_test.dart: friendly reminder popup matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: lesson intro matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: recording praise fireworks match the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: sentence practice matches the approved direction`
- `test/features/listening/lesson_flow_golden_test.dart: song journey uses English-first titles and music markers`
- `test/features/listening/lesson_flow_golden_test.dart: topic lesson journey matches the approved direction`
- `test/features/listening/song_karaoke_screen_test.dart: karaoke screen matches the selected visual direction`
- `test/features/settings/history_sheet_test.dart: empty history keeps the shared HOMI visual system`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: parent suggestion selection stays visually quiet`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: parent-added journey uses the welcoming HOMI`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: review journey uses the navy anchor tile`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: review practice HOMI stage at 390x844`
- `test/features/vocabulary/vocabulary_practice_golden_test.dart: stars journey uses the singing HOMI`

## Thứ tự xử lý đề xuất

1. Sửa6 finder BLE và1 accessibility trước: thay đổi test có căn cứ, khôi phục coverage của các luồng quan trọng.
2. Đồng bộ contract/test khoảng nghỉ audio với quyết định0s hiện có, giữ kiểm thứ tự kết thúc phát.
3. Chuẩn hóa môi trường golden rồi review/cập nhật ảnh có chọn lọc.
4. Chạy hồi quy đầy đủ; kiểm trên điện thoại + HOMI thật các case Hủy/Thử lại, thiếu HFP, tick nền và phát câu song ngữ.

Lượt điều tra này chưa thay code production, chưa sửa test chính thức, chưa cập nhật golden, chưa build/cài APK. Bản probe tạm đã được gỡ khỏi test discovery, lưu dạng `.dart.txt` cùng log trong `HOMI/docs/session-artifacts/2026-10-21-test-failure-audit/`. Các log MissingPluginException/HTTP400/TimeoutException xuất hiện trong harness mock không tự chứng minh lỗi runtime trên máy thật.
