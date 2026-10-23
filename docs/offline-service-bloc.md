# OfflineService / OfflineServiceBloc — 23/10/2026

## Scope

Chuyển toàn bộ state nghiệp vụ của SettingsOfflineLanguagePacksCard sang OfflineServiceBloc/Event/State tại presentation/offline/bloc. Widget không còn StatefulWidget, setState, timer, store hoặc khởi tạo adapter. BlocProvider sở hữu scope theo vòng đời card, đóng Bloc/service khi card unmount. SettingsScreen nhận factory qua constructor (mặc định factory DI), truyền bắt buộc xuống RecognitionSection/card, không có fallback state cũ.

OfflineService là contract tại domain/offline/offline_service.dart. PlatformOfflineService tại data/offline dùng các adapter/store hiện có qua constructor injection; OfflineDependencies tại app/di là nơi tạo dependency theo nền tảng. Tái sử dụng model/enum Android hiện tại để giữ nghĩa trạng thái; chưa di chuyển cả native/model layer trong task này.

## Ownership và hành vi giữ nguyên

- Service: đọc/ghi consent key v2 và fallback key v1 qua store cũ; kiểm tra model, tổng hợp Android en-US/vi-VN với tiến độ có trọng số, mốc95% khi speech xong nhưng dịch chưa có; chuẩn bị Apple vi-VN/en-US; dịch qua Wi-Fi; cancel Android khi tắt.
- Bloc: consent, status, preparation, busy, preparingIosModels, revision thông báo; event refresh/đổi lựa chọn; timer2giây chỉ khi pending. Guard ngăn refresh cũ ghi đè lúc lưu; single-flight chuẩn bị; đóng scope bỏ kết quả muộn.
- UI: giữ nguyên chữ VI/ZH, layout, switch và snackbar. Đọc state/render, gửi event; không gọi native/store trực tiếp.
- Bật tải vẫn báo requested trước khi chuẩn bị nền, tắt không xóa model đã có. Chuẩn bị kiểm tra consent trước khi tải dịch; close không khởi động bước tiếp theo trên translator đã đóng. Lỗi chuẩn bị nền được thu lại để refresh trạng thái, không để Future unawaited văng lỗi.

Luồng tự chuẩn bị khi Home/startup/resume trong AiSpeakingApp vẫn giữ lịch30giây và owner hiện tại; đây là luồng riêng ngoài phạm vi chuyển card Settings đã thống nhất. Không có nhánh chạy state cũ song song trong card. Không thay recognition/translation runtime, firmware, BLE/HFP, API hoặc luồng học.

## Kiểm tra nhanh

18/18 test trọng tâm (7 mới +11 hiện có), analyzer sạch, diff check sạch. Không full regression, không cài/chạy thiết bị. Evidence HOMI/docs/session-artifacts/2026-10-23-offline-service-bloc/.

User test thủ công: mở Settings khi đã có/chưa có model; bật tự tải qua Wi-Fi và xem tiến độ; tắt trong lúc chuẩn bị, đóng/mở lại Settings kiểm tra lựa chọn và trạng thái. Sau khi tải đủ, thử Chủ đề/dịch khi mất mạng trên máy thật.
