# DeviceConnectionService / DeviceBloc — onboarding pilot

Ngày: 22/10/2026. Phạm vi: onboarding Android/iOS. Home, Settings, MAIN dispatcher, audio playback và native BLE/HFP vẫn dùng triển khai cũ. Đây là chuyển phần điều phối có kiểm thử, không phải xác nhận đã sửa lỗi quảng bá BLE trên mẫu HM-D001 thực tế.

## Tài liệu đối chiếu

| Nguồn | Ngôn ngữ | Quyết định áp dụng |
|---|---|---|
| `docs/aiv0_v1_h20_integration.md` | Việt | HFP/SCO cho âm thanh; BLE 9E3B cho MAIN/pin/firmware. Giữ điều kiện GATT + CCCD Indicate trong native. Không mở SCO thường trực để coi thiết bị sẵn sàng. |
| `docs/aiv0_v1_h20_integration_zh-CN.md` | Trung | Cùng phân chia HFP/BLE và yêu cầu reconnect/đăng ký Indicate. Phần nói chưa giải mã MAIN đã cũ so với packet thực tế trong source; không quay lại vô hiệu hóa MAIN. |
| `output/docs/AIVO_V1_YEU_CAU_TICH_HOP_ODM_VI_RUT_GON.docx` và bản `ZH_CN` | Việt/Trung | HFP và BLE phải chạy đồng thời. UUID/quảng bá, sleep/wake, danh tính chip, firmware vẫn là yêu cầu ODM cần xác nhận; không suy diễn thao tác giữ nút/pair hoặc MAC chung. |
| `tools/build_aivo_odm_bilingual_doc.py`, `build_aivo_odm_vi_compact.py` | Việt/Trung/thuật ngữ Anh | Đối chiếu source soạn hợp đồng. Không bật APP State draft hay OTA từ tài liệu đề xuất. |
| `docs/hm-d001-connection-audit-2026-10-01.md` | Việt | Giữ generation guard, GATT ownership, CCCD readiness và phân biệt mất MAIN với mất HFP. |
| `docs/qa-task-homi-hfp-after-ble-2026-10-03.md` | Việt | Kiểm tra HFP xuất hiện muộn sau BLE. Mô tả cho hoàn tất setup chỉ với BLE là lịch sử; pilot giữ yêu cầu hiện tại MAIN + HFP đúng thiết bị. |
| `docs/superpowers/plans/2026-08-29-ios-ble-hfp-diagnostic-timeline.md` | Anh | Giữ timeline native để phân biệt MAIN_NOTIFY_ENABLED, HFP route và BLE reconnect; không thay pipeline sự kiện. |
| `output/docx/H20-Android后台运行可行性简报-中文.docx`, `H20-iOS原生后台运行可行性简报-中文.docx` | Trung | Giới hạn background/lifecycle vẫn thuộc bridge và session hiện tại. Không thêm dịch vụ nền hoặc cam kết chạy khi app bị hệ điều hành dừng. |
| `docs/innotrik-integration.md`, `docs/innotrik-hardware-test-zh-cn.md`, `deliverables/YEU_CAU_TICH_HOP_THIET_BI_INNOTRIK_V0.2_2026-08-07.docx` | Việt/Trung | Tài liệu legacy FF12/FF13/FF14 audio, Opus, HFP/A2DP. Không trộn UUID, retry 3 lần hay giả định cùng identity của mẫu cũ vào H20 V1 9E3B. |

Các bản Word được đọc trực tiếp OOXML; trích xuất phục vụ đối chiếu lưu ở `../docs/session-artifacts/2026-10-22-device-service/`. Không sửa nội dung tài liệu gốc.

## Cấu trúc và DI

- `lib/domain/device/device_connection.dart`: snapshot, trạng thái, lỗi có kiểu, lựa chọn micro, interface `DeviceConnectionPort`.
- `lib/core/device/device_connection_service.dart`: sở hữu một lượt kết nối, chờ lựa chọn, hủy/timeout, bỏ kết quả cũ, kết hợp MAIN + audio. Không import Flutter hoặc feature.
- `lib/presentation/device/bloc/`: tách `device_bloc.dart`, `device_event.dart`, `device_state.dart` bằng `part`/`part of`; Bloc nhận service qua constructor. `DeviceState` ở presentation ánh xạ từ `DeviceConnectionState` của domain, core không import presentation. Connect không chặn event Cancel/Selection.
- `lib/presentation/device/device_microphone_sheet.dart`: picker chỉ hiển thị và trả lựa chọn; cuộn ở màn hình nhỏ/chữ lớn, khóa lựa chọn khi MAIN mất.
- `lib/app/device/legacy_device_connection_port.dart`: adapter chuyển tiếp sang BLE bridge và ConversationController hiện có để giữ association, device history, chọn đúng mic và native cancellation. Adapter nằm ở composition layer, không kéo feature vào core/domain.
- `lib/app/di/device_dependencies.dart`: tạo/inject service → Bloc, quản lý dispose; không global singleton. `BlocProvider.value` chỉ bọc nhánh onboarding và không tự dispose instance do composition sở hữu.

Quyền/microphone/Bluetooth enable và hướng dẫn hệ điều hành vẫn dùng helper hiện có qua access boundary, nhằm giữ consent và popup cấp quyền. Service gọi access boundary trước transport, nhưng không giữ BuildContext hay tự mở popup. Việc lưu hoàn tất onboarding/companion association vẫn do presentation/app xử lý sau kết quả verified ready.

## Luồng

1. Kiểm consent, quyền micro/Bluetooth và radio. Không có quyền/radio thì không quét.
2. Thao tác chủ động khôi phục chính sách auto-connect như cũ.
3. Xác minh MAIN: tái sử dụng BLE saved identity/scan. Lần đầu Android có thể fallback Classic → system bond → cập nhật bond/xác minh HFP thực có giới hạn → BLE rescan → đọc lại HFP trước chọn candidate, tuyệt đối không lấy Classic MAC làm MAIN chưa xác minh.
4. Đọc riêng trạng thái audio đã pair. Nếu MAIN chưa có: partial, không mở picker/không chọn micro.
5. MAIN có rồi: ghép đôi bổ sung khi cần, tìm HFP đã khả dụng và liên kết đúng thiết bị. Giữ các nhịp dò HFP hiện tại: Android 0/350/650/900/1200/1600ms; iOS 0/600/600ms.
6. Nếu cần người dùng chọn/xác nhận association: phát `choosingMicrophone`, Bloc/UI trả lựa chọn kèm attempt token. Không nhận lựa chọn từ lượt cũ hoặc sau MAIN mất/đổi thiết bị.
7. Nếu chọn HFP làm MAIN rớt, thử khôi phục qua adapter hiện có. Chỉ trả ready khi cả MAIN và audio đã xác minh; SCO chỉ mở khi phiên audio cần.
8. Cancel dừng lượt hiện tại, không opt-out retry và không tự chọn mic điện thoại. Timeout Android75s/iOS45s. Luồng cũ và mới không cùng điều phối onboarding.

Không thêm vòng retry nền ở onboarding: trước đó onboarding cũng không chạy timer nền15s/60s. Các timer ngoài onboarding và retry native được giữ nguyên. Mở rộng service sang toàn app là đợt sau; lúc đó cần chuyển quyền sở hữu timer, không chạy song song hai scheduler.

## Giữ code cũ và rollback

`_runParentH20Setup` cùng coordinator/bridge cũ được giữ. Build mặc định chọn pilot cho onboarding. Muốn đối chiếu luồng cũ:

```sh
flutter run --dart-define-from-file=dart_defines.production.json --dart-define=DEVICE_CONNECTION_SERVICE_ONBOARDING=false
```

Trong test có thể truyền `AiSpeakingApp(useDeviceConnectionService: false)`. Home/Settings không nhận DeviceBloc và vẫn dùng coordinator cũ kể cả khi pilot bật.

## Kiểm chứng

Các test mới kiểm tra first install, pair-only, MAIN trước mic, mất MAIN khi picker mở, xác nhận association, double tap, cancel rồi retry, callback muộn, timeout và Bloc Cancel khi Connect đang chờ. App tests chạy cả Android/iOS và cả pilot/legacy cho kết nối thành công. Bộ regression giữ kiểm tra Settings/Home, quyền, layout, persistence và transport. Kết quả cuối được lưu trong verification.json ở evidence và SESSION.md; test giả lập không thay thế xác minh radio/mic/loa thật.


## Xác minh trạng thái sau pair — đang áp dụng (22/10/2026)

Chỉ adapter pilot onboarding Android truyền `verifyPairing` vào auto-connect. Transport giữ mặc định không có hook cho Home/Settings/legacy; iOS không chạy bước này. Hook cũng áp dụng khi pairing trên BLE candidate/địa chỉ MAIN đã lưu, và khi pair bổ sung cho MAIN đang kết nối.

- Native vẫn chờ `BOND_BONDED`; adapter nhận bool thực và cập nhật `audioPaired` ngay khi bond thành công. Không đánh dấu `audioReady` hoặc `mainReady` từ bond.
- Đọc lại trạng thái adapter và danh sách HFP, chỉ đối chiếu đúng địa chỉ vừa pair, không lấy thiết bị cùng tên khác làm bằng chứng. Nếu bond thành công nhưng profile chưa connected, đọc lại mỗi250ms, tối đa5 giây trong deadline75 giây của lượt hiện tại. Kết nối đã có thì đi tiếp ngay. Đây là khoảng chờ điều phối có giới hạn, không phải cam kết về thời gian firmware.
- Hết thời hạn/đọc HFP lỗi vẫn thử BLE độc lập. Pair bị từ chối không chạy vòng chờ profile; vẫn cho phép MAIN được xác minh nếu có quảng bá BLE hợp lệ. Các lần đọc một lượt không chờ profile có deadline1 giây.
- Sau BLE rescan8 giây có sẵn, đọc lại HFP một lần để nhận thay đổi trong lúc quét. `connectedHfpDeviceIds` trong pilot chỉ nhận địa chỉ có `isConnected=true` từ lần đọc mới; không tự điền địa chỉ vừa yêu cầu pair. Danh tính MAIN vẫn cần BLE advert và native GATT/CCCD.
- Không chọn/route mic trước MAIN. Giữ nguyên UI đang kết nối, nút Hủy, lịch retry15/60 giây, throttle10 giây và native reconnect. Không thêm scan, filter, reset radio hoặc yêu cầu bật/tắt Bluetooth.
- Cancel/dispose dừng timer và vô hiệu hóa kết quả đọc muộn. Radio off/resetting/permission unavailable kết thúc observation; native hiện có chặn scan/connect khi radio tắt. Kiểm generation cả quanh lần pair bổ sung và refresh snapshot để callback cũ không ghi vào lượt mới.

Kiểm chứng: 204 test Dart tập trung qua, trong đó9 case app mới về profile xuất hiện trễ/trong scan, không nhầm bond thành connected, identity khác, từ chối pair, cancel/retry, radio off/retry và inventory lỗi/treo/trả muộn. Cập nhật thời gian pump trong test cho giai đoạn xác minh mới; không nới điều kiện readiness. Analyzer/build và checksum lưu tại `../docs/session-artifacts/2026-10-22-postpair-verification/`. Không truy cập điện thoại; chưa xác nhận khắc phục lỗi first-pair trên phần cứng. Nhánh recovery/filter ở phần lịch sử bên dưới vẫn đã thu hồi.

## Nhánh recovery sau pair đã thu hồi (22/10/2026)

**Trạng thái hiện tại: đã gỡ khỏi runtime.** User báo bản này làm mất cả khả năng kết nối sau tắt/bật Bluetooth thủ công. Chưa có bằng chứng xác định nguyên nhân chính xác; đã rollback riêng nhánh recovery, native timer/filter và adapter flag để trở lại hành vi trước đợt bổ sung. Service/Bloc/DI và các sửa trước đó vẫn giữ. Nội dung bên dưới chỉ là lịch sử triển khai/test, không mô tả code đang chạy.

Test trên thiết bị đã pair trước đó không đại diện cho first-pair. Không dùng kết quả đó để khẳng định lỗi thực tế đã được sửa. Từ yêu cầu mới của user, không tự cài/chạy hoặc kiểm thử trên điện thoại; chỉ kiểm tra source, test tự động và build local.


Bằng chứng thật: ở cùng PID11160, trước tắt/bật Bluetooth Android chỉ tìm thấy HM-D001 qua Classic. Sau tắt/bật, scan BLE trả đúng HM-D001/9E3B0001, GATT/CCCD được xác nhận và MAIN accepted. Điều này khoanh vùng discovery nhưng chưa phân biệt Android stack với trạng thái quảng bá thiết bị.

Nhánh bổ sung chỉ được bật bởi adapter của onboarding qua `recoverPairedDiscovery` và thao tác chủ động. Điều kiện: scan bình thường không có candidate, chưa có BLE identity đã lưu, và có một audio identity đã pair trong lượt hiện tại hoặc một audio HOMI đang kết nối. Native kiểm tra lại bond và tên nhận diện trước recovery.

1. Dừng scan cũ của app, hủy Classic discovery, xóa tập kết quả scan tạm. Không xóa bond, không ngắt audio hoặc bật/tắt radio.
2. Chờ Classic discovery ngừng ổn định 1 giây; tối đa 3 giây. Timer hủy được qua Cancel, adapter off và dispose. Không can thiệp nếu GATT đang tồn tại.
3. Tạo một lượt BLE LOW_LATENCY mới 8 giây với các bộ lọc OR: địa chỉ audio đã pair, service9E3B0001, hoặc tênHM-D001. UUID/name filter cho phép radioBLE có địa chỉ khác audio. Vẫn dùng selector chống candidate không rõ ràng.
4. Chỉ connect nếu có kết quả BLE thực; không mở GATT mù trên ClassicMAC. Native vẫn xác minh services/characteristics/CCCD trước ready và lưu định danh.
5. Chỉ thêm một recovery trong mỗi lượt bấm kết nối. Giữ deadline75s Android, retry nền15s/60s, throttle10s và lịch native reconnect. Home/Settings, iOS và pilot flagfalse không bật nhánh này.

Đây là recovery discovery trong app, không tương đương reset Bluetooth stack toàn hệ thống. Không dùng APIẩn `refresh/removeBond/disconnect` của profile hay tự cycle adapter. Tài liệuAPI tham khảo: [BluetoothAdapter](https://developer.android.com/reference/android/bluetooth/BluetoothAdapter), [ScanFilter.Builder](https://developer.android.com/reference/android/bluetooth/le/ScanFilter.Builder). Việc chờ sau inquiry là quyết định triển khai có giới hạn, không phải cam kết từ Android rằng sẽ sửa mọi lỗi radio.

Kiểm chứng bổ sung: 207 test Dart, 26 test native đều qua; analyzer sạch. APK debug đã cài giữ dữ liệu. Vivo thực chạy preparation→filtered scan→GATT verified thành công sau tạm ngắt riêng MAIN; cuối MAIN/audio/paired đều true, không cycle radio hoặc xóa pair. Chưa tái hiện từ trạng thái chưa từng pair trên phần cứng trong lượt này. Evidence: `../docs/session-artifacts/2026-10-22-postpair-recovery/`.


## Ghép đôi trong Cài đặt hệ thống — đang áp dụng (22/10/2026)

Onboarding Android không còn tự `createBond()`/Classic discovery. Bằng chứng thật: sau bond trong app, MAIN BLE không xuất hiện kể cả khi HFP/A2DP đã kết nối hoặc tắt/bật nguồn HOMI; chỉ tắt/bật Bluetooth điện thoại làm MAIN hiện. Nhánh tự mở HFP/A2DP qua API ẩn đã thử và gỡ bỏ vì không giải quyết.

- Bấm "Kết nối HOMI" khi chưa ghép đôi (Android: `audioPaired`; iOS: chưa có MAIN/HFP) → `showHomiPairingGuide` (`lib/features/onboarding/presentation/homi_pairing_guide.dart`), nội dung theo hệ điều hành. Đã ghép đôi thì kết nối ngay.
- "Mở Cài đặt Bluetooth" (Android `ACTION_BLUETOOTH_SETTINGS`; iOS chỉ mở được trang Cài đặt của app, guide nhắc quay về trang chính → Bluetooth). Màn setup tự kết nối lại khi app resumed, không cần bấm thêm. "Tôi đã ghép đôi, kết nối ngay" kết nối trực tiếp.
- `LegacyDeviceConnectionPort.connectMain` bỏ `requestBond`/`verifyPairing`; quét BLE với HFP đang connected như trước. `pairConnectedMain` (MAIN có, audio chưa pair) và Settings sheet ngoài onboarding giữ nguyên.
- Chưa kiểm chứng trên vivo: pair lần đầu trong Cài đặt rồi mở app có lên MAIN hay không.
