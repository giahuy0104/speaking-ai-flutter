# Task thử năng lực xử lý bug — 03/10/2026

## iOS: HM-D001 xuất hiện sau BLE nhưng mic không tự được chọn

**Mức ưu tiên:** P1 · **Nền tảng chính:** iOS · **Đối chứng:** Android
**Bản thử:** build iOS từ nhánh `ios-next-2026-10-01`, commit tối thiểu `82e7e508`. Ghi số build thực tế; TestFlight 152 không chứa thay đổi này. Dùng HM-D001 thật, ghi model iPhone, iOS và firmware thiết bị.

### Tình huống cần kiểm tra

1. Để Bluetooth bật nhưng chưa có mic HFP HM-D001 khả dụng trong iOS. Mở HOMI, kết nối BLE để nút MAIN được báo đã kết nối và hoàn tất thiết lập.
2. Giữ BLE đang kết nối. Sau đó làm cho mic HFP HM-D001 xuất hiện qua Cài đặt Bluetooth của iPhone rồi quay lại HOMI. Không nhấn **Chọn micro HOMI** hoặc ngắt BLE thủ công.
3. Đợi 30 giây, mở **Chẩn đoán thiết bị** và thử luồng nói. Lặp lại ít nhất ba lượt; nếu iOS tự làm rớt BLE khi chuyển profile, ghi rõ lần đó thay vì gộp với trường hợp BLE giữ nguyên.
4. Chạy cùng trình tự trên Android để đối chiếu lúc mic HFP xuất hiện muộn.

**Mong đợi:** Khi BLE vẫn kết nối và mic HM-D001 đã khả dụng, app tự phát hiện/chọn đúng mic mà không cần bấm chọn thủ công. Trạng thái phải phân biệt rõ BLE MAIN và HFP; nút MAIN vật lý chỉ bắt đầu lượt nói khi audio route sẵn sàng.

**Dấu hiệu lỗi cần xác nhận:** Mic đã xuất hiện trong hệ thống nhưng HOMI tiếp tục dùng mic iPhone hoặc báo HFP chưa sẵn sàng sau khi trở lại app, cho đến khi người dùng chọn mic thủ công hoặc ngắt/kết nối lại BLE. Đây là khoảng trống suy ra từ luồng mã hiện tại, **chưa được tái hiện trên build iPhone mới**; nhóm cần xác nhận bằng máy thật trước khi chốt bug.

### Bài nộp của người xử lý

- Video ngắn có thời điểm BLE connected, thời điểm HFP xuất hiện và kết quả sau 30 giây; ảnh Chẩn đoán thiết bị gồm BLE GATT/MAIN Notify, HFP, audio route và timeline.
- Bước tái hiện ổn định, tỉ lệ lỗi trên ít nhất ba lượt, và khác biệt với Android. Ghi rõ trường hợp BLE không hề rớt so với trường hợp iOS chuyển profile làm BLE reconnect.
- Phân tích nguyên nhân có bằng chứng, bản sửa nhỏ nhất giữ nguyên thao tác chọn mic thủ công và không chen vào phiên MAIN/ghi âm đang chạy.
- Kiểm thử hồi quy: BLE trước/HFP sau, HFP có sẵn từ đầu, người dùng chủ động chọn mic iPhone, app vào nền rồi quay lại, và không chọn nhầm tai nghe Bluetooth khác.

**Điều kiện hoàn thành:** Tái hiện được lỗi hoặc chứng minh bằng log rằng điều kiện tái hiện không xảy ra trên build thử; nếu sửa, cho thấy ca lỗi hết và các ca hồi quy trên iOS/Android vẫn đạt. Không đánh dấu “đã sửa” chỉ vì Flutter unit test qua trên Windows.
