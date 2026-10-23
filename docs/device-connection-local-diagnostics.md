# Chẩn đoán kết nối onboarding — 23/10/2026

Phạm vi: xử lý phần có thể xác minh local, không dùng điện thoại/HOMI. Giữ BLE-first, yêu cầu MAIN + audio đã xác minh, không tự fallback mic điện thoại. Không đổi retry nền15s/60s, throttle10s, timeout service Android75s/iOS45s hoặc nhịp dò audio Android0/350/650/900/1200/1600ms và iOS0/600/600ms.

## Log mới

`DeviceDependencies` inject diagnostics vào service. Debug bật sẵn; Dart release chỉ bật nếu build với `HOMI_BLE_DIAGNOSTICS=true`. Native Android tự ghi cho attempt được đánh dấu trong build debug; release vẫn cần opt-in log tag `HomiBleDiag` như trước. Không thêm profile proxy, không chủ động connect/disconnect audio để chẩn đoán.

- Dart: console `HomiConnectionDiag: {JSON}`. Có `utcMs`, `attemptId`, `event`. Service/Bloc/UI ghi `stage`, `issue`, MAIN/audio identities, audioPaired/audioConnected/audioReady, scoRouteActive, firmware nếu đã đọc được. `ui.state` là lần build UI, có thể lặp; generation0 là trạng thái trước lượt kết nối đầu tiên.
- Native Android: Logcat `HomiBleDiag`, file app external-files `ble-diagnostic.jsonl`; xoay sang `ble-diagnostic.previous.jsonl` khi vượt khoảng2MB, như cơ chế cũ. Có buildType/versionName/versionCode.
- `attemptId` trên request/scan/bond/GATT là lượt khởi tạo. Async Zone giữ ID gốc, GATT lưu ID theo instance; callback GATT cũ ghi `currentGatt=false` và không làm ready lượt mới.
- `audio.profile.observed` là broadcast hệ thống HFP/A2DP/SCO, ghi device ID, state/previousState/action. `observerAttemptId` chỉ liên kết với lượt inventory gần nhất được quan sát; **không khẳng định lượt đó tạo ra sự kiện**, không khẳng định còn đang chạy. `attribution=observation_not_origin`. Chưa gọi inventory trong attempt thì không có observer ID.
- `hfp.inventory` đọc bondedDevices + headsetProfile. `isConnected` là HFP; `a2dpAdapterState` là trạng thái toàn adapter, không phải bằng chứng A2DP của riêng HOMI. Broadcast A2DP có device ID mới cho phép đối chiếu từng thiết bị. `scoRouteActive=false` lúc nghỉ không làm HOMI mất trạng thái ready.
- `gatt.cccd.result` phân biệt kết quả ghi descriptor với service discovery hoặc lời gọi đăng ký notification. `main.ready` chỉ sau callback CCCD success của GATT hiện tại.
- Native iOS chưa được thêm timeline/CCCD trong đợt này; Dart service/Bloc/UI vẫn có trace. Không mô tả đây là diagnostic end-to-end trên iOS.

Diagnostics mới không ghi PCM hoặc nội dung hội thoại. Log có định danh Bluetooth/tên thiết bị; che định danh khi chia sẻ bên ngoài. Timeline cũ chưa có attempt ID không thể tự gán retroactively.

## Đọc một lượt lỗi

1. Tìm `attempt.start`; đối chiếu ID của `scan.request`, `scan.complete`, `selection` (nếu có). Không có candidate thì chưa đến GATT; đừng quy lỗi UI chưa verify pair.
2. Có `gatt.open` → kiểm `gatt.state`, `gatt.services`, `gatt.cccd.result` status0, `main.ready`.
3. Đối chiếu inventory/broadcast audio theo device ID và thời gian; paired ≠ HFP connected ≠ SCO active. Cùng tên không chứng minh cùng physical unit.
4. Theo `service.state` → `bloc.state` → `ui.state`. `ready` cần MAIN + audioReady, không chỉ bond/profile.
5. Khi Hủy/Thử lại, xem ID và currentGatt để loại callback cũ. `attempt.complete ready=false` sau hủy là kết thúc lượt, không phải một lần phát sinh lỗi radio khác.

## Kiểm chứng local

Test mới bảo vệ: Zone qua await và lượt mới; logger lỗi không tác động kết nối; service/Bloc/native cùng ID; cancel/late callback; HFP có nhưng MAIN thiếu; audio đến làm MAIN rớt; giữ nhịp retry cả Android/iOS. Android Robolectric: CCCD failure không ready, CCCD cũ không làm ready lượt mới, CCCD thành công hiện tại trả snapshot, scan cũ không gắn failure vào ID mới. App test có sẵn mô phỏng audio trước MAIN → MAIN trước audio → cả hai ready, bổ sung kiểm tra lời hướng dẫn không khẳng định nguyên nhân.

Lệnh chính từ repo:

```sh
flutter test --no-pub test/device test/core_device_connection_diagnostics_channel_test.dart
flutter test --no-pub --dart-define-from-file=dart_defines.production.json test/app/bluetooth_power_setup_app_test.dart
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' android/gradlew -p android :app:testDebugUnitTest
flutter analyze --no-pub
```

Kết quả đầy đủ, baseline và log: `../docs/session-artifacts/2026-10-23-connection-local-hardening/summary.md`. Không xác nhận quảng bá RF, pairing/SCO/mic/loa thật hoặc coexistence BLE+HFP đã hoạt động.

## Gói bằng chứng chuẩn bị cho ODM (chưa gửi)

Nguồn gốc và dòng log: [review đã lưu](../../docs/session-artifacts/2026-10-23-first-connection-audit/review.md).

| Phiên 22/10 | Quan sát chắc chắn | Giới hạn |
|---|---|---|
|11:28–11:29|Không thấy BLE trước pair; Classic bond thành công; BLE rescan28ms sau vẫn thiếu MAIN|Không đủ HFP timeline cùng phiên; chưa mở GATT|
|11:34–11:35|Sau radio toggle thấy HM-D001/9E3B; GATT/services thành công; nhận Button Event và MAIN accepted|Log cũ thiếu callback CCCD riêng|
|14:48–14:49|Pair từ Settings; HFP Connected14:48:48.478, A2DP Connected14:48:49.530; hai scan sau vẫn thiếu MAIN|Không nhận adv trên Android không chứng minh thiết bị không phát RF|
|15:54–15:55|Scan không candidate; direct GATT LE20s/BR-EDR10s không kết nối|Không có cơ sở tiếp tục dùng Classic MAC để thử GATT mù|

Cần ODM xác nhận: firmware/build, BLE/Classic dùng identity nào; chính sách advertising/connectability khi HFP/A2DP connected; cách BLE reconnect khi đang SCO; CCCD có cần đăng ký lại sau reconnect; có bảo đảm thiết lập BLE đồng thời audio từ mọi thứ tự hay không. Không khẳng định tài liệu protocol dự kiến đã là hành vi firmware hiện tại.

Bước còn cần user/phần cứng: MAIN + CCCD trước, bật HFP/A2DP sau, bấm MAIN và xác nhận hai link đồng thời; nếu rớt, tách HFP-only/A2DP-only/cả hai trong cùng điều kiện nguồn/firmware. Không dùng việc tắt profile kèm power-cycle để kết luận riêng HFP là nguyên nhân. Chưa yêu cầu user thực hiện trong đợt xử lý local này.
