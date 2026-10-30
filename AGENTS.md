# Rule review

Áp dụng trước khi đề xuất merge một nhánh vào `dev` hoặc nhánh đích khác.

1. Cập nhật nhánh đích từ remote, xác nhận nhánh hiện tại và trạng thái working tree. So sánh toàn bộ diff từ merge base đến nhánh cần merge; kiểm tra merge thử để phát hiện xung đột. Không gọi một thay đổi là đã merge nếu lịch sử Git chưa xác nhận.
2. Viết lại ngắn gọn hành vi mong đợi của task và lần theo từng luồng bị ảnh hưởng từ thao tác người dùng đến kết quả cuối cùng. Kiểm tra cả đường thành công, hủy, quay lại, lỗi, dữ liệu rỗng hoặc đã đổi, thao tác lặp và chuyển màn hình khi tác vụ bất đồng bộ còn chạy.
3. Kiểm tra logic và vòng đời state, route, audio, microphone, callback và tài nguyên dùng chung. Xác định các lệnh dừng, khởi động hoặc điều hướng có thể chạy trễ, chạy hai lần hay hủy tác vụ kế tiếp. Đối chiếu điều kiện hiển thị, điều kiện xử lý và dữ liệu được lưu với cùng một nguồn hợp lệ.
4. Rà từng file trong diff: chỉ giữ thay đổi phục vụ task; loại bỏ mã, import, state, comment, fallback và hằng số trùng hoặc không còn dùng. Chỉ đề xuất tối ưu khi chỉ ra được chi phí hiện tại và lợi ích cụ thể; tránh refactor ngoài phạm vi task.
5. Chạy analyzer, lint và test tập trung cho luồng thay đổi; thêm hoặc sửa test cho rủi ro logic thực sự, nhất là ranh giới bất đồng bộ. Nếu hành vi phụ thuộc thiết bị hoặc backend, ghi rõ phần đã kiểm thử thực tế và phần chưa thể xác minh. Kiểm tra `git diff --check` và trạng thái repository sau cùng.
6. Báo cáo phát hiện theo mức độ ảnh hưởng, kèm file, dòng, điều kiện tái hiện và hậu quả. Phân biệt lỗi chặn merge với rủi ro còn lại. Chỉ kết luận sẵn sàng merge khi các kiểm tra bắt buộc đã đạt; nếu không tìm thấy lỗi, nêu rõ phạm vi đã review và giới hạn xác minh. Không tự merge khi task chỉ yêu cầu review.
