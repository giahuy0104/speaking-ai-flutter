/// Existing fixed prompts approved for native TTS on 2026-09-19.
/// Exact texts only: adding a new missing prompt still requires review.
/// This is a coverage contract, not a replacement for authored audio or a
/// runtime override. MainAssistantAudioPromptService already falls back to TTS.
const approvedAssistantTtsFallbacks = <String>{
  'Bạn muốn nghe lại, câu trước hay câu sau?',
  'Mình học câu sau nhé',
  'Nói theo mình nhé.',
  'Bây giờ đến lượt bạn. Bạn nói lại nhé.',
  'Bạn hãy nói “Luyện lại từ đầu” hoặc “Bài tiếp theo” nhé.',
  'Bạn nói lại lựa chọn nhé.',
  'Bạn đã học xong chủ đề này rồi. Bạn chọn tiếp chủ đề mới nhé.',
  'Bạn làm tốt lắm',
  'Bạn tập trung học nhé.',
  'Bây giờ bạn thử nói lại lần nữa nhé.',
  'Bạn đã cố gắng rồi! Mình sẽ luyện thêm sau. Cùng học câu tiếp nào.',
  'Bạn đang ở phần đầu bài học rồi.',
  'Bạn hãy vào bài học trước nhé.',
  'Bạn xem bài học thêm một chút nhé.',
  'Bạn hãy quay lại danh sách để chọn bài trước nhé.',
  'Bạn hãy học xong bài hát này trước nhé.',
};
