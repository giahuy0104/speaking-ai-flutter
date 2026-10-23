# Luồng Chủ đề theo source hiện tại — 23/10/2026

Phạm vi: review source, không sửa runtime hoặc chạy điện thoại. Các mô tả dưới đây là hành vi trong code, chưa phải xác minh thiết bị thật.

## 1. Vào Chủ đề
HomeLearningShell._openTopicListening dùng AppNavigator/AppRouteNames.topicCatalog, chuyển từ phải vào. Truyền tuổi, ngôn ngữ, controller, progress store, callback kiểm thiết bị và voice navigation. Chặn mở trùng bằng _openingTopics. Mở catalog chưa gọi ensureDeviceConnected; khi chạm topic/song, _runDeviceAction mới gọi callback và chặn double tap bằng _waitingForDevice. Đường giọng nói có initialVoiceTarget riêng.

## 2. Nội dung và chọn bài
TopicListeningScreen chọn catalog theo tuổi, đọc assets/data/listening_lessons.json qua AssetListeningContentRepository và load progress. Asset hiện tại schema4/contentVersion4.2, năm nhóm3–5,6–7,8–10,11–12,13–15; mỗi nhóm10 chủ đề, mỗi chủ đề2–3 bài. Topic trong cùng tuổi là ngang cấp, không phải mở khóa tuần tự topic; bài trong topic mở tuần tự theo bài trước, có ngoại lệ migration v4.2.

_openTopic xử lý: chưa học → bài đầu chưa hoàn thành; đang học → bài chưa hoàn thành kèm lời nhắc học tiếp; đã hoàn thành → hỏi học lại hay chọn topic khác. Học lại topic reset run các bài và bắt đầu bài đầu. Sau đó push TopicLessonListScreen với initialLessonNumber; màn này tự mở LessonIntroScreen. Vì vậy thao tác chọn topic có thể đi thẳng vào bài, không dừng ở danh sách bài.

## 3. Bài học
LessonIntroScreen phát hướng dẫn/khôi phục checkpoint rồi replace sang LessonPracticeScreen cho V4. Có nhánh legacy karaoke/review cho dữ liệu cũ.

Core: phát mẫu song ngữ → lời mời lặp lại → mở thu âm → nhận dạng/đánh giá → phản hồi. good lưu achieved, cộng sao Core chưa có, lưu bộ Sao rồi sang câu tiếp. retry cho thử lần2; còn chưa đạt thì needsPractice và chuyển tiếp. unclear/noResponse không đồng nghĩa trả lời sai; V4 nhắc lại một lượt, lần không sử dụng được thứ2 tạm dừng. Android practice ưu tiên nhận dạng on-device; có nhánh backend fallback, không được hiểu toàn bộ flow luôn offline.

Sau Core, _openReview(V4) chọn một Challenge trong challengeBank, ưu tiên câu chưa đạt/bỏ qua và có cơ chế luân phiên/cố định lựa chọn khi resume. Challenge không tạo slot Sao. Kết quả challenge cập nhật tập cần luyện; câu còn yếu được đưa vào Từ vựng/Luyện lại. Nếu có songTitle, mở V4SongStageScreen; kết thúc hoặc bỏ qua song đều có thể đi tiếp, gián đoạn giữ checkpoint song. Sau hoạt động cuối mới markV4LessonActivityCompleted rồi hỏi nextLesson/relearnCurrentLesson/stop hoặc nextTopic/relearnTopic/stop; hết toàn bộ topic thì đánh dấu hoàn thành khóa theo nhóm tuổi.

## 4. Tiến độ và điều khiển
ListeningProgressStore lưu câu hiện tại, kết quả từng câu, sao, câu bỏ qua/cần luyện, challenge đã xử lý, stage core/challenge/song/completed/waitingForChoice, cùng lựa chọn đang chờ. Native lưu listening-progress.json trong application support. ActiveListeningSessionStore lưu tuổi/topic/bài đang hoạt động; lịch sử ghi âm có store riêng.

Nút MAIN dùng ActiveLearningModule/handleMainCommand: tạm dừng phát/thu, nhường audio cho trợ lý, tiếp nhận tiếp tục/nghe lại/câu trước/câu sau/bài tiếp/dừng/về Home. ListeningLessonSession dùng generation ticket loại callback cũ. LessonMediaService quản lý audio route/record/playback; mất HFP trong lượt đang dùng sẽ ngắt playback/recording thay vì phát tiếp ra loa điện thoại. Điều kiện thiết bị đầu vào do callback của app, không do DeviceBloc onboarding quản lý module Chủ đề.

## 5. Cấu trúc đáng lưu ý
Đã tách domain rules, media/evaluator, session và persistence, nhưng presentation còn giữ phần lớn orchestration. LessonPracticeScreen5724 dòng, TopicListeningScreen2114, TopicLessonListScreen1320 tại lúc đọc. State vẫn chủ yếu StatefulWidget/setState và nhiều cờ/Future/timer; chưa có TopicBloc/LessonBloc. Nếu refactor sau này nên giữ domain rules và các boundary MAIN/audio/checkpoint hiện tại, chuyển orchestration riêng trước, không gộp thay đổi navigation/Bluetooth/chấm điểm cùng lúc.

Điểm cần phân biệt: hoàn thành khác đạt toàn bộ Sao; chọn topic có thể auto-resume vào bài; flow runtime V4 không còn bắt đi Level tuần tự dù dữ liệu/model legacy còn Level/Mission/RolePlay.

Nguồn chính: lib/features/home/presentation/home_learning_shell.dart:_openTopicListening; lib/features/listening/presentation/topic_listening_screen.dart:_runDeviceAction/_openTopic; topic_lesson_list_screen.dart:_startLesson/_openInitialLesson; lesson_intro_screen.dart:_beginIntro/_openLesson; lesson_practice_screen.dart:_startGuidedSentenceSequence/_applyAttemptOutcome/_openReview/_showV4CompletionChoice/handleMainCommand; domain/listening_curriculum_flow.dart; domain/lesson_star_flow.dart; data/listening_progress_store.dart.
