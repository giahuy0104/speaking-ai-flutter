# HOMI — đối chiếu điều hướng trợ lý với Master FINAL

Ngày rà soát: 16/09/2026.

Cập nhật tiếp theo cùng ngày theo ảnh 2 được người dùng duyệt: STOP dịch chỉ nói “Đã dừng.” và kết thúc phiên; chỉ khi nhấn MAIN mới hỏi “Bạn muốn tiếp tục dịch, học Chủ đề hay Bộ từ vựng?”. Khi chọn tiếp tục, nói “Mình tiếp tục nhé.”. Bản DOCX đồng bộ nằm tại `output/documents/HOMI_Master_FINAL_cap_nhat_luong_dich_MAIN_2026-09-16.docx`; file gốc được giữ nguyên.

Nguồn: `HOMI_Master_Hoi_thoai_Intent_Dieu_huong_FINAL_gui_IT_2026-09-16.docx` do người dùng cung cấp. Đã đọc nội dung và bảng bằng quy trình đọc tài liệu của skill `documents`; không sửa tài liệu nguồn. Các quy định trong tài liệu được xem là yêu cầu sản phẩm để đối chiếu, không phải chỉ dẫn thực thi vượt phạm vi yêu cầu của người dùng.

## 1. Kết luận và phạm vi

Đã tích hợp phần điều hướng vào mã hiện tại theo nguyên tắc **xác định trạng thái trước, nhận diện câu lệnh sau**. Trợ lý chỉ chọn hành động hợp lệ tại câu hỏi hiện tại rồi bàn giao cho màn học/dịch đang sở hữu phiên.

Không viết lại bộ dịch, phát âm, chấm điểm, quy tắc đạt/chưa đạt, dữ liệu bài học, luật mở khóa, lưu sao hoặc tiến độ. Các thay đổi UI, Android bỏ xác thực và giới hạn hàng chờ từ vựng đã có trong workspace được giữ lại. Đây không phải tuyên bố hoàn tất toàn bộ đặc tả runtime trong Word: các điểm còn cần bổ sung hoặc nghiệm thu riêng nằm ở mục 6.

## 2. Hiện trạng trước khi sửa và cách phân chia

| Thành phần | Hiện trạng/rủi ro phát hiện | Trách nhiệm sau sửa |
|---|---|---|
| MAIN và wake word | Có đường dùng bộ nhận diện điều hướng tổng quát; dễ nhận lệnh không thuộc câu hỏi đang hỏi | Đều vào hội thoại MAIN theo trạng thái; wake chỉ chạy khi cấu hình cho phép |
| `MainVoiceAssistantFlow` | Còn nhánh hỏi tuổi, chọn bài tự do, xác nhận học lại có/không; một số matcher tìm cụm từ trong cả câu | Câu hỏi đóng, lựa chọn theo Level, số bài/chủ đề hợp lệ, nhắc lại đúng câu hỏi |
| `VoiceNavigationController` | Lần im lặng đầu có thể nhắc menu gốc ở sai nhánh; kết thúc MAIN có nguy cơ khiến màn học tự tiếp tục | Nhắc câu hỏi hiện tại; lần hai phát lệnh dừng cho màn học trước khi kết thúc MAIN |
| Các màn học/từ vựng | Biết câu hiện tại, loại phiên, cuối nhóm/cuối danh sách nhưng trợ lý chưa có đủ ngữ cảnh | Công bố ngữ cảnh chỉ đọc qua `ActiveLearningVoiceContext`; vẫn sở hữu mọi thao tác học |
| Lựa chọn cuối bài V4 | Đã có bộ xử lý và tiến độ; một số alias khớp chuỗi con hoặc nhận số không đúng lựa chọn | Dùng lại bộ xử lý; siết parser, chống câu phủ định/echo và số ngoài lựa chọn |
| Dịch liên tục | Có bộ chặn câu điều khiển riêng nhưng còn xác nhận trung gian và nhiều câu dừng tương đương | Chỉ chặn câu điều khiển được duyệt; bàn giao ngay sang mic điều hướng khi chuyển phần |

Ranh giới triển khai:

```text
Mic điều hướng → Controller → hội thoại/trạng thái → intent hoặc command
                                                    ↓
                                      màn học / màn từ vựng hiện hữu
                                                    ↓
                                    audio, chấm điểm, tiến độ hiện hữu

Mic dịch → bộ chặn câu điều khiển → bàn giao MAIN nếu là lệnh
                               → pipeline dịch hiện hữu nếu không phải lệnh
```

`ActiveLearningVoiceSelectionContext` bổ sung cách nhận diện các lựa chọn có số bài/Level tại màn hoàn thành. Trợ lý không tự suy luận bài kế tiếp hay tự cập nhật trạng thái hoàn thành.

## 3. Bảng THÊM / SỬA / GIỮ / LOẠI

| Phân loại | Hạng mục | Đã áp dụng |
|---|---|---|
| THÊM | Contract Master FINAL | Tập câu mẫu, prompt và metadata trạng thái tập trung trong `master_navigation_contract.dart` |
| THÊM | Ngữ cảnh phiên | Phân biệt Core, Challenge, Review, Today, Parent, Star và các câu hỏi cuối nhóm/danh sách |
| THÊM | Guard trạng thái | Khi có ngữ cảnh cụ thể, lệnh không hợp lệ không rơi ngược về grammar tổng quát |
| THÊM | Guard số | Chỉ đọc số trong dạng câu chọn đúng loại; kiểm tra danh sách Chủ đề/Level được màn sở hữu cung cấp |
| THÊM | Hồi quy | Kiểm tra câu mẫu, câu phủ định, số sai phạm vi, im lặng, MAIN-only và bàn giao mic |
| SỬA | Câu mở MAIN | “HOMI đây. Bạn muốn dịch tiếng Anh, học Chủ đề hay Bộ từ vựng?” |
| SỬA | Im lặng | Lần đầu nhắc đúng câu hỏi; lần hai tạm dừng. MAIN gốc có câu hướng dẫn nhấn gọi lại riêng |
| SỬA | Chọn Chủ đề | Dùng tuổi đã cấu hình và Level từ tiến độ; màn Chủ đề chọn bài bắt đầu phù hợp |
| SỬA | Chủ đề đã xong | Hỏi “Chủ đề khác” hoặc “học lại Chủ đề N”; không hiểu có/không thành quyết định |
| SỬA | Cuối bài | Prompt có số bài thật; câu mơ hồ “Học tiếp” phải hỏi lại theo T09 |
| SỬA | “Học lại” / “Nghe lại” | Today cuối phiên phát lại Today; Parent/Star cuối danh sách phát lại danh sách; không trộn với phát lại câu |
| SỬA | Từ vựng lựa chọn đóng | Menu rỗng/kết thúc chỉ nhận các nhánh thực sự được đưa ra; Review kết thúc chỉ Parent/Star |
| SỬA | Dịch liên tục | Hướng dẫn mới; chỉ “Dừng lại” khớp toàn câu có dấu mới là lệnh dừng dịch |
| SỬA | Chuyển khỏi dịch | Chuyển ngay sang hội thoại điều hướng, không chờ xác nhận có/không trong mic dịch |
| SỬA | Dừng dịch | Chỉ “Đã dừng.”, kết thúc phiên và tắt mic; chặn tự nghe lại/wake đến khi nhấn MAIN |
| SỬA | Tiếp tục dịch | Sau dừng phải nhấn MAIN mới mở menu; ở menu chuyển phần có thể chọn tiếp tục ngay. Cả hai nói “Mình tiếp tục nhé.” và bàn giao lại pipeline hiện hữu |
| GIỮ | Bộ dịch và media | Không đổi backend, request dịch, thuật toán phát/thu hoặc adapter native |
| GIỮ | Luật học | Không sửa evaluator, retry của bài học, điểm, sao, quy tắc lưu tiến độ hoặc mở khóa |
| GIỮ | Dữ liệu và giao diện đã sửa | Không thay asset, thiết kế màn học, kho từ vựng hay bản vá quota vì tài liệu điều hướng |
| GIỮ | Tương thích có kiểm soát | Một số câu đã phát hành vẫn được nhận dưới dạng alias đầy đủ, không dùng tìm chuỗi con ở các nhánh đã siết |
| LOẠI khỏi luồng MAIN mới | Hỏi tuổi bằng giọng nói | Không còn đi vào nhánh này; cấu hình tuổi/onboarding thuộc màn sở hữu |
| LOẠI khỏi luồng MAIN mới | Chọn bài tự do | Chọn Chủ đề bàn giao về màn Chủ đề, không mở thêm menu “bài số mấy” |
| LOẠI khỏi điều hướng trợ lý | “Bài trước” | Không còn ánh xạ thành lệnh lùi bài trong resolver MAIN; không xóa thao tác nội bộ của engine |
| LOẠI | Xác nhận học lại Chủ đề kiểu có/không | Thay bằng tên lựa chọn rõ ràng |
| LOẠI | Dừng dịch bằng mọi biến thể STOP | Không dùng STOP_GLOBAL/INT-018 để chặn câu dịch; tránh nuốt nhầm nội dung cần dịch |

“Loại” ở đây là loại khỏi đường chạy điều hướng mới. Không xóa ồ ạt enum/helper hoặc API tương thích còn được bộ kiểm thử hay thành phần khác tham chiếu.

## 4. Các điểm chưa thống nhất trong tài liệu và quyết định

1. **S04 và T09:** bản gốc mâu thuẫn về “Học tiếp” tại cuối bài. Bản DOCX cập nhật đã bỏ mẫu này khỏi NEXT_LESSON và ghi rõ hỏi lại theo T09. “Bài tiếp theo”, “Bài 2” hoặc lựa chọn rõ ràng vẫn được xử lý.
2. **Menu chuyển khỏi dịch:** ảnh 2 đã chốt ba lựa chọn. Bản cập nhật dùng đúng prompt của ảnh, đồng thời tách TRANSLATE_STOP khỏi TRANSLATE_MAIN_AFTER_STOP; không còn tự mở menu sau câu dừng.
3. **Dừng dịch:** giữ dấu tiếng Việt, chỉ chuẩn hóa chữ hoa/thường, khoảng trắng và dấu câu. “DỪNG LẠI!” được chấp nhận; “dung lai”, “đừng lại”, câu dài chứa “dừng lại” không bị tự ý coi là lệnh dừng.
4. **STOP và dữ liệu:** ngoài dịch, STOP được ưu tiên ở các node điều hướng. Với màn đang học, gửi command dừng về owner, không tự ghi hoàn thành, không tự next/skip. Hành vi đóng màn hoàn thành vẫn thuộc owner hiện có.

## 5. Các vùng mã thay đổi

- `lib/features/voice_navigation/domain/master_navigation_contract.dart`: nguồn câu mẫu/prompt mới.
- `lib/features/voice_navigation/application/`: quản lý hội thoại, các resolver MAIN/dịch, wake và timeout.
- `lib/core/device/active_learning_module.dart`: chỉ thêm interface ngữ cảnh, không thay store tiến độ.
- `lib/app/ai_speaking_app.dart`: truyền ngữ cảnh module và cấu hình wake; cập nhật lời nhắc im lặng của dịch.
- Các màn `lesson_practice`, `lesson_review`, `lesson_challenge`, `vocabulary_home`, `vocabulary_practice`: công bố ngữ cảnh/câu hỏi đang hiển thị để MAIN dùng đúng bộ lệnh.
- `lib/features/listening/domain/v4_completion_flow.dart`: chỉ sửa nhận diện lựa chọn điều hướng, không sửa thực thi học/chấm điểm.

Lưu ý kiểm diff: workspace đã có nhiều chỉnh sửa UI và từ vựng trước đợt này. Tổng diff so với HEAD của hai màn từ vựng lớn hơn phần thay đổi điều hướng; không được coi toàn bộ là thay đổi do Master FINAL.

## 6. Giới hạn và phần cần xử lý riêng

- **Today NEXT sau EN+VN:** chưa mở lệnh NEXT qua MAIN. Owner hiện tự chuyển sau phát audio và chưa công bố một mốc an toàn riêng để phân biệt trước/sau EN+VN. Giữ chặn NEXT/SKIP để không bỏ qua nội dung bắt buộc. Muốn khớp đầy đủ mục này cần thêm capability từ owner và test audio trên thiết bị; không nên bật NEXT vô điều kiện.
- **Checkpoint câu hỏi:** các lựa chọn MAIN như Chủ đề/Level có thể tạm dừng và gọi lại trong phiên controller còn sống. Chưa thêm lưu bền toàn bộ `WAITING_FOR_CHOICE` qua kill app/restart. Checkpoint học đang có vẫn thuộc store cũ; không thay thế bằng checkpoint trợ lý.
- **Review nghe lại ở lần thử 1/2:** giữ nguyên engine hiện có. Resolver chỉ cho phép nghe lại đúng ngữ cảnh; chưa thay thuật toán attempt hay xác nhận bằng thiết bị thật toàn bộ biến thể trong tài liệu.
- **Log đầy đủ và confidence:** chưa triển khai bảng audit có transcript/confidence như tài liệu gợi ý. Đường MAIN hiện dùng transcript chuỗi; không tự tạo confidence giả hoặc lưu thêm lời nói của trẻ. Cần thiết kế schema, nguồn confidence và chính sách lưu riêng nếu muốn nghiệm thu phần này.
- **Dataset:** contract chứa các câu mẫu tĩnh và metadata; chưa phải công cụ import/export NLU hoàn chỉnh. Các slot số được resolver kiểm tra trong ngữ cảnh, không sinh toàn bộ tổ hợp thành dataset.
- **Phạm vi nền tảng:** không chỉnh lại chính sách xác thực iOS/native. Logic hội thoại Dart là phần dùng chung nên cần smoke test iOS trước khi phát hành iOS; không coi Android test là chứng minh iOS đã đạt.
- **Phát hành:** chưa build lại APK production sau đợt điều hướng này; APK cũ không chứa các thay đổi mới. Không deploy backend, không commit hay phát hành store.

## 7. Kiểm chứng

Kết quả cuối đợt:

- **551/551 test đạt** trong nhóm điều hướng, từ vựng, listening, conversation, điều phối phiên app và Home shell.
- `flutter analyze --no-pub` trên toàn bộ vùng nguồn/test liên quan: **No issues found**.
- `git diff --check`: không có lỗi whitespace; Git có cảnh báo chuẩn hóa LF/CRLF của workspace Windows.
- Một test wake trước đây dùng chờ cứng 5/20/140 ms gây lỗi khi chạy nhiều nhóm cùng lúc. Đã chuyển sang chờ điều kiện thực tế của controller; giữ nguyên các assert mic chỉ mở sau khi lời nhắc xong.

Lệnh hồi quy:

```powershell
flutter test test/features/voice_navigation test/features/vocabulary test/features/listening test/features/conversation test/core_session_app_flow_coordinator_test.dart test/features/home/home_learning_shell_test.dart --reporter expanded
```

Log kết quả sau cập nhật ảnh 2: `output/apk/translation-main-revision-full-regression.log` (551 test đạt). Sau khi đồng bộ metadata state và thêm alias “Dịch” cho CONTINUE_TRANSLATE, chạy lại 9 test contract: đều đạt; analyzer không có lỗi.

DOCX cập nhật đã được kiểm tra toàn bộ 176 block nội dung và 13 trang render bằng Word. 35/35 ô trong bảng luồng dịch khớp ảnh 2; các bảng state/TTS/intent/checklist được đối chiếu chéo, nội dung ngoài danh sách chỉnh sửa giữ nguyên. Đã sửa hàng bảng bị tách trang và tiêu đề bảng bị đứng riêng. Script tái kiểm tra: `output/documents/translation-main-revision/validate_doc.py`.

Chưa nghiệm thu trên thiết bị thật. Bản DOCX cập nhật có 23 tình huống (giữ 15 ca cũ, thêm T16–T23 cho dịch/MAIN). Trước phát hành cần kiểm tra: MAIN giữa audio; STOP không tăng tiến độ; sau STOP dịch không tự mở mic/menu; nhấn MAIN mới mở ba lựa chọn; lệnh ngoài ngữ cảnh; bàn giao mic; im lặng hai lần; replay đúng phạm vi; số bị khóa; H20/BLE và foreground/background. Các mục chưa triển khai ở mục 6 không được đánh dấu đạt chỉ dựa trên test tự động.
