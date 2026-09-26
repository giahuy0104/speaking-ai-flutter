import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'vocabulary_entry.dart';
import 'vocabulary_flow_v3.dart';

abstract final class VocabularyAudioKeys {
  static const Map<String, String> _fixedByState = <String, String>{
    'VOCAB_MENU_01': 'vocabulary.flow.menu.vi',
    'TODAY_INTRO_01': 'vocabulary.flow.today_intro.vi',
    'TODAY_RESUME_01': 'vocabulary.flow.today_resume.vi',
    'TODAY_BLOCK_END_01': 'vocabulary.flow.today_completed.vi',
    'PARENT_LIST_SHORT_01': 'vocabulary.flow.parent_listen.vi',
    'PARENT_RESUME': 'vocabulary.flow.parent_resume.vi',
    'PARENT_LIST_BLOCK_END_01': 'vocabulary.flow.parent_group_completed.vi',
    'PARENT_LIST_OTHER_MENU_01': 'vocabulary.flow.parent_other_menu.vi',
    'PARENT_LIST_END_01': 'vocabulary.flow.parent_completed.vi',
    'PARENT_LIST_EMPTY_01': 'vocabulary.flow.parent_empty.vi',
    'STAR_INTRO_01': 'vocabulary.flow.star_listen.vi',
    'STAR_INTRO_0_01': 'vocabulary.flow.star_empty.vi',
    'STAR_MY_VOICE_01': 'vocabulary.flow.star_my_voice.vi',
    'STAR_RESUME_ALL_01': 'vocabulary.flow.star_resume.vi',
    'STAR_BLOCK_END_01': 'vocabulary.flow.star_group_completed.vi',
    'STAR_OTHER_MENU_01': 'vocabulary.flow.star_other_menu.vi',
    'STAR_END_01': 'vocabulary.flow.star_completed.vi',
    'REVIEW_INTRO_01': 'vocabulary.flow.review_listen.vi',
    'REVIEW_RESUME_01': 'vocabulary.flow.review_resume.vi',
    'REVIEW_BLOCK_END_01': 'vocabulary.flow.review_group_completed.vi',
    'REVIEW_OTHER_MENU_01': 'vocabulary.flow.review_other_menu.vi',
    'REVIEW_PASS_END_01': 'vocabulary.flow.review_completed.vi',
    'REVIEW_EMPTY_01': 'vocabulary.flow.review_empty.vi',
  };

  static String? fixedPrompt(VocabularyFixedPrompt prompt) =>
      _fixedByState[prompt.stateId];

  static String? builtInEntry(VocabularyEntry entry, String locale) {
    if (entry.isParentAdded) return null;
    final entryId = entry.sourceSentenceId?.trim();
    if (entryId == null || entryId.isEmpty || !_safeId.hasMatch(entryId)) {
      return null;
    }
    final isEnglish = locale.toLowerCase().startsWith('en');
    return 'vocabulary.entry.$entryId.${isEnglish ? 'word.en' : 'meaning.vi'}';
  }

  static String dynamic({
    required String text,
    required String locale,
    required String voiceProfile,
  }) {
    final normalized = text.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return sha256
        .convert(utf8.encode('$locale\u0000$voiceProfile\u0000$normalized'))
        .toString();
  }

  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
}
