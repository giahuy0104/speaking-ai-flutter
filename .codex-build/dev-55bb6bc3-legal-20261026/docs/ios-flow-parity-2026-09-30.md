# Rà soát luồng iOS theo phản hồi tester — 30-09-2026

Lấy hành vi Android làm chuẩn cho lời dẫn, thứ tự audio, Core, Challenge và
điều hướng. Ba trợ lý kiểm tra riêng phần thưởng/hook, Challenge và native
audio iOS; phần điều hướng và kiểm chứng tích hợp được kiểm tra chung.

## Các lỗi đã sửa trong mã nguồn

| Phản hồi tester | Nguyên nhân tìm được | Thay đổi |
| --- | --- | --- |
| Thiếu lời nhận ngôi sao đầu tiên/âm thanh thưởng | Core đã có chung lời thưởng Android/iOS. Tuy nhiên Apple Speech có thể kết thúc sau cửa sổ chờ ngắn của Android; thông tin WAV chỉ có ở sự kiện final/error, trong khi V4 phải phát lại bản ghi trước khi thưởng | Native gửi metadata của WAV đã đóng ngay tại `speech.end`; Dart giữ metadata khi phải dùng transcript tạm và chờ final iOS trong giới hạn có sẵn. Giữ nguyên trình tự phát bản ghi → phản hồi đúng → lưu sao → lời sao đầu tiên/SFX/ting |
| Thiếu hook, tiếng chó/mèo | 13 audio hook từng có ở commit `4091f3fa`, bị bỏ cùng nhánh phát hook khi chuyển thư viện audio | Khôi phục đúng 13 file từ Git, thêm semantic key vào `listening-common` và đóng gói trong Flutter. Phát lời mở bài → hook có sẵn → câu bắt đầu, mỗi phần một lần; resume không lặp hook |
| Lời dẫn bị bỏ qua hoặc mic mở sai thời điểm | Dart nuốt lỗi awaited TTS/cue trên iOS; native cue từng báo thành công cả khi route/player/decoder lỗi | iOS truyền lỗi lên luồng điều khiển, không mở mic sau cue thất bại; các yêu cầu cue đồng thời cùng đợi một lần phát. TTS bị ngắt ngoài ý muốn trả lỗi |
| Challenge giật/chậm, phản hồi lệch lượt | Không theo dõi sự kiện hoàn tất Apple Speech trong Challenge nên có thể chờ endpoint dù native đã kết thúc | Đăng ký listener trước khi start, xử lý cả final sớm trong lúc start chưa trả về, chỉ stop/chấm một lần. Hủy listener và quyền xử lý khi MAIN, replay, stop, lỗi hoặc rời màn |
| Dùng nút điều hướng tiếp tục phần bị ngắt | Chuyển câu cũ có thể hoàn tất đọc/lưu tiến độ sau khi MAIN đã ngắt, rồi đổi câu hoặc phát audio vào lượt mới | Kiểm tra lượt và vị trí câu sau các bước bất đồng bộ; ngắt ngay khoảng chờ audio. Tuần tự hóa checkpoint và sửa cursor nếu write cũ đã commit; Back lưu vị trí hiển thị sau các write cũ. MAIN chờ đọc cursor khởi tạo, gộp thao tác lặp trong lúc chờ. Nút ảo và MAIN dùng cùng thứ tự mẫu Anh → Việt → cue → mic |
| Kết quả Apple Speech cũ can thiệp lượt MAIN mới | Callback finalization của SpeechAnalyzer chưa kiểm tra generation và session; legacy engine còn phát final hai lần, lần đầu trước khi đóng WAV | Kiểm tra quyền sở hữu trước cả success/error; `speech.stop` xác nhận yêu cầu ngay. Legacy chỉ phát một final sau khi đóng WAV và có metadata; final/error đi qua event stream có giới hạn chờ |

iOS cũng nhận speechRate/pitch theo từng câu như Android, không mang cấu hình
của câu dịch sang lời coach tiếp theo. Không đổi API chấm bài Android, ID câu,
dữ liệu tiến độ, bản ghi đã lưu hoặc bộ nhận ý định MAIN.

## Audio khôi phục

- 13 MP3, tổng 610.558 byte, khôi phục nguyên bản từ Git; không tạo audio mới.
- Dùng key `listening.lesson.<lessonId>.hook.vi`, có SHA-256 của file và textHash
  khớp entry hiện tại; không đưa legacy URL trở lại curriculum.
- Thư viện `listening-common`: 442 mục. Toàn bộ 16 pack: 3.948 mục,
  textHash coverage 100%.
- Đã cập nhật index, công cụ build index, và báo cáo audit để lần tái tạo sau
  vẫn giữ đúng mapping và hash.

## Kiểm chứng tự động

Kiểm tra tại workspace Windows:

| Kiểm tra | Kết quả |
| --- | --- |
| `flutter test --no-pub --concurrency=4 --reporter expanded` | 1.362 ca: 1.357 đạt, 5 golden Home/Onboarding lệch ảnh mẫu; không có lỗi kiểm thử chức năng |
| `flutter analyze --no-pub` | Không có lỗi/cảnh báo/info |
| `dart run tool/check_architecture_boundaries.dart` | Đạt |
| `git diff --check` | Đạt |
| Hash của 13 hook so với Git `4091f3fa` | Khớp toàn bộ |
| PowerShell AST của generator đã sửa | Cú pháp hợp lệ; không chạy tạo audio/API |

Năm golden đã được chạy lại trên checkout riêng của commit gốc
`21dba923a14437d1db8f43b9ce624edbfbf10c32`: cùng 5 lỗi (3 ca còn lại đạt),
cùng số pixel lệch và cả 5 ảnh render có SHA-256 giống hệt kết quả hiện tại.
Các lỗi ảnh mẫu này tồn tại trước đợt sửa; ảnh mẫu giữ nguyên.

| Golden có lỗi sẵn trên commit gốc | Pixel lệch |
| --- | --- |
| Home vocabulary | 214.407 (65,14%) |
| Home add vocabulary | 1.490.082 (50,30%) |
| Dark home vocabulary | 241.276 (73,30%) |
| Startup permissions | 1.474 (0,45%) |
| Dark startup permissions | 1.474 (0,45%) |

Log đầy đủ: `.codex_tmp/ios-parity-full-tests-2026-09-30.log`. Log baseline:
`.codex_tmp/ios-parity-baseline-goldens-21dba923.log`; so sánh hash:
`.codex_tmp/ios-parity-baseline-render-comparison-21dba923.json`.

Các ca hồi quy bổ sung kiểm tra:

- Callback lưu tiến độ cũ sau MAIN không đổi câu/audio mới hoặc cursor lưu trên
  Android và iOS; lệnh MAIN trong lúc đang đọc vị trí khởi tạo chờ đúng câu và
  thao tác lặp chỉ khởi động một lượt.
- Nút Câu trước/Câu sau/Nghe lại và lệnh MAIN cùng chờ mẫu Anh, mẫu Việt hoàn
  tất trước khi mở mic trên cả hai nền tảng.
- Hook được phát đúng vị trí, không lặp tiêu đề; thiếu hook vẫn có fallback
  đúng phần lời, resume không phát lại hook.
- Challenge dùng cùng lời dẫn/retry/đáp án mẫu; final sớm, final trong pending
  start và callback cũ sau MAIN không được xử lý hai lần.
- iOS nhận final sau stable partial, giữ WAV khi dùng partial và không nuốt
  lỗi Apple sau khi native đã xác nhận stop.
- Lỗi awaited prompt/cue ngăn capture; Android giữ cửa sổ final ngắn hiện có.

## Nghiệm thu trên iPhone/H20

Windows chỉ chạy được Dart/widget tests và kiểm tra asset; chưa biên dịch
Swift/Xcode hoặc chạy iPhone/H20 thật. Cần chạy workflow `ios-bootstrap` trong
`codemagic.yaml` để build simulator và RunnerTests, sau đó bản TestFlight cùng
commit để đối chiếu với Android.

| Ca | Kết quả cần xác nhận |
| --- | --- |
| Core trả lời đúng lần đầu với tài khoản chưa có sao | Phát lại giọng trẻ, phản hồi đúng, lời nhận sao đầu tiên và âm thanh thưởng đúng thứ tự; không chồng tiếng |
| Bài có hook chó/mèo và các hook còn lại | Lời mở bài → hook → câu bắt đầu, không thiếu tiếng cảnh và không lặp lời |
| Challenge đúng/sai/im lặng | Cùng lời dẫn, số lần retry và đáp án mẫu như Android; native kết thúc không để UI chờ mic đã dừng |
| Dừng, Câu trước, Câu sau, Nghe lại qua MAIN/nút ảo/nút H20 đã xác nhận | Audio/mic cũ dừng; bắt đầu lại đúng câu và đúng lời dẫn; bấm liên tiếp không phát lời của lượt cũ |
| MAIN trong lúc thu âm/chấm/phát thưởng/chuyển Core sang Challenge | Một chủ sở hữu mic/audio; kết quả cũ không đóng hoặc điều hướng lượt mới |
| Loa iPhone, H20, mất/kết nối lại Bluetooth, khóa/mở màn hình | Cue nghe được một lần trên đúng route, WAV phát lại được, không tự mở mic sau lỗi route |

Các khác biệt có chủ đích về Apple Speech, wake-word, học nền và offline dịch
vẫn theo [tài liệu parity](ios-feature-parity.md). Luồng Flutter tương đương
không phải bằng chứng âm thanh hoặc nút vật lý đã đạt trên thiết bị.

## Rà soát mở rộng sau phản hồi tiếp theo

Bốn trợ lý rà độc lập MAIN/trò chuyện, từ vựng và màn Home, native iOS audio,
và luồng bài học. Các sai lệch tìm thấy và đã sửa thêm:

| Khu vực | Sai lệch iOS | Cách xử lý |
| --- | --- | --- |
| MAIN khi im lặng | Apple Speech trả `IOS_SPEECH_NO_SPEECH` nhưng bộ điều khiển chỉ coi mã Android là im lặng hợp lệ, nên iOS báo lỗi mic thay vì nhắc lại | Cho iOS dùng cùng luồng nhắc lại/kết thúc sau hai lượt im lặng của Android |
| Nút MAIN trên màn hình | Bị vô hiệu trong lúc dịch liên tục dù lệnh MAIN vật lý có thể ngắt phiên dịch | Cho nút màn hình gọi cùng đường ngắt phiên dịch khi đang ghi âm hoặc phát bản dịch |
| Chuyển trang bằng giọng nói | iOS trả về trước khi `PageView` hoàn tất chuyển sang Trò chuyện, có thể mở mic MAIN khi màn Từ vựng còn hiển thị; resume không chỉnh lại trang | Chờ animation và frame cuối như Android, đồng bộ lại trang khi ứng dụng quay về foreground |
| Review Từ vựng | iOS phát cue trước mic nhưng không xác nhận lại đầu ra H20 ngay trước cue như Android | Chuẩn bị lại đầu ra được chọn và chỉ tiếp tục khi route hợp lệ |
| Ghi âm Core/lựa chọn cuối bài | Apple Speech đã nhận quyền capture nhưng lesson vẫn giữ lease HFP của lượt phát trước; iOS recorder thông thường lại nhả HFP trước lời phản hồi | Bàn giao lease khi Apple Speech bắt đầu; giữ HFP qua chấm điểm/phản hồi trên cả iOS và Android |
| Native H20 và tiếng “ting” | iOS có thể chọn nhầm HFP khác, hoặc bắt đầu cue/TTS/file lời dẫn trước khi tuyến HFP thực sự sẵn sàng | Xác nhận đúng thiết bị H20 đã chọn và tuyến hai chiều trước capture/phát âm thanh; chờ 180 ms đuôi cue, báo lỗi nếu route mất |
| Bài hát sau Challenge | Lỗi tuyến H20 khi phát lời mở đầu bị nuốt, bài hát có thể vẫn bắt đầu trên đầu ra sai | Giữ màn bài hát ở trạng thái lỗi để thử lại, không tự tiếp tục sau lỗi HFP |
| Giọng dịch offline | Tốc độ/cao độ bản dịch iOS khác cấu hình Android | Gửi cùng `speechRate=0.80`, `pitch=1.05`; không để style này dính sang lời coach tiếp theo |

Kiểm tra sau sửa: `flutter analyze --no-pub` sạch; kiểm tra kiến trúc và
`git diff --check` đạt; **1.313/1.313 kiểm thử không dùng ảnh mẫu đạt** theo
cùng bộ lọc test của workflow iOS. Kiểm thử tập trung cả Android/iOS đạt sau
khi sửa một lỗi chỉ nằm ở cách test đọc `PageView` trong lúc `pump`. Log:
`.codex_tmp/ios-parity-nongolden-tests-2026-09-30.log`.

Giới hạn xác nhận vẫn là Swift/Xcode và âm thanh thật trên iPhone/H20: Windows
không chạy được `RunnerTests`, simulator hay TestFlight. Chưa biết số build
Android/iOS của tester nên chưa thể chứng minh bản họ đang cài chứa các sửa đổi
trong workspace này. Cần một bản iOS build từ đúng commit đã sửa để nghiệm thu.

## Kiểm toán độc lập lần hai — 2026-10-01

Android tiếp tục là mốc hành vi. Ba lượt rà độc lập kiểm tra native HFP/Apple
Speech, luồng MAIN/Home/Trò chuyện và dữ liệu/CI; lượt kiểm tra Core/lựa chọn
cuối bài chạy thêm ở màn Luyện nghe. Những lệch mới tìm được và đã sửa trong
workspace:

| Luồng | Lệch phát hiện | Sửa đổi |
| --- | --- | --- |
| Core iOS | Apple Speech tự kết thúc trước khi lệnh mở mic trả về hoặc trước hạn endpoint; màn Core không nghe tín hiệu `completed`, nên có thể đứng chờ mic đã dừng | Đăng ký final/partial trước khi mở capture, chốt lượt đúng một lần và hủy callback cũ khi MAIN/Back ngắt |
| Lựa chọn cuối bài | Final của Apple Speech đến trong lúc mở mic bị bỏ lỡ | Gắn listener trước native start và xử lý final chờ sau khi lượt có quyền mic |
| Phát bài qua H20 | Service Flutter chỉ nghe mất route trên Android; iOS có thể tiếp tục file qua loa điện thoại | Cùng chính sách dừng playback/hủy ghi âm khi mất HFP trên Android và iOS |
| Native H20 | Route iOS đổi hoặc mất trong lúc TTS, file lời dẫn, tiếng “ting” hay Apple Speech vẫn có thể chạy tiếp; một UID HFP cũ có thể bị nhận là tuyến hoạt động | Kiểm tra route hai chiều theo thiết bị đã chọn, dừng lượt với lỗi HFP khi mất tuyến và xác nhận lại sau khi route ổn định |
| Tiếng “ting” | iOS dùng WAV 44,1 kHz/170 ms/to hơn Android | Dùng mẫu 16 kHz/120 ms/−21 dBFS như Android; XCTest kiểm tra header và RMS |
| MAIN → Chủ đề | Lệnh điều hướng có thể báo xong trước khi Navigator cài route Chủ đề, khiến lượt MAIN tiếp theo mở sớm | Chờ Navigator cài route có giới hạn thời gian; không chờ người dùng thoát màn Chủ đề |
| Từ vựng → Giao tiếp | MAIN có thể mở mic dịch khi lệnh dừng audio Từ vựng vẫn đang treo; thao tác Back cũng có thể bị chặn nếu chờ dừng quá lâu | MAIN chỉ chuyển và mở mic sau cleanup hoàn tất; timeout giữ màn Từ vựng và báo thử lại. Back/chạm đổi trang tức thời như trước |
| Trò chuyện/H20 | Mất tuyến H20 đang được xử lý ở Android nhưng chưa áp vào iOS | Dùng cùng guard ngắt phiên trên iOS |
| Bản dịch qua A2DP | Sau Apple Speech, iOS phát qua tuyến Bluetooth chỉ phát; HFP báo rảnh không đủ để nhận biết tai nghe rớt giữa clip, và âm thanh có thể chuyển sang loa iPhone | Native phát loại cổng đầu ra cùng thứ tự thay đổi route; chỉ giám sát clip iOS đang phát trên Bluetooth, bỏ event cũ và dừng khi xác nhận chuyển sang loa máy. Metadata thiếu/route chưa rõ không bị suy đoán theo tên thiết bị |
| Build iOS | Hai workflow Codemagic ghi đè `REALTIME_BATCH_FALLBACK=false`, khác Android | Chuyển cả hai sang `true` để dùng cùng cấu hình fallback tùy chọn |

Kiểm tra dữ liệu: 3.948 khóa âm thanh trong 16 manifest đều có file, hash và
khai báo đóng gói. Trong 18 bài có hook, 13 có clip hiệu ứng riêng; 5 bài còn
lại có intro thu sẵn nhưng lịch sử Git không có clip hook riêng trên **cả hai**
nền tảng. Đây là khoảng trống nội dung chung, không được xem là lỗi đóng gói
iOS. Chưa tự tạo hiệu ứng không có bản gốc để tránh thay đổi nội dung bài.

Kiểm chứng cuối lượt: **1.323/1.323** test Flutter không dùng ảnh mẫu đạt
(cùng bộ lọc của CI), gồm các ca Android/iOS mới cho Core nhận final sớm, lựa
chọn cuối bài, mất H20/A2DP, bàn giao MAIN, timeout Từ vựng và route Chủ đề;
`flutter analyze --no-pub`, kiểm tra ranh giới kiến trúc và `git diff --check`
đều đạt. Log: `.codex_tmp/ios-parity-nongolden-tests-2026-10-01-final.log`.

Mã hiện ở working tree, chưa commit/push. Codemagic lấy mã từ Git để tạo
TestFlight; **chưa có bằng chứng bản tester đang dùng chứa các sửa đổi lần này**.
Chưa có số build tester cung cấp. Cần build iOS từ cùng revision, chạy
`ios-bootstrap`/RunnerTests, rồi nghiệm thu trên iPhone và H20 thật: Core,
Challenge, hook, nút Dừng/Câu trước/Câu sau/Nghe lại, chuyển MAIN qua mọi
màn, mất và nối lại Bluetooth giữa lời dẫn/ting/ghi âm, nút H20 vật lý, khóa
màn hình và phiên dịch. Widget test trên Windows chỉ xác nhận hành vi Flutter;
không xác nhận Swift compile hoặc âm thanh/hardware thực tế.

## Kiểm toán trước sửa theo yêu cầu tester — lượt ba, 2026-10-01

Ba trợ lý AI kiểm tra độc lập luồng học/Từ vựng, native audio/H20 và MAIN;
người điều phối kiểm tra Giao tiếp, cấu hình build, asset và ảnh giao diện.
Chỉ sửa sau khi có đường gọi và tình huống lỗi cụ thể. Rà tất cả nơi nhận
`StreamingSpeechInput.completed` cho thấy các bản sửa Core/Challenge/lựa chọn
cuối bài trước đó chưa bao phủ hết những nơi dùng Apple Speech.

| Luồng | Lỗi mới đã xác minh | Xử lý trong mã |
| --- | --- | --- |
| Review/Ngôi sao Từ vựng | Apple tự kết thúc nhưng màn hình chưa nghe `completed`; final có thể đến khi native start còn pending | Gắn listener trước start, giữ final/partial đến khi lượt có quyền mic, hủy callback khi MAIN/Back/pause/dispose |
| Ghi âm Từ vựng qua H20 | Native đã nhận quyền capture nhưng media vẫn giữ lease đầu ra HFP trước đó | Bàn giao đầu ra được chọn sau khi native start thành công và generation còn hiện hành |
| MAIN | Final/endpoint/partial trong lúc chờ native start hoặc ready cue bị bỏ qua | Giữ sự kiện theo generation, xử lý sau khi sẵn sàng; activation vẫn trả thành công khi đã nhận kết quả ngay, bỏ sự kiện của lượt bị hủy |
| Giao tiếp | Final trong lúc mở mic/ready cue bị bỏ qua; câu có final hợp lệ còn có thể bị loại thành quá ngắn/im lặng trước khi đọc kết quả native | Giữ final/partial của lượt hiện hành; native terminal đi qua `stop()` để lấy transcript/error, gồm final-only và final trong cleanup khi nhấn Dừng |
| Chọn thiết bị H20 native | Bridge dùng tên chuẩn hóa nhưng audio-session coordinator chỉ so tên chính xác; UID đổi cùng tên `HOMI-H20`/`HOMI H20` có thể được bridge nhận nhưng coordinator từ chối | Dùng cùng chính sách chọn HFP, ưu tiên UID và chỉ fallback theo tên của thiết bị đã chọn |

Các phần **chưa đồng bộ đầy đủ hoặc chưa thể xác nhận**:

| Phần | Bằng chứng/giới hạn còn lại |
| --- | --- |
| Dịch offline | Android có ML Kit Việt–Anh/Anh–Việt; iOS chưa có engine thay thế. Settings đã thể hiện giới hạn này; không gọi đây là parity đầy đủ |
| Độ lớn lời trợ lý | Android đọc `gainDb` và áp dụng điều chỉnh loudness; iOS đang phát TTS/file với volume 1 và chưa dùng cùng phép điều chỉnh. Cần đo loa/H20 trên iPhone rồi thiết kế xử lý gain để không gây clipping |
| H20 chập chờn | Android có cửa sổ phục hồi route 5 giây; iOS dừng khi xác nhận mất tuyến. Cần log hardware để phân biệt đứt kết nối và biến động route có thể phục hồi; chưa đổi thuật toán bằng phỏng đoán |
| Nhận giọng nói/chấm điểm | iOS Apple Speech + đối chiếu cục bộ; Android backend-first + fallback cục bộ. Nội dung/điều hướng chung không đảm bảo hai engine cho cùng transcript/điểm trên mọi bản ghi |
| Wake-word/học nền/nút H20 | MAIN chủ động iOS và giới hạn học nền vẫn khác Android; nút vật lý phải có bằng chứng firmware/thiết bị. Chưa có nghiệm thu iPhone/H20 |
| Nội dung hook | 5/18 bài không có hook SFX riêng trên cả hai nền tảng; có intro thu sẵn. 13 hook có bản gốc đã khôi phục; chưa tạo nội dung thay thế |

Chạy lại toàn bộ các file test có `matchesGoldenFile`: **50 đạt, 5 lệch ảnh
mẫu**. Ba golden Home lệch chủ yếu vì thanh điều hướng dưới hiện có trong
giao diện Flutter chung; hai golden quyền onboarding lệch dòng “micro H20” →
“micro HOMI”. Đã xem ảnh render/master. Các baseline này giữ nguyên; không
coi ảnh Flutter chung là bằng chứng lỗi riêng iOS, cũng không báo golden sạch.
Log: `.codex_tmp/ios-parity-golden-audit-2026-10-01.log`.

Kiểm chứng sau khi ghép toàn bộ bản sửa của lượt ba:

| Kiểm tra | Kết quả |
| --- | --- |
| Toàn bộ Flutter test không dùng ảnh mẫu, cùng bộ lọc CI | **1.333/1.333 đạt**, gồm hồi quy kết thúc sớm, hủy lượt, final-only, no-speech, cue pending và H20 handoff trên các luồng liên quan |
| `flutter analyze --no-pub` | Không có issue |
| `dart run tool/check_architecture_boundaries.dart` | Đạt |
| `git diff --check` | Đạt |
| Swift policy test chọn H20 khi UID/tên thay đổi | Đã thêm; chưa chạy vì máy hiện tại là Windows |

Log cuối: `.codex_tmp/ios-parity-nongolden-tests-2026-10-01-audit3.log` và
`.codex_tmp/ios-parity-audit3-analyze-final.log`. Không thay ảnh mẫu để che
golden thất bại, không gửi audio hoặc tạo asset mới trong lượt ba.

Mã sửa vẫn ở workspace. Chưa build/upload TestFlight hoặc xác minh build đang
được tester cài. Flutter tests trên Windows không chứng minh Swift biên dịch,
âm thanh trên iPhone hay firmware H20 đạt. Kết luận phù hợp hiện tại là parity
đã được cải thiện trong mã, **chưa xác nhận Android/iOS đồng bộ hoàn toàn**.
