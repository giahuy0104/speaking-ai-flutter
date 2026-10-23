# Kết quả thử Android audio-fix-v2

Log `device.log`, SHA-256
`5E927C8C0AB963D480CC8C0CF57ABE5662EDB55AE3B3B94FAAE96857A1D44BC1`.
Lượt thao tác được ghi khoảng 23:03:02–23:07:47 ngày 18/09/2026, UTC+7.
908 sự kiện chẩn đoán; cùng tiến trình ứng dụng 24467. Đã dừng đúng tiến trình
capture 6692 và tắt native diagnostic tag. Không xóa log hay cài bản khác.

## Kết luận

Bản v2 giảm được một số thời gian chờ nhưng chưa đạt yêu cầu đồng nhất âm lượng
và ổn định hoàn toàn. Có bằng chứng cụ thể cho nhánh gain dự phòng không phù hợp,
một lỗi hủy lượt chưa được bắt, và hai lần mất đường SCO. Không ghi nhận hai lần
phát ting trùng nhau từ ứng dụng; chưa đủ dữ liệu để phủ nhận tiếng báo bên ngoài app.

## 1. Chậm lựa chọn: phân biệt màn hình và lời nói tiếp theo

Các mốc bên dưới bắt đầu khi controller nhận transcript, không phải lúc người
dùng thực sự ngừng nói. Frame marker cũng không đo toàn bộ animation hay data-ready.

| Lượt đo | Nhận lệnh → frame marker | Nhận lệnh → native prompt-start marker |
| --- | ---: | ---: |
| Vào chủ đề, 23:05:11 | 57 ms | 652 ms |
| Chọn chủ đề, 23:05:23 | 48 ms | 1.353 ms |
| Vào bộ từ vựng, 23:05:47 | 34 ms | 1.092 ms |

Đơn vị trong bảng là mili giây; 1.353 ms nghĩa là 1,353 giây.
Chứng cứ: dòng 406–431, 458–477 và 566–589.

Bốn lượt xử lý nội bộ bộ từ vựng, generation 16/17/18/20, từ nhận lệnh đến mốc
phát prompt kế tiếp lần lượt 591/845/571/584 ms (dòng 615–632, 701–718,
744–761, 833–850). Resolver chỉ mất 19–40 ms. Log không ghi transcript hoặc
mã lựa chọn, nên không gán chắc từng generation cho Ngôi sao/Ba mẹ/Luyện lại.

Lượt chọn chủ đề có `speech.end` 23:05:23.150, endpoint hợp lệ .170, final .181,
dispatch .233, frame .276: từ endpoint Android đến frame là 126 ms.
Đây chỉ là một mẫu; final cũng đến nhanh, chưa chứng minh fast path cải thiện
mọi trường hợp nhận diện chậm. Một endpoint khác không đủ hợp lệ được giữ lại
để chờ final như thiết kế.

So với mẫu cũ, vào Vocabulary → prompt-start giảm từ khoảng 3.755 ms xuống
1.089 ms tính từ dispatch. Hai mẫu không phải benchmark lặp có kiểm soát.

HFP có 49 lần bắt đầu/xác nhận lại route, không phải 49 lần đóng–mở SCO vật lý.
Trung vị 260 ms; 43 lần không quá 350 ms. Năm lần trên 700 ms: 1.044/996/2.530/
912/1.829 ms. Lần 2.530 ms là mở lại sau nhả route khi idle; lần 1.829 ms sau
mất SCO. Vẫn có thời gian xác nhận route lặp giữa các clip cần tối ưu.

Menu đóng gói đã được dùng; 18 bundled-source events. Năm lần remote timeout
rơi về TTS sau 352–358 ms, không còn khoảng 2 giây của cấu hình cũ. Còn một
khoảng chờ mới đáng kể ở bước đo âm lượng: prepare → gain applied của các
prompt đo thất bại là 427–491 ms. Log chưa phân biệt codec timeout, lỗi codec
và thời gian xếp hàng worker; không được khẳng định tất cả là cùng một lỗi.

## 2. Âm lượng chưa đồng nhất — đã xác định một nhánh sai

- Prompt: 23/34 lần đo thành công, 11/34 lần `measured=false`, dùng +8 dB.
- Media: 15/17 lần đo thành công, 2/17 lần dùng +8 dB dự phòng.
- Tất cả snapshot volume có Media 15/15 và Voice Call 11/11; không có thay đổi
  volume trong các mẫu này giải thích sự khác biệt.

Ví dụ cùng nhóm menu: RUN-046 và RUN-056 dùng +8 dB khi không đo được
(dòng 588, 717, 804); RUN-058 được giảm khoảng −9,34 dB (dòng 760, 849).
Gain khác nhau tự nó không chứng minh âm lượng khác nhau vì mục đích là cân
nguồn. Do đó đã kiểm tra thêm file nguồn local bằng FFmpeg volumedetect,
không chỉnh sửa file:

| Asset | RMS toàn file | Sample peak |
| --- | ---: | ---: |
| RUNTIME-MAIN-NAVIGATION-001 | −11,7 dBFS | −0,7 dBFS |
| RUN-046 | −12,3 dBFS | −0,9 dBFS |
| RUN-056 | −12,2 dBFS | −1,2 dBFS |
| RUN-058 | −12,6 dBFS | −1,7 dBFS |

Các nguồn này vốn đã gần nhau và lớn hơn mục tiêu −21 dBFS. Tăng thêm +8 dB
khi phép đo thất bại đi ngược mục tiêu cân mức; có nguy cơ làm limiter can thiệp.
Đây không phải đo âm thanh vật lý ở loa, và RMS toàn file không đồng nhất với
gated RMS hoặc LUFS. Không kết luận độ chênh âm học đúng bằng chênh gain.

Liên hệ code: `AndroidPlaybackLoudness.kt` có hạn mức giải mã 350 ms và trả null
cho lỗi/timeout/nguồn không hỗ trợ; `VoicePromptBridge.kt:423` chọn gain dự phòng
+8 dB, thêm watchdog 450 ms. Authored prompt được ghi tên file mới theo utterance,
trong khi cache mức âm thanh khóa theo đường dẫn/size/mtime; lời lặp lại không
tận dụng được cùng kết quả đo một cách ổn định.

Ưu tiên sửa: đo/chuẩn hóa asset trước hoặc cấp metadata gain đã kiểm chứng,
cache theo nội dung; không tăng +8 dB cho một nguồn chưa biết mức. TTS/ghi âm
động giữ phép đo riêng với fallback an toàn và log nguyên nhân cụ thể.
Không chỉ nâng timeout vì sẽ làm điều hướng/lời nói chậm thêm.

## 3. Ting: không có lần phát app trùng trong mẫu này

14 delegate/channel requests, 14 native starts và 14 completions, cueId 1–14;
không lỗi cue. 11 MAIN, 3 listeningLesson. Khoảng cách ngắn nhất giữa hai
native starts là 7.722 ms (7,722 giây), không có hai start đồng thời/gần nhau.

Actual routed-device snapshot: 10 lần là Bluetooth SCO type 7, device 8256;
4 lần null (cue 1/4/7/13). Null nghĩa là chưa có dữ liệu đầu ra tại thời điểm
đọc, không phải bằng chứng phát ở loa điện thoại. Tất cả 11 MAIN cue vẫn ghi
mode NORMAL (0); ba lesson cue là IN_COMMUNICATION (3). Do đó việc tái xác nhận
HFP trước cue chưa bảo đảm mode không bị thay đổi tiếp sau đó. Chưa xác định
tác nhân thay đổi mode từ bộ log này.

Cần lời xác nhận nghe thực tế của người thử; tiếng báo từ recognizer/H20 không
được đếm bởi native app cue. Không có bằng chứng web đang phát trong lượt này.
Nếu tái hiện, bổ sung routing-changed callbacks và trace chủ sở hữu AudioManager
mode thay vì suy đoán có hai pipeline ứng dụng.

## 4. Hai vấn đề ổn định còn lại

23:05:30.127, dòng 500–514: Dart `Unhandled Exception: Lượt âm thanh đã dừng.`
Stack: ScopedHfpAudioControl.startAudioRoute → LessonMediaService route prepare
→ LessonPracticeScreen._speakLessonPrompt → _openReview → _resumeV4Stage →
_loadStartingPoint. Ứng dụng vẫn tiếp tục cùng PID, không có FATAL EXCEPTION.
Lệnh route cũ bị hủy là cơ chế bảo vệ đúng; đường resume chạy unawaited chưa
xử lý exception đó. Cần bắt riêng cancellation của lượt đã hết hiệu lực;
không nuốt mọi lỗi route rồi tiếp tục phát trên loa khác.

23:06:31.842 và 23:07:32.105: selected H20 SCO disconnected. Lần đầu làm prompt
vocabulary operation 58 thất bại ngay sau khi chuyển remote timeout sang TTS
(dòng 767–784); lần sau xảy ra trong cửa sổ nhận diện (dòng 998–1018).
Không có bằng chứng đủ phân biệt người dùng tắt thiết bị với tranh chấp audio
mode/lỗi Bluetooth. Cần đối chiếu thao tác người thử trước khi quy nguyên nhân.

Chưa sửa code hay build thêm trong lượt đọc log này. Bản v2 chưa được nghiệm thu
là đã xử lý triệt để cả ba triệu chứng.
