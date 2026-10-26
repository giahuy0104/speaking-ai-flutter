import 'package:ai_speaking_flutter_app/core/audio/audio_playback_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test('recognizes the iOS insufficient-priority audio session error', () {
    expect(
      isIosAudioSessionInsufficientPriority(
        PlatformException(
          code: '561017449',
          message: "The operation couldn't be completed.",
        ),
      ),
      isTrue,
    );
    expect(
      isIosAudioSessionInsufficientPriority(
        PlatformException(code: 'OTHER_AUDIO_ERROR'),
      ),
      isFalse,
    );
  });

  test('does not accept a stale completed state before the source end', () {
    expect(
      isPlaybackAtSourceEnd(
        processingState: ProcessingState.completed,
        position: const Duration(milliseconds: 1600),
        duration: const Duration(milliseconds: 11700),
        currentPlaybackStarted: true,
      ),
      isFalse,
    );
  });

  test('does not accept old end position immediately after a new start', () {
    expect(
      isPlaybackAtSourceEnd(
        processingState: ProcessingState.completed,
        position: const Duration(milliseconds: 11700),
        duration: const Duration(milliseconds: 11700),
        currentPlaybackStarted: false,
      ),
      isFalse,
    );
  });

  test('accepts completion when the current source reaches its end', () {
    expect(
      isPlaybackAtSourceEnd(
        processingState: ProcessingState.completed,
        position: const Duration(milliseconds: 11600),
        duration: const Duration(milliseconds: 11700),
        currentPlaybackStarted: true,
      ),
      isTrue,
    );
  });

  test('armed listener replaces the previous source duration', () {
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.completed,
      playing: false,
      duration: const Duration(milliseconds: 2600),
    );

    expect(
      tracker.observe(
        processingState: ProcessingState.loading,
        playing: true,
        position: Duration.zero,
        duration: const Duration(milliseconds: 2600),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.ready,
        playing: true,
        position: const Duration(milliseconds: 100),
        duration: const Duration(milliseconds: 1200),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 1200),
        duration: const Duration(milliseconds: 1200),
      ),
      isTrue,
    );
  });

  test('stale completed state cannot finish an armed listener', () {
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.completed,
      playing: false,
      duration: const Duration(milliseconds: 2600),
    );

    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 2600),
        duration: const Duration(milliseconds: 2600),
      ),
      isFalse,
    );
  });

  test('accepts completed before the final position event arrives', () {
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.completed,
      playing: false,
      duration: const Duration(milliseconds: 2600),
    );

    expect(
      tracker.observe(
        processingState: ProcessingState.loading,
        playing: true,
        position: Duration.zero,
        duration: const Duration(milliseconds: 2600),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.ready,
        playing: true,
        position: const Duration(milliseconds: 100),
        duration: const Duration(milliseconds: 1200),
      ),
      isFalse,
    );

    // On iOS the completed state can win the scheduling race against the final
    // position update. There is no second player-state event after this one.
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 850),
        duration: const Duration(milliseconds: 1200),
      ),
      isTrue,
    );
  });

  test('a session-long tracker closes its gate on every new source', () {
    // JustAudioPlaybackService keeps one tracker for the whole session to know
    // when to release the audio turn. Before the gate was reset per source it
    // latched open on the first clip, so a completed state replayed for an
    // already finished source released the turn under the clip playing now.
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.idle,
      playing: false,
      duration: null,
    );

    // First clip plays through and legitimately completes.
    expect(
      tracker.observe(
        processingState: ProcessingState.ready,
        playing: true,
        position: const Duration(milliseconds: 50),
        duration: const Duration(milliseconds: 900),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 900),
        duration: const Duration(milliseconds: 900),
      ),
      isTrue,
    );

    // A second clip is loaded but has not started yet.
    expect(
      tracker.observe(
        processingState: ProcessingState.loading,
        playing: false,
        position: Duration.zero,
        duration: null,
      ),
      isFalse,
    );

    // The first clip's completed state is replayed. It must not read as the
    // end of the clip that is loading now.
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 900),
        duration: const Duration(milliseconds: 900),
      ),
      isFalse,
    );

    // The second clip then plays and completes on its own terms.
    expect(
      tracker.observe(
        processingState: ProcessingState.ready,
        playing: true,
        position: const Duration(milliseconds: 40),
        duration: const Duration(milliseconds: 700),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: false,
        position: const Duration(milliseconds: 700),
        duration: const Duration(milliseconds: 700),
      ),
      isTrue,
    );
  });

  test('a source that is already playing when it loads still completes', () {
    // The reset must run before the re-arm in the same observe() call: a
    // loading event usually carries playing: true, because just_audio leaves
    // playing set after the previous source ended. Reversing the two strands
    // the gate closed and the clip never reports completion, which blocks
    // every queued prompt because the turn is released nowhere else.
    final tracker = PlaybackCompletionTracker(
      processingState: ProcessingState.idle,
      playing: false,
      duration: null,
    );

    expect(
      tracker.observe(
        processingState: ProcessingState.loading,
        playing: true,
        position: Duration.zero,
        duration: const Duration(milliseconds: 800),
      ),
      isFalse,
    );
    expect(
      tracker.observe(
        processingState: ProcessingState.completed,
        playing: true,
        position: const Duration(milliseconds: 800),
        duration: const Duration(milliseconds: 800),
      ),
      isTrue,
    );
  });
}
