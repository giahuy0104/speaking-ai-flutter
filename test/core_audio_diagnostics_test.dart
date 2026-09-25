import 'package:ai_speaking_flutter_app/core/audio/audio_diagnostics.dart';
import 'package:ai_speaking_flutter_app/core/device/active_learning_module.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AudioDiagnostics.setObserverForTesting(null));

  test('diagnostic payload keeps schema fields and redacts user data', () {
    final payload = AudioDiagnostics.buildPayload(
      'test.event',
      <String, Object?>{
        'operation': 7,
        'generation': 3,
        'stage': 'prepare',
        'transcript': 'private speech',
        'recordingPath': '/private/child.wav',
        'deviceId': 'private-device',
        'nested': <String, Object?>{
          'promptText': 'private prompt',
          'status': 'ready',
        },
        'event': 'cannot_override',
        'utcMs': -1,
        'platform': 'cannot_override',
        'lifecycle': 'cannot_override',
      },
      utcMs: 100,
      elapsedUs: 200,
    );

    expect(payload, containsPair('event', 'test.event'));
    expect(payload, containsPair('utcMs', 100));
    expect(payload, containsPair('elapsedUs', 200));
    expect(payload['platform'], isNot('cannot_override'));
    expect(payload['lifecycle'], isNot('cannot_override'));
    expect(payload, containsPair('operation', 7));
    expect(payload, containsPair('generation', 3));
    expect(payload, containsPair('transcript', '<redacted>'));
    expect(payload, containsPair('recordingPath', '<redacted>'));
    expect(payload, containsPair('deviceId', '<redacted>'));
    expect(payload['nested'], <String, Object?>{
      'promptText': '<redacted>',
      'status': 'ready',
    });
    expect(
      AudioDiagnostics.stableId(<Object?>['entry', 7]),
      AudioDiagnostics.stableId(<Object?>['entry', 7]),
    );
    expect(
      AudioDiagnostics.stableId(<Object?>['entry', 7]),
      isNot(AudioDiagnostics.stableId(<Object?>['entry', 8])),
    );
  });

  test('registry diagnostics correlate owner generation and command', () async {
    final events = <Map<String, Object?>>[];
    AudioDiagnostics.setObserverForTesting(events.add);
    final registry = ActiveLearningModuleRegistry();
    final module = _DiagnosticModule();

    final token = registry.register(module);
    expect(await registry.pauseForMainAssistant(), isTrue);
    final result = await registry.execute(ActiveLearningCommand.resume);
    registry.unregister(token);
    registry.dispose();

    expect(result.wasHandled, isTrue);
    final registered = events.singleWhere(
      (event) => event['event'] == 'active_learning.owner.registered',
    );
    final started = events.singleWhere(
      (event) => event['event'] == 'active_learning.command.started',
    );
    final completed = events.singleWhere(
      (event) => event['event'] == 'active_learning.command.completed',
    );
    expect(registered['ownerGeneration'], 1);
    expect(started['ownerGeneration'], 1);
    expect(started['node'], ActiveLearningVoiceNode.core.name);
    expect(started['command'], ActiveLearningCommand.resume.name);
    expect(completed['sameOwner'], isTrue);
    expect(completed['status'], ActiveLearningCommandStatus.handled.name);
  });
}

class _DiagnosticModule
    implements ActiveLearningModuleController, ActiveLearningVoiceContext {
  bool _paused = false;

  @override
  ActiveLearningModuleKind get moduleKind =>
      ActiveLearningModuleKind.listeningLesson;

  @override
  ActiveLearningVoiceNode get mainVoiceNode => ActiveLearningVoiceNode.core;

  @override
  String get mainVoicePrompt => 'must not be logged';

  @override
  bool get isPausedForMain => _paused;

  @override
  Future<void> pauseForMainAssistant() async => _paused = true;

  @override
  Future<ActiveLearningCommandResult> handleMainCommand(
    ActiveLearningCommand command,
  ) async {
    _paused = false;
    return const ActiveLearningCommandResult.handled();
  }
}
