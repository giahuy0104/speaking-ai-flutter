# Back trong Chủ đề / Từ vựng khi dùng H20

## Phạm vi đã sửa

- Back trên màn hình và Back hệ thống rời màn học mà không chờ native audio trả lời. Giữ checkpoint, không tự đánh dấu hoàn thành phần chưa học.
- Chủ đề: tách nút Back khỏi vùng khóa thao tác khi MAIN tạm dừng bài; popup nhắc học không nuốt thao tác Back. Áp dụng cả phần xem lại bài và Thử thách.
- Từ vựng hôm nay: bỏ việc buộc học xong nhóm trước khi Back. Giữ phiên đang học để lần sau tiếp tục. Back không tự phát menu hay mở lại bài.
- Khi route học đóng, hủy ngữ cảnh MAIN; lượt takeover cũ không được mở mic hay tự khôi phục module đã rời.
- Khi chuyển từ trang Từ vựng về Giao tiếp, vô hiệu lượt phát cũ và yêu cầu dừng các nguồn âm thanh. Phản hồi tải audio / chuẩn bị tuyến H20 đến trễ không được phát lại sau Back.
- Chỉ thay cơ chế thoát, hủy tác vụ và khóa thao tác. Không thay nội dung học, chấm điểm, thuật toán dịch, hay mã Bluetooth/native của iOS/Android.

## Kiểm chứng

- 560/560 test đạt: voice_navigation, vocabulary, listening, conversation, AppFlowCoordinator và HomeLearningShell.
- Có 9 test bổ sung cho Back màn hình / hệ thống, âm thanh dừng bị treo, MAIN takeover đến trễ, cache audio đến trễ, hủy chuẩn bị fixed prompt và thông báo thoát route.
- Analyzer vùng nguồn và test liên quan: `No issues found`.
- Golden Thử thách được đối chiếu: chỉ nút Back chuyển từ disabled sang enabled; cập nhật đúng golden này.
- Log hồi quy: `output/apk/back-h20-final-regression.log`.
- Chưa nghiệm thu trên điện thoại/H20 thật (ADB không có thiết bị).

## Kiểm tra trên thiết bị

1. Chủ đề: Back khi đang đọc, đang thu, MAIN đang hỏi và MAIN đã im lặng. Kiểm tra cả mũi tên và Back Android.
2. Từ vựng hôm nay: Back trước khi hết nhóm; vào lại kiểm tra vị trí học, không bị đánh dấu hoàn thành trước.
3. Ba mẹ đã thêm / Ngôi sao: Back giữa câu, rồi chuyển về Giao tiếp; không phát tiếp hoặc mở mic từ phiên cũ.
4. Sau mỗi lần Back, mở lại bài / nhấn MAIN; kiểm tra bàn giao mic và âm thanh H20.

Lưu ý: stop được gửi nhưng không chặn điều hướng nếu native không trả lời. Test giả lập không thay thế kiểm tra firmware / đường âm thanh H20 thực tế.
