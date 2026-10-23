# Chủ đề: học khi mất mạng

Cập nhật 23/10/2026.

## Hành vi

- Giữ Core → Challenge → Song (nếu có) → lựa chọn cuối bài, số lượt trả lời, điều kiện cấp Sao và checkpoint hiện tại.
- Android tiếp tục ưu tiên bộ nhận dạng tiếng Anh trên máy. Có model thì nhận dạng không cần API; kết quả nhận dạng thật vẫn được đối chiếu đáp án theo quy tắc cũ. Chỉ lỗi/thiếu bộ nhận dạng mới đi vào fallback API hiện có.
- Sau frame đầu của Home, service dùng chung kiểm tra model tiếng Anh. Model thiếu thì xếp lịch tải nền; trang Chủ đề không còn nút tải hoặc thẻ trạng thái model. Không chặn Home/điều hướng và không mở popup.
- Android WorkManager chỉ tải khi có Wi-Fi đã xác minh Internet, không tính phí và đủ bộ nhớ lưu trữ. Nếu chưa có Wi-Fi thì chờ; mất Wi-Fi giữa lượt tải sẽ dừng và retry theo worker hiện có. Job có tên duy nhất dùng KEEP, giữ tiến trình khi Home/Settings cùng yêu cầu. File tải được kiểm tra SHA-256 rồi mới giải nén/cài đặt và đánh dấu installed.
- Mặc định chưa chọn cài đặt tải ngôn ngữ vẫn tự chuẩn bị riêng `en-US` cho Chủ đề; không tự bật tải tiếng Việt/bộ dịch. Nếu phụ huynh đã chủ động tắt tự tải thì tôn trọng lựa chọn đó. Service không ghi đè setting, kiểm tra lại khi app resume và bỏ callback muộn khi dispose; worker native tiếp tục độc lập khi đổi màn hình.
- iOS cũng kiểm tra riêng tiếng Anh sau frame đầu Home và khi resume. Luồng `speech.prepareTopicAssets` không xin quyền, không mở micro và không gọi `prepareBestEngine`, tránh thay/cancel phiên MAIN/lesson. iOS 26 kiểm tra AssetInventory trước; installed/downloading/unsupported không tạo request mới. Model thiếu chỉ khởi tạo tải khi NWPath báo Wi-Fi, satisfied, không expensive/constrained. Apple quản lý download/retry sau đó; API không cung cấp điều khiển cellular/cancel từng request nên không cam kết Wi-Fi-only suốt vòng đời như Android.
- iOS kiểm tra lại sau 30 giây khi đang chờ Wi-Fi, pending hoặc lỗi tạm thời, không phụ thuộc còn ở Home hay không. Dừng timer khi ready/unavailable/declined/dispose; lần Home/resume tiếp theo kiểm tra lại. iOS có thể suspend app nền; không cam kết timer chạy khi app bị suspend/kill. Explicit opt-out chặn yêu cầu mới, không hủy download hệ thống Apple đã nhận.
- Trước iOS 26 (hoặc máy không hỗ trợ SpeechAnalyzer), chỉ kiểm tra SFSpeechRecognizer.supportsOnDeviceRecognition. Apple không cung cấp API tải model legacy tương đương; kết quả khả dụng không phải phép thử nhận dạng thực tế. Không hứa mọi iPhone mới cài đều học offline ngay.
- Model sẵn sàng được dùng ở lượt nhận dạng tiếp theo; không tự chấm lại bản ghi, chuyển câu hoặc thay checkpoint. Chính sách chấm và xử lý mạng bên dưới giữ nguyên.
- Core và Challenge: mất mạng, timeout hoặc lỗi dịch vụ chấm không trở thành `retry`/`needsPractice`/`noResponse`. Giữ câu hiện tại và bản thu, không tăng lượt sai, không cấp Sao và không ghi kết quả chưa được xác minh. Có nút **Chấm lại bản ghi**; yêu cầu mới dùng lại audio, nội dung và số lượt cũ. Ghi âm lại hoặc điều hướng vẫn theo các thao tác cũ.
- Core giữ nghe lại câu mẫu/bản thu. Challenge đã phát lại bản thu trước khi phản hồi theo flow cũ. Chấm lại tiếp tục chờ phát lại kết thúc trước feedback.
- MAIN/pause/thoát màn hình tiếp tục dùng session/request guard: callback chấm đến muộn không được cấp Sao hoặc chuyển câu. Không đổi Bluetooth retry hoặc tự chuyển sang mic điện thoại.
- Bao toàn bộ lời gọi backend chấm bằng thời hạn 30 giây (bao gồm auth/identity, upload, response body, các lần thử nội bộ). Kiểm tra transport có giới hạn 2 giây; transport không xác định không bị coi là chắc chắn mất Internet. API lựa chọn cuối bài có giới hạn tổng 15 giây để lỗi mạng trả quyền thao tác về các nút chọn đã có.
- iOS giữ chính sách native hiện tại, không tự upload qua backend khi native thất bại. Các mã lỗi mạng/dịch vụ/route được nhận diện rõ không đi vào xử lý câu trả lời; yêu cầu ghi âm lại khi native sẵn sàng.

## Phạm vi offline

Đây là khả năng phục hồi lỗi trong phiên học và tái sử dụng bộ nhận dạng/asset/cache hiện có, không phải hàng đợi chấm nền bền vững. Bản thu chờ chấm lại được giữ trong màn đang học; không tự gửi lại khi có mạng, không hứa tự phục hồi nút chấm lại sau khi kill app. Tiến độ đã lưu vẫn dùng store cũ.

Muốn chấm offline trên Android phải tải xong model tiếng Anh trước. Model chưa có và không có mạng: có thể nghe nội dung local, ghi âm/nghe lại, nhưng không giả lập điểm hoặc tự đánh dấu hoàn thành để đi tiếp. Audio từ xa chưa có asset/cache vẫn cần mạng; thay đổi này không tải tất cả audio từ xa hoặc thêm engine offline cho web/iOS.

## Kiểm tra

Evidence: `../../docs/session-artifacts/2026-10-23-topic-offline/`.

- Test nhận dạng local thành công khi mất mạng, model thiếu + không transport, timeout identity/body, phân biệt lỗi native kỹ thuật, timeout nhận dạng lựa chọn.
- Test Core/Challenge lỗi mạng liên tiếp, dùng cùng audio và cùng attempt khi chấm lại, không ghi sai/Sao trước kết quả hợp lệ, chấm lại thành công; MAIN bỏ kết quả chấm lại đến muộn.
- Đợt đầu kiểm tra UI tải thủ công. Đợt sau thay bằng test service tải nền: chưa có model, installed/pending/unsupported, gọi trùng, lỗi scheduler/thử lại, tắt tự tải trong lúc query, dispose và Home chỉ gọi sau render/một lần mỗi mount. Native test kiểm tra job duy nhất, giữ tiến trình, network/storage constraints và marker/file hợp lệ trước khi bỏ qua download.
- Đợt triển khai offline trước khi chuyển tải nền Home: toàn bộ listening **585 qua, 10 golden lỗi cũ**. Sáu suite tập trung: **270/270 qua**. `flutter analyze --no-pub`: sạch. 10 golden lệch mẫu có sẵn được tái hiện trên snapshot HEAD độc lập. Cả 10 ảnh render giống hệt trước/sau thay đổi; không cập nhật golden để làm xanh test.

## Tự kiểm tra trên máy (người dùng thực hiện)

1. Bản cài chưa có model/chưa tắt tự tải: vào Home khi có Wi-Fi, tiếp tục sử dụng app trong lúc model tải nền; Chủ đề không có nút tải. Sau khi model cài xong, tắt Wi-Fi/dữ liệu di động nhưng giữ Bluetooth → kiểm tra Core và Challenge.
2. Vào Home khi chỉ có 4G/5G hoặc offline: model chỉ được xếp lịch, chưa tải dữ liệu; bật Wi-Fi thì worker tự tiếp tục, không cần quay lại Home.
3. Khi model chưa có, mất mạng → ghi âm → giữ nguyên câu, không mất lượt/Sao; nghe lại được bản thu Core.
4. Bật mạng → bấm **Chấm lại bản ghi** → chấm bản thu cũ; không tự chuyển câu chỉ vì có mạng trở lại.
5. Khi đang chấm lại, bấm MAIN hoặc thoát màn → kết quả muộn không thay tiến độ.
6. Cuối bài, khi không nhận dạng được giọng nói, chạm các nút lựa chọn như cũ.

Không cài/chạy app hoặc thao tác điện thoại theo yêu cầu của người dùng. Gradle build chỉ phục vụ unit test native local.


Đợt chuyển tải nền Home: xem `../../docs/session-artifacts/2026-10-23-home-offline-preparation/` và SESSION.md để biết kết quả local mới nhất. Không thay các kỳ vọng golden/vị trí mây trong đợt này.

Kiểm chứng chuyển tải nền Home: **116 Flutter test qua, 2 lỗi vị trí mây có sẵn** (đã tái hiện trên HEAD độc lập); **108/108 Android JVM test qua**, analyzer sạch. Test service gồm chống gọi trùng, thiếu/đã có model, lỗi scheduler, opt-out và dispose. Chưa xác minh tải model/nhận dạng thực tế trên thiết bị.

## Bổ sung iOS Home — 23/10/2026

Evidence: `../../docs/session-artifacts/2026-10-23-ios-topic-preparation/`. Kiểm tra thật do người dùng thực hiện: iPhone/iOS 26 có hỗ trợ, vào Home bằng Wi-Fi chờ model cài, tắt Internet nhưng giữ Bluetooth rồi học Core/Challenge; thử Home khi chỉ có cellular/offline rồi bật Wi-Fi, thử opt-out và điều hướng sang màn khác khi đang chuẩn bị. Phiên bản iOS cũ cần xác minh khả năng on-device của máy. Phát audio remote chưa cache vẫn cần mạng.

Apple API references: [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory), [downloadAndInstall](https://developer.apple.com/documentation/speech/assetinstallationrequest/downloadandinstall%28%29).

Kết quả đợt iOS: **262/262 test Flutter qua** (61 service/settings/speech + 200 lesson + 1 Home), analyzer/diff check sạch; **build iOS debug không ký mã thành công**. Build simulator bị chặn tại linker bởi MLKitCommon binary cho máy thật, chưa có runtime test iPhone/simulator. Không cài app lên điện thoại.

Đợt bổ sung full regression: xem [topic-offline-test-coverage.md](topic-offline-test-coverage.md) cho coverage/lệnh chạy. Thêm13 test mới đều qua; tổng786 Flutter qua/22 lỗi UI cũ được đối chứng baseline,111/111 Android native qua, analyzer sạch.
