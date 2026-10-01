import AVFoundation
import Flutter
import google_mlkit_translation
@testable import Runner
import Speech
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testIOSMainPhoneTurnSelectsBuiltInPrearmBeforeAnyPrompt() {
    let target = IOSMainTurnAudioRoutePolicy.inputTarget(fromChannelValue: "builtInMic")
    XCTAssertEqual(target, .builtInMic)
    XCTAssertEqual(IOSBackgroundAudioHandoffPolicy.audioSource(
      mainInputTarget: target,
      activeAudioSource: nil,
      hasAvailableHfpInput: true
    ), .builtInMic)
    let forcePhone = IOSMainTurnAudioRoutePolicy.forcesPhoneSpeaker(
      explicitRequest: false,
      mainInputTarget: target
    )
    XCTAssertTrue(forcePhone)
    // TTS, authored selected-media prompts and the cue use this same policy.
    XCTAssertFalse(IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: forcePhone,
      hasAvailableHfpInput: true,
      retainedBackgroundHfpRoute: false
    ))
    XCTAssertFalse(IOSMainTurnAudioRoutePolicy.requiresHfp(
      mainInputTarget: target,
      explicitPhoneRequest: false
    ))
  }

  func testIOSMainHfpTurnNeverSelectsPhonePrearmWhenTheRouteDisappears() {
    let target = IOSMainTurnAudioRoutePolicy.inputTarget(fromChannelValue: "hfp")
    XCTAssertEqual(target, .hfp)
    XCTAssertEqual(IOSBackgroundAudioHandoffPolicy.audioSource(
      mainInputTarget: target,
      activeAudioSource: nil,
      hasAvailableHfpInput: false
    ), .hfp)
    XCTAssertTrue(IOSMainTurnAudioRoutePolicy.requiresHfp(
      mainInputTarget: target,
      explicitPhoneRequest: false
    ))
    XCTAssertFalse(IOSMainTurnAudioRoutePolicy.forcesPhoneSpeaker(
      explicitRequest: false,
      mainInputTarget: target
    ))
  }

  func testIOSLegacyMainRouteSelectionPreservesAutomaticAndActiveCapturePolicy() {
    XCTAssertNil(IOSMainTurnAudioRoutePolicy.inputTarget(fromChannelValue: nil))
    XCTAssertNil(IOSMainTurnAudioRoutePolicy.inputTarget(fromChannelValue: "unknown"))
    XCTAssertEqual(IOSBackgroundAudioHandoffPolicy.audioSource(
      mainInputTarget: nil, activeAudioSource: nil, hasAvailableHfpInput: true
    ), .hfp)
    XCTAssertEqual(IOSBackgroundAudioHandoffPolicy.audioSource(
      mainInputTarget: nil, activeAudioSource: nil, hasAvailableHfpInput: false
    ), .builtInMic)
    XCTAssertEqual(IOSBackgroundAudioHandoffPolicy.audioSource(
      mainInputTarget: nil, activeAudioSource: .builtInMic, hasAvailableHfpInput: true
    ), .builtInMic)
  }

  func testIOSMainSourceChangeReplacesOnlyAnIdleBackgroundGraph() {
    XCTAssertTrue(IOSBackgroundAudioHandoffPolicy.shouldReplaceIdleSource(
      current: .hfp, requested: .builtInMic, captureActive: false
    ))
    XCTAssertTrue(IOSBackgroundAudioHandoffPolicy.shouldReplaceIdleSource(
      current: .builtInMic, requested: .hfp, captureActive: false
    ))
    XCTAssertFalse(IOSBackgroundAudioHandoffPolicy.shouldReplaceIdleSource(
      current: .hfp, requested: .builtInMic, captureActive: true
    ))
    XCTAssertFalse(IOSBackgroundAudioHandoffPolicy.shouldReplaceIdleSource(
      current: .builtInMic, requested: .builtInMic, captureActive: false
    ))
  }

  func testIOSBackgroundHandoffRetryBelongsOnlyToTheCurrentArmGeneration() {
    // Disarm completed the HFP arm's obsolete waiters, then a phone arm began.
    // Its old delayed retry must neither reopen HFP nor drain the phone waiters.
    XCTAssertFalse(IOSBackgroundAudioHandoffPolicy.shouldRunArmAttempt(
      disposed: false, phase: .arming, requestedGeneration: 1, currentGeneration: 3
    ))
    XCTAssertTrue(IOSBackgroundAudioHandoffPolicy.shouldRunArmAttempt(
      disposed: false, phase: .arming, requestedGeneration: 3, currentGeneration: 3
    ))
    XCTAssertFalse(IOSBackgroundAudioHandoffPolicy.shouldRunArmAttempt(
      disposed: false, phase: .idle, requestedGeneration: 3, currentGeneration: 3
    ))
    XCTAssertFalse(IOSBackgroundAudioHandoffPolicy.shouldRunArmAttempt(
      disposed: true, phase: .arming, requestedGeneration: 3, currentGeneration: 3
    ))
  }

  func testIOSMainRoutePolicyIsSetBeforeBackgroundArmAndClearedByItsExactTurn() {
    let coordinator = IOSAudioSessionCoordinator()
    let handoff = MainTurnAudioTargetHandoff(coordinator: coordinator)
    coordinator.backgroundCaptureHandoffDelegate = handoff
    coordinator.setBackgroundLearningEnabled(true, caller: "RunnerTests")
    let turnId = coordinator.beginMainTurn(
      source: "RunnerTests", audioInputTarget: .builtInMic, forceNewTurn: true
    )
    coordinator.requestBackgroundCaptureArm(caller: "RunnerTests")
    XCTAssertEqual(handoff.targets.compactMap { $0 }.last, .builtInMic)
    coordinator.endMainTurn(
      reason: "obsolete_reply", caller: "RunnerTests", expectedTurnId: "obsolete"
    )
    XCTAssertEqual(coordinator.mainAudioInputTarget, .builtInMic)
    coordinator.endMainTurn(
      reason: "test_complete", caller: "RunnerTests", expectedTurnId: turnId
    )
    XCTAssertNil(coordinator.mainAudioInputTarget)
    coordinator.dispose()
  }

  func testIOSVirtualMainActivationsGetFreshIdsBeforeAnOldBeginReplyCompletes() {
    let coordinator = IOSAudioSessionCoordinator()
    let firstTurn = coordinator.beginMainTurn(
      source: "RunnerTests.firstVirtual", audioInputTarget: .builtInMic, forceNewTurn: true
    )
    let secondTurn = coordinator.beginMainTurn(
      source: "RunnerTests.secondVirtual", audioInputTarget: .hfp, forceNewTurn: true
    )
    XCTAssertNotEqual(firstTurn, secondTurn)
    coordinator.endMainTurn(
      reason: "late_first_begin_reply", caller: "RunnerTests", expectedTurnId: firstTurn
    )
    XCTAssertTrue(coordinator.isMainTurnActive)
    XCTAssertEqual(coordinator.mainAudioInputTarget, .hfp)
    coordinator.endMainTurn(
      reason: "test_complete", caller: "RunnerTests", expectedTurnId: secondTurn
    )
    XCTAssertFalse(coordinator.isMainTurnActive)
    XCTAssertNil(coordinator.mainAudioInputTarget)
    coordinator.dispose()
  }

  func testIOSPromptPhoneOutputDoesNotWaitForAnAvailablePairedHfpInput() {
    XCTAssertFalse(IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: true, hasAvailableHfpInput: true, retainedBackgroundHfpRoute: false
    ))
    XCTAssertFalse(IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: true, hasAvailableHfpInput: false, retainedBackgroundHfpRoute: false
    ))
  }

  func testIOSPromptSelectedOutputAndDefaultCueStillRequireAvailableHfp() {
    XCTAssertTrue(IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: false, hasAvailableHfpInput: true, retainedBackgroundHfpRoute: false
    ))
    XCTAssertFalse(IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: false, hasAvailableHfpInput: false, retainedBackgroundHfpRoute: false
    ))
  }

  func testIOSPromptRetainedBackgroundHfpGraphKeepsRouteLossMonitoring() {
    XCTAssertTrue(IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: true, hasAvailableHfpInput: true, retainedBackgroundHfpRoute: true
    ))
    XCTAssertTrue(IOSPromptOutputRoutePolicy.expectsHfp(
      forcePhoneSpeaker: true, hasAvailableHfpInput: false, retainedBackgroundHfpRoute: true
    ))
  }

  func testIOSOfflineTranslationSupportsTheSameVietnameseEnglishPair() {
    XCTAssertTrue(GoogleMlKitTranslationPlugin.supportsLanguage("vi"))
    XCTAssertTrue(GoogleMlKitTranslationPlugin.supportsLanguage("en"))
    XCTAssertFalse(GoogleMlKitTranslationPlugin.supportsLanguage("unknown"))
  }

  #if targetEnvironment(simulator)
  func testIOSSimulatorTranslationModelCheckDoesNotPretendTheModelIsReady() {
    let plugin = GoogleMlKitTranslationPlugin()
    var response: Any?
    var callbacks = 0
    plugin.handle(FlutterMethodCall(
      methodName: "nlp#manageLanguageModelModels", arguments: ["task": "check", "model": "vi"]
    )) { value in
      response = value
      callbacks += 1
    }
    XCTAssertEqual(callbacks, 1)
    XCTAssertEqual(response as? Bool, false)
  }

  func testIOSSimulatorTranslationAndDownloadReturnAnExplicitDeviceRequirement() throws {
    let plugin = GoogleMlKitTranslationPlugin()
    let calls = [
      FlutterMethodCall(methodName: "nlp#manageLanguageModelModels", arguments: [
        "task": "download", "model": "vi", "wifi": true,
      ]),
      FlutterMethodCall(methodName: "nlp#startLanguageTranslator", arguments: [
        "id": "simulator-test", "source": "vi", "target": "en", "text": "Xin chào",
      ]),
    ]
    for call in calls {
      var response: Any?
      var callbacks = 0
      plugin.handle(call) { value in
        response = value
        callbacks += 1
      }
      XCTAssertEqual(callbacks, 1)
      let error = try XCTUnwrap(response as? FlutterError)
      XCTAssertEqual(error.code, "OFFLINE_TRANSLATION_SIMULATOR_UNAVAILABLE")
    }
  }

  func testIOSSimulatorTranslationCloseCompletesExactlyOnce() {
    let plugin = GoogleMlKitTranslationPlugin()
    var callbacks = 0
    plugin.handle(FlutterMethodCall(
      methodName: "nlp#closeLanguageTranslator", arguments: ["id": "simulator-test"]
    )) { value in
      callbacks += 1
      XCTAssertNil(value)
    }
    XCTAssertEqual(callbacks, 1)
  }
  #endif

  func testIOSPromptRequestedGainUsesAndroidBoundsAndDefault() {
    XCTAssertEqual(IOSPromptPlaybackAudio.requestedGainDb(nil), 8)
    XCTAssertEqual(IOSPromptPlaybackAudio.requestedGainDb(.nan), 8)
    XCTAssertEqual(IOSPromptPlaybackAudio.requestedGainDb(.infinity), 8)
    XCTAssertEqual(IOSPromptPlaybackAudio.requestedGainDb(-2), 0)
    XCTAssertEqual(IOSPromptPlaybackAudio.requestedGainDb(7.5), 7.5)
    XCTAssertEqual(IOSPromptPlaybackAudio.requestedGainDb(20), 12)
  }

  func testIOSPromptMeterMatchesAndroidForQuietAndLoudClips() throws {
    for amplitude in [0.01, 0.5] {
      var meter = IOSPromptPlaybackLevelMeter(sampleRate: 16_000, channelCount: 1)
      for _ in 0..<640 { meter.addSample(amplitude) }
      let level = try XCTUnwrap(meter.result())
      XCTAssertEqual(level.measuredDb, 20 * log10(amplitude), accuracy: 0.00001)
      XCTAssertEqual(level.gainDb, -21 - 20 * log10(amplitude), accuracy: 0.00001)
    }
  }

  func testIOSPromptMeterDoesNotAmplifySilenceOrBackgroundNoise() throws {
    for amplitude in [0.0, 0.0001] {
      var meter = IOSPromptPlaybackLevelMeter(sampleRate: 16_000, channelCount: 1)
      for _ in 0..<640 { meter.addSample(amplitude) }
      let level = try XCTUnwrap(meter.result())
      XCTAssertEqual(level.gainDb, 0)
      XCTAssertEqual(level.activeWindowCount, 0)
      XCTAssertTrue(level.measuredDb.isFinite)
    }
  }

  func testIOSPromptMeterIgnoresPausesAndCapsGainAt28Db() throws {
    var meter = IOSPromptPlaybackLevelMeter(sampleRate: 16_000, channelCount: 1)
    for _ in 0..<320 { meter.addSample(0) }
    for _ in 0..<320 { meter.addSample(0.0032) }
    for _ in 0..<320 { meter.addSample(0) }
    let level = try XCTUnwrap(meter.result())
    XCTAssertEqual(level.gainDb, 28)
    XCTAssertEqual(level.activeWindowCount, 1)
    XCTAssertEqual(level.measuredDb, 20 * log10(0.0032), accuracy: 0.00001)
  }

  func testIOSPromptMeterWeightsFinalPartialWindowBySampleCount() throws {
    var meter = IOSPromptPlaybackLevelMeter(sampleRate: 8_000, channelCount: 1)
    for _ in 0..<160 { meter.addSample(0.1) }
    for _ in 0..<80 { meter.addSample(0.2) }
    let level = try XCTUnwrap(meter.result())
    XCTAssertEqual(level.activeWindowCount, 2)
    XCTAssertEqual(level.measuredDb, 10 * log10(0.02), accuracy: 0.00001)
  }

  func testIOSPromptMeterDoesNotLetFinalClickExcludeQuietSpeech() throws {
    var meter = IOSPromptPlaybackLevelMeter(sampleRate: 16_000, channelCount: 1)
    for _ in 0..<320 { meter.addSample(0.01) }
    meter.addSample(1)
    let level = try XCTUnwrap(meter.result())
    XCTAssertEqual(level.activeWindowCount, 2)
    XCTAssertEqual(level.measuredDb, 10 * log10(1.032 / 321), accuracy: 0.00001)
    XCTAssertEqual(level.gainDb, -1)
  }

  func testIOSPromptMeterUsesEveryChannelForPeakHeadroom() throws {
    var meter = IOSPromptPlaybackLevelMeter(sampleRate: 16_000, channelCount: 2)
    for index in 0..<640 {
      meter.addSample(index == 0 ? 0.8 : 0.01)
      meter.addSample(0.01)
    }
    let level = try XCTUnwrap(meter.result())
    XCTAssertEqual(level.peakDb, 20 * log10(0.8), accuracy: 0.00001)
    XCTAssertEqual(level.gainDb, -1 - 20 * log10(0.8), accuracy: 0.00001)
    XCTAssertLessThanOrEqual(0.8 * pow(10, level.gainDb / 20), pow(10, -1.0 / 20) + 0.00001)
  }

  func testIOSPromptMeterRejectsIncompleteChannelsAndNonFinitePcm() {
    var incomplete = IOSPromptPlaybackLevelMeter(sampleRate: 16_000, channelCount: 2)
    incomplete.addSample(0.1)
    XCTAssertNil(incomplete.result())
    var invalid = IOSPromptPlaybackLevelMeter(sampleRate: 16_000, channelCount: 1)
    invalid.addSample(.nan)
    invalid.addSample(0.1)
    XCTAssertNil(invalid.result())
  }

  func testIOSPromptPreparationMatchesLevelWithoutChangingSourceBytes() throws {
    let format = try XCTUnwrap(AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 2, interleaved: false
    ))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 640))
    buffer.frameLength = 640
    for frame in 0..<640 {
      buffer.floatChannelData?[0][frame] = 0.01
      buffer.floatChannelData?[1][frame] = -0.01
    }
    let source = FileManager.default.temporaryDirectory
      .appendingPathComponent("prompt-source-\(UUID().uuidString).caf")
    let output = source.deletingPathExtension().appendingPathExtension("wav")
    defer {
      try? FileManager.default.removeItem(at: source)
      try? FileManager.default.removeItem(at: output)
    }
    do {
      let writer = try AVAudioFile(
        forWriting: source, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false
      )
      try writer.write(from: buffer)
    }
    let original = try Data(contentsOf: source)
    let level = try IOSPromptPlaybackAudio.prepare(source: source, output: output)
    XCTAssertEqual(try Data(contentsOf: source), original)
    XCTAssertEqual(level.gainDb, 19, accuracy: 0.001)
    let reader = try AVAudioFile(forReading: output)
    XCTAssertEqual(reader.fileFormat.commonFormat, .pcmFormatInt16)
    XCTAssertEqual(reader.fileFormat.sampleRate, 16_000)
    XCTAssertEqual(reader.fileFormat.channelCount, 2)
    XCTAssertEqual(reader.length, 640)
    let played = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 640))
    try reader.read(into: played)
    XCTAssertEqual(try XCTUnwrap(played.floatChannelData?[0][0]), Float(pow(10, -21.0 / 20)), accuracy: 0.00005)
    XCTAssertEqual(try XCTUnwrap(played.floatChannelData?[1][0]), -Float(pow(10, -21.0 / 20)), accuracy: 0.00005)
  }

  func testIOSPromptSynthesisFinishesOnceAndCancellationIgnoresLateBuffers() throws {
    let format = try XCTUnwrap(AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    ))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
    buffer.frameLength = 160
    for frame in 0..<160 { buffer.floatChannelData?[0][frame] = 0.1 }
    let terminal = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
    terminal.frameLength = 0
    let operation = IOSPromptSynthesisOperation(token: UUID())
    defer { operation.cancel() }
    var completions = 0
    let callback: (Result<Void, Error>) -> Void = { result in
      completions += 1
      if case let .failure(error) = result { XCTFail("Unexpected synthesis failure: \(error)") }
    }
    operation.accept(buffer, completion: callback)
    XCTAssertEqual(completions, 0)
    operation.accept(terminal, completion: callback)
    operation.accept(terminal, completion: callback)
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(try AVAudioFile(forReading: operation.source).length, 160)
    operation.cancel()
    operation.accept(buffer, completion: callback)
    XCTAssertTrue(operation.isCancelled)
    XCTAssertFalse(FileManager.default.fileExists(atPath: operation.source.path))
    XCTAssertEqual(completions, 1)
  }

  func testIOSOutputRouteKindDistinguishesA2dpFromPhoneSpeaker() {
    XCTAssertEqual(IOSAudioOutputRoutePolicy.kind(for: .bluetoothA2DP), "bluetoothA2DP")
    XCTAssertEqual(IOSAudioOutputRoutePolicy.kind(for: .bluetoothHFP), "bluetoothHFP")
    XCTAssertEqual(IOSAudioOutputRoutePolicy.kind(for: .builtInSpeaker), "builtInSpeaker")
    XCTAssertEqual(IOSAudioOutputRoutePolicy.kind(for: .builtInReceiver), "builtInReceiver")
  }

  func testIOSReadyCueMatchesAndroidDurationRateAndLevel() {
    let bytes = [UInt8](VoicePromptBridge.makeReadyCueWavData())
    XCTAssertEqual(bytes.count, 44 + 16_000 * 120 / 1_000 * 2)
    XCTAssertEqual(Array(bytes[0..<4]), Array("RIFF".utf8))
    XCTAssertEqual(Array(bytes[24..<28]), [0x80, 0x3E, 0x00, 0x00])

    let activeSamples = (128..<(1_920 - 128)).map { frame -> Double in
      let offset = 44 + frame * 2
      let bits = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
      return Double(Int16(bitPattern: bits)) / Double(Int16.max)
    }
    let meanSquare = activeSamples.reduce(0.0) { $0 + $1 * $1 }
      / Double(activeSamples.count)
    XCTAssertEqual(20.0 * log10(sqrt(meanSquare)), -21.0, accuracy: 0.25)
  }

  func testIOSSpeechRouteMatchesOnlyTheSelectedHfpInput() {
    let selected = IOSHfpInputIdentity(uid: "h20-1", name: "HOMI H20")
    XCTAssertTrue(IOSSelectedHfpRoutePolicy.matches(active: selected, selected: selected))
    XCTAssertTrue(IOSSelectedHfpRoutePolicy.matches(
      active: IOSHfpInputIdentity(uid: "h20-2", name: "HOMI H20"),
      selected: selected
    ))
    XCTAssertFalse(IOSSelectedHfpRoutePolicy.matches(
      active: IOSHfpInputIdentity(uid: "other-headset", name: "Other headset"),
      selected: selected
    ))
    XCTAssertFalse(IOSSelectedHfpRoutePolicy.matches(active: selected, selected: nil))
  }

  func testHmD001ObservedButtonsDoNotChangeLegacyH20Mapping() {
    let mainShort: [UInt8] = [1, 1, 1, 0, 0x1C, 0, 79, 0, 0, 0, 0, 0]
    let mainLong: [UInt8] = [1, 1, 2, 0, 0x1D, 0, 79, 0, 0, 0, 0, 0]
    let downLong: [UInt8] = [1, 4, 2, 0, 0x1E, 0, 79, 0, 0, 0, 0, 0]
    let upLong: [UInt8] = [1, 3, 2, 0, 0x1F, 0, 79, 0, 0, 0, 0, 0]
    let powerShort: [UInt8] = [1, 2, 1, 0, 0x29, 0, 0x47, 0, 0xF1, 0x60, 0x36, 0]
    XCTAssertEqual(H20BleControlObservation.fields(for: mainShort)["gesture"] as? String, "shortPress")
    XCTAssertEqual(H20BleControlObservation.fields(for: mainLong)["gesture"] as? String, "longPress")
    XCTAssertEqual(H20BleControlObservation.fields(for: downLong)["button"] as? String, "volumeDown")
    XCTAssertEqual(H20BleControlObservation.fields(for: upLong)["button"] as? String, "volumeUp")
    XCTAssertEqual(H20BleControlObservation.fields(for: powerShort)["button"] as? String, "power")
    XCTAssertEqual(H20BleControlObservation.fields(for: powerShort)["gesture"] as? String, "shortPress")
    XCTAssertFalse(H20BleControlObservation.isHmD001Packet(
      [1, 2, 2, 0, 0x29, 0, 0x47, 0, 0, 0, 0, 0]
    ))
    XCTAssertEqual(H20BleControlObservation.batteryPercent(mainLong), 79)
    XCTAssertFalse(H20BleControlObservation.isObservedMainShort(mainLong))
    XCTAssertTrue(H20BleControlObservation.isObservedMainShort(
      [1, 1, 0x10, 1, 0, 0, 79, 0, 0, 0, 0, 0]
    ))
  }

  func testBackgroundTurnExecutionPolicyOnlyBridgesAnEnabledBackgroundInteraction() {
    XCTAssertTrue(
      IOSBackgroundTurnExecutionPolicy.shouldRetain(
        backgroundLearningEnabled: true,
        applicationIsActive: false,
        interactionPendingOrActive: true
      )
    )
    XCTAssertFalse(
      IOSBackgroundTurnExecutionPolicy.shouldRetain(
        backgroundLearningEnabled: false,
        applicationIsActive: false,
        interactionPendingOrActive: true
      )
    )
    XCTAssertFalse(
      IOSBackgroundTurnExecutionPolicy.shouldRetain(
        backgroundLearningEnabled: true,
        applicationIsActive: true,
        interactionPendingOrActive: true
      )
    )
    XCTAssertFalse(
      IOSBackgroundTurnExecutionPolicy.shouldRetain(
        backgroundLearningEnabled: true,
        applicationIsActive: false,
        interactionPendingOrActive: false
      )
    )

    XCTAssertTrue(
      IOSBackgroundTurnExecutionPolicy.shouldDeferToActiveAudio(
        applicationIsActive: false,
        promptActive: true,
        speechCaptureActive: false,
        backgroundCaptureRunning: false
      )
    )
    XCTAssertTrue(
      IOSBackgroundTurnExecutionPolicy.shouldDeferToActiveAudio(
        applicationIsActive: false,
        promptActive: false,
        speechCaptureActive: true,
        backgroundCaptureRunning: false
      )
    )
    XCTAssertFalse(
      IOSBackgroundTurnExecutionPolicy.shouldDeferToActiveAudio(
        applicationIsActive: true,
        promptActive: true,
        speechCaptureActive: true,
        backgroundCaptureRunning: true
      )
    )
    XCTAssertFalse(
      IOSBackgroundTurnExecutionPolicy.shouldDeferToActiveAudio(
        applicationIsActive: false,
        promptActive: false,
        speechCaptureActive: false,
        backgroundCaptureRunning: false
      )
    )
    XCTAssertTrue(
      IOSBackgroundTurnExecutionPolicy.shouldDeferToActiveAudio(
        applicationIsActive: false,
        promptActive: false,
        speechCaptureActive: false,
        backgroundCaptureRunning: true
      )
    )
  }

  func testBackgroundAudioHandoffOnlyStaysWarmOutsideForeground() {
    XCTAssertTrue(
      IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
        backgroundLearningEnabled: true,
        applicationIsActive: false
      )
    )
    XCTAssertFalse(
      IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
        backgroundLearningEnabled: false,
        applicationIsActive: false
      )
    )
    XCTAssertFalse(
      IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
        backgroundLearningEnabled: true,
        applicationIsActive: true
      )
    )
  }

  func testAiv0PendingButtonBufferIsBoundedAndDrainsChronologically() throws {
    var buffer = Aiv0PendingButtonEventBuffer(capacity: 2)

    buffer.append(["sequence": 1])
    buffer.append(["sequence": 2])
    buffer.append(["sequence": 3])

    XCTAssertEqual(buffer.count, 2)
    let drained = buffer.drain()
    XCTAssertEqual(drained.compactMap { $0["sequence"] as? Int }, [2, 3])
    XCTAssertEqual(buffer.count, 0)
  }

  func testAiv0ReconnectPolicyRecoversMainImmediatelyThenUsesBoundedBackoff() {
    XCTAssertEqual(Aiv0ReconnectPolicy.maxAttempts, 5)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 1), 0)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 2), 0.25)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 3), 0.75)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 4), 1.5)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 5), 3)
  }

  func testIOSSpeechStopSalvagePolicyPreservesOnlyStopTimePartialText() {
    XCTAssertEqual(
      IOSSpeechStopSalvagePolicy.transcript(
        stopping: true,
        latestText: "  Con muốn đi sở thú  "
      ),
      "Con muốn đi sở thú"
    )
    XCTAssertNil(
      IOSSpeechStopSalvagePolicy.transcript(
        stopping: true,
        latestText: "   "
      )
    )
    XCTAssertNil(
      IOSSpeechStopSalvagePolicy.transcript(
        stopping: false,
        latestText: "Con muốn đi sở thú"
      )
    )
  }

  func testAiv0DuplicatePacketFilterUsesAndroidParityWindow() {
    var filter = Aiv0DuplicatePacketFilter()

    XCTAssertFalse(filter.register(bytes: [0x01, 0x01], uptimeMilliseconds: 1_000))
    XCTAssertTrue(filter.register(bytes: [0x01, 0x01], uptimeMilliseconds: 1_750))
    XCTAssertEqual(filter.duplicateCount, 1)
    XCTAssertFalse(filter.register(bytes: [0x01, 0x02], uptimeMilliseconds: 1_800))

    filter.resetWindow()
    XCTAssertFalse(filter.register(bytes: [0x01, 0x02], uptimeMilliseconds: 1_900))
    XCTAssertEqual(filter.duplicateCount, 1)
  }

  func testAiv0DuplicatePacketFilterCollapsesObservedH20MainBurst() {
    var filter = Aiv0DuplicatePacketFilter()
    let packets: [[UInt8]] = [
      [0x01, 0x01, 0x06, 0x01, 0x01, 0x00, 0x39, 0x00, 0x83, 0x8C, 0x03, 0x00],
      [0x01, 0x01, 0x07, 0x01, 0x01, 0x00, 0x39, 0x00, 0x2B, 0x8F, 0x03, 0x00],
      [0x01, 0x01, 0x08, 0x01, 0x01, 0x00, 0x39, 0x00, 0xF3, 0x8F, 0x03, 0x00],
      [0x01, 0x01, 0x09, 0x01, 0x01, 0x00, 0x39, 0x00, 0xBB, 0x90, 0x03, 0x00],
      [0x01, 0x01, 0x0A, 0x01, 0x01, 0x00, 0x39, 0x00, 0x4B, 0x92, 0x03, 0x00],
    ]

    XCTAssertFalse(filter.register(bytes: packets[0], uptimeMilliseconds: 1_000))
    for (index, packet) in packets.dropFirst().enumerated() {
      XCTAssertTrue(
        filter.register(
          bytes: packet,
          uptimeMilliseconds: 1_200 + TimeInterval(index * 200)
        )
      )
    }
    XCTAssertEqual(filter.duplicateCount, 4)

    XCTAssertFalse(filter.register(bytes: packets[0], uptimeMilliseconds: 2_751))
  }

  func testAiv0DuplicatePacketFilterAcceptsANewMainAfterTheQuietWindow() {
    var filter = Aiv0DuplicatePacketFilter()
    let mainPacket: [UInt8] = [
      0x01, 0x01, 0x10, 0x01, 0x01, 0x00, 0x39, 0x00, 0x00, 0x10, 0x00, 0x00,
    ]

    XCTAssertFalse(filter.register(bytes: mainPacket, uptimeMilliseconds: 1_000))
    XCTAssertTrue(filter.register(bytes: mainPacket, uptimeMilliseconds: 1_750))
    XCTAssertFalse(filter.register(bytes: mainPacket, uptimeMilliseconds: 2_501))
    XCTAssertEqual(filter.duplicateCount, 1)
  }

  func testH20RemoteControlsRequireForegroundH20AndAnExplicitContext() {
    XCTAssertTrue(
      H20RemoteControlPolicy.shouldListen(
        applicationIsActive: true,
        learningActive: true,
        diagnosticsActive: false,
        bluetoothPortNames: ["HM-D001 Hands-Free"]
      )
    )
    XCTAssertTrue(
      H20RemoteControlPolicy.shouldListen(
        applicationIsActive: true,
        learningActive: true,
        diagnosticsActive: false,
        bluetoothPortNames: ["H20"]
      )
    )
    XCTAssertFalse(
      H20RemoteControlPolicy.shouldListen(
        applicationIsActive: false,
        learningActive: true,
        diagnosticsActive: true,
        bluetoothPortNames: ["H20 Hands-Free"]
      )
    )
    XCTAssertFalse(
      H20RemoteControlPolicy.shouldListen(
        applicationIsActive: true,
        learningActive: false,
        diagnosticsActive: false,
        bluetoothPortNames: ["H20"]
      )
    )
    XCTAssertFalse(
      H20RemoteControlPolicy.shouldListen(
        applicationIsActive: true,
        learningActive: true,
        diagnosticsActive: true,
        bluetoothPortNames: ["AirPods Pro"]
      )
    )
    XCTAssertTrue(
      H20RemoteControlPolicy.shouldListen(
        applicationIsActive: true,
        learningActive: false,
        diagnosticsActive: true,
        bluetoothPortNames: ["H20 Stereo"]
      )
    )
  }

  func testH20RemoteControlsNeverInventAPhysicalButtonOrBLEPacket() {
    for command in ["play", "pause", "togglePlayPause", "nextTrack", "previousTrack"] {
      let event = H20RemoteControlPolicy.observation(
        command: command,
        receivedAtEpochMs: 123
      )
      XCTAssertEqual(event["type"] as? String, "controlObservation")
      XCTAssertEqual(event["source"] as? String, "iosRemoteCommand")
      XCTAssertEqual(event["mediaCommand"] as? String, command)
      XCTAssertEqual(event["rawPayload"] as? String, command)
      XCTAssertEqual(event["button"] as? String, "unknown")
      XCTAssertEqual(event["gesture"] as? String, "unknown")
      XCTAssertEqual(event["protocol"] as? String, "unknown")
      XCTAssertEqual(event["receivedAtEpochMs"] as? Int, 123)
      XCTAssertNil(event["bytes"])
      XCTAssertNil(event["sequence"])
    }
  }

  func testH20BLEDiagnosticsDescribeOnlyObservedMainShort() {
    let blePacket: [UInt8] = [
      0x01, 0x01, 0x19, 0x01, 0x01, 0x00, 0x37, 0x00, 0x10, 0x04, 0x00, 0x00,
    ]
    let event = H20BleControlObservation.fields(for: blePacket)
    XCTAssertEqual(event["button"] as? String, "main")
    XCTAssertEqual(event["gesture"] as? String, "shortPress")
    XCTAssertEqual(event["protocol"] as? String, "observedV1")
    XCTAssertEqual(event["sequence"] as? Int, 0x19)
    XCTAssertEqual(H20BleControlObservation.batteryPercent(blePacket), 55)
    XCTAssertEqual(event["rawPayload"] as? String, "01 01 19 01 01 00 37 00 10 04 00 00")
  }

  func testH20BLEDiagnosticsKeepDraftAndMalformedPacketsUnknown() {
    let packets: [[UInt8]] = [
      [],
      [0x01, 0x01],
      [0x01, 0x01, 0x19, 0x02, 0x01, 0x00, 0x37, 0x00, 0x10, 0x04, 0x00, 0x00],
      [0x01, 0x02, 0x19, 0x01, 0x01, 0x00, 0x37, 0x00, 0x10, 0x04, 0x00, 0x00],
      [0xA5, 0x01, 0x01, 0x01, 0x01, 0x00, 0x37, 0x00, 0x10, 0x04, 0x00, 0x00],
    ]
    for packet in packets {
      let event = H20BleControlObservation.fields(for: packet)
      XCTAssertEqual(event["button"] as? String, "unknown")
      XCTAssertEqual(event["gesture"] as? String, "unknown")
      XCTAssertEqual(event["protocol"] as? String, "unknown")
      XCTAssertNil(event["sequence"])
      XCTAssertEqual(
        event["rawPayload"] as? String,
        packet.map { String(format: "%02X", $0) }.joined(separator: " ")
      )
    }
  }

  func testAiv0ReconnectPolicyCapsBackoffAfterTheFifthAttempt() {
    XCTAssertEqual(Aiv0ReconnectPolicy.maxAttempts, 5)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 5), 3)
    XCTAssertEqual(Aiv0ReconnectPolicy.delaySeconds(forAttempt: 6), 3)
  }

  func testAiv0DisconnectRecoveryDoesNotFightCoreBluetoothAutoReconnect() {
    XCTAssertEqual(
      Aiv0DisconnectRecoveryPolicy.nextStep(
        manualDisconnect: false,
        disposed: false,
        systemIsReconnecting: true
      ),
      .waitForSystem
    )
    XCTAssertEqual(
      Aiv0DisconnectRecoveryPolicy.nextStep(
        manualDisconnect: false,
        disposed: false,
        systemIsReconnecting: false
      ),
      .scheduleManualReconnect
    )
    XCTAssertEqual(
      Aiv0DisconnectRecoveryPolicy.nextStep(
        manualDisconnect: true,
        disposed: false,
        systemIsReconnecting: true
      ),
      .ignore
    )
  }

  func testAiv0ReconnectPolicyKeepsBleControlRecoveryIndependentOfHfpAudio() {
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: true,
        promptActive: false,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: false,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: true,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: false,
        speechCaptureActive: true,
        hfpRouteActive: false
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferReconnect(
        mainTurnActive: false,
        promptActive: false,
        speechCaptureActive: false,
        hfpRouteActive: true
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
        mainTurnActive: false,
        speechCaptureActive: false,
        hfpRouteActive: true
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
        mainTurnActive: false,
        speechCaptureActive: false,
        hfpRouteActive: false
      )
    )
    XCTAssertFalse(
      Aiv0ReconnectPolicy.shouldDeferNotificationMaintenance(
        mainTurnActive: false,
        speechCaptureActive: true,
        hfpRouteActive: true
      )
    )
  }

  func testIOSHfpIdleRouteReleaseWaitsForTheAuthoritativeRouteChange() {
    XCTAssertEqual(
      IOSHfpIdleRouteReleasePolicy.nextStep(
        hasTwoWayHfpRoute: true,
        attemptsRemaining: 20
      ),
      .wait
    )
    XCTAssertEqual(
      IOSHfpIdleRouteReleasePolicy.nextStep(
        hasTwoWayHfpRoute: false,
        attemptsRemaining: 20
      ),
      .complete
    )
    XCTAssertEqual(
      IOSHfpIdleRouteReleasePolicy.nextStep(
        hasTwoWayHfpRoute: true,
        attemptsRemaining: 0
      ),
      .timedOut
    )
  }

  func testIOSHfpVerifiedSelectionStaysReadyAfterIdleRouteRelease() {
    XCTAssertEqual(
      IOSHfpIdleReadinessPolicy.phase(
        hasVerifiedSelection: true,
        hasSelectedInput: true
      ),
      "ready"
    )
    XCTAssertEqual(
      IOSHfpIdleReadinessPolicy.phase(
        hasVerifiedSelection: false,
        hasSelectedInput: true
      ),
      "idle"
    )
    XCTAssertEqual(
      IOSHfpIdleReadinessPolicy.phase(
        hasVerifiedSelection: true,
        hasSelectedInput: false
      ),
      "idle"
    )
  }

  func testIOSAudioOwnershipKeepsPromptAliveWhenMainTurnEnds() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.mainTurn)
    ownership.acquire(.prompt)
    ownership.release(.mainTurn)

    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.prompt])

    ownership.release(.prompt)
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testIOSAudioOwnershipKeepsHfpRouteAcrossSpeechHandoffs() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.hfpRoute)
    ownership.acquire(.speechCapture)
    ownership.release(.speechCapture)

    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.hfpRoute])

    ownership.release(.hfpRoute)
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testIOSAudioEngineStartupPolicyAllowsExactlyOneBoundedRetry() {
    XCTAssertEqual(IOSAudioEngineStartupPolicy.maxAttempts, 2)
    XCTAssertTrue(IOSAudioEngineStartupPolicy.shouldRetry(afterAttempt: 1))
    XCTAssertFalse(IOSAudioEngineStartupPolicy.shouldRetry(afterAttempt: 2))
    XCTAssertGreaterThan(IOSAudioEngineStartupPolicy.retryDelayNanoseconds, 0)
  }

  func testIOSAudioOwnershipKeepsActiveLessonAcrossBackgroundAudioGap() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.backgroundTransition)
    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.backgroundTransition])

    ownership.release(.backgroundTransition)
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testIOSAudioOwnershipKeepsPrearmedBackgroundCaptureAcrossPromptHandoff() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.backgroundCapture)
    ownership.acquire(.prompt)
    ownership.release(.prompt)

    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.backgroundCapture])

    ownership.release(.backgroundCapture)
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testIOSAudioOwnershipOnlyReportsARealCaptureReleaseOnce() {
    var ownership = IOSAudioSessionOwnershipState()

    XCTAssertFalse(ownership.contains(.speechCapture))
    XCTAssertFalse(ownership.release(.speechCapture))
    ownership.acquire(.speechCapture)
    XCTAssertTrue(ownership.contains(.speechCapture))
    XCTAssertTrue(ownership.release(.speechCapture))
    XCTAssertFalse(ownership.release(.speechCapture))
  }

  func testIOSAudioOwnershipRequiresEverySameOwnerLeaseToRelease() {
    var ownership = IOSAudioSessionOwnershipState()

    ownership.acquire(.prompt)
    ownership.acquire(.prompt)

    XCTAssertTrue(ownership.release(.prompt))
    XCTAssertFalse(ownership.canDeactivate)
    XCTAssertEqual(ownership.activeOwners, [.prompt])

    XCTAssertTrue(ownership.release(.prompt))
    XCTAssertTrue(ownership.canDeactivate)
  }

  func testVoicePromptLeaseIgnoresAStaleCompletionFromThePreviousPrompt() {
    var lease = IOSPromptOperationLeaseState()
    let firstPrompt = UUID()
    let secondPrompt = UUID()

    lease.activate(firstPrompt)
    XCTAssertTrue(lease.release(firstPrompt))

    lease.activate(secondPrompt)
    XCTAssertFalse(lease.release(firstPrompt))
    XCTAssertEqual(lease.activeToken, secondPrompt)
    XCTAssertTrue(lease.release(secondPrompt))
    XCTAssertNil(lease.activeToken)
  }

  func testIOSStyledTranslationDoesNotChangeTheFollowingCoachPrompt() {
    let translated = AVSpeechUtterance(string: "I like apples.")
    IOSPromptSpeechStyle.apply(to: translated, speechRate: 0.85, pitch: 1.05)
    XCTAssertEqual(translated.rate, AVSpeechUtteranceDefaultSpeechRate * 0.85, accuracy: 0.001)
    XCTAssertEqual(translated.pitchMultiplier, 1.05, accuracy: 0.001)

    let coach = AVSpeechUtterance(string: "Giỏi lắm!")
    IOSPromptSpeechStyle.apply(to: coach, speechRate: nil, pitch: nil)
    XCTAssertEqual(coach.rate, AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.001)
    XCTAssertEqual(coach.pitchMultiplier, 1.0, accuracy: 0.001)
  }

  func testIOSPromptStyleBoundsInvalidChannelValues() {
    let utterance = AVSpeechUtterance(string: "Model")
    IOSPromptSpeechStyle.apply(to: utterance, speechRate: .infinity, pitch: .nan)
    XCTAssertEqual(utterance.rate, AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.001)
    XCTAssertEqual(utterance.pitchMultiplier, 1.0, accuracy: 0.001)

    IOSPromptSpeechStyle.apply(to: utterance, speechRate: 50, pitch: -1)
    XCTAssertEqual(utterance.rate, AVSpeechUtteranceDefaultSpeechRate * 1.5, accuracy: 0.001)
    XCTAssertEqual(utterance.pitchMultiplier, 0.8, accuracy: 0.001)
  }

  func testIOSHfpRouteLeaseReleasesAtUtteranceBoundary() {
    var lease = IOSHfpRouteLeaseState()

    XCTAssertTrue(lease.acquireIfNeeded(generation: 1))
    XCTAssertFalse(lease.acquireIfNeeded(generation: 1))
    XCTAssertTrue(lease.isHeld)

    XCTAssertTrue(lease.finishUtterance(generation: 1))
    XCTAssertFalse(lease.finishUtterance(generation: 1))
    XCTAssertFalse(lease.isHeld)
  }

  func testIOSHfpRouteLeaseIgnoresAStaleActivationCompletion() {
    var lease = IOSHfpRouteLeaseState()

    XCTAssertTrue(lease.acquireIfNeeded(generation: 1))
    XCTAssertTrue(lease.finishUtterance(generation: 1))
    XCTAssertTrue(lease.acquireIfNeeded(generation: 2))

    XCTAssertFalse(lease.releaseIfHeld(generation: 1))
    XCTAssertEqual(lease.activeGeneration, 2)
    XCTAssertTrue(lease.releaseIfHeld(generation: 2))
  }

  func testIOSHfpRouteLeaseTransfersWithoutAddingAnotherOwner() {
    var lease = IOSHfpRouteLeaseState()

    XCTAssertTrue(lease.acquireIfNeeded(generation: 1))
    XCTAssertFalse(lease.acquireIfNeeded(generation: 2))
    XCTAssertEqual(lease.activeGeneration, 2)
    XCTAssertFalse(lease.releaseIfHeld(generation: 1))
    XCTAssertTrue(lease.releaseIfHeld(generation: 2))
  }

  func testIOSHfpRouteReuseRequiresAnActiveAudioSession() {
    XCTAssertTrue(
      IOSHfpRouteReusePolicy.canReuse(
        hasTwoWayHfpRoute: true,
        audioSessionActive: true
      )
    )
    XCTAssertFalse(
      IOSHfpRouteReusePolicy.canReuse(
        hasTwoWayHfpRoute: true,
        audioSessionActive: false
      )
    )
  }

  func testIOSHfpRouteReuseRejectsAnActiveSessionWithoutTwoWayHfp() {
    XCTAssertFalse(
      IOSHfpRouteReusePolicy.canReuse(
        hasTwoWayHfpRoute: false,
        audioSessionActive: true
      )
    )
  }

  func testIOSPromptDoesNotReuseAStaleHfpRouteAfterSessionDeactivation() {
    XCTAssertFalse(
      IOSHfpRouteReusePolicy.canReuse(
        hasTwoWayHfpRoute: true,
        audioSessionActive: false
      )
    )
  }

  func testIOSCaptureDoesNotReuseAStaleHfpRouteAfterInterruption() {
    XCTAssertFalse(
      IOSHfpRouteReusePolicy.canReuse(
        hasTwoWayHfpRoute: true,
        audioSessionActive: false
      )
    )
  }

  func testIOSHfpInputSelectionRecoversTheSameH20AfterUIDChanges() {
    let selected = IOSHfpInputSelectionPolicy.select(
      from: [
        IOSHfpInputIdentity(uid: "new-h20-uid", name: "H20"),
        IOSHfpInputIdentity(uid: "airpods", name: "AirPods Pro")
      ],
      selectedUID: "old-h20-uid",
      selectedName: "H20"
    )

    XCTAssertEqual(selected?.uid, "new-h20-uid")
  }

  func testIOSHfpInputSelectionNeverSubstitutesAnUnrelatedHeadset() {
    let selected = IOSHfpInputSelectionPolicy.select(
      from: [IOSHfpInputIdentity(uid: "airpods", name: "AirPods Pro")],
      selectedUID: "old-h20-uid",
      selectedName: "H20"
    )

    XCTAssertNil(selected)
  }

  func testIOSPromptAndSpeechResolveRepublishedSelectedH20ByNormalizedName() {
    let inputs = [
      IOSHfpInputIdentity(uid: "airpods", name: "AirPods Pro"),
      IOSHfpInputIdentity(uid: "new-h20-uid", name: "HOMI H20")
    ]
    XCTAssertEqual(
      IOSPreferredHfpInputPolicy.select(
        from: inputs,
        selectedUID: "old-h20-uid",
        selectedName: "HOMI-H20"
      )?.uid,
      "new-h20-uid"
    )
    XCTAssertEqual(
      IOSPreferredHfpInputPolicy.select(
        from: inputs + [IOSHfpInputIdentity(uid: "old-h20-uid", name: "Other")],
        selectedUID: "old-h20-uid",
        selectedName: "HOMI-H20"
      )?.uid,
      "old-h20-uid"
    )
    XCTAssertNil(IOSPreferredHfpInputPolicy.select(
      from: [inputs[0]],
      selectedUID: "old-h20-uid",
      selectedName: "HOMI-H20"
    ))
    XCTAssertEqual(
      IOSPreferredHfpInputPolicy.select(
        from: inputs,
        selectedUID: nil,
        selectedName: nil
      )?.uid,
      "airpods"
    )
  }

  func testAiv0MainNotificationRefreshPreservesAHealthySubscription() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: false,
        isNotifying: true
      ),
      .complete
    )
  }

  func testAiv0MainNotificationRecoveryNeverTogglesAHealthyHfpSubscription() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        isNotifying: true
      ),
      .complete
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        isNotifying: false
      ),
      .enable
    )
  }

  func testAiv0MainNotificationTimeoutNeverDisconnectsAHealthyGattLink() {
    XCTAssertEqual(
      Aiv0MainNotificationTimeoutPolicy.nextStep(
        peripheralConnected: true,
        isNotifying: true
      ),
      .complete
    )
    XCTAssertEqual(
      Aiv0MainNotificationTimeoutPolicy.nextStep(
        peripheralConnected: true,
        isNotifying: false
      ),
      .reportFailure
    )
    XCTAssertEqual(
      Aiv0MainNotificationTimeoutPolicy.nextStep(
        peripheralConnected: false,
        isNotifying: false
      ),
      .reconnect
    )
  }

  func testAiv0DeferredRecoveryRepairsBleControlDuringAnHfpTurn() {
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: true,
        peripheralConnected: true,
        hasButtonCharacteristic: true
      ),
      .rearmNotification
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: true,
        peripheralConnected: true,
        hasButtonCharacteristic: false
      ),
      .rediscover
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: true,
        peripheralConnected: false,
        hasButtonCharacteristic: false
      ),
      .reconnect
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: false,
        peripheralConnected: true,
        hasButtonCharacteristic: true
      ),
      .rearmNotification
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: false,
        peripheralConnected: true,
        hasButtonCharacteristic: false
      ),
      .rediscover
    )
    XCTAssertEqual(
      Aiv0DeferredRecoveryPolicy.nextStep(
        audioCritical: false,
        peripheralConnected: false,
        hasButtonCharacteristic: false
      ),
      .reconnect
    )
  }

  func testAiv0DeferredRecoveryTraceCollapsesRepeatedWaits() {
    var traceState = Aiv0DeferredRecoveryTraceState()

    XCTAssertTrue(traceState.record(.wait))
    XCTAssertFalse(traceState.record(.wait))
    XCTAssertFalse(traceState.record(.wait))
    XCTAssertEqual(traceState.repeatCount, 3)

    XCTAssertTrue(traceState.record(.rearmNotification))
    XCTAssertEqual(traceState.repeatCount, 1)

    traceState.reset()
    XCTAssertEqual(traceState.repeatCount, 0)
    XCTAssertTrue(traceState.record(.wait))
  }

  func testAiv0MainNotificationRefreshEnablesOnlyAMissingSubscription() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: false,
        isNotifying: false
      ),
      .enable
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: true,
        isNotifying: false
      ),
      .enable
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        refreshInProgress: true,
        isNotifying: true
      ),
      .complete
    )
  }

  func testAiv0MainNotificationRefreshSkipsAnUnavailableGattLink() {
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: false,
        hasButtonCharacteristic: true,
        refreshInProgress: false,
        isNotifying: true
      ),
      .reconnect
    )
    XCTAssertEqual(
      Aiv0MainNotificationRefreshPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: false,
        refreshInProgress: false,
        isNotifying: false
      ),
      .rediscover
    )
  }

  func testAiv0ConnectStartPreservesAnAlreadyReadyGattSession() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        hasStateCharacteristic: true,
        isNotifying: true
      ),
      .complete
    )
  }

  func testAiv0ConnectStartRediscoversWithoutReconnectingAnAttachedPeripheral() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: false,
        hasStateCharacteristic: false,
        isNotifying: false
      ),
      .rediscover
    )
  }

  func testAiv0ConnectStartRestoresOnlyAMissingNotification() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: true,
        hasButtonCharacteristic: true,
        hasStateCharacteristic: true,
        isNotifying: false
      ),
      .enable
    )
  }

  func testAiv0ConnectStartConnectsOnlyADisconnectedPeripheral() {
    XCTAssertEqual(
      Aiv0ConnectStartPolicy.nextStep(
        peripheralConnected: false,
        hasButtonCharacteristic: false,
        hasStateCharacteristic: false,
        isNotifying: false
      ),
      .connect
    )
  }

  func testAiv0InitialNotificationSetupCompletesAnExistingSubscription() {
    XCTAssertEqual(
      Aiv0InitialNotificationSetupPolicy.nextStep(isNotifying: true),
      .complete
    )
    XCTAssertEqual(
      Aiv0InitialNotificationSetupPolicy.nextStep(isNotifying: false),
      .enable
    )
  }

  func testIOSAudioCoordinatorPromotesPhysicalMainIntoOneTurnTimeline() {
    let coordinator = IOSAudioSessionCoordinator()
    var timeline: [[String: Any]] = []
    coordinator.attachTraceSink { timeline.append($0) }

    coordinator.notePhysicalMain(rawHex: "01 01 01 01")
    let turnId = coordinator.beginMainTurn(source: "RunnerTests")

    let rawEvent = timeline.first {
      ($0["stage"] as? String) == "MAIN_RAW_RECEIVED"
    }
    XCTAssertEqual(rawEvent?["turnId"] as? String, turnId)
    XCTAssertTrue(
      timeline.contains { ($0["stage"] as? String) == "main_turn_started" }
    )
    XCTAssertTrue(coordinator.isMainTurnActive)

    coordinator.endMainTurn(reason: "test_complete", caller: "RunnerTests")
    XCTAssertFalse(coordinator.isMainTurnActive)
    let lastMainTurnStage = timeline.reversed().compactMap {
      $0["stage"] as? String
    }.first { $0.hasPrefix("main_turn_") }
    XCTAssertEqual(lastMainTurnStage, "main_turn_ended")
    XCTAssertTrue(
      timeline.contains {
        ($0["stage"] as? String) == "audio_session_release_requested"
      }
    )
    coordinator.dispose()
  }

  func testIOSAudioCoordinatorIgnoresStaleMainTurnEnd() {
    let coordinator = IOSAudioSessionCoordinator()
    var timeline: [[String: Any]] = []
    coordinator.attachTraceSink { timeline.append($0) }

    let turnId = coordinator.beginMainTurn(source: "RunnerTests")
    coordinator.endMainTurn(
      reason: "late_controller_pause",
      caller: "RunnerTests",
      expectedTurnId: "obsolete-turn"
    )

    XCTAssertTrue(coordinator.isMainTurnActive)
    let stageAfterStaleEnd = timeline.reversed().compactMap {
      $0["stage"] as? String
    }.first { $0.hasPrefix("main_turn_") }
    XCTAssertEqual(stageAfterStaleEnd, "main_turn_end_stale_ignored")

    coordinator.endMainTurn(
      reason: "test_complete",
      caller: "RunnerTests",
      expectedTurnId: turnId
    )
    XCTAssertFalse(coordinator.isMainTurnActive)
    let stageAfterValidEnd = timeline.reversed().compactMap {
      $0["stage"] as? String
    }.first { $0.hasPrefix("main_turn_") }
    XCTAssertEqual(stageAfterValidEnd, "main_turn_ended")
    XCTAssertTrue(
      timeline.contains {
        ($0["stage"] as? String) == "audio_session_release_requested"
      }
    )
    coordinator.dispose()
  }

  func testIOSAudioCoordinatorGivesASecondPhysicalPressAFreshTurn() {
    let coordinator = IOSAudioSessionCoordinator()
    var timeline: [[String: Any]] = []
    coordinator.attachTraceSink { timeline.append($0) }

    coordinator.notePhysicalMain(rawHex: "01 01 01 01")
    let firstTurnId = coordinator.beginMainTurn(source: "RunnerTests.first")

    coordinator.notePhysicalMain(rawHex: "01 01 02 01")
    let secondRawEvent = timeline.last {
      ($0["stage"] as? String) == "MAIN_RAW_RECEIVED"
    }
    let secondTurnId = coordinator.beginMainTurn(source: "RunnerTests.second")

    XCTAssertNotEqual(secondTurnId, firstTurnId)
    XCTAssertEqual(secondRawEvent?["turnId"] as? String, secondTurnId)
    XCTAssertTrue(
      timeline.contains {
        ($0["stage"] as? String) == "main_turn_superseded"
          && ($0["previousTurnId"] as? String) == firstTurnId
      }
    )

    coordinator.endMainTurn(
      reason: "late_first_turn_cleanup",
      caller: "RunnerTests",
      expectedTurnId: firstTurnId
    )
    XCTAssertTrue(coordinator.isMainTurnActive)
    XCTAssertEqual(
      timeline.last { ($0["stage"] as? String)?.hasPrefix("main_turn_") == true }?["stage"] as? String,
      "main_turn_end_stale_ignored"
    )

    coordinator.endMainTurn(
      reason: "test_complete",
      caller: "RunnerTests",
      expectedTurnId: secondTurnId
    )
    XCTAssertFalse(coordinator.isMainTurnActive)
    coordinator.dispose()
  }

  func testIOSAudioCoordinatorReturnsABoundedChronologicalDiagnosticTimeline() {
    let coordinator = IOSAudioSessionCoordinator()
    for index in 0..<205 {
      coordinator.trace(
        stage: "event_\(index)",
        caller: "RunnerTests",
        values: ["index": index]
      )
    }

    let timeline = coordinator.diagnosticTimelineSnapshot()

    XCTAssertEqual(timeline.count, 200)
    XCTAssertEqual(timeline.first?["stage"] as? String, "event_5")
    XCTAssertEqual(timeline.last?["stage"] as? String, "event_204")
    XCTAssertEqual(
      coordinator.diagnosticTimelineSnapshot(limit: 2).compactMap {
        $0["stage"] as? String
      },
      ["event_203", "event_204"]
    )
    coordinator.dispose()
  }

  func testIOSNativeSpeechPrefersSpeechAnalyzerOnIOS26() {
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: true,
        speechAnalyzerSupported: true,
        sfOnDeviceSupported: true
      ),
      .speechAnalyzer
    )
  }

  func testIOSNativeSpeechFallsBackOnlyToOnDeviceLegacyRecognizer() {
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: true,
        speechAnalyzerSupported: false,
        sfOnDeviceSupported: true
      ),
      .sfSpeechRecognizer
    )
    XCTAssertNil(
      IOSNativeSpeechEngineSelector.select(
        isIOS26OrNewer: false,
        speechAnalyzerSupported: false,
        sfOnDeviceSupported: false
      )
    )
  }

  func testIOSMainUsesDictationForVietnameseNavigationPhrases() {
    XCTAssertEqual(
      IOSNativeSpeechTaskHintSelector.select(commandMode: true),
      .dictation
    )
  }

  func testIOSMainKeepsPreparedSpeechAnalyzerOnIOS26() {
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.selectForRecognition(
        preparedEngine: .speechAnalyzer,
        commandMode: true,
        sfOnDeviceSupported: true
      ),
      .speechAnalyzer
    )
    XCTAssertEqual(
      IOSNativeSpeechEngineSelector.selectForRecognition(
        preparedEngine: .speechAnalyzer,
        commandMode: false,
        sfOnDeviceSupported: true
      ),
      .speechAnalyzer
    )
  }

  func testIOSAudioBufferLevelReadsFloatAndInt16MicrophoneBuffers() throws {
    let floatFormat = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    let floatBuffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: floatFormat, frameCapacity: 4)
    )
    floatBuffer.frameLength = 4
    for index in 0..<4 {
      floatBuffer.floatChannelData?[0][index] = 0.5
    }

    let int16Format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 8_000,
        channels: 1,
        interleaved: false
      )
    )
    let int16Buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: int16Format, frameCapacity: 4)
    )
    int16Buffer.frameLength = 4
    for index in 0..<4 {
      int16Buffer.int16ChannelData?[0][index] = 16_384
    }

    XCTAssertEqual(try XCTUnwrap(IOSAudioBufferLevel.dbfs(floatBuffer)), -6.02, accuracy: 0.1)
    XCTAssertEqual(try XCTUnwrap(IOSAudioBufferLevel.dbfs(int16Buffer)), -6.02, accuracy: 0.1)
  }

  func testIOSLessonRecordingFormatKeepsHfpAndPhoneRatesWithPCM16Storage() throws {
    for rate in [8_000.0, 16_000.0, 48_000.0] {
      let format = try XCTUnwrap(
        AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: rate,
          channels: 1,
          interleaved: false
        )
      )
      let settings = IOSLessonRecordingFormat.settings(for: format)
      XCTAssertEqual(settings[AVSampleRateKey] as? Double, rate)
      XCTAssertEqual(settings[AVNumberOfChannelsKey] as? AVAudioChannelCount, 1)
      XCTAssertEqual(settings[AVLinearPCMBitDepthKey] as? Int, 16)
      XCTAssertEqual(settings[AVLinearPCMIsFloatKey] as? Bool, false)
      XCTAssertEqual(settings[AVLinearPCMIsBigEndianKey] as? Bool, false)
    }
  }

  func testIOSLessonRecordingWritesReadablePCM16WavWithoutMutatingASRBuffer() throws {
    let format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
      )
    )
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
    buffer.frameLength = 480
    for index in 0..<480 { buffer.floatChannelData?[0][index] = 0.25 }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("homi-pcm16-test-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    var writer: AVAudioFile? = try AVAudioFile(
      forWriting: url,
      settings: IOSLessonRecordingFormat.settings(for: format),
      commonFormat: format.commonFormat,
      interleaved: format.isInterleaved
    )
    try writer?.write(from: buffer)
    writer = nil

    let reader = try AVAudioFile(forReading: url)
    XCTAssertEqual(reader.fileFormat.commonFormat, .pcmFormatInt16)
    XCTAssertEqual(reader.fileFormat.sampleRate, 48_000)
    XCTAssertEqual(reader.length, 480)
    XCTAssertEqual(try XCTUnwrap(buffer.floatChannelData?[0][0]), 0.25, accuracy: 0.0001)
    let readBack = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 480)
    )
    try reader.read(into: readBack)
    XCTAssertEqual(try XCTUnwrap(readBack.floatChannelData?[0][0]), 0.25, accuracy: 0.0001)
  }

  func testIOSLessonRecordingGainRaisesAndClipsPersistedSamples() throws {
    let format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    let buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)
    )
    buffer.frameLength = 2
    buffer.floatChannelData?[0][0] = 0.2
    buffer.floatChannelData?[0][1] = 0.8

    IOSLessonRecordingGain.apply(to: buffer)

    XCTAssertEqual(try XCTUnwrap(buffer.floatChannelData?[0][0]), 0.5, accuracy: 0.001)
    XCTAssertEqual(try XCTUnwrap(buffer.floatChannelData?[0][1]), 1, accuracy: 0.001)
  }

  func testLessonRecordingLevelingBringsQuietAndLoudSpeechToTarget() throws {
    for inputDbfs in [-35.0, -6.0] {
      let buffer = try Self.lessonSpeech(dbfs: inputDbfs, frames: 16_000)
      let channels = try XCTUnwrap(buffer.floatChannelData)

      XCTAssertTrue(
        VoicePromptBridge.levelLessonRecording(
          channels: channels,
          channelCount: 1,
          frameLength: Int(buffer.frameLength),
          sampleRate: 16_000
        )
      )

      XCTAssertEqual(
        Self.rmsDbfs(channels[0], range: 0..<3_200),
        VoicePromptBridge.lessonRecordingTargetDbfs,
        accuracy: 0.2
      )
    }
  }

  func testLessonRecordingLevelingLimitsAPlosiveInsteadOfCappingGain() throws {
    let buffer = try Self.lessonSpeech(dbfs: -35, frames: 32_000)
    let channels = try XCTUnwrap(buffer.floatChannelData)
    channels[0][16_000] = 1
    channels[0][16_001] = -1

    XCTAssertTrue(
      VoicePromptBridge.levelLessonRecording(
        channels: channels,
        channelCount: 1,
        frameLength: Int(buffer.frameLength),
        sampleRate: 16_000
      )
    )

    let ceiling = Float(pow(10.0, -1.0 / 20.0)) + 0.000_1
    for frame in 0..<32_000 {
      XCTAssertLessThanOrEqual(abs(channels[0][frame]), ceiling)
    }
    XCTAssertEqual(
      Self.rmsDbfs(channels[0], range: 19_200..<22_400),
      VoicePromptBridge.lessonRecordingTargetDbfs,
      accuracy: 0.2
    )
  }

  func testLessonRecordingLevelingIgnoresAClickFarLouderThanSpeech() throws {
    let buffer = try Self.lessonSpeech(dbfs: -35, frames: 32_000)
    let channels = try XCTUnwrap(buffer.floatChannelData)
    for frame in 16_000..<16_032 {
      channels[0][frame] = frame.isMultiple(of: 2) ? 1 : -1
    }

    XCTAssertTrue(
      VoicePromptBridge.levelLessonRecording(
        channels: channels,
        channelCount: 1,
        frameLength: Int(buffer.frameLength),
        sampleRate: 16_000
      )
    )

    XCTAssertEqual(
      Self.rmsDbfs(channels[0], range: 0..<3_200),
      VoicePromptBridge.lessonRecordingTargetDbfs,
      accuracy: 0.2
    )
  }

  func testLessonRecordingLevelingRaisesVeryQuietSpeechByAtMost20Db() throws {
    let buffer = try Self.lessonSpeech(dbfs: -45, frames: 32_000)
    let channels = try XCTUnwrap(buffer.floatChannelData)

    XCTAssertTrue(
      VoicePromptBridge.levelLessonRecording(
        channels: channels,
        channelCount: 1,
        frameLength: Int(buffer.frameLength),
        sampleRate: 16_000
      )
    )

    XCTAssertEqual(Self.rmsDbfs(channels[0], range: 0..<3_200), -25, accuracy: 0.2)
  }

  func testLessonRecordingLevelingNeverRaisesSteadyBackgroundNoise() throws {
    let buffer = try Self.lessonTone(dbfs: -200, frames: 32_000)
    let channels = try XCTUnwrap(buffer.floatChannelData)
    Self.addNoise(channels[0], frames: 32_000, dbfs: -45)

    XCTAssertFalse(
      VoicePromptBridge.levelLessonRecording(
        channels: channels,
        channelCount: 1,
        frameLength: Int(buffer.frameLength),
        sampleRate: 16_000
      )
    )
  }

  func testLessonRecordingLevelingTurnsLongPausesDownButKeepsWordGaps() throws {
    // Five words over 1.5 s, then 1.5 s of silence, over steady room noise.
    let buffer = try Self.lessonSpeech(dbfs: -37, frames: 48_000)
    let channels = try XCTUnwrap(buffer.floatChannelData)
    for frame in 24_000..<48_000 { channels[0][frame] = 0 }
    Self.addNoise(channels[0], frames: 48_000, dbfs: -60)

    XCTAssertTrue(
      VoicePromptBridge.levelLessonRecording(
        channels: channels,
        channelCount: 1,
        frameLength: Int(buffer.frameLength),
        sampleRate: 16_000
      )
    )

    XCTAssertEqual(
      Self.rmsDbfs(channels[0], range: 0..<3_200),
      VoicePromptBridge.lessonRecordingTargetDbfs,
      accuracy: 0.2
    )
    // A 100 ms gap between words keeps the full gain: -60 + 20 dB.
    XCTAssertEqual(Self.rmsDbfs(channels[0], range: 3_200..<4_800), -40, accuracy: 1)
    // Well after the last word the noise is 10 dB lower.
    XCTAssertEqual(Self.rmsDbfs(channels[0], range: 35_200..<48_000), -50, accuracy: 1)
  }

  func testLessonRecordingLevelingNeverTurnsSpeechDownForALongKnock() throws {
    let buffer = try Self.lessonTone(dbfs: -40, frames: 32_000)
    let channels = try XCTUnwrap(buffer.floatChannelData)
    for frame in 16_000..<17_280 {
      channels[0][frame] = frame.isMultiple(of: 2) ? 1 : -1
    }

    _ = VoicePromptBridge.levelLessonRecording(
      channels: channels,
      channelCount: 1,
      frameLength: Int(buffer.frameLength),
      sampleRate: 16_000
    )

    XCTAssertEqual(Self.rmsDbfs(channels[0], range: 0..<15_000), -40, accuracy: 0.1)
  }

  private static func lessonTone(dbfs: Double, frames: Int) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    let buffer = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
    )
    buffer.frameLength = AVAudioFrameCount(frames)
    let amplitude = sqrt(2.0) * pow(10.0, dbfs / 20.0)
    let channel = try XCTUnwrap(buffer.floatChannelData?[0])
    for frame in 0..<frames {
      channel[frame] = Float(amplitude * sin(2 * Double.pi * 220 * Double(frame) / 16_000))
    }
    return buffer
  }

  /// `lessonTone` cut into 200 ms words with 100 ms pauses, like speech.
  private static func lessonSpeech(dbfs: Double, frames: Int) throws -> AVAudioPCMBuffer {
    let buffer = try lessonTone(dbfs: dbfs, frames: frames)
    let channel = try XCTUnwrap(buffer.floatChannelData?[0])
    for frame in 0..<frames where frame % 4_800 >= 3_200 {
      channel[frame] = 0
    }
    return buffer
  }

  /// Adds seeded white noise whose RMS is `dbfs`.
  private static func addNoise(_ samples: UnsafeMutablePointer<Float>, frames: Int, dbfs: Double) {
    let amplitude = sqrt(3.0) * pow(10.0, dbfs / 20.0)
    var state: UInt64 = 7
    for frame in 0..<frames {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let unit = Double(state >> 11) / Double(1 << 53)
      samples[frame] += Float((unit * 2 - 1) * amplitude)
    }
  }

  private static func rmsDbfs(_ samples: UnsafeMutablePointer<Float>, range: Range<Int>) -> Double {
    var power = 0.0
    for frame in range {
      power += Double(samples[frame]) * Double(samples[frame])
    }
    return 10 * log10(power / Double(range.count))
  }

  func testIOSBuiltInMicPolicyExcludesBluetoothOptions() {
    let options = IOSNativeSpeechAudioRoutePolicy.categoryOptions(
      for: .builtInMic
    )

    XCTAssertTrue(options.contains(.defaultToSpeaker))
    XCTAssertFalse(options.contains(.allowBluetoothHFP))
    XCTAssertFalse(options.contains(.allowBluetoothA2DP))
    XCTAssertTrue(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .builtInMic,
        for: .builtInMic
      )
    )
    XCTAssertFalse(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .bluetoothHFP,
        for: .builtInMic
      )
    )
  }

  func testIOSHfpPolicyRequiresARealBluetoothInputRoute() {
    let options = IOSNativeSpeechAudioRoutePolicy.categoryOptions(for: .hfp)

    XCTAssertTrue(options.contains(.allowBluetoothHFP))
    XCTAssertFalse(options.contains(.defaultToSpeaker))
    XCTAssertFalse(options.contains(.allowBluetoothA2DP))
    XCTAssertTrue(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .bluetoothHFP,
        for: .hfp
      )
    )
    XCTAssertFalse(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .bluetoothLE,
        for: .hfp
      )
    )
    XCTAssertFalse(
      IOSNativeSpeechAudioRoutePolicy.accepts(
        portType: .builtInMic,
        for: .hfp
      )
    )
    XCTAssertTrue(
      IOSHfpRoutePolicy.isTwoWayHfpRoute(
        inputTypes: [.bluetoothHFP],
        outputTypes: [.bluetoothHFP]
      )
    )
    XCTAssertFalse(
      IOSHfpRoutePolicy.isTwoWayHfpRoute(
        inputTypes: [.bluetoothHFP],
        outputTypes: [.builtInSpeaker]
      )
    )
  }

}

private final class MainTurnAudioTargetHandoff: IOSBackgroundCaptureHandoffDelegate {
  private unowned let coordinator: IOSAudioSessionCoordinator
  private(set) var targets: [IOSAudioInputTarget?] = []

  init(coordinator: IOSAudioSessionCoordinator) {
    self.coordinator = coordinator
  }

  func armBackgroundAudioHandoff(caller: String, completion: @escaping () -> Void) {
    targets.append(coordinator.mainAudioInputTarget)
    completion()
  }

  func disarmBackgroundAudioHandoff(caller: String) {}
}
