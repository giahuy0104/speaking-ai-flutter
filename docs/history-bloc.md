# HistoryBloc — 23/10/2026

## Phạm vi và cấu trúc

```text
app/di/history_dependencies.dart
presentation/history/
  bloc/history_bloc.dart
  bloc/history_event.dart
  bloc/history_state.dart
  screen/history_sheet.dart
  widgets/history_widgets.dart
```

Di chuyển thực HistorySheet khỏi presentation/settings/screen, không giữ shim/export hay constructor controller dự phòng. Các widget và helper hiển thị nằm trong widgets; dùng Dart part để giữ private, không thay layout/styles/text. History ghi âm bài học (LessonRecordingHistorySheet) là module khác, chưa chuyển trong đợt này.

HistorySheet bắt buộc nhận factory HistoryBloc và callback ngôn ngữ. HistoryDependencies inject ConversationHistoryPort sẵn có. Mỗi lần mở sheet tạo một Bloc qua BlocProvider; khi đóng sheet tự close. Không global singleton; không dispose shared ConversationController/backend/audio. Cả route History từ Home và nút trong Settings iOS dùng factory này. Giữ route/sheet, parental gate và pause/resume voice navigation ở chủ sở hữu cũ.

## State và hành vi

HistoryState giữ danh sách immutable, query, filter, loading, inline load error, busyItems theo ID và notice kèm revision. Visible items giữ tìm kiếm trim/case-insensitive trên câu Việt/bản dịch kết hợp filter; danh sách mới nhất trước và ba bản thu gần nhất không bị filter ảnh hưởng.

Event gồm load/refresh, query/filter, phát bản dịch/bản thu, duyệt, xóa một mục và xóa tất cả. View giữ TextEditingController, dialog xác nhận và snackbar. Không còn setState nghiệp vụ hoặc nhánh fallback gọi port trực tiếp trong view. Bloc gọi port; các method controller tiếp tục dùng repository/playback cũ, không đổi API, rate, URL audio hay transport.

- Duyệt cập nhật lạc quan, nhận learning outcome khi thành công, hoàn tác đúng ID nếu thất bại.
- Xóa chỉ cập nhật danh sách sau server xác nhận. Hủy dialog không gửi event. Xóa thất bại giữ dữ liệu.
- Load lỗi hiện inline/Thử lại; action lỗi là notice để view hiện snackbar như cũ. Notice revision tránh phát lại snackbar do rebuild và cho phép báo cùng lỗi ở hai lần thử.
- Guard theo item chống thao tác trùng. Fetch/review/delete/clear đi qua hàng đợi IO để không ghi đè danh sách bằng response cũ hoặc sửa nhầm index; query/filter và playback không chờ hàng đợi. Clear/refresh đang pending được gộp hoặc chặn lặp. Đây là bảo vệ cạnh tranh tác vụ, không thay quy tắc nghiệp vụ thông thường.
- Close giải phóng handler đang chờ, bỏ kết quả cập nhật UI muộn, không chạy command còn xếp hàng. Request server/audio đã bắt đầu vẫn do port cũ hoàn tất; không tự dừng audio khi đóng sheet.

## Kiểm chứng

Unit/DI: sort/search/filter/recent audio, immutability, lỗi load/retry, review true/false lạc quan/rollback, delete/clear thành công/thất bại, duplicate, refresh đua với review/clear, playback hai loại, dispose khi load/review/delete/clear/play còn chờ và scope độc lập.

Widget: filter/search/retry, busy UI, snackbar một lần, dialog hủy/xác nhận, giữ dữ liệu đến server ack, playback, VI/ZH, ownership/dispose. Test integration app kiểm tra History từ Settings iOS tạo mới/đóng Bloc; test Home giữ đường mở route và gate hiện tại. Test cũ dùng controller thật nối fake repository để kiểm tra luồng hiện có.

Evidence/command/count: `HOMI/docs/session-artifacts/2026-10-23-history-bloc/summary.md`. Golden History đang có lỗi baseline, không cập nhật golden để che lỗi. Không test/cài app trên thiết bị thật hoặc thay phần Settings fallback đang tạm hoãn.
