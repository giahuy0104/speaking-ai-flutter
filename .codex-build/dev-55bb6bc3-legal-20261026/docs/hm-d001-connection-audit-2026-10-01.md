# Rà soát HM-D001: BLE, HFP và audio (01/10/2026)

## Kết quả hiện có

- Máy phát triển không thấy điện thoại Android/iPhone qua `flutter devices` hoặc `adb devices -l`. Chưa thể đo tỉ lệ rớt kết nối, thời gian khôi phục hay chất lượng âm thanh trên HM-D001 thật.
- Phép đo phần mềm: 48 ca BLE/HFP/phát âm thanh chạy 10 lượt, qua 10/10; trung bình 9,28 giây/lượt trên máy này. Thêm 88 ca audio/chẩn đoán qua. 11 ca Android native HFP qua.
- Bài golden `audio and data settings keep the shared visual rhythm` vẫn lệch 7,25% sau khi bỏ toàn bộ sửa đổi giao diện; chưa thuộc thay đổi BLE/audio này.

## Luồng hiện tại

| Hệ | Nút MAIN | Mic/loa | Điểm cần phân biệt |
| --- | --- | --- | --- |
| Android | BLE GATT 9E3B0001, xác nhận Indicate 9E3B0002 rồi mới connected; tối đa 5 lượt retry mỗi lần mất liên kết | Bluetooth HFP/SCO, chọn communication device riêng | BLE reconnect không tự chứng minh HFP đã mất. Overlay kết nối có thể xuất hiện khi chỉ MAIN mất BLE. |
| iOS | CoreBluetooth, iOS 17+ cho phép hệ thống tự reconnect; bản cũ dùng retry trong app; có thể hoãn trong lượt audio | AVAudioSession route `bluetoothHFP` hai chiều, xác nhận mic và loa riêng | `reconnecting` có thể là BLE GATT/MAIN, không nhất thiết là mic/loa. Timeline native có mã lỗi CoreBluetooth. |

## Lỗi mã đã xác nhận và sửa

1. Android có thể nhận callback từ BluetoothGatt cũ sau khi đóng GATT và mở phiên mới. Callback cũ từng có thể đặt lại `bluetoothGatt`, làm trạng thái mới bị mất hoặc hiện reconnect sai. Callback GATT giờ chỉ được xử lý nếu thuộc phiên đang hoạt động.
2. Android đã hẹn retry nhưng không hủy khi ngắt thủ công/dừng phiên nền/đổi thiết bị. Retry cũ giờ được hủy và kiểm tra lại phiên trước khi mở GATT.
3. Android từng đặt lại bộ đếm retry ngay khi radio báo connected, trước khi GATT service và MAIN Indicate được xác nhận. Bộ đếm giờ chỉ đặt lại sau callback CCCD thành công.
4. iOS có thể nhận callback của peripheral cũ sau khi chọn thiết bị khác. Callback không còn được phép ghi đè trạng thái thiết bị hiện hành; peripheral trước được ngắt khi chuyển thiết bị.
5. Android hiện xuất mã/thời điểm ngắt BLE gần nhất trong chẩn đoán. Logcat capture đã thêm `Aiv0BleControl` và `BluetoothGatt` để đối chiếu lần reconnect với HFP/audio.

## Benchmark cần chạy trên thiết bị thật

Chạy cùng một bản build và cùng HM-D001 trên Android và iOS. Ghi số lần reconnect, mã ngắt BLE, thời gian từ ngắt đến MAIN Notify, trạng thái HFP, và việc mic/loa/nút MAIN còn hoạt động. Trên Android cắm USB, bật USB debugging, lấy serial từ `adb devices -l`, rồi chạy `tool/start_audio_diagnostic_capture.ps1 -DeviceId <serial>`. Giữ file `device.log`. Trên iOS xuất timeline BLE/HFP ở màn hình Chẩn đoán thiết bị.

1. Để yên 10 phút sau khi cả BLE và HFP đã connected.
2. Phát 20 prompt liên tiếp; giữa mỗi prompt kiểm tra MAIN.
3. Ghi âm và phát lại 20 lượt; kiểm tra đường mic và loa thật.
4. Đưa app xuống nền rồi mở lại 10 lượt.
5. Tắt/bật Bluetooth và tắt/bật HM-D001 mỗi loại 3 lượt, đo thời gian phục hồi.

Nếu xuất hiện "đang kết nối lại", đối chiếu thời điểm với `Aiv0BleControl Reconnect`/`lastDisconnectCode` (Android) hoặc `BLE_DISCONNECTED`/`ble_main_notification_refresh_failed` (iOS). Nếu không có sự kiện mất BLE nhưng HFP đổi route, điều tra HFP; nếu chỉ có BLE mất và HFP vẫn ổn, điều tra GATT/firmware/điều kiện radio. Không thể quy nguyên nhân phần cứng hoặc firmware chỉ từ bộ test trên máy phát triển.
