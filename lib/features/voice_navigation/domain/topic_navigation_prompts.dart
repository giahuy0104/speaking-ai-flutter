/// Shared wording for the user-provided ten-topic navigation recordings.
abstract final class TopicNavigationPrompts {
  static const chooseTen = 'Có 10 Chủ đề. Bạn chọn Chủ đề số mấy?';
  static const chooseTenRange = 'Bạn chọn Chủ đề từ số 1 đến số 10 nhé.';
  static const courseRelearn =
      'Bạn đã hoàn thành khóa học rồi. Bạn muốn học lại Chủ đề số mấy?';

  static String choose(int count) =>
      count == 10 ? chooseTen : 'Có $count Chủ đề. Bạn chọn Chủ đề số mấy?';

  static bool isFullTenTopics(Iterable<int> numbers) {
    final unique = numbers.toSet();
    return unique.length == 10 &&
        List.generate(10, (index) => index + 1).every(unique.contains);
  }

  static String invalid(Iterable<int> numbers) => isFullTenTopics(numbers)
      ? chooseTenRange
      : 'Nhóm tuổi này có ${numbers.toSet().length} Chủ đề. Bạn chọn lại nhé.';

  static String relearnInvalid(Iterable<int> numbers) {
    if (isFullTenTopics(numbers)) return chooseTenRange;
    final available = numbers.toSet().toList()..sort();
    return 'Bạn chọn Chủ đề ${available.join(', ')} nhé.';
  }
}
