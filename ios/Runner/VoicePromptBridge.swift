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

/// Native iOS prompt output for the fixed MAIN assistant. Keeping prompts in
/// AVSpeechSynthesizer or verified bundled audio avoids a network round trip
/// before command recognition. Both use the existing MAIN audio-session owner.
final class VoicePromptBridge: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private let synthesizer = AVSpeechSynthesizer()
  private var waitingResult: FlutterResult?
  private var readyCueResult: FlutterResult?
  private var readyCueToken: UUID?
  private var readyCueAudioToken: UUID?
  private var readyCueFallback: DispatchWorkItem?
  private var readyCuePlayer: AVAudioPlayer?
  private var activeUtterance: AVSpeechUtterance?
  private var activeUtteranceAudioToken: UUID?
  private var authoredPromptPlayer: AVAudioPlayer?
  private var authoredPromptAudioToken: UUID?
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
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed else {
      result(FlutterError(code: "VOICE_PROMPT_DISPOSED", message: "Bộ đọc đã đóng.", details: nil))
      return
    }
    switch call.method {
    case "beginMainTurn":
      let turnId = audioSessionCoordinator.beginMainTurn(
        source: "VoicePromptBridge.beginMainTurn"
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
        forcePhoneSpeaker: forcePhoneSpeaker,
        forceMediaPlayback: forceMediaPlayback,
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

  /// Decodes the child's short lesson capture, lifts only quiet recordings,
  /// and writes a PCM WAV sibling. Authored prompts never pass through this
  /// path, so their established loudness is untouched. Peak headroom prevents
  /// clipping while the gated RMS ignores pauses around the spoken sentence.
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
        let gainDb = Self.lessonRecordingGainDb(
          channels: channels,
          channelCount: Int(format.channelCount),
          frameLength: Int(buffer.frameLength),
          sampleRate: format.sampleRate
        )
        guard gainDb > 0.05 else {
          DispatchQueue.main.async { result(path) }
          return
        }
        let multiplier = pow(10.0, gainDb / 20.0)
        for channel in 0..<Int(format.channelCount) {
          for frame in 0..<Int(buffer.frameLength) {
            channels[channel][frame] *= Float(multiplier)
          }
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

  static func lessonRecordingGainDb(
    channels: UnsafePointer<UnsafeMutablePointer<Float>>,
    channelCount: Int,
    frameLength: Int,
    sampleRate: Double
  ) -> Double {
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
    guard let strongest = windowEnergies.max(), strongest > 0, peak > 0 else { return 0 }
    let gate = max(pow(10.0, -50.0 / 10.0), strongest / 1000.0)
    let active = windowEnergies.filter { $0 >= gate }
    guard !active.isEmpty else { return 0 }
    let rmsPower = active.reduce(0, +) / Double(active.count)
    let measuredDb = 10.0 * log10(rmsPower)
    let peakDb = 20.0 * log10(peak)
    let desired = -21.0 - measuredDb
    let headroom = -1.0 - peakDb
    return max(0.0, min(28.0, min(desired, headroom)))
  }

  private func speak(
    _ text: String,
    locale: String,
    forcePhoneSpeaker: Bool,
    forceMediaPlayback: Bool,
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
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    utterance.volume = 1.0
    activeUtterance = utterance
    activeUtteranceAudioToken = audioToken
    if waitForCompletion {
      waitingResult = result
    } else {
      result(nil)
    }
    synthesizer.speak(utterance)
  }

  @discardableResult
  private func configurePromptAudioSession(
    forcePhoneSpeaker: Bool = false,
    forceMediaPlayback: Bool = false
  ) -> UUID? {
    let audioToken = UUID()
    let preferredHfpInput = audioSessionCoordinator.selectedOrAvailableHfpInput()
    // While H20 is selected and available, assistant speech must not be
    // forced back to the handset by a legacy phone-speaker request. The
    // handset remains the fallback only after H20 has actually lost its route.
    if forcePhoneSpeaker, preferredHfpInput == nil {
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

  private func stop() {
    let authoredAudioToken = authoredPromptAudioToken
    authoredPromptAudioToken = nil
    authoredPromptPlayer?.delegate = nil
    authoredPromptPlayer?.stop()
    authoredPromptPlayer = nil
    let utteranceAudioToken = activeUtteranceAudioToken
    activeUtterance = nil
    activeUtteranceAudioToken = nil
    if synthesizer.isSpeaking || synthesizer.isPaused {
      synthesizer.stopSpeaking(at: .immediate)
    }
    completeWaitingResult()
    completeReadyCue()
    releasePromptAudioSession(token: utteranceAudioToken)
    releasePromptAudioSession(token: authoredAudioToken)
  }

  private func playAuthoredPrompt(
    _ data: Data,
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
    do {
      let player = try AVAudioPlayer(data: data)
      authoredPromptPlayer = player
      player.delegate = self
      player.volume = 1.0
      player.numberOfLoops = 0
      player.prepareToPlay()
      // Speed was applied once during offline generation; playback stays at 1x.
      guard player.play() else { throw ReadyCueError.playbackFailed }
      audioSessionCoordinator.trace(stage: "prompt_playback_active", caller: "VoicePromptBridge.playAuthoredPrompt")
      audioSessionCoordinator.backgroundAudioActivityDidStart(caller: "VoicePromptBridge.playAuthoredPrompt")
    } catch {
      finishAuthoredPrompt(success: false)
    }
  }

  private func finishAuthoredPrompt(success: Bool) {
    authoredPromptPlayer?.delegate = nil
    authoredPromptPlayer?.stop()
    authoredPromptPlayer = nil
    let token = authoredPromptAudioToken
    authoredPromptAudioToken = nil
    releasePromptAudioSession(token: token)
    let result = waitingResult
    waitingResult = nil
    if success {
      audioSessionCoordinator.trace(stage: "prompt_finished", caller: "VoicePromptBridge.finishAuthoredPrompt")
      audioSessionCoordinator.trace(stage: "prompt_done", caller: "VoicePromptBridge.finishAuthoredPrompt")
      result?(nil)
    } else {
      result?(FlutterError(code: "PROMPT_AUDIO_FAILED", message: "Unable to play authored prompt.", details: nil))
    }
  }

  private func completeWaitingResult() {
    let result = waitingResult
    waitingResult = nil
    result?(nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
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
    audioSessionCoordinator.trace(stage: "prompt_finished", caller: "VoicePromptBridge.didFinish")
    audioSessionCoordinator.trace(stage: "prompt_done", caller: "VoicePromptBridge.didFinish")
    releasePromptAudioSession(token: audioToken)
    completeWaitingResult()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    guard activeUtterance === utterance else { return }
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
    let audioToken = activeUtteranceAudioToken
    activeUtterance = nil
    activeUtteranceAudioToken = nil
    audioSessionCoordinator.trace(stage: "prompt_cancelled", caller: "VoicePromptBridge.didCancel")
    releasePromptAudioSession(token: audioToken)
    completeWaitingResult()
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
    completeReadyCue()
    let audioToken = configurePromptAudioSession()
    audioSessionCoordinator.trace(stage: "ready_cue_started", caller: "VoicePromptBridge.playSpeechReadyCue")

    let token = UUID()
    readyCueToken = token
    readyCueAudioToken = audioToken
    readyCueResult = result
    let fallback = DispatchWorkItem { [weak self] in
      self?.completeReadyCue(token: token)
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
      completeReadyCue(token: token)
      return
    }

    // AVAudioPlayer normally completes after 170 ms. Keep a bounded fallback
    // so a route interruption can never prevent Apple Speech from opening.
    DispatchQueue.main.asyncAfter(
      deadline: .now() + .milliseconds(380),
      execute: fallback
    )
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if player === authoredPromptPlayer {
      finishAuthoredPrompt(success: flag)
      return
    }
    guard player === readyCuePlayer else { return }
    completeReadyCue(token: readyCueToken)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    if player === authoredPromptPlayer {
      finishAuthoredPrompt(success: false)
    } else if player === readyCuePlayer {
      completeReadyCue(token: readyCueToken)
    }
  }

  private static func makeReadyCueWavData() -> Data {
    let sampleRate: UInt32 = 44_100
    let durationSeconds = 0.17
    let sampleCount = Int(Double(sampleRate) * durationSeconds)
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
    let fadeSamples = 220.0
    for index in 0..<sampleCount {
      let position = Double(index)
      let fadeIn = min(1.0, position / fadeSamples)
      let fadeOut = min(1.0, Double(sampleCount - index - 1) / fadeSamples)
      let envelope = min(fadeIn, fadeOut)
      let phase = 2.0 * Double.pi * frequency * position / Double(sampleRate)
      let value = sin(phase) * envelope * 0.42 * Double(Int16.max)
      data.appendLittleEndian(Int16(value.rounded()))
    }
    return data
  }

  private func completeReadyCue(token: UUID? = nil) {
    if let token, token != readyCueToken {
      return
    }
    let hadActiveCue = readyCueToken != nil || readyCueResult != nil || readyCuePlayer != nil
    readyCueFallback?.cancel()
    readyCueFallback = nil
    readyCuePlayer?.delegate = nil
    readyCuePlayer?.stop()
    readyCuePlayer = nil
    readyCueToken = nil
    let audioToken = readyCueAudioToken
    readyCueAudioToken = nil
    let result = readyCueResult
    readyCueResult = nil
    if hadActiveCue {
      audioSessionCoordinator.trace(
        stage: "ready_cue_finished",
        caller: "VoicePromptBridge.completeReadyCue"
      )
    }
    // Release only this cue's prompt lease. A prearmed background-capture lease
    // deliberately keeps AVAudioSession and its input engine alive so the next
    // Apple Speech turn can open its buffer gate without rebuilding the graph.
    releasePromptAudioSession(token: audioToken)
    result?(nil)
  }

  func dispose() {
    guard !disposed else { return }
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
