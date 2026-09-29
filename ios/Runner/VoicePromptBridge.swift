import AVFoundation
import Flutter
import Foundation

struct IOSPromptOperationLeaseState {
  private var activeTokens: Set<UUID> = []

  var activeToken: UUID? { activeTokens.count == 1 ? activeTokens.first : nil }

  mutating func activate(_ token: UUID) {
    activeTokens.insert(token)
  }

  @discardableResult
  mutating func release(_ token: UUID) -> Bool {
    activeTokens.remove(token) != nil
  }
}

enum IOSPromptOutputRoutePolicy {
  static func expectsHfp(
    forcePhoneSpeaker: Bool,
    hasAvailableHfpInput: Bool,
    retainedBackgroundHfpRoute: Bool
  ) -> Bool {
    // The coordinator preserves a prearmed background input graph. Its real
    // HFP output still needs loss monitoring even if a legacy caller asks for
    // the handset. Otherwise, explicit phone playback never waits for HFP.
    retainedBackgroundHfpRoute || (!forcePhoneSpeaker && hasAvailableHfpInput)
  }
}

enum IOSPromptSpeechStyle {
  static func apply(
    to utterance: AVSpeechUtterance,
    speechRate: Float?,
    pitch: Float?
  ) {
    // Dart sends a rate multiplier, while AVSpeechUtterance expects its own
    // bounded rate. Keep unstyled coach/MAIN speech at the existing default.
    let rateMultiplier = speechRate.flatMap { $0.isFinite ? $0 : nil } ?? 1.0
    utterance.rate = max(
      AVSpeechUtteranceMinimumSpeechRate,
      min(AVSpeechUtteranceMaximumSpeechRate,
          AVSpeechUtteranceDefaultSpeechRate * max(0.5, min(1.5, rateMultiplier)))
    )
    let pitchMultiplier = pitch.flatMap { $0.isFinite ? $0 : nil } ?? 1.0
    utterance.pitchMultiplier = max(0.8, min(1.2, pitchMultiplier))
  }
}

struct IOSPromptPlaybackLevel {
  let gainDb: Double
  let measuredDb: Double
  let peakDb: Double
  let activeWindowCount: Int
}

/// Matches Android's gated PCM meter, including weighting the final partial
/// window by its actual sample count. This is sample-peak/RMS, not LUFS.
struct IOSPromptPlaybackLevelMeter {
  private struct Window {
    let energy: Double
    let count: Int
  }

  private let channelCount: Int
  private let windowSamples: Int
  private var windows: [Window] = []
  private var energy = 0.0
  private var windowCount = 0
  private var sampleCount = 0
  private var peak = 0.0
  private var valid = true

  init(sampleRate: Int, channelCount: Int) {
    self.channelCount = max(1, channelCount)
    windowSamples = max(1, sampleRate / 50) * max(1, channelCount)
    valid = sampleRate > 0 && channelCount > 0
  }

  mutating func addSample(_ sample: Double) {
    guard sample.isFinite else { valid = false; return }
    peak = max(peak, abs(sample))
    energy += sample * sample
    windowCount += 1
    sampleCount += 1
    if windowCount == windowSamples {
      windows.append(Window(energy: energy, count: windowCount))
      energy = 0
      windowCount = 0
    }
  }

  func result() -> IOSPromptPlaybackLevel? {
    guard valid, sampleCount > 0, sampleCount % channelCount == 0 else { return nil }
    let complete = windowCount > 0
      ? windows + [Window(energy: energy, count: windowCount)] : windows
    let strongest = complete.map { $0.energy / Double(windowSamples) }.max() ?? 0
    let gate = max(0.00001, strongest / 1000)
    let active = complete.filter { $0.energy / Double(windowSamples) >= gate }
    let peakDb = peak > 0 ? 20 * log10(peak) : -120
    guard !active.isEmpty else {
      let meanSquare = complete.reduce(0) { $0 + $1.energy } / Double(sampleCount)
      return IOSPromptPlaybackLevel(
        gainDb: 0,
        measuredDb: meanSquare > 0 ? 10 * log10(meanSquare) : -120,
        peakDb: peakDb,
        activeWindowCount: 0
      )
    }
    let meanSquare = active.reduce(0) { $0 + $1.energy }
      / Double(active.reduce(0) { $0 + $1.count })
    let measuredDb = 10 * log10(meanSquare)
    return IOSPromptPlaybackLevel(
      gainDb: min(min(-21 - measuredDb, 28), -1 - peakDb),
      measuredDb: measuredDb,
      peakDb: peakDb,
      activeWindowCount: active.count
    )
  }
}

enum IOSPromptPlaybackAudio {
  static func requestedGainDb(_ value: Double?) -> Double {
    let finite = value.flatMap { $0.isFinite ? $0 : nil } ?? 8
    return max(0, min(12, finite))
  }

  /// Called on a worker. Only complete short clips can be boosted: measuring
  /// the beginning of a longer clip could miss a loud ending and cause clipping.
  static func prepare(source: URL, output: URL) throws -> IOSPromptPlaybackLevel {
    let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = input.processingFormat
    guard format.sampleRate >= 8_000, format.sampleRate <= 192_000,
      format.channelCount > 0, format.channelCount <= 8,
      input.length > 0, input.length <= AVAudioFramePosition(format.sampleRate * 30),
      input.length * AVAudioFramePosition(format.channelCount) <= 16 * 1024 * 1024,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2_048)
    else { throw PromptPlaybackPreparationError.unsupportedAudio }
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    var meter = IOSPromptPlaybackLevelMeter(
      sampleRate: Int(format.sampleRate), channelCount: Int(format.channelCount)
    )
    while input.framePosition < input.length {
      guard ProcessInfo.processInfo.systemUptime < deadline else {
        throw PromptPlaybackPreparationError.timedOut
      }
      try input.read(into: buffer)
      guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
        throw PromptPlaybackPreparationError.unsupportedAudio
      }
      for frame in 0..<Int(buffer.frameLength) {
        for channel in 0..<Int(format.channelCount) {
          meter.addSample(Double(channels[channel][frame]))
        }
      }
    }
    guard let level = meter.result() else { throw PromptPlaybackPreparationError.unsupportedAudio }
    input.framePosition = 0
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: Int(format.channelCount),
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]
    // Scope the writer so its WAV header is finalized before AVAudioPlayer opens it.
    do {
      let writer = try AVAudioFile(
        forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false
      )
      let multiplier = Float(pow(10, level.gainDb / 20))
      while input.framePosition < input.length {
        guard ProcessInfo.processInfo.systemUptime < deadline else {
          throw PromptPlaybackPreparationError.timedOut
        }
        try input.read(into: buffer)
        guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
          throw PromptPlaybackPreparationError.unsupportedAudio
        }
        for channel in 0..<Int(format.channelCount) {
          for frame in 0..<Int(buffer.frameLength) { channels[channel][frame] *= multiplier }
        }
        try writer.write(from: buffer)
      }
    }
    return level
  }
}

/// The synthesis callback owns its buffer only during the call. Write it under
/// a short lock, then decode/match the completed file off the main thread.
final class IOSPromptSynthesisOperation {
  let source: URL
  let output: URL
  private let lock = NSLock()
  private var writer: AVAudioFile?
  private var cancelled = false
  private var finished = false

  init(token: UUID) {
    let directory = FileManager.default.temporaryDirectory
    source = directory.appendingPathComponent("homi-prompt-\(token.uuidString).caf")
    output = directory.appendingPathComponent("homi-prompt-\(token.uuidString).wav")
  }

  func accept(_ buffer: AVAudioBuffer, completion: @escaping (Result<Void, Error>) -> Void) {
    lock.lock()
    guard !cancelled, !finished else { lock.unlock(); return }
    do {
      guard let pcm = buffer as? AVAudioPCMBuffer else {
        throw PromptPlaybackPreparationError.unsupportedAudio
      }
      if pcm.frameLength == 0 {
        writer = nil
        finished = true
        lock.unlock()
        completion(.success(()))
        return
      }
      if writer == nil {
        writer = try AVAudioFile(
          forWriting: source, settings: pcm.format.settings,
          commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved
        )
      }
      try writer?.write(from: pcm)
      lock.unlock()
    } catch {
      writer = nil
      finished = true
      lock.unlock()
      completion(.failure(error))
    }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    writer = nil
    lock.unlock()
    removeFiles()
  }

  var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  func removeFiles() {
    try? FileManager.default.removeItem(at: source)
    try? FileManager.default.removeItem(at: output)
  }
}

private enum PromptPlaybackPreparationError: Error {
  case unsupportedAudio
  case timedOut
}

/// Native iOS prompt output for the fixed MAIN assistant. Keeping prompts in
/// AVSpeechSynthesizer or verified bundled audio avoids a network round trip
/// before command recognition. Both use the existing MAIN audio-session owner.
final class VoicePromptBridge: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private let synthesizer = AVSpeechSynthesizer()
  private var waitingResult: FlutterResult?
  private var readyCueResults: [FlutterResult] = []
  private var readyCueToken: UUID?
  private var readyCueExpectsHfp = false
  private var readyCueAudioToken: UUID?
  private var readyCueFallback: DispatchWorkItem?
  private var readyCuePlayer: AVAudioPlayer?
  private var activeUtterance: AVSpeechUtterance?
  private var activeUtteranceAudioToken: UUID?
  private var activeUtteranceExpectsHfp = false
  private var synthesisOperation: IOSPromptSynthesisOperation?
  private var synthesisTimeout: DispatchWorkItem?
  private var authoredPromptPlayer: AVAudioPlayer?
  private var authoredPromptAudioToken: UUID?
  private var authoredPromptExpectsHfp = false
  private var authoredPromptFiles: [URL] = []
  private var routeChangeToken: NSObjectProtocol?
  private var interruptionToken: NSObjectProtocol?
  private var promptOperationLeases = IOSPromptOperationLeaseState()
  private var disposed = false

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionCoordinator: IOSAudioSessionCoordinator
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
    channel = FlutterMethodChannel(name: "ailingo_voice_prompt", binaryMessenger: messenger)
    super.init()
    synthesizer.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    routeChangeToken = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: audioSessionCoordinator.session,
      queue: .main
    ) { [weak self] _ in
      self?.stopPlaybackIfSelectedHfpRouteWasLost()
    }
    interruptionToken = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: audioSessionCoordinator.session,
      queue: .main
    ) { [weak self] notification in
      let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
      guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
      self?.interruptPlayback()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed else {
      result(FlutterError(code: "VOICE_PROMPT_DISPOSED", message: "Bộ đọc đã đóng.", details: nil))
      return
    }
    switch call.method {
    case "beginMainTurn":
      let arguments = call.arguments as? [String: Any]
      let turnId = audioSessionCoordinator.beginMainTurn(
        source: "VoicePromptBridge.beginMainTurn",
        audioInputTarget: IOSMainTurnAudioRoutePolicy.inputTarget(
          fromChannelValue: arguments?["audioSource"]
        ),
        // A cancelled begin can return after the next virtual MAIN activation.
        // Its exact-ID cleanup must never close that newer activation.
        forceNewTurn: true
      )
      // Arm the record-capable engine before Flutter starts the assistant
      // prompt. If the app moves to background while that prompt is speaking,
      // Apple Speech can reuse this running engine instead of trying to create
      // a new input graph after iOS has suspended foreground-only startup.
      audioSessionCoordinator.requestBackgroundCaptureArm(
        caller: "VoicePromptBridge.beginMainTurn"
      ) {
        result(turnId)
      }
    case "endMainTurn":
      let arguments = call.arguments as? [String: Any]
      guard let turnId = arguments?["turnId"] as? String, !turnId.isEmpty else {
        audioSessionCoordinator.trace(
          stage: "main_turn_end_missing_id_ignored",
          caller: "VoicePromptBridge.endMainTurn",
          message: arguments?["reason"] as? String ?? "dart_requested"
        )
        result(nil)
        return
      }
      audioSessionCoordinator.endMainTurn(
        reason: arguments?["reason"] as? String ?? "dart_requested",
        caller: "VoicePromptBridge.endMainTurn",
        expectedTurnId: turnId
      )
      result(nil)
    case "playAuthoredAudioAndWait":
      let arguments = call.arguments as? [String: Any]
      guard let bytes = arguments?["bytes"] as? FlutterStandardTypedData,
            !bytes.data.isEmpty, bytes.data.count <= 2 * 1024 * 1024 else {
        result(FlutterError(code: "INVALID_PROMPT_AUDIO", message: "Invalid authored prompt bytes.", details: nil))
        return
      }
      playAuthoredPrompt(
        bytes.data,
        gainDb: IOSPromptPlaybackAudio.requestedGainDb((arguments?["gainDb"] as? NSNumber)?.doubleValue),
        forcePhoneSpeaker: arguments?["forcePhoneSpeaker"] as? Bool ?? false,
        forceMediaPlayback: arguments?["forceMediaPlayback"] as? Bool ?? false,
        result: result
      )
    case "speak", "speakAndWait":
      let arguments = call.arguments as? [String: Any]
      let text = (arguments?["text"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let locale = arguments?["locale"] as? String ?? "vi-VN"
      let forcePhoneSpeaker = arguments?["forcePhoneSpeaker"] as? Bool ?? false
      let forceMediaPlayback = arguments?["forceMediaPlayback"] as? Bool ?? false
      speak(
        text,
        locale: locale,
        gainDb: IOSPromptPlaybackAudio.requestedGainDb((arguments?["gainDb"] as? NSNumber)?.doubleValue),
        forcePhoneSpeaker: forcePhoneSpeaker,
        forceMediaPlayback: forceMediaPlayback,
        speechRate: (arguments?["speechRate"] as? NSNumber)?.floatValue,
        pitch: (arguments?["pitch"] as? NSNumber)?.floatValue,
        waitForCompletion: call.method == "speakAndWait",
        result: result
      )
    case "playSpeechReadyCue":
      playSpeechReadyCue(result)
    case "normalizeLessonRecording":
      let arguments = call.arguments as? [String: Any]
      guard let path = arguments?["path"] as? String, !path.isEmpty else {
        result(FlutterError(code: "INVALID_RECORDING_PATH", message: "Missing recording path.", details: nil))
        return
      }
      normalizeLessonRecording(path: path, result: result)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Decodes the child's short lesson capture, levels it with
  /// `levelLessonRecording`, and writes a PCM WAV sibling. Authored prompts
  /// never pass through this path, so their established loudness is untouched.
  private func normalizeLessonRecording(path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let sourceURL = URL(fileURLWithPath: path)
        let input = try AVAudioFile(forReading: sourceURL)
        let format = input.processingFormat
        guard input.length > 0,
              input.length <= AVAudioFramePosition(format.sampleRate * 12)
        else {
          throw LessonRecordingNormalizationError.invalidRecording
        }
        let frameLength = AVAudioFrameCount(input.length)
        guard
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength)
        else {
          throw LessonRecordingNormalizationError.invalidRecording
        }
        try input.read(into: buffer, frameCount: frameLength)
        guard let channels = buffer.floatChannelData else {
          throw LessonRecordingNormalizationError.unsupportedPcm
        }
        guard Self.levelLessonRecording(
          channels: channels,
          channelCount: Int(format.channelCount),
          frameLength: Int(buffer.frameLength),
          sampleRate: format.sampleRate
        ) else {
          DispatchQueue.main.async { result(path) }
          return
        }
        let outputURL = sourceURL.deletingPathExtension()
          .appendingPathExtension("normalized.wav")
        try? FileManager.default.removeItem(at: outputURL)
        let settings: [String: Any] = [
          AVFormatIDKey: kAudioFormatLinearPCM,
          AVSampleRateKey: format.sampleRate,
          AVNumberOfChannelsKey: Int(format.channelCount),
          AVLinearPCMBitDepthKey: 16,
          AVLinearPCMIsFloatKey: false,
          AVLinearPCMIsBigEndianKey: false,
        ]
        let output = try AVAudioFile(
          forWriting: outputURL,
          settings: settings,
          commonFormat: .pcmFormatFloat32,
          interleaved: false
        )
        try output.write(from: buffer)
        try? FileManager.default.removeItem(at: sourceURL)
        DispatchQueue.main.async { result(outputURL.path) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "LESSON_RECORDING_NORMALIZATION_FAILED",
            message: "Unable to normalize lesson recording.",
            details: error.localizedDescription
          ))
        }
      }
    }
  }

  /// Gated speech level of a saved child recording. Mirrors
  /// `lessonRecordingTargetDbfs` in lesson_wav_normalizer.dart.
  static let lessonRecordingTargetDbfs = -17.0
  private static let lessonRecordingPeakCeilingDbfs = -1.0
  /// Most a quiet recording is raised; more mostly raises the room's hiss.
  private static let lessonRecordingMaxGainDb = 20.0
  /// Most the pauses between words are turned down, so a raised recording
  /// does not replay its background noise at speech level.
  private static let lessonRecordingPauseCutDb = 10.0

  /// Brings a lesson recording, quiet or loud, to one speech level in place.
  /// Pauses are excluded from the measurement. A look-ahead limiter, linked
  /// across channels, keeps peaks under -1 dBFS so one plosive does not cap
  /// the gain of the whole recording. A recording that is only steady noise
  /// is never raised, and pauses are turned down by up to 10 dB so the raised
  /// noise floor does not hiss. Mirrors `normalizeLessonWavLoudness`.
  /// Returns false when nothing changed.
  static func levelLessonRecording(
    channels: UnsafePointer<UnsafeMutablePointer<Float>>,
    channelCount: Int,
    frameLength: Int,
    sampleRate: Double
  ) -> Bool {
    let windowFrames = max(1, Int(sampleRate / 50.0))
    var windowEnergies: [Double] = []
    var peak = 0.0
    var start = 0
    while start < frameLength {
      let end = min(frameLength, start + windowFrames)
      var energy = 0.0
      for frame in start..<end {
        for channel in 0..<channelCount {
          let sample = Double(channels[channel][frame])
          peak = max(peak, abs(sample))
          energy += sample * sample
        }
      }
      let count = max(1, (end - start) * channelCount)
      windowEnergies.append(energy / Double(count))
      start = end
    }
    // A click fills at most two 20 ms windows. Leaving the two strongest out
    // keeps it from setting the gate or the level; the limiter holds its peak.
    let ranked = windowEnergies.sorted(by: >)
    let measured = ranked.count > 2 ? Array(ranked.dropFirst(2)) : ranked
    guard let strongest = measured.first, strongest > 0, peak > 0 else { return false }
    let gate = max(pow(10.0, -50.0 / 10.0), strongest / 1000.0)
    let active = measured.filter { $0 >= gate }
    guard !active.isEmpty else { return false }
    let rmsPower = active.reduce(0, +) / Double(active.count)
    let measuredDb = 10.0 * log10(rmsPower)
    // The quietest tenth of the recording is its background noise.
    let floorPower = max(1e-10, ranked[ranked.count - 1 - ranked.count / 10])
    let separationDb = measuredDb - 10.0 * log10(floorPower)
    var gainDb = min(lessonRecordingMaxGainDb, lessonRecordingTargetDbfs - measuredDb)
    // Under 100 ms above the gate is a knock, not speech; never turn the child
    // down to match it.
    let knockOnly = active.count < 5
    if knockOnly { gainDb = max(0, gainDb) }
    // Nothing rises 6 dB over the noise: raising it would only replay hiss.
    if separationDb < 6 { gainDb = min(0, gainDb) }
    let multiplier = pow(10.0, gainDb / 20.0)
    let ceiling = pow(10.0, lessonRecordingPeakCeilingDbfs / 20.0)
    guard abs(gainDb) > 0.05 || peak * multiplier > ceiling else { return false }

    // Ramp the reduction down over 5 ms before a peak and back up over 60 ms,
    // so limiting does not click or pump.
    let attackStep = 1.0 / max(1.0, (sampleRate * 0.005).rounded(.down))
    let releaseStep = 1.0 / max(1.0, (sampleRate * 0.06).rounded(.down))
    var reduction = [Double](repeating: 1, count: frameLength)
    var next = 1.0
    for frame in stride(from: frameLength - 1, through: 0, by: -1) {
      var level = 0.0
      for channel in 0..<channelCount {
        level = max(level, abs(Double(channels[channel][frame])) * multiplier)
      }
      next = min(level > ceiling ? ceiling / level : 1.0, next + attackStep)
      reduction[frame] = next
    }
    let pauses = pauseGain(
      windowEnergies: windowEnergies,
      windowFrames: windowFrames,
      frameLength: frameLength,
      sampleRate: sampleRate,
      // Halfway, in dB, between the noise floor and the speech level.
      threshold: (floorPower * rmsPower).squareRoot(),
      // Noisy recordings get a shallower cut, so the gate does not chatter.
      cutDb: knockOnly ? 0 : min(max(separationDb - 6, 0), lessonRecordingPauseCutDb)
    )
    var previous = 1.0
    for frame in 0..<frameLength {
      previous = min(reduction[frame], previous + releaseStep)
      let gain = Float(multiplier * previous * pauses[frame])
      for channel in 0..<channelCount {
        channels[channel][frame] *= gain
      }
    }
    return true
  }

  /// Per-frame gain that turns 20 ms windows under `threshold` down by
  /// `cutDb`. It stays open 200 ms after speech, opens 20 ms before it and
  /// closes over 100 ms, so word edges and short gaps are never cut.
  private static func pauseGain(
    windowEnergies: [Double],
    windowFrames: Int,
    frameLength: Int,
    sampleRate: Double,
    threshold: Double,
    cutDb: Double
  ) -> [Double] {
    var gain = [Double](repeating: 1, count: frameLength)
    guard cutDb > 0, frameLength > 0 else { return gain }
    let floor = pow(10.0, -cutDb / 20.0)
    let holdWindows = 10
    var sinceSpeech = holdWindows + 1
    for (window, energy) in windowEnergies.enumerated() {
      sinceSpeech = energy >= threshold ? 0 : sinceSpeech + 1
      guard sinceSpeech > holdWindows else { continue }
      let start = window * windowFrames
      for frame in start..<min(frameLength, start + windowFrames) {
        gain[frame] = floor
      }
    }
    let closeStep = (1 - floor) / max(1.0, (sampleRate / 10).rounded(.down))
    let openStep = (1 - floor) / max(1.0, (sampleRate / 50).rounded(.down))
    var previous = 1.0
    for frame in 0..<frameLength {
      previous = max(gain[frame], previous - closeStep)
      gain[frame] = previous
    }
    var next = gain[frameLength - 1]
    for frame in stride(from: frameLength - 1, through: 0, by: -1) {
      next = max(gain[frame], next - openStep)
      gain[frame] = next
    }
    return gain
  }

  private func speak(
    _ text: String,
    locale: String,
    gainDb: Double,
    forcePhoneSpeaker: Bool,
    forceMediaPlayback: Bool,
    speechRate: Float?,
    pitch: Float?,
    waitForCompletion: Bool,
    result: @escaping FlutterResult
  ) {
    guard !text.isEmpty else {
      result(nil)
      return
    }
    stop()
    guard let audioToken = configurePromptAudioSession(
      forcePhoneSpeaker: forcePhoneSpeaker,
      forceMediaPlayback: forceMediaPlayback
    ) else {
      result(FlutterError(
        code: "PROMPT_AUDIO_ROUTE_FAILED",
        message: "Unable to prepare prompt route.",
        details: nil
      ))
      return
    }
    audioSessionCoordinator.trace(stage: "prompt_started", caller: "VoicePromptBridge.speak")
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: locale)
      ?? AVSpeechSynthesisVoice(language: "vi-VN")
    IOSPromptSpeechStyle.apply(to: utterance, speechRate: speechRate, pitch: pitch)
    utterance.volume = 1.0
    activeUtterance = utterance
    activeUtteranceAudioToken = audioToken
    waitingResult = result
    let expectsHfp = promptExpectsHfp(forcePhoneSpeaker: forcePhoneSpeaker)
    waitForSelectedPromptRoute(
      expectsHfp: expectsHfp,
      attemptsRemaining: 20,
      isCurrent: { [weak self] in
        guard let self else { return false }
        return self.activeUtterance === utterance
          && self.activeUtteranceAudioToken == audioToken
      }
    ) { [weak self] routeReady in
      guard let self,
        self.activeUtterance === utterance,
        self.activeUtteranceAudioToken == audioToken
      else { return }
      guard routeReady else {
        self.activeUtterance = nil
        self.activeUtteranceAudioToken = nil
        self.releasePromptAudioSession(token: audioToken)
        self.completeWaitingResult(error: FlutterError(
          code: "PROMPT_AUDIO_ROUTE_FAILED",
          message: "The selected HFP output did not become ready.",
          details: nil
        ))
        return
      }
      if !waitForCompletion {
        self.completeWaitingResult()
      }
      self.activeUtteranceExpectsHfp = expectsHfp
      self.synthesizePrompt(utterance, audioToken: audioToken, gainDb: gainDb)
    }
  }

  private func synthesizePrompt(_ utterance: AVSpeechUtterance, audioToken: UUID, gainDb: Double) {
    let operation = IOSPromptSynthesisOperation(token: audioToken)
    synthesisOperation = operation
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.activeUtteranceAudioToken == audioToken else { return }
      self.failSynthesizedPrompt(audioToken: audioToken, code: "PROMPT_SYNTHESIS_TIMEOUT")
    }
    synthesisTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(30), execute: timeout)
    audioSessionCoordinator.trace(
      stage: "prompt_synthesis_started", caller: "VoicePromptBridge.synthesizePrompt",
      values: ["requestedGainDb": gainDb]
    )
    synthesizer.write(utterance) { [weak self] buffer in
      operation.accept(buffer) { outcome in
        DispatchQueue.main.async {
          guard let self, self.activeUtteranceAudioToken == audioToken,
            self.synthesisOperation === operation else { operation.cancel(); return }
          switch outcome {
          case .failure:
            self.failSynthesizedPrompt(audioToken: audioToken, code: "PROMPT_SYNTHESIS_FAILED")
          case .success:
            self.prepareSynthesizedPrompt(operation, audioToken: audioToken, gainDb: gainDb)
          }
        }
      }
    }
  }

  private func prepareSynthesizedPrompt(
    _ operation: IOSPromptSynthesisOperation, audioToken: UUID, gainDb: Double
  ) {
    // Synthesis delegate completion is not playback completion. Keep this same
    // audio lease until the locally rendered clip actually finishes playing.
    synthesisTimeout?.cancel()
    synthesisTimeout = nil
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard !operation.isCancelled else { operation.removeFiles(); return }
      let measured = try? IOSPromptPlaybackAudio.prepare(source: operation.source, output: operation.output)
      guard !operation.isCancelled else { operation.removeFiles(); return }
      let url = measured == nil ? operation.source : operation.output
      DispatchQueue.main.async {
        guard let self, self.activeUtteranceAudioToken == audioToken,
          self.synthesisOperation === operation else { operation.cancel(); return }
        let expectsHfp = self.activeUtteranceExpectsHfp
        self.activeUtterance = nil
        self.activeUtteranceAudioToken = nil
        self.activeUtteranceExpectsHfp = false
        self.synthesisOperation = nil
        self.authoredPromptAudioToken = audioToken
        self.authoredPromptFiles = [operation.source, operation.output]
        self.startPreparedPrompt(url, token: audioToken, expectsHfp: expectsHfp,
                                 gainDb: measured?.gainDb ?? 0, requestedGainDb: gainDb)
      }
    }
  }

  private func failSynthesizedPrompt(audioToken: UUID, code: String) {
    guard activeUtteranceAudioToken == audioToken else { return }
    activeUtterance = nil
    activeUtteranceAudioToken = nil
    activeUtteranceExpectsHfp = false
    synthesisTimeout?.cancel()
    synthesisTimeout = nil
    synthesisOperation?.cancel()
    synthesisOperation = nil
    synthesizer.stopSpeaking(at: .immediate)
    releasePromptAudioSession(token: audioToken)
    completeWaitingResult(error: FlutterError(code: code, message: "Unable to render prompt audio.", details: nil))
  }

  private func waitForSelectedPromptRoute(
    expectsHfp: Bool,
    attemptsRemaining: Int,
    isCurrent: @escaping () -> Bool,
    completion: @escaping (Bool) -> Void
  ) {
    guard isCurrent() else { return }
    if !expectsHfp || audioSessionCoordinator.hasSelectedTwoWayHfpRoute() {
      completion(true)
      return
    }
    guard attemptsRemaining > 0 else {
      completion(false)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
      self?.waitForSelectedPromptRoute(
        expectsHfp: expectsHfp,
        attemptsRemaining: attemptsRemaining - 1,
        isCurrent: isCurrent,
        completion: completion
      )
    }
  }

  @discardableResult
  private func configurePromptAudioSession(
    forcePhoneSpeaker: Bool = false,
    forceMediaPlayback: Bool = false
  ) -> UUID? {
    let audioToken = UUID()
    // Match Android's explicit phone-output request even when a paired HFP
    // input remains available. The coordinator may retain an already-running
    // background capture graph; the playback guard follows that actual route.
    if IOSMainTurnAudioRoutePolicy.forcesPhoneSpeaker(
      explicitRequest: forcePhoneSpeaker,
      mainInputTarget: audioSessionCoordinator.mainAudioInputTarget
    ) {
      do {
        try audioSessionCoordinator.preparePhoneSpeaker(
          caller: "VoicePromptBridge.configurePromptAudioSession"
        )
        promptOperationLeases.activate(audioToken)
        return audioToken
      } catch {
        audioSessionCoordinator.trace(
          stage: "prompt_audio_error",
          caller: "VoicePromptBridge.configurePromptAudioSession",
          code: "PHONE_PROMPT_AUDIO_SESSION_FAILED",
          message: error.localizedDescription
        )
        return nil
      }
    }
    let preferredHfpInput = audioSessionCoordinator.selectedOrAvailableHfpInput()
    if IOSMainTurnAudioRoutePolicy.requiresHfp(
      mainInputTarget: audioSessionCoordinator.mainAudioInputTarget,
      explicitPhoneRequest: forcePhoneSpeaker
    ), preferredHfpInput == nil {
      audioSessionCoordinator.trace(
        stage: "prompt_audio_error",
        caller: "VoicePromptBridge.configurePromptAudioSession",
        code: "MAIN_HFP_INPUT_UNAVAILABLE"
      )
      return nil
    }
    // A selected H20 must keep assistant speech on its HFP route. Media
    // playback is only used if that route is genuinely unavailable, such as
    // after the H20 has been disconnected.
    if forceMediaPlayback, preferredHfpInput == nil {
      do {
        try audioSessionCoordinator.prepareMediaPlayback(
          caller: "VoicePromptBridge.configurePromptAudioSession"
        )
        promptOperationLeases.activate(audioToken)
        return audioToken
      } catch {
        audioSessionCoordinator.trace(
          stage: "prompt_audio_error",
          caller: "VoicePromptBridge.configurePromptAudioSession",
          code: "MEDIA_PROMPT_AUDIO_SESSION_FAILED",
          message: error.localizedDescription
        )
        return nil
      }
    }
    do {
      _ = try audioSessionCoordinator.preparePrompt(
        preferredHfpInput: preferredHfpInput,
        caller: "VoicePromptBridge.configurePromptAudioSession"
      )
      promptOperationLeases.activate(audioToken)
      return audioToken
    } catch {
      audioSessionCoordinator.trace(
        stage: "prompt_audio_error",
        caller: "VoicePromptBridge.configurePromptAudioSession",
        code: "PROMPT_AUDIO_SESSION_FAILED",
        message: error.localizedDescription
      )
      return nil
    }
  }

  private func promptExpectsHfp(forcePhoneSpeaker: Bool) -> Bool {
    let usesPhoneSpeaker = IOSMainTurnAudioRoutePolicy.forcesPhoneSpeaker(
      explicitRequest: forcePhoneSpeaker,
      mainInputTarget: audioSessionCoordinator.mainAudioInputTarget
    )
    return IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: usesPhoneSpeaker,
      hasAvailableHfpInput: !usesPhoneSpeaker
        && audioSessionCoordinator.selectedOrAvailableHfpInput() != nil,
      retainedBackgroundHfpRoute: audioSessionCoordinator.isBackgroundCaptureEngineRunning
        && audioSessionCoordinator.hasSelectedTwoWayHfpRoute()
    )
  }

  private func stop() {
    let hadActiveSynthesis = synthesisOperation != nil
    synthesisTimeout?.cancel()
    synthesisTimeout = nil
    synthesisOperation?.cancel()
    synthesisOperation = nil
    let authoredAudioToken = authoredPromptAudioToken
    authoredPromptAudioToken = nil
    authoredPromptPlayer?.delegate = nil
    authoredPromptPlayer?.stop()
    authoredPromptPlayer = nil
    removeAuthoredPromptFiles()
    let utteranceAudioToken = activeUtteranceAudioToken
    activeUtterance = nil
    activeUtteranceAudioToken = nil
    activeUtteranceExpectsHfp = false
    authoredPromptExpectsHfp = false
    if hadActiveSynthesis || synthesizer.isSpeaking || synthesizer.isPaused {
      synthesizer.stopSpeaking(at: .immediate)
    }
    completeWaitingResult()
    completeReadyCue()
    releasePromptAudioSession(token: utteranceAudioToken)
    releasePromptAudioSession(token: authoredAudioToken)
  }

  private func playAuthoredPrompt(
    _ data: Data,
    gainDb: Double,
    forcePhoneSpeaker: Bool,
    forceMediaPlayback: Bool,
    result: @escaping FlutterResult
  ) {
    stop()
    guard let token = configurePromptAudioSession(
      forcePhoneSpeaker: forcePhoneSpeaker,
      forceMediaPlayback: forceMediaPlayback
    ) else {
      result(FlutterError(code: "PROMPT_AUDIO_ROUTE_FAILED", message: "Unable to prepare prompt route.", details: nil))
      return
    }
    authoredPromptAudioToken = token
    waitingResult = result
    audioSessionCoordinator.trace(stage: "prompt_started", caller: "VoicePromptBridge.playAuthoredPrompt")
    let expectsHfp = promptExpectsHfp(forcePhoneSpeaker: forcePhoneSpeaker)
    let directory = FileManager.default.temporaryDirectory
    let source = directory.appendingPathComponent("homi-authored-\(token.uuidString).mp3")
    let output = directory.appendingPathComponent("homi-authored-\(token.uuidString).wav")
    authoredPromptFiles = [source, output]
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let prepared: Result<(URL, Double), Error>
      do {
        try data.write(to: source, options: .atomic)
        let measured = try? IOSPromptPlaybackAudio.prepare(source: source, output: output)
        prepared = .success((measured == nil ? source : output, measured?.gainDb ?? 0))
      } catch {
        prepared = .failure(error)
      }
      DispatchQueue.main.async {
        guard let self, self.authoredPromptAudioToken == token else {
          try? FileManager.default.removeItem(at: source)
          try? FileManager.default.removeItem(at: output)
          return
        }
        switch prepared {
        case let .success((url, appliedGain)):
          self.startPreparedPrompt(url, token: token, expectsHfp: expectsHfp,
                                   gainDb: appliedGain, requestedGainDb: gainDb)
        case .failure:
          self.finishAuthoredPrompt(success: false)
        }
      }
    }
  }

  private func startPreparedPrompt(
    _ url: URL, token: UUID, expectsHfp: Bool, gainDb: Double, requestedGainDb: Double
  ) {
    waitForSelectedPromptRoute(
      expectsHfp: expectsHfp, attemptsRemaining: 20,
      isCurrent: { [weak self] in self?.authoredPromptAudioToken == token }
    ) { [weak self] routeReady in
      guard let self, self.authoredPromptAudioToken == token else { return }
      guard routeReady else {
        self.finishAuthoredPrompt(success: false, errorCode: "PROMPT_AUDIO_ROUTE_FAILED")
        return
      }
      self.startAuthoredPromptPlayback(url, expectsHfp: expectsHfp,
                                       gainDb: gainDb, requestedGainDb: requestedGainDb)
    }
  }

  private func startAuthoredPromptPlayback(
    _ url: URL, expectsHfp: Bool, gainDb: Double, requestedGainDb: Double
  ) {
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      authoredPromptPlayer = player
      player.delegate = self
      player.volume = 1.0
      player.numberOfLoops = 0
      player.prepareToPlay()
      authoredPromptExpectsHfp = expectsHfp
      // Speed was applied once during offline generation; playback stays at 1x.
      guard player.play() else { throw ReadyCueError.playbackFailed }
      audioSessionCoordinator.trace(
        stage: "prompt_playback_active", caller: "VoicePromptBridge.playAuthoredPrompt",
        values: ["gainDb": gainDb, "requestedGainDb": requestedGainDb]
      )
      audioSessionCoordinator.backgroundAudioActivityDidStart(caller: "VoicePromptBridge.playAuthoredPrompt")
    } catch {
      finishAuthoredPrompt(success: false)
    }
  }

  private func finishAuthoredPrompt(success: Bool, errorCode: String = "PROMPT_AUDIO_FAILED") {
    authoredPromptPlayer?.delegate = nil
    authoredPromptPlayer?.stop()
    authoredPromptPlayer = nil
    removeAuthoredPromptFiles()
    let token = authoredPromptAudioToken
    authoredPromptAudioToken = nil
    authoredPromptExpectsHfp = false
    releasePromptAudioSession(token: token)
    let result = waitingResult
    waitingResult = nil
    if success {
      audioSessionCoordinator.trace(stage: "prompt_finished", caller: "VoicePromptBridge.finishAuthoredPrompt")
      audioSessionCoordinator.trace(stage: "prompt_done", caller: "VoicePromptBridge.finishAuthoredPrompt")
      result?(nil)
    } else {
      result?(FlutterError(code: errorCode, message: "Unable to play authored prompt.", details: nil))
    }
  }

  private func removeAuthoredPromptFiles() {
    let files = authoredPromptFiles
    authoredPromptFiles.removeAll()
    for url in files { try? FileManager.default.removeItem(at: url) }
  }

  private func interruptPlayback() {
    guard activeUtteranceAudioToken != nil || authoredPromptAudioToken != nil || readyCueToken != nil else {
      return
    }
    audioSessionCoordinator.trace(
      stage: "prompt_interrupted", caller: "VoicePromptBridge.interruption",
      code: "AUDIO_SESSION_INTERRUPTED"
    )
    completeWaitingResult(error: FlutterError(
      code: "AUDIO_SESSION_INTERRUPTED", message: "Prompt playback was interrupted.", details: nil
    ))
    completeReadyCue(errorCode: "AUDIO_SESSION_INTERRUPTED")
    stop()
  }

  private func completeWaitingResult(error: FlutterError? = nil) {
    let result = waitingResult
    waitingResult = nil
    result?(error)
  }

  /// A live H20 prompt must never continue on the handset after iOS drops its
  /// two-way Bluetooth route. Synthesis also aborts once its prepared HFP route
  /// is lost; a finished file cannot silently pick a different output later.
  private func stopPlaybackIfSelectedHfpRouteWasLost() {
    guard !disposed else { return }
    let cueIsPlayingOnHfp = readyCueExpectsHfp && readyCuePlayer != nil
    let speechIsPlayingOnHfp = activeUtteranceExpectsHfp && activeUtterance != nil
    let authoredIsPlayingOnHfp = authoredPromptExpectsHfp && authoredPromptPlayer != nil
    guard cueIsPlayingOnHfp || speechIsPlayingOnHfp || authoredIsPlayingOnHfp,
      !audioSessionCoordinator.hasSelectedTwoWayHfpRoute()
    else { return }

    audioSessionCoordinator.trace(
      stage: "prompt_hfp_route_lost",
      caller: "VoicePromptBridge.routeChange",
      code: "HFP_ROUTE_LOST"
    )
    if cueIsPlayingOnHfp {
      completeReadyCue(errorCode: "HFP_ROUTE_LOST")
    }
    if authoredIsPlayingOnHfp {
      finishAuthoredPrompt(success: false, errorCode: "HFP_ROUTE_LOST")
    }
    if speechIsPlayingOnHfp {
      if synthesisOperation != nil, let token = activeUtteranceAudioToken {
        failSynthesizedPrompt(audioToken: token, code: "HFP_ROUTE_LOST")
        return
      }
      let audioToken = activeUtteranceAudioToken
      activeUtterance = nil
      activeUtteranceAudioToken = nil
      activeUtteranceExpectsHfp = false
      synthesizer.stopSpeaking(at: .immediate)
      releasePromptAudioSession(token: audioToken)
      completeWaitingResult(error: FlutterError(
        code: "HFP_ROUTE_LOST",
        message: "The selected HFP output was lost during speech.",
        details: nil
      ))
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    if activeUtterance === utterance, synthesisOperation != nil { return }
    guard activeUtterance === utterance else {
      audioSessionCoordinator.trace(
        stage: "prompt_stale_finish_ignored",
        caller: "VoicePromptBridge.didFinish"
      )
      return
    }
    let audioToken = activeUtteranceAudioToken
    activeUtterance = nil
    activeUtteranceAudioToken = nil
    activeUtteranceExpectsHfp = false
    audioSessionCoordinator.trace(stage: "prompt_finished", caller: "VoicePromptBridge.didFinish")
    audioSessionCoordinator.trace(stage: "prompt_done", caller: "VoicePromptBridge.didFinish")
    releasePromptAudioSession(token: audioToken)
    completeWaitingResult()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    guard activeUtterance === utterance else { return }
    guard synthesisOperation == nil else { return }
    audioSessionCoordinator.trace(
      stage: "prompt_playback_active",
      caller: "VoicePromptBridge.didStart"
    )
    audioSessionCoordinator.backgroundAudioActivityDidStart(
      caller: "VoicePromptBridge.didStart"
    )
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    guard activeUtterance === utterance else {
      audioSessionCoordinator.trace(
        stage: "prompt_stale_cancel_ignored",
        caller: "VoicePromptBridge.didCancel"
      )
      return
    }
    if synthesisOperation != nil, let token = activeUtteranceAudioToken {
      failSynthesizedPrompt(audioToken: token, code: "PROMPT_CANCELLED")
      return
    }
    let audioToken = activeUtteranceAudioToken
    activeUtterance = nil
    activeUtteranceAudioToken = nil
    activeUtteranceExpectsHfp = false
    audioSessionCoordinator.trace(stage: "prompt_cancelled", caller: "VoicePromptBridge.didCancel")
    releasePromptAudioSession(token: audioToken)
    completeWaitingResult(error: FlutterError(
      code: "PROMPT_CANCELLED",
      message: "Prompt playback was interrupted.",
      details: nil
    ))
  }

  private func releasePromptAudioSession(token: UUID?) {
    guard let token else { return }
    guard promptOperationLeases.release(token) else {
      audioSessionCoordinator.trace(
        stage: "prompt_stale_audio_release_ignored",
        caller: "VoicePromptBridge.releasePromptAudioSession"
      )
      return
    }
    audioSessionCoordinator.releasePrompt(
      usedHfp: false,
      caller: "VoicePromptBridge.releasePromptAudioSession"
    )
  }

  private func playSpeechReadyCue(_ result: @escaping FlutterResult) {
    if readyCueToken != nil {
      // Concurrent readiness requests await one cue, as on Android. Replacing
      // an in-flight cue would cut the ting and report completion too early.
      readyCueResults.append(result)
      return
    }
    guard let audioToken = configurePromptAudioSession() else {
      result(FlutterError(
        code: "PROMPT_AUDIO_ROUTE_FAILED",
        message: "Unable to prepare the speech-ready cue route.",
        details: nil
      ))
      return
    }
    audioSessionCoordinator.trace(stage: "ready_cue_started", caller: "VoicePromptBridge.playSpeechReadyCue")

    let token = UUID()
    readyCueToken = token
    readyCueAudioToken = audioToken
    readyCueResults.append(result)
    readyCueExpectsHfp = promptExpectsHfp(forcePhoneSpeaker: false)
    // setPreferredInput can return before the Bluetooth voice route is live.
    // Starting this very short WAV then can play it on the phone (or lose it)
    // while the lesson already opens its microphone gate. Android likewise
    // waits for SCO before starting its ready cue.
    waitForReadyCueRoute(
      token: token,
      expectsHfp: readyCueExpectsHfp,
      attemptsRemaining: 20
    )
  }

  private func waitForReadyCueRoute(
    token: UUID,
    expectsHfp: Bool,
    attemptsRemaining: Int
  ) {
    guard readyCueToken == token else { return }
    if expectsHfp && !audioSessionCoordinator.hasSelectedTwoWayHfpRoute() {
      guard attemptsRemaining > 0 else {
        completeReadyCue(token: token, errorCode: "READY_CUE_ROUTE_UNAVAILABLE")
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
        self?.waitForReadyCueRoute(
          token: token,
          expectsHfp: expectsHfp,
          attemptsRemaining: attemptsRemaining - 1
        )
      }
      return
    }

    let fallback = DispatchWorkItem { [weak self] in
      self?.completeReadyCue(token: token, errorCode: "READY_CUE_TIMEOUT")
    }
    readyCueFallback = fallback

    do {
      let player = try AVAudioPlayer(data: Self.makeReadyCueWavData())
      player.delegate = self
      player.volume = 1.0
      player.numberOfLoops = 0
      player.prepareToPlay()
      readyCuePlayer = player
      guard player.play() else {
        throw ReadyCueError.playbackFailed
      }
    } catch {
      completeReadyCue(token: token, errorCode: "READY_CUE_UNAVAILABLE")
      return
    }

    // AVAudioPlayer normally completes after 120 ms. Leave room for the same
    // acoustic tail as Android before opening the lesson microphone gate.
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(900),
      execute: fallback
    )
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if player === authoredPromptPlayer {
      finishAuthoredPrompt(success: flag)
      return
    }
    guard player === readyCuePlayer else { return }
    guard flag else {
      completeReadyCue(token: readyCueToken, errorCode: "READY_CUE_UNAVAILABLE")
      return
    }
    guard let token = readyCueToken else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) { [weak self] in
      self?.completeReadyCue(token: token)
    }
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    if player === authoredPromptPlayer {
      finishAuthoredPrompt(success: false)
    } else if player === readyCuePlayer {
      completeReadyCue(token: readyCueToken, errorCode: "READY_CUE_UNAVAILABLE")
    }
  }

  static func makeReadyCueWavData() -> Data {
    // Match Android ReadyCueWaveform exactly: 120 ms, 880 Hz, 8 ms edge
    // fades, and -21 dBFS active RMS. HFP carries 16 kHz mono PCM directly.
    let sampleRate: UInt32 = 16_000
    let sampleCount = Int(sampleRate * 120 / 1_000)
    let dataByteCount = UInt32(sampleCount * MemoryLayout<Int16>.size)
    var data = Data()
    data.append(contentsOf: Array("RIFF".utf8))
    data.appendLittleEndian(UInt32(36) + dataByteCount)
    data.append(contentsOf: Array("WAVEfmt ".utf8))
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(sampleRate)
    data.appendLittleEndian(sampleRate * UInt32(MemoryLayout<Int16>.size))
    data.appendLittleEndian(UInt16(MemoryLayout<Int16>.size))
    data.appendLittleEndian(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    data.appendLittleEndian(dataByteCount)

    let frequency = 880.0
    let fadeSamples = Double(sampleRate * 8 / 1_000)
    let amplitude = sqrt(2.0) * pow(10.0, -21.0 / 20.0)
    for index in 0..<sampleCount {
      let position = Double(index)
      let fadeIn = min(1.0, position / fadeSamples)
      let fadeOut = min(1.0, Double(sampleCount - index - 1) / fadeSamples)
      let envelope = min(fadeIn, fadeOut)
      let phase = 2.0 * Double.pi * frequency * position / Double(sampleRate)
      let value = sin(phase) * amplitude * envelope * Double(Int16.max)
      data.appendLittleEndian(Int16(value.rounded()))
    }
    return data
  }

  private func completeReadyCue(token: UUID? = nil, errorCode: String? = nil) {
    if let token, token != readyCueToken {
      return
    }
    let hadActiveCue = readyCueToken != nil || !readyCueResults.isEmpty || readyCuePlayer != nil
    let resolvedErrorCode = errorCode ?? (
      readyCueExpectsHfp && !audioSessionCoordinator.hasSelectedTwoWayHfpRoute()
        ? "HFP_ROUTE_LOST" : nil
    )
    readyCueFallback?.cancel()
    readyCueFallback = nil
    readyCuePlayer?.delegate = nil
    readyCuePlayer?.stop()
    readyCuePlayer = nil
    readyCueToken = nil
    readyCueExpectsHfp = false
    let audioToken = readyCueAudioToken
    readyCueAudioToken = nil
    let results = readyCueResults
    readyCueResults.removeAll()
    if hadActiveCue {
      audioSessionCoordinator.trace(
        stage: resolvedErrorCode == nil ? "ready_cue_finished" : "ready_cue_failed",
        caller: "VoicePromptBridge.completeReadyCue",
        code: resolvedErrorCode
      )
    }
    // Release only this cue's prompt lease. A prearmed background-capture lease
    // deliberately keeps AVAudioSession and its input engine alive so the next
    // Apple Speech turn can open its buffer gate without rebuilding the graph.
    releasePromptAudioSession(token: audioToken)
    let error = resolvedErrorCode.map {
      FlutterError(code: $0, message: "Unable to play the speech-ready cue.", details: nil)
    }
    for result in results { result(error) }
  }

  func dispose() {
    guard !disposed else { return }
    if let routeChangeToken {
      NotificationCenter.default.removeObserver(routeChangeToken)
      self.routeChangeToken = nil
    }
    if let interruptionToken {
      NotificationCenter.default.removeObserver(interruptionToken)
      self.interruptionToken = nil
    }
    stop()
    audioSessionCoordinator.endMainTurn(
      reason: "prompt_bridge_disposed",
      caller: "VoicePromptBridge.dispose"
    )
    disposed = true
    synthesizer.delegate = nil
    channel.setMethodCallHandler(nil)
  }
}

private enum ReadyCueError: Error {
  case playbackFailed
}

private enum LessonRecordingNormalizationError: Error {
  case invalidRecording
  case unsupportedPcm
}

private extension Data {
  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    var littleEndianValue = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
      append(contentsOf: bytes)
    }
  }
}
