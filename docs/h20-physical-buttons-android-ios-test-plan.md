# Kế hoạch thêm và kiểm thử nút vật lý H20 trên Android và iOS

> Ngày lập: 18-09-2026  
> Nhánh kiểm tra: `origin/audio-17th9`  
> Commit nền khi lập tài liệu: `f81acb07`  
> Trạng thái: **Kế hoạch triển khai và nghiệm thu — chưa xác nhận giao thức của thiết bị mới**

## 1. Mục tiêu

Chuẩn bị sẵn màn hình chẩn đoán, mô hình sự kiện và ca kiểm thử để khi thiết bị
H20 mới đến có thể:

1. Kết nối thiết bị với Android hoặc iOS.
2. Bấm riêng từng nút vật lý.
3. Xem ứng dụng nhận tín hiệu qua BLE hay Media Key.
4. Lưu Raw Hex và kiểu thao tác thực tế.
5. Xác nhận giao thức trước khi ánh xạ sang lệnh bài học.
6. Kiểm thử câu trước, câu sau, nghe lại, tạm dừng và tiếp tục mà không sửa lại
   luồng luyện nghe.

Tài liệu này chỉ bao gồm **đầu vào điều khiển từ thiết bị**. Không thay đổi cơ
chế dịch, ASR, chấm điểm, API, nội dung bài học hoặc nguồn âm thanh ElevenLabs.

## 2. Hiện trạng trên nhánh

### Đã có

- Android và iOS đã có cầu nối BLE cho sự kiện MAIN.
- Packet H20 đã quan sát hiện chỉ được xác nhận là `MAIN + SHORT`.
- Flutter đã có luồng MAIN nhấn ngắn.
- Flutter đã có xử lý nhấn giữ MAIN ở tầng ứng dụng.
- Màn luyện nghe đã có ba nút ảo `Câu trước`, `Nghe lại`, `Câu sau`.
- Ba nút ảo gọi các lệnh dùng chung `previousItem`, `replayCurrent`,
  `nextItem`; không cần viết lại nghiệp vụ bài học.
- Các lệnh dừng/tiếp tục bài học đã có trong `ActiveLearningCommand`.

### Chưa có hoặc chưa được thiết bị thật xác nhận

- MAIN vật lý nhấn giữ và sự kiện thả nút.
- Volume Up/Volume Down nhấn giữ gửi vào ứng dụng.
- Power của **thiết bị H20** nhấn ngắn gửi vào ứng dụng.
- Ánh xạ nút vật lý sang câu trước/câu sau/nghe lại.
- Xử lý đầy đủ Media Key tương ứng trên Android.
- `nextTrack`/`previousTrack` tương ứng trên iOS.
- Mã Button ID, Gesture ID, sequence, debounce và ACK của firmware mới.

Không được hiểu nút Power trong tài liệu này là nút nguồn của điện thoại. Ứng
dụng không được thiết kế để chặn nút nguồn hệ thống của Android hoặc iPhone.

## 3. Bảng ánh xạ nghiệp vụ dự kiến

Đây là ánh xạ sản phẩm dự kiến để viết giao diện và fake test. Chỉ bật ánh xạ
cho thiết bị thật sau khi đã ghi nhận được tín hiệu thực tế.

| Nút H20 | Gesture | Hành động dự kiến | Trạng thái hiện tại |
|---|---|---|---|
| MAIN | SHORT | Gọi trợ lý; nếu bài đang tạm dừng thì tiếp tục | MAIN SHORT đã có; hành vi resume cần kiểm thử |
| MAIN | LONG | Tạm dừng hoạt động hiện tại | Logic ứng dụng đã có; tín hiệu vật lý chưa xác nhận |
| Volume Up | LONG | Câu trước | Chưa xác nhận tín hiệu vật lý |
| Volume Down | LONG | Câu sau | Chưa xác nhận tín hiệu vật lý |
| Power H20 | SHORT | Nghe lại câu hiện tại | Chưa xác nhận tín hiệu vật lý |
| Volume Up/Down | SHORT | Thiết bị tự chỉnh âm lượng, APP không điều hướng | Chưa xác nhận hành vi firmware |
| Power H20 | LONG | Thiết bị tự bật/tắt, APP không xử lý | Chưa xác nhận hành vi firmware |

Nếu quyết định sản phẩm đổi chiều Volume Up/Down thì chỉ sửa tại
`AivoControlIntentMapper`; không sửa logic trong màn luyện nghe.

## 4. Bảng chẩn đoán cần thêm trong Cài đặt

Đổi tên khu vực hiện tại từ phạm vi chỉ nói về MAIN thành:

**Điều khiển thiết bị H20**

### 4.1. Trạng thái kết nối

| Trường | Nội dung |
|---|---|
| Thiết bị | Tên và mã thiết bị đang kết nối |
| BLE Control | Đã kết nối / Đang kết nối / Mất kết nối |
| Audio route | HFP / A2DP / loa điện thoại / không xác định |
| Nguồn sự kiện cuối | BLE / Android Media Key / iOS Remote Command / nút ảo |
| Protocol | Observed V1 / Draft / Unknown |

### 4.2. Sự kiện nút cuối cùng

| Trường | Ví dụ hiển thị |
|---|---|
| Nút nhận được | `MAIN`, `VOLUME_UP`, `VOLUME_DOWN`, `POWER`, `UNKNOWN` |
| Gesture | `SHORT`, `LONG`, `RELEASE`, `UNKNOWN` |
| Thời gian | `14:35:22.184` |
| Sequence | Giá trị từ packet hoặc `—` |
| Raw Hex | Chuỗi byte nguyên bản, không tự sửa |
| Intent sau ánh xạ | `previousItem`, `replayCurrent`, `pauseCurrent` hoặc `none` |
| Kết quả xử lý | `accepted`, `ignored`, `unavailable`, `duplicate`, `failed` |
| Trạng thái trước/sau | Ví dụ `playing -> paused` |

### 4.3. Lịch sử gần nhất

- Giữ tối thiểu 20 sự kiện gần nhất trong RAM để kiểm thử tại chỗ.
- Có nút **Sao chép log** và **Xóa log**.
- Mỗi dòng phải có thời gian, nền tảng, nguồn, button, gesture, raw và kết quả.
- Không ghi audio, lời trẻ nói, token, khóa API hoặc thông tin riêng tư vào log.
- Sự kiện không nhận diện phải giữ nguyên là `UNKNOWN`, không tự đoán thành MAIN.

### 4.4. Bảng khả năng của từng nút

| Nút/gesture | Android | iOS | Ghi chú |
|---|---|---|---|
| MAIN SHORT | Đã nhận / Không nhận | Đã nhận / Không nhận | Hiển thị theo phiên chạy thật |
| MAIN LONG | Chưa thử / Đã nhận / Không nhận | Chưa thử / Đã nhận / Không nhận | Không suy ra từ thời gian ở Dart nếu firmware không gửi đủ dữ liệu |
| Volume Up LONG | Chưa thử / Đã nhận / Không nhận | Chưa thử / Đã nhận / Không nhận | Ghi rõ BLE hay Media Key |
| Volume Down LONG | Chưa thử / Đã nhận / Không nhận | Chưa thử / Đã nhận / Không nhận | Ghi rõ BLE hay Media Key |
| Power SHORT | Chưa thử / Đã nhận / Không nhận | Chưa thử / Đã nhận / Không nhận | Chỉ là Power của H20 |

Trước khi có thiết bị, các dòng chưa xác nhận phải hiển thị **Chưa thử** hoặc
**Chờ thiết bị**, không hiển thị **Đã hỗ trợ**.

## 5. Mô hình sự kiện dùng chung dự kiến

Android, iOS, BLE và nút ảo phải chuẩn hóa về cùng một sự kiện:

```text
Control source
  -> button + gesture + raw data + timestamp
  -> intent mapper
  -> shared dispatcher
  -> ActiveLearningCommand / MAIN coordinator
  -> result + diagnostic log
```

Thông tin tối thiểu:

```text
source: ble | androidMediaKey | iosRemoteCommand | virtualButton
button: main | volumeUp | volumeDown | power | unknown
gesture: shortPress | longPress | release | unknown
occurredAt: timestamp
deviceId: optional
sequence: optional
rawPayload: chỉ dùng cho chẩn đoán
```

Raw payload không được truyền vào màn luyện nghe. Màn luyện nghe chỉ nhận intent
nghiệp vụ đã chuẩn hóa.

## 6. Phần dự định thêm cho Android

### 6.1. BLE

- Tiếp tục nhận indication từ characteristic điều khiển hiện có.
- Ghi log toàn bộ packet hợp lệ và packet chưa nhận diện.
- Chỉ thêm Button ID/Gesture ID sau khi có Raw Hex từ thiết bị thật hoặc tài
  liệu chính thức của ODM.
- Phát sự kiện chuẩn hóa sang Flutter; không xử lý câu trước/câu sau trong
  Kotlin.
- Chống event trùng bằng sequence hoặc dấu thời gian sau khi hiểu firmware.

### 6.2. Media Key

- Kiểm tra thiết bị có phát Android media key hay không.
- Nếu có, thêm điểm nhận phù hợp bằng MediaSession/MediaButton.
- Ghi lại key code, action down/up, repeat count và thời gian giữ.
- Không chiếm phím âm lượng ngắn nếu thiết bị dùng nó để chỉnh âm lượng.
- Không giả định Android sẽ chuyển Power của H20 thành một key code cụ thể.

### 6.3. Chuyển sự kiện sang Flutter

- Native chỉ báo loại sự kiện đã quan sát được.
- Flutter intent mapper quyết định hành động nghiệp vụ.
- Mọi lệnh bài học đi qua `ActiveLearningModuleRegistry` và cơ chế ngắt an
  toàn hiện có.

## 7. Phần dự định thêm cho iOS

### 7.1. BLE

- Thực hiện cùng quy tắc parser và Raw Hex như Android.
- Không tạo khác biệt ánh xạ nghiệp vụ giữa hai nền tảng.
- Unknown packet phải được hiển thị trong bảng chẩn đoán.

### 7.2. Remote Command

iOS hiện có thể nhận `play`, `pause`, `togglePlayPause` trong một số cấu hình
thiết bị. Cần kiểm tra và dự định bổ sung:

- `nextTrackCommand` nếu H20 phát sự kiện Next.
- `previousTrackCommand` nếu H20 phát sự kiện Previous.
- Ghi rõ tên remote command vào diagnostic source/raw description.
- Không tự coi mọi Play/Pause là Power SHORT cho đến khi test đúng thiết bị.
- Chỉ bật command trong ngữ cảnh cho phép để tránh điều khiển nhầm ứng dụng âm
  thanh khác.

iOS không cung cấp cơ chế chung để ứng dụng chặn nút nguồn của iPhone. Chỉ xử
lý được tín hiệu BLE hoặc remote command do phụ kiện H20 thực sự gửi.

## 8. Trình tự triển khai

### Giai đoạn A — Chuẩn bị trước khi có thiết bị

1. Thêm bảng chẩn đoán trong Cài đặt.
2. Thêm event model và lịch sử sự kiện dùng chung.
3. Thêm các giá trị domain `main`, `volumeUp`, `volumeDown`, `power`, `unknown`.
4. Giữ parser packet chưa biết ở trạng thái `unknown`.
5. Thêm intent mapper theo bảng dự kiến.
6. Dùng fake input kiểm thử cả năm thao tác chính.
7. Không bật cờ draft protocol trong bản production.

### Giai đoạn B — Khi thiết bị đến

1. Test Android trước ở foreground, sau đó test iOS.
2. Kết nối BLE và audio profile.
3. Bấm từng nút một lần, không mở bài học, để lấy raw baseline.
4. Bấm SHORT, LONG và giữ đến khi thả cho từng nút có hỗ trợ.
5. Lặp lại mỗi thao tác tối thiểu 10 lần.
6. Kiểm tra cùng một thao tác có phát một hay nhiều event.
7. Kiểm tra LONG có phát kèm SHORT trước hoặc sau hay không.
8. Lặp lại khi đang phát audio và khi đang ghi âm.
9. So sánh packet Android/iOS.
10. Chốt bảng Button ID/Gesture ID bằng log thật.

### Giai đoạn C — Khóa giao thức và nối nghiệp vụ

1. Viết fixture từ Raw Hex đã xác nhận.
2. Viết unit test parser trước khi sửa parser production.
3. Ánh xạ sự kiện chuẩn hóa sang intent.
4. Nối intent vào dispatcher dùng chung.
5. Bật từng nút vật lý trong bảng khả năng.
6. Chạy toàn bộ test tự động và test thiết bị thật.

## 9. Ma trận kiểm thử chức năng

Chạy toàn bộ ma trận riêng cho Android và iOS.

| Mã | Điều kiện | Thao tác | Kết quả mong đợi |
|---|---|---|---|
| BTN-01 | APP foreground, không ở bài học | MAIN SHORT | Mở/gọi trợ lý đúng luồng hiện có |
| BTN-02 | Đang phát câu luyện nghe | MAIN LONG | Audio dừng, giữ nguyên bài và câu, trạng thái paused |
| BTN-03 | Bài đang paused | MAIN SHORT | Tiếp tục đúng câu, không mở phiên trợ lý mới |
| BTN-04 | Đang ở câu giữa | Volume Up LONG | Chuyển về câu trước theo mapping dự kiến |
| BTN-05 | Đang ở câu giữa | Volume Down LONG | Chuyển sang câu sau theo mapping dự kiến |
| BTN-06 | Đang ở một câu | Power H20 SHORT | Giữ nguyên chỉ số và phát lại câu hiện tại |
| BTN-07 | Đang ghi âm | Previous/Next/Replay | Ghi âm dừng an toàn; kết quả cũ trả về sau đó bị bỏ qua |
| BTN-08 | Đang chấm điểm | Previous/Next/Replay | Không để kết quả cũ ghi vào câu mới |
| BTN-09 | Câu đầu | Previous | Không đổi câu; trả `unavailable` |
| BTN-10 | Câu cuối | Next | Tuân theo luồng hoàn thành bài hiện có |
| BTN-11 | Nhấn nhanh liên tục | Cùng một nút nhiều lần | Không tạo hai player, recorder hoặc phiên chuyển câu xung đột |
| BTN-12 | Packet/event bị lặp | Phát lại cùng sequence | Chỉ xử lý một lần, log `duplicate` |
| BTN-13 | Mất BLE | Bấm nút | Không crash; diagnostic báo mất kết nối |
| BTN-14 | Kết nối lại | Bấm lại nút | Nhận sự kiện bình thường, không nhân đôi subscription |
| BTN-15 | Audio dùng HFP/A2DP | Dùng mọi nút | Điều khiển không làm sai audio route |
| BTN-16 | APP background hoặc khóa màn hình | Dùng mọi nút | Ghi nhận chính xác khả năng/giới hạn của từng OS |
| BTN-17 | Cuộc gọi hoặc audio interruption | Dùng nút | Không tự khởi động recorder/player sai trạng thái |
| BTN-18 | Nút không biết | Gửi packet lạ | Log `UNKNOWN`, không chạy hành động bài học |

## 10. Kiểm thử tín hiệu thô bắt buộc

Với mỗi tổ hợp nút/gesture, ghi lại:

| Nền tảng | Firmware | Nút | Gesture | Nguồn | Raw/Key/Command | Số event | Kết luận |
|---|---|---|---|---|---|---:|---|
| Android |  | MAIN | SHORT |  |  |  |  |
| Android |  | MAIN | LONG |  |  |  |  |
| Android |  | Volume Up | LONG |  |  |  |  |
| Android |  | Volume Down | LONG |  |  |  |  |
| Android |  | Power H20 | SHORT |  |  |  |  |
| iOS |  | MAIN | SHORT |  |  |  |  |
| iOS |  | MAIN | LONG |  |  |  |  |
| iOS |  | Volume Up | LONG |  |  |  |  |
| iOS |  | Volume Down | LONG |  |  |  |  |
| iOS |  | Power H20 | SHORT |  |  |  |  |

Ngoài Raw Hex cần ghi rõ:

- Model điện thoại và phiên bản Android/iOS.
- Model H20 và firmware.
- BLE có đang kết nối không.
- HFP/A2DP có đang kết nối không.
- APP ở foreground, background hay màn hình khóa.
- LONG được giữ bao nhiêu mili giây.
- Có event DOWN/UP/RELEASE riêng không.
- Có event SHORT phát kèm LONG không.

## 11. Test tự động cần có

### Unit test

- Mỗi button + gesture hợp lệ tạo đúng intent.
- Volume SHORT và Power LONG trả `noAppAction`.
- Unknown không chạy lệnh nghiệp vụ.
- Draft packet không được giải mã khi cờ xác nhận đang tắt.
- Packet thực tế đã xác nhận có fixture cho cả Android và iOS.
- Duplicate sequence chỉ dispatch một lần.

### Widget test

- Bảng Cài đặt hiển thị đúng event gần nhất.
- Unknown hiển thị Raw Hex mà không đổi thành MAIN.
- Nút sao chép/xóa log hoạt động.
- Trạng thái `Chưa thử`, `Đã nhận`, `Không nhận` không bị ghi sai.

### Integration test không cần H20

- Fake BLE và nút ảo cùng input tạo cùng kết quả bài học.
- Previous/Next/Replay ngắt audio và recorder đúng cách.
- MAIN LONG pause; MAIN SHORT resume khi paused.
- Callback ASR/chấm điểm cũ không thay đổi câu mới.

### Integration test với H20

- Dùng đúng packet/key/remote command thật.
- Mỗi thao tác vật lý chỉ tạo đúng một intent.
- Kết quả giống nút ảo tương ứng.
- Không ảnh hưởng dịch, ASR, chấm điểm hoặc audio prompt.

## 12. Bằng chứng cần lưu sau buổi kiểm thử

Tạo một thư mục kết quả theo ngày, ví dụ:

```text
output/h20-button-test-YYYYMMDD/
  android-events.log
  ios-events.log
  raw-packet-matrix.md
  test-result.md
  screenshots/
```

`test-result.md` cần ghi:

- Build/commit đã test.
- Thiết bị điện thoại và H20.
- Phiên bản firmware.
- Các ca Pass/Fail/Blocked.
- Raw mẫu được chọn làm fixture.
- Khác biệt Android/iOS.
- Quyết định mapping cuối cùng.

Không commit log có token, thông tin tài khoản hoặc dữ liệu giọng nói của trẻ.

## 13. Điều kiện được phép bật chức năng cho người dùng

Một nút vật lý chỉ được đánh dấu hoàn thành khi:

- Có Raw Hex, key code hoặc remote command thật làm bằng chứng.
- Đã phân biệt được SHORT/LONG/RELEASE hoặc có quy tắc native rõ ràng.
- Không phát hai intent cho một lần thao tác.
- Android và iOS đã được test riêng; không suy kết quả của nền tảng này cho nền
  tảng kia.
- Fake input, nút ảo và nút vật lý cho cùng kết quả nghiệp vụ.
- Không làm hỏng audio route, recorder, dịch hoặc chấm điểm.
- Unknown packet luôn an toàn và không chạy nhầm lệnh.
- Toàn bộ test liên quan đạt.

## 14. Các file nền liên quan

- `lib/core/device/aiv0_ble_control.dart`: model và parser BLE hiện tại.
- `lib/core/device/active_learning_module.dart`: lệnh bài học dùng chung.
- `lib/core/device/main_button_coordinator.dart`: điều phối MAIN.
- `lib/features/listening/presentation/lesson_practice_screen.dart`: nút ảo và
  hành vi luyện nghe.
- `android/app/src/main/kotlin/com/innotrik/aispeaking/Aiv0BleControlBridge.kt`:
  cầu nối BLE Android.
- `ios/Runner/Aiv0BleControlBridge.swift`: BLE và remote command iOS.
- `docs/aivo_shared_virtual_ble_control_plan.md`: kiến trúc dispatcher dùng
  chung và ánh xạ V1.

## 15. Quy tắc quan trọng khi thực hiện

1. Làm bảng chẩn đoán trước, ánh xạ thiết bị thật sau.
2. Không bật `AIV0_DRAFT_PROTOCOL_CONFIRMED` chỉ để thử đoán packet.
3. Không sao chép logic luyện nghe vào Kotlin hoặc Swift.
4. Không tạo luồng Previous/Next/Replay riêng cho Android và iOS.
5. Không sửa cơ chế dịch, API, chấm điểm và ElevenLabs trong hạng mục này.
6. Nếu Android và iOS nhận tín hiệu khác nhau, chỉ adapter native khác nhau;
   intent và nghiệp vụ Flutter vẫn dùng chung.

## 16. Màn hình kiểm thử đã triển khai

Vào **Cài đặt → Điều khiển thiết bị H20** trên Android hoặc iPhone. Kết nối
audio H20 trong cài đặt Bluetooth của điện thoại và kết nối BLE trong ứng dụng
trước khi thu bằng chứng. BLE kết nối không đồng nghĩa micro/audio route đã sẵn sàng.

1. Mặc định chỉ quan sát, không thực thi lệnh. Chọn **Thử 8 giây**, rồi thao tác
   nút thật; xem nguồn, raw, gesture, intent, kết quả và trạng thái trước/sau.
2. **Đã nhận** chỉ áp dụng cho tín hiệu vật lý đã nhận diện trên nền tảng đang
   chạy. **Không nhận trong 8 giây** không phải kết luận không hỗ trợ phần cứng.
3. Các nút mô phỏng dùng dispatcher chung. Muốn chạy vào bài học đang mở, bật
   **Chạy lệnh thử vào bài đang mở**; có thể dừng ghi âm/chuyển câu/mở trợ lý.
   Mô phỏng không xác nhận firmware. Thoát màn hình sẽ tắt chế độ thực thi thử.
4. MAIN LONG chỉ dừng; MAIN SHORT tiếp tục bài đã dừng khi không có lượt trợ lý
   đang hoạt động. Khi không có bài tạm dừng, MAIN SHORT dùng luồng trợ lý hiện có.
5. **Sao chép log** xuất tối đa 80 sự kiện trong RAM; không xuất bản ghi, transcript,
   khóa API hoặc mã thiết bị. Không thay bằng log audio/timeline cũ vì chúng có
   thể chứa nội dung lời nói. **Xóa log** không xóa tiến độ hay bản ghi bài học.

Hiện chỉ mẫu BLE MAIN SHORT đã quan sát được nhận diện. Các packet lạ và lệnh
media của hệ điều hành vẫn là UNKNOWN, không tự đổi thành MAIN/Power. iOS không
còn tạo packet BLE giả từ play/pause. Cần kiểm thử H20 thật riêng trên từng hệ
điều hành trước khi mở thêm mapping; `AIV0_DRAFT_PROTOCOL_CONFIRMED=false`.

Trong hạng mục iOS bổ sung theo yêu cầu riêng của người dùng, Core/Challenge/
từ vựng tiếp tục nhận giọng nói và đối chiếu đáp án trên máy. Nếu Apple Speech
không khởi động được, không tự mở recorder khác để gửi audio lên API chấm.
Bản ghi luyện tập dùng WAV PCM16 theo sample rate thực của route; dịch/trợ lý
giữ luồng riêng hiện có. Các thay đổi này không bật API chấm audio mới cho iOS.

Build trên Codemagic: chạy `ios-bootstrap` trước để kiểm tra Swift và RunnerTests,
sau đó `ios-app-store` khi cần IPA/TestFlight và đã có cấu hình signing/privacy.
Kiểm thử Flutter trên Windows không thay thế việc build Xcode hoặc kiểm thử H20
vật lý. Xem thêm `docs/ios-app-store-release.md`.

### Trạng thái kiểm chứng và điều kiện build

- `flutter analyze --no-pub` và kiểm tra ranh giới kiến trúc: đạt.
- 33 unit test native Android: đạt. Swift/XCTest chưa chạy trên Windows.
- Các test mới về màn hình Settings, bridge, dispatcher, hủy MAIN và chấm cục bộ
  iOS đã đạt; vẫn cần điện thoại/H20 thật để xác nhận khả năng phần cứng.
- Ngày 2026-09-19, người dùng xác nhận giữ native TTS cho câu thiếu audio,
  không tạo audio mới. Hai ca coverage đã được cập nhật với danh sách chính xác
  16 câu trong `test/support/approved_assistant_tts_fallbacks.dart`. Không bỏ qua
  kiểm thử: câu thiếu mới ngoài danh sách vẫn báo lỗi; asset/hash/receipt vẫn
  được kiểm tra. Test riêng xác minh mỗi câu chỉ phát TTS một lần trên đúng
  route của Android/iOS. Chi tiết đồng bộ luồng: `docs/ios-feature-parity.md`.
- Diagnostic cũ ngoài bộ `test/`,
  `output/apk/recheck-vocabulary-choice_test.dart`, cũng còn hai kỳ vọng ban đầu
  `choiceRequests == 1` không đạt; chưa sửa hành vi/fixture ngoài phạm vi này.
