// Diagnostic supplement: MAIN receives the active screen's voice context.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:ai_speaking_flutter_app/features/voice_navigation/application/main_voice_assistant_flow.dart';
import 'package:ai_speaking_flutter_app/features/vocabulary/domain/vocabulary_flow_v3.dart';

class _Context implements ActiveLearningVoiceContext {
  const _Context(this.mainVoiceNode, this.mainVoicePrompt);
  @override final ActiveLearningVoiceNode mainVoiceNode;
  @override final String mainVoicePrompt;
}

void main() {
  test('supplement live screen MAIN context instead of null-context defaults', () async {
    const dir = 'deliverables/audio-runtime-audit-2026-09-17';
    final domain = jsonDecode(File('$dir/fresh-domain-audit.json').readAsStringSync()) as Map<String,dynamic>;
    final contexts = <_Context>[
      const _Context(ActiveLearningVoiceNode.core, 'Bạn muốn nghe lại, học câu tiếp theo, học câu trước hay dừng lại?'),
      const _Context(ActiveLearningVoiceNode.core, 'Bạn chọn một trong các lựa chọn trên màn hình nhé.'),
      const _Context(ActiveLearningVoiceNode.challenge, ''),
      const _Context(ActiveLearningVoiceNode.review, ''),
      const _Context(ActiveLearningVoiceNode.today, 'Bạn muốn nghe lại, nghe câu trước hay dừng lại?'),
      for (final node in [ActiveLearningVoiceNode.parent,ActiveLearningVoiceNode.star])
        _Context(node, 'Bạn muốn nghe lại, nghe câu trước, câu tiếp theo hay dừng lại?'),
      const _Context(ActiveLearningVoiceNode.vocabularyMenu, VocabularyFlowV3.menu),
      for (final text in [VocabularyFlowV3.parentEmpty,VocabularyFlowV3.parentOtherMenu])
        _Context(ActiveLearningVoiceNode.parentAlternatives,text),
      for (final text in [VocabularyFlowV3.starEmpty,VocabularyFlowV3.starOtherMenu])
        _Context(ActiveLearningVoiceNode.starAlternatives,text),
      for (final text in [VocabularyFlowV3.reviewEmpty,VocabularyFlowV3.reviewOtherMenu,VocabularyFlowV3.reviewCycleFinished])
        _Context(ActiveLearningVoiceNode.reviewAlternatives,text),
      const _Context(ActiveLearningVoiceNode.todayEnd,VocabularyFlowV3.todayCompletion),
      const _Context(ActiveLearningVoiceNode.blockEnd,VocabularyFlowV3.parentGroupCompletion),
      for (final text in [VocabularyFlowV3.starFinished,VocabularyFlowV3.parentFinished])
        _Context(ActiveLearningVoiceNode.listEnd,text),
      // During V4 completion the core owner supplies this dynamic choice text.
      for (final row in domain['rows'] as List)
        if (row['scope']=='current' && row['family']=='completion')
          _Context(ActiveLearningVoiceNode.core,row['text'] as String),
    ];
    // Verify copied screen literals have not drifted from source.
    final screenSource = [
      'lib/features/listening/presentation/lesson_practice_screen.dart',
      'lib/features/vocabulary/presentation/vocabulary_home_screen.dart',
      'lib/features/vocabulary/presentation/vocabulary_practice_screen.dart',
    ].map((p)=>File(p).readAsStringSync()).join('\n');
    for (final index in [0,1,4,5,6]) {
      expect(screenSource.contains(contexts[index].mainVoicePrompt),true);
    }
    final additions = <Map<String,dynamic>>[];
    void add(String text, _Context c, String step, {String locale='vi-VN'}) {
      if(text.trim().isEmpty) return;
      if(additions.any((r)=>r['text']==text && r['locale']==locale)) return;
      additions.add({'text':text,'locale':locale,'scope':'current',
        'family':'active_screen_main_context',
        'source':'lib/features/voice_navigation/application/main_voice_assistant_flow.dart',
        'exampleContext':'${c.mainVoiceNode.name}: $step',
        'evidence':'executed_domain_with_source_verified_screen_context'});
    }
    for(final context in contexts) {
      for(final input in ['xyz','giúp mình','nghe lại','câu trước','câu tiếp theo','học tiếp','học cái khác','dừng lại','']) {
        final flow=MainVoiceAssistantFlow(childAge:6);
        add(flow.beginActiveLearning(
          kind: context.mainVoiceNode==ActiveLearningVoiceNode.core || context.mainVoiceNode==ActiveLearningVoiceNode.challenge
            ? ActiveLearningModuleKind.listeningLesson : ActiveLearningModuleKind.vocabulary,
          voiceContext:context),context,'begin');
        for(var attempt=0;attempt<3;attempt++) {
          final turn=await flow.handle(input);
          if(turn.promptSequence.isEmpty) {add(turn.promptText,context,'$input attempt=$attempt');}
          else {for(final part in turn.promptSequence) {add(part.text,context,'$input attempt=$attempt',locale:part.locale);}}
          if(!turn.continueListening) break;
        }
      }
    }
    final combined = {...domain,'screenContexts':contexts.length,
      'rows':[...domain['rows'] as List,...additions]};
    File('$dir/context-domain-audit.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(combined));
    print('Screen contexts: ${contexts.length}; distinct additional outputs: ${additions.length}');
  });
}
