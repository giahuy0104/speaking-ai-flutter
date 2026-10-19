# Bổ sung điều hướng MAIN đến các phần Bộ từ vựng

Từ Dịch tiếng Anh và Chủ đề, kích hoạt MAIN rồi nói “Ba mẹ đã thêm”, “Ngôi sao” hoặc “Luyện lại” để vào trực tiếp phần tương ứng. Ba phần này vẫn nằm trong Bộ từ vựng. Không thêm màn hình, tab hay menu giao diện.

## Phần tái sử dụng và phần bổ sung

Tái sử dụng `VoiceVocabularyTarget`, `_moduleNavigationTurn`, shell, controller Bộ từ vựng và toàn bộ luồng phát/học tại đích. Nhánh điều hướng khi đang học một hoạt động Chủ đề vẫn dùng logic có sẵn. “Luyện lại” tiếp tục đi qua luồng voice, bao gồm `allowPendingToday=true`; không đổi quy tắc của nút giao diện.

Bổ sung nhận ba đích ở MAIN ban đầu, khi đang dịch, sau khi dừng dịch, menu chuyển phần và các bước chọn/học lại chủ đề hoặc bài. Bộ chấp nhận lệnh, handler, partial, resolver và controlled lexicon cùng sử dụng các alias khớp toàn câu đã có. Các câu nhiều đích, câu tự do chứa tên đích, partial chưa đủ và prompt của app được kiểm tra bằng test. Không đưa resolver điều hướng vào pipeline dịch liên tục.

Kiểm tra controller đích đã attach trước khi rời nguồn. MAIN xác nhận thất bại trên cả Android/iOS nếu đích không sẵn sàng. Yêu cầu mở phần không đợi người dùng học hết phiên; native MAIN được kết thúc trước khi đích phát audio. Thông báo lỗi muộn được giới hạn theo thế hệ điều hướng.

Android dùng `LANGUAGE_MODEL_FREE_FORM`; bridge iOS dùng dictation. Không có phrase manifest điều hướng truyền từ Dart cần sửa ở hai bridge này. Không sửa native, plugin, permission, schema, store, backend, phiên dịch hay nội dung bài. Không thêm câu hướng dẫn audio mới. Các thay đổi bỏ Level và ba MP3 đã thêm trước tác vụ được giữ nguyên.

## File mã nguồn thay đổi

- [main_voice_assistant_flow.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/main_voice_assistant_flow.dart): mở rộng các trạng thái MAIN bằng nhánh dùng chung; giữ logic cũ của hoạt động học.
- [voice_navigation_intent_resolver.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/voice_navigation_intent_resolver.dart): phân giải đích con bằng lệnh đầy đủ.
- [voice_navigation_controller.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/application/voice_navigation_controller.dart): xác nhận đích con đã sẵn sàng trên cả hai nền tảng.
- [master_navigation_contract.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/domain/master_navigation_contract.dart): bổ sung metadata trạng thái cho ba intent đã có.
- [controlled_speech_lexicon.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/voice_navigation/domain/controlled_speech_lexicon.dart): bổ sung 30 alias vào các menu; không mở rộng trạng thái dịch liên tục.
- [home_learning_shell.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/home/presentation/home_learning_shell.dart): kiểm tra đích, giữ thứ tự bàn giao và xử lý lỗi muộn.
- [vocabulary_home_screen.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/lib/features/vocabulary/presentation/vocabulary_home_screen.dart): controller báo lỗi khi chưa attach; không đổi logic học.

Test mới/được bổ sung tại [vocabulary_cross_navigation_test.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/test/features/voice_navigation/vocabulary_cross_navigation_test.dart), [voice_navigation_controller_test.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/test/features/voice_navigation/voice_navigation_controller_test.dart), [controlled_speech_lexicon_test.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/test/features/voice_navigation/controlled_speech_lexicon_test.dart), [main_speaking_command_resolver_test.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/test/features/voice_navigation/main_speaking_command_resolver_test.dart), [home_learning_shell_test.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/test/features/home/home_learning_shell_test.dart) và [vocabulary_home_screen_test.dart](D:/Code/HuaMei/App_noi/flutter/23_23th9/speaking-ai-flutter/test/features/vocabulary/vocabulary_home_screen_test.dart) trong các thư mục feature tương ứng.

## Kiểm thử

Chạy PowerShell tại thư mục repository:

```powershell
$taskTests = @(rg --files test/features/voice_navigation test/features/home test/features/listening test/features/vocabulary test/features/conversation | Where-Object { $_ -like '*_test.dart' -and $_ -notlike '*golden*' })
$taskTests += @('test/architecture_boundaries_test.dart','test/assistant_audio_inventory_test.dart','test/fixed_audio_prompt_coverage_test.dart','test/core_audio_main_assistant_audio_prompt_service_test.dart','test/core_audio_audio_registry_test.dart','test/core_session_app_flow_coordinator_test.dart','test/lesson_intro_state_audio_coverage_test.dart')
flutter test --no-pub --concurrency=2 @taskTests --reporter expanded
flutter analyze --no-pub
git diff --check
flutter devices --machine
```

- 1.140 test đạt; bao gồm 24 widget case Android/iOS từ dịch đang chạy, dịch đã dừng, dịch chưa chạy và chọn Chủ đề đến ba đích. Kiểm tra đích đúng, Today không tự chạy chồng, dữ liệu còn nguyên và audio đích sau khi MAIN kết thúc.
- Các test dữ liệu rỗng, Today đang dở, checkpoint, Back, lỗi/timeout bàn giao, microphone và lệnh cũ của các feature đều nằm trong bộ hồi quy trên.
- `flutter analyze`: không có vấn đề. `git diff --check`: đạt.
- Lần chạy với mức song song mặc định có một test thời gian của dịch thất bại. Cả 17 test trong file đó đạt khi chạy riêng; bộ đầy đủ đạt khi chạy với `--concurrency=2`.
- Đối chiếu byte với trạng thái đầu tác vụ: chín file bảo vệ về lưu dữ liệu, tiến độ, session, pipeline dịch, microphone, curriculum và `pubspec.yaml` không đổi.

`flutter devices` chỉ tìm thấy Windows, Chrome và Edge. Widget test chạy với biến thể Android/iOS không chứng minh Bluetooth/HFP, ASR hay nút thiết bị thật. Chưa kiểm thử Android/iOS trên thiết bị hoặc simulator. Không build, tăng app version hay phát hành. Bộ hồi quy này không chạy golden test.
