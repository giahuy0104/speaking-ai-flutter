import AVFoundation
import Flutter
import Foundation
import UIKit

enum IOSAudioInputTarget: String {
  case builtInMic
  case hfp
}

enum IOSMainTurnAudioRoutePolicy {
  static func inputTarget(fromChannelValue value: Any?) -> IOSAudioInputTarget? {
    guard let value = value as? String else { return nil }
    return IOSAudioInputTarget(rawValue: value)
  }

  static func forcesPhoneSpeaker(
    explicitRequest: Bool,
    mainInputTarget: IOSAudioInputTarget?
  ) -> Bool {
    explicitRequest || mainInputTarget == .builtInMic
  }

  static func requiresHfp(
    mainInputTarget: IOSAudioInputTarget?,
    explicitPhoneRequest: Bool
  ) -> Bool {
    mainInputTarget == .hfp && !explicitPhoneRequest
  }
}

enum IOSAudioSessionOwner: String, Hashable {
  case backgroundCapture
  case backgroundTransition
  case mainTurn
  case prompt
  case playback
  case hfpRoute
  case speechCapture
}

struct IOSBackgroundCaptureMixingPolicy {
  static func shouldMix(
    backgroundCaptureArmed: Bool,
    owners: [IOSAudioSessionOwner],
    interrupted: Bool
  ) -> Bool {
    backgroundCaptureArmed && !interrupted && !owners.contains {
      $0 == .mainTurn || $0 == .prompt || $0 == .playback
        || $0 == .speechCapture || $0 == .hfpRoute
    }
  }

  static func options(
    base: AVAudioSession.CategoryOptions,
    mixing: Bool
  ) -> AVAudioSession.CategoryOptions {
    mixing ? base.union(.mixWithOthers) : base.subtracting(.mixWithOthers)
  }
}

/// The hardware operations at the warm-input boundary are injectable; ownership
/// and generation checks remain in the coordinator for both device and tests.
struct IOSBackgroundCaptureSessionDriver {
  let prepare: (IOSAudioInputTarget, Bool, String) throws -> Void
  let applyMixing: (Bool, String) throws -> Void
  let isOtherAudioPlaying: () -> Bool
}

/// Shared with the main-thread event sink; never waits for native audio work.
private final class IOSPassiveAudioEventGate {
  private let lock = NSLock()
  private var generation = 0
  private var pending: Int?
  private var delivered = false

  func issue() -> Int? {
    lock.lock()
    defer { lock.unlock() }
    guard pending == nil, !delivered else { return nil }
    generation += 1
    pending = generation
    return generation
  }

  func claim(_ candidate: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard pending == candidate else { return false }
    pending = nil
    delivered = true
    return true
  }

  func cancel() {
    lock.lock()
    defer { lock.unlock() }
    generation += 1
    pending = nil
    delivered = false
  }
}

/// Keep speech capture on the headset selected in Settings, including when
/// iOS republishes the same device with a new transient HFP input UID.
struct IOSSelectedHfpRoutePolicy {
  static func matches(
    active: IOSHfpInputIdentity?,
    selected: IOSHfpInputIdentity?
  ) -> Bool {
    guard let active, let selected else { return false }
    return IOSHfpInputSelectionPolicy.select(
      from: [active],
      selectedUID: selected.uid,
      selectedName: selected.name
    ) != nil
  }
}

/// Applies the same selected-device identity rule while resolving an input
/// for prompt and speech setup. An unselected app may use the first HFP input;
/// once a device is selected, an unrelated headset is never a fallback.
struct IOSPreferredHfpInputPolicy {
  static func select(
    from inputs: [IOSHfpInputIdentity],
    selectedUID: String?,
    selectedName: String?
  ) -> IOSHfpInputIdentity? {
    if selectedUID == nil && selectedName == nil {
      return inputs.first
    }
    return IOSHfpInputSelectionPolicy.select(
      from: inputs,
      selectedUID: selectedUID,
      selectedName: selectedName
    )
  }
}

/// The serial executor of the native audio and device bridges.
///
/// AVAudioSession, AVAudioPlayer and AVAudioEngine calls block their caller
/// until the audio hardware has answered, and Flutter draws its frames on the
/// main thread. The bridges and the coordinator therefore keep their state on
/// this queue. Only Flutter channel replies, event sinks and UIKit calls go
/// back to the main thread.
enum IOSNativeWork {
  private static let queueKey = DispatchSpecificKey<Bool>()
  private static let stateLock = NSLock()
  private static var applicationActive = false
  private static var applicationStateTokens: [NSObjectProtocol] = []

  static let queue: DispatchQueue = {
    let queue = DispatchQueue(label: "ailingo.native-work", qos: .userInitiated)
    queue.setSpecific(key: queueKey, value: true)
    return queue
  }()

  static let operationQueue: OperationQueue = {
    let operationQueue = OperationQueue()
    operationQueue.underlyingQueue = queue
    operationQueue.maxConcurrentOperationCount = 1
    return operationQueue
  }()

  static var isCurrent: Bool { DispatchQueue.getSpecific(key: queueKey) == true }

  /// Runs `work` on the queue and waits for it. The queue never waits for the
  /// main thread, so the main thread may use this for an application
  /// lifecycle step that must finish before iOS moves the app on.
  static func sync<T>(_ work: () throws -> T) rethrows -> T {
    if isCurrent { return try work() }
    return try queue.sync(execute: work)
  }

  static func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  /// Whether the latest UIKit lifecycle event left the app active.
  static var applicationIsActive: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return applicationActive
  }

  /// Call on the main thread.
  static func refreshApplicationState() {
    let active = UIApplication.shared.applicationState == .active
    stateLock.lock()
    applicationActive = active
    stateLock.unlock()
  }

  /// UIKit can still report `.active` inside willResignActive. Mark the
  /// transition immediately so queued audio work cannot stop a prearmed input.
  /// Call on the main thread.
  static func markApplicationInactive() {
    stateLock.lock()
    applicationActive = false
    stateLock.unlock()
  }

  /// Call on the main thread when UIKit reports that the app became active.
  static func markApplicationActive() {
    stateLock.lock()
    applicationActive = true
    stateLock.unlock()
  }

  /// Call once on the main thread, before any bridge observes the lifecycle.
  static func observeApplicationState() {
    guard applicationStateTokens.isEmpty else { return }
    refreshApplicationState()
    let names: [Notification.Name] = [
      UIApplication.didBecomeActiveNotification,
      UIApplication.willResignActiveNotification,
      UIApplication.didEnterBackgroundNotification,
      UIApplication.willEnterForegroundNotification,
    ]
    applicationStateTokens = names.map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
        if name == UIApplication.didBecomeActiveNotification {
          markApplicationActive()
        } else {
          markApplicationInactive()
        }
      }
    }
  }

  /// A method-call handler that runs on the queue and replies on the main thread.
  static func handler(
    _ handle: @escaping (FlutterMethodCall, @escaping FlutterResult) -> Void
  ) -> FlutterMethodCallHandler {
    { call, result in
      queue.async {
        handle(call) { value in
          DispatchQueue.main.async { result(value) }
        }
      }
    }
  }

  /// An event sink that may be called from the queue.
  static func mainSink(_ sink: @escaping FlutterEventSink) -> FlutterEventSink {
    { event in
      DispatchQueue.main.async { sink(event) }
    }
  }
}

/// Runs Swift concurrency jobs on `IOSNativeWork.queue`, so an `async`
/// function of a bridge keeps touching bridge state on that queue.
final class IOSNativeWorkExecutor: SerialExecutor {
  func enqueue(_ job: UnownedJob) {
    IOSNativeWork.queue.async {
      job.runSynchronously(on: self.asUnownedSerialExecutor())
    }
  }

  func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    UnownedSerialExecutor(ordinary: self)
  }
}

@globalActor
actor IOSNativeWorkActor {
  static let shared = IOSNativeWorkActor()
  private static let executor = IOSNativeWorkExecutor()

  nonisolated var unownedExecutor: UnownedSerialExecutor {
    Self.executor.asUnownedSerialExecutor()
  }
}

/// Ends a background task once, from whichever thread gets there first. iOS
/// calls the expiration handler on the main thread and ends the process when
/// the task is still open after the handler returns.
final class IOSBackgroundTaskEnder {
  private let lock = NSLock()
  private var identifier = UIBackgroundTaskIdentifier.invalid
  private var ended = false

  func set(_ identifier: UIBackgroundTaskIdentifier) {
    lock.lock()
    let endNow = ended
    if !endNow { self.identifier = identifier }
    lock.unlock()
    if endNow, identifier != .invalid {
      UIApplication.shared.endBackgroundTask(identifier)
    }
  }

  func end() {
    lock.lock()
    ended = true
    let identifier = identifier
    self.identifier = .invalid
    lock.unlock()
    if identifier != .invalid {
      UIApplication.shared.endBackgroundTask(identifier)
    }
  }
}

/// A flag written on the native work queue and read on the main thread.
final class IOSNativeWorkFlag {
  private let lock = NSLock()
  private var stored = false

  var value: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return stored
    }
    set {
      lock.lock()
      stored = newValue
      lock.unlock()
    }
  }
}

struct IOSAudioSessionOwnershipState {
  private var leaseCounts: [IOSAudioSessionOwner: Int] = [:]

  mutating func acquire(_ owner: IOSAudioSessionOwner) {
    leaseCounts[owner, default: 0] += 1
  }

  @discardableResult
  mutating func release(_ owner: IOSAudioSessionOwner) -> Bool {
    guard let count = leaseCounts[owner], count > 0 else { return false }
    if count == 1 {
      leaseCounts.removeValue(forKey: owner)
    } else {
      leaseCounts[owner] = count - 1
    }
    return true
  }

  func contains(_ owner: IOSAudioSessionOwner) -> Bool {
    (leaseCounts[owner] ?? 0) > 0
  }

  var canDeactivate: Bool { leaseCounts.isEmpty }

  var activeOwners: [IOSAudioSessionOwner] {
    leaseCounts.keys.sorted { $0.rawValue < $1.rawValue }
  }
}

struct IOSBackgroundTurnExecutionPolicy {
  static func shouldRetain(
    backgroundLearningEnabled: Bool,
    applicationIsActive: Bool,
    interactionPendingOrActive: Bool
  ) -> Bool {
    backgroundLearningEnabled
      && !applicationIsActive
      && interactionPendingOrActive
  }

  static func shouldDeferToActiveAudio(
    applicationIsActive: Bool,
    promptActive: Bool,
    speechCaptureActive: Bool,
    backgroundCaptureRunning: Bool
  ) -> Bool {
    !applicationIsActive
      && (promptActive || speechCaptureActive || backgroundCaptureRunning)
  }
}

protocol IOSBackgroundCaptureHandoffDelegate: AnyObject {
  func armBackgroundAudioHandoff(
    caller: String,
    completion: @escaping () -> Void
  )

  func disarmBackgroundAudioHandoff(caller: String)

  func interruptBackgroundAudioHandoff(caller: String)

  func isBackgroundAudioHandoffReady(for target: IOSAudioInputTarget?) -> Bool
  func cancelBackgroundAudioHandoffConfirmation()
}

extension IOSBackgroundCaptureHandoffDelegate {
  func cancelBackgroundAudioHandoffConfirmation() {}

  func interruptBackgroundAudioHandoff(caller: String) {
    disarmBackgroundAudioHandoff(caller: caller)
  }
}

enum IOSMainTurnPreparationError: Error, Equatable {
  case cancelled
  case microphoneUnavailable
}

/// The single writer for AVAudioSession during an iOS MAIN turn.
///
/// HFP, prompt playback and speech capture may inspect the shared session, but
/// every mutation is routed through this coordinator. It also keeps a bounded
/// per-turn timeline so a device build can identify the exact caller that
/// changed a route or ended a turn.
final class IOSAudioSessionCoordinator: NSObject {
  let session = AVAudioSession.sharedInstance()

  private var routeChangeToken: NSObjectProtocol?
  private var interruptionToken: NSObjectProtocol?
  private var traceSink: (([String: Any]) -> Void)?
  private var traceBuffer: [[String: Any]] = []
  private var pendingTurnId: String?
  private var pendingTurnStartedAt: Date?
  private var activeTurnId: String?
  private var activeTurnStartedAt: Date?
  private var sequence = 0
  private var turnTimeout: DispatchWorkItem?
  private var backgroundTurnTask = UIBackgroundTaskIdentifier.invalid
  private var backgroundTurnTaskEnder: IOSBackgroundTaskEnder?
  private var backgroundTurnTaskGeneration = 0
  private var ownership = IOSAudioSessionOwnershipState()
  private var playbackTokens = Set<String>()
  private let passiveAudioEvents = IOSPassiveAudioEventGate()
  private let backgroundCaptureSessionDriver: IOSBackgroundCaptureSessionDriver?
  private(set) var isBackgroundCaptureMixing = false
  private var preferredHfpInputUID: String?
  private var preferredHfpInputName: String?
  private var hasVerifiedHfpSelection = false
  /// `currentRoute` can keep reporting bluetoothHFP briefly after
  /// `setActive(false)` has completed. Keep the activation state written by
  /// this coordinator separate from that lagging route snapshot so a new HFP
  /// owner never mistakes a stale route for a usable audio session.
  private(set) var isAudioSessionActive = false
  private(set) var isAudioInterruptionSuspended = false
  private(set) var isMainTurnActive = false
  private(set) var mainAudioInputTarget: IOSAudioInputTarget?
  private(set) var isBackgroundLearningEnabled = false
  private(set) var isActiveLearningRequested = false
  private(set) var isBackgroundCaptureEngineRunning = false
  var isSpeechCaptureActive: Bool { ownership.contains(.speechCapture) }
  var isBackgroundCaptureArmed: Bool { ownership.contains(.backgroundCapture) }
  var isPromptActive: Bool { ownership.contains(.prompt) }
  var isHfpRouteActive: Bool { ownership.contains(.hfpRoute) }
  var isBackgroundTransitionLeaseActive: Bool {
    ownership.contains(.backgroundTransition)
  }
  var onMainTurnEnded: (() -> Void)?
  var onSpeechCaptureStarted: (() -> Void)?
  var onSpeechCaptureEnded: (() -> Void)?
  var onHfpRouteOwnershipChanged: (() -> Void)?
  var onPromptEnded: (() -> Void)?
  var onAudioSessionReleased: (() -> Void)?
  var onBackgroundLearningEvent: (([String: Any]) -> Void)?
  weak var backgroundCaptureHandoffDelegate: IOSBackgroundCaptureHandoffDelegate?

  init(backgroundCaptureSessionDriver: IOSBackgroundCaptureSessionDriver? = nil) {
    self.backgroundCaptureSessionDriver = backgroundCaptureSessionDriver
    super.init()
    routeChangeToken = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: session,
      queue: IOSNativeWork.operationQueue
    ) { [weak self] notification in
      self?.recordRouteChange(notification)
    }
    interruptionToken = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: session,
      queue: IOSNativeWork.operationQueue
    ) { [weak self] notification in
      self?.recordInterruption(notification)
    }
  }

  func setBackgroundLearningEnabled(_ enabled: Bool) {
    isBackgroundLearningEnabled = enabled
    trace(
      stage: enabled ? "background_learning_enabled" : "background_learning_disabled",
      caller: "BackgroundLearningBridge"
    )
    if !enabled {
      setActiveLearningRequested(false)
      requestBackgroundCaptureDisarm(caller: "BackgroundLearningBridge.stop")
      endBackgroundTurnExecution(caller: "BackgroundLearningBridge.stop")
      releaseAudioSessionIfIdle(caller: "BackgroundLearningBridge.stop")
    }
  }

  func setActiveLearningRequested(_ requested: Bool) {
    guard isActiveLearningRequested != requested else { return }
    isActiveLearningRequested = requested
    trace(
      stage: requested ? "active_learning_requested" : "active_learning_ended",
      caller: "BackgroundLearningBridge"
    )
  }

  func applicationDidEnterBackground() {
    let applicationIsActive = IOSNativeWork.applicationIsActive
    if IOSBackgroundTurnExecutionPolicy.shouldDeferToActiveAudio(
      applicationIsActive: applicationIsActive,
      promptActive: isPromptActive,
      speechCaptureActive: isSpeechCaptureActive,
      backgroundCaptureRunning: isBackgroundCaptureEngineRunning
    ) {
      trace(
        stage: "background_turn_execution_deferred_to_active_audio",
        caller: "BackgroundLearningBridge.didEnterBackground",
        values: ["owners": ownership.activeOwners.map(\.rawValue)]
      )
      return
    }
    retainBackgroundTurnExecutionIfNeeded(
      caller: "BackgroundLearningBridge.didEnterBackground"
    )
  }

  func applicationWillEnterForeground() {
    cancelPassiveAudioEvent()
    // Opening HOMI is an explicit opportunity to prepare its input again.
    // An interruption-ended notification alone must not reclaim another app's audio.
    isAudioInterruptionSuspended = false
    endBackgroundTurnExecution(
      caller: "BackgroundLearningBridge.willEnterForeground"
    )
  }

  /// Requests a real, record-capable AVAudioEngine while iOS still permits it.
  /// The speech bridge owns that engine; the coordinator only serializes the
  /// request with prompt/capture ownership and AVAudioSession mutations.
  func requestBackgroundCaptureArm(
    caller: String,
    completion: @escaping () -> Void = {}
  ) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        guard let self else {
          completion()
          return
        }
        self.requestBackgroundCaptureArm(caller: caller, completion: completion)
      }
      return
    }
    guard isBackgroundLearningEnabled, !isAudioInterruptionSuspended else {
      trace(
        stage: "background_capture_arm_skipped", caller: caller,
        message: isAudioInterruptionSuspended ? "interrupted" : "disabled"
      )
      completion()
      return
    }
    guard let backgroundCaptureHandoffDelegate else {
      trace(stage: "background_capture_arm_unavailable", caller: caller)
      completion()
      return
    }
    trace(stage: "background_capture_arm_requested", caller: caller)
    backgroundCaptureHandoffDelegate.armBackgroundAudioHandoff(
      caller: caller,
      completion: completion
    )
  }

  /// A physical/visible MAIN action may try normal session activation again
  /// after interruption. iOS still decides whether background recording is allowed.
  /// No prompt is acknowledged until the current turn's input is actually ready.
  func prepareExplicitMainTurn(
    source: String,
    audioInputTarget: IOSAudioInputTarget?,
    completion: @escaping (Result<String, IOSMainTurnPreparationError>) -> Void
  ) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        guard let self else {
          completion(.failure(.cancelled))
          return
        }
        self.prepareExplicitMainTurn(
          source: source, audioInputTarget: audioInputTarget, completion: completion
        )
      }
      return
    }
    isAudioInterruptionSuspended = false
    let turnId = beginMainTurn(
      source: source, audioInputTarget: audioInputTarget, forceNewTurn: true
    )
    requestBackgroundCaptureArm(caller: source) { [weak self] in
      guard let self, self.isMainTurnActive, self.activeTurnId == turnId else {
        completion(.failure(.cancelled))
        return
      }
      if self.isAudioInterruptionSuspended {
        completion(.failure(.cancelled))
        return
      }
      do {
        try self.reconcileBackgroundCaptureMixing(caller: source)
      } catch {
        self.endMainTurn(reason: "audio_priority_unavailable", caller: source, expectedTurnId: turnId)
        completion(.failure(.microphoneUnavailable))
        return
      }
      if !IOSNativeWork.applicationIsActive &&
        !self.hasBackgroundCaptureReady(for: audioInputTarget) {
        self.endMainTurn(reason: "microphone_unavailable", caller: source, expectedTurnId: turnId)
        self.requestBackgroundCaptureDisarm(caller: "\(source).failed")
        completion(.failure(.microphoneUnavailable))
        return
      }
      completion(.success(turnId))
    }
  }

  func requestBackgroundCaptureDisarm(caller: String) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        self?.requestBackgroundCaptureDisarm(caller: caller)
      }
      return
    }
    trace(stage: "background_capture_disarm_requested", caller: caller)
    backgroundCaptureHandoffDelegate?.disarmBackgroundAudioHandoff(
      caller: caller
    )
  }

  func notePhysicalMain(rawHex: String, source: String = "ble") {
    // Every accepted physical MAIN packet starts a new logical turn. The BLE
    // bridge has already collapsed the firmware notification burst before this
    // method is called, so retaining an older active turn here can only make a
    // second real press inherit stale cleanup from the previous one.
    pendingTurnId = makeTurnId()
    pendingTurnStartedAt = Date()
    sequence = 0
    trace(
      stage: "MAIN_RAW_RECEIVED",
      caller: source == "ble" ? "Aiv0BleControlBridge" : "HomiRemoteMainBridge",
      message: rawHex,
      values: [
        "turnId": pendingTurnId ?? "",
        "supersedesTurnId": activeTurnId ?? "",
        "transportSource": source,
      ]
    )
    retainBackgroundTurnExecutionIfNeeded(
      caller: "IOSAudioSessionCoordinator.notePhysicalMain"
    )
  }

  func acquireHfpRoute(caller: String) throws {
    try requirePassiveAudioPriority(caller: caller)
    acquireSessionOwner(.hfpRoute, caller: caller)
    do {
      try reconcileBackgroundCaptureMixing(caller: caller)
      try ensureExclusiveAudioSession(caller: caller)
    } catch {
      releaseSessionOwner(.hfpRoute, caller: caller)
      releaseAudioSessionIfIdle(caller: "\(caller).failed")
      throw error
    }
    onHfpRouteOwnershipChanged?()
  }

  func beginAudioPlayback(token: String, caller: String) throws -> Bool {
    guard !token.isEmpty else { return false }
    if playbackTokens.contains(token) { return true }
    try requirePassiveAudioPriority(caller: caller)
    playbackTokens.insert(token)
    acquireSessionOwner(.playback, caller: caller)
    do {
      try reconcileBackgroundCaptureMixing(caller: caller)
      try ensureExclusiveAudioSession(caller: caller)
      return true
    } catch {
      endAudioPlayback(token: token, caller: "\(caller).failed")
      throw error
    }
  }

  func endAudioPlayback(token: String, caller: String) {
    guard playbackTokens.remove(token) != nil else { return }
    releaseSessionOwner(.playback, caller: caller)
    releaseAudioSessionIfIdle(caller: caller)
  }

  func releaseHfpRoute(caller: String) {
    releaseSessionOwner(.hfpRoute, caller: caller)
    onHfpRouteOwnershipChanged?()
    releaseAudioSessionIfIdle(caller: caller)
  }

  func releaseCapture(caller: String) {
    let captureWasActive = releaseSessionOwner(.speechCapture, caller: caller)
    if captureWasActive {
      refreshBackgroundTurnExecutionForHandoff(caller: caller)
    }
    releaseAudioSessionIfIdle(caller: caller)
    if captureWasActive {
      trace(stage: "speech_capture_ended", caller: caller)
      // This callback only releases BLE recovery work that was already pending.
      // It must never create a notification refresh for a healthy subscription.
      onSpeechCaptureEnded?()
    }
  }

  @discardableResult
  func beginMainTurn(
    source: String,
    audioInputTarget: IOSAudioInputTarget? = nil,
    forceNewTurn: Bool = false
  ) -> String {
    cancelPassiveAudioEvent()
    backgroundCaptureHandoffDelegate?.cancelBackgroundAudioHandoffConfirmation()
    let now = Date()
    let pendingIsRecent = pendingTurnStartedAt.map {
      now.timeIntervalSince($0) <= 5
    } ?? false
    if pendingIsRecent, let pendingTurnId {
      let previousTurnId = activeTurnId
      turnTimeout?.cancel()
      turnTimeout = nil
      activeTurnId = pendingTurnId
      activeTurnStartedAt = pendingTurnStartedAt
      mainAudioInputTarget = audioInputTarget
      self.pendingTurnId = nil
      pendingTurnStartedAt = nil
      isMainTurnActive = true
      if !ownership.contains(.mainTurn) {
        acquireSessionOwner(.mainTurn, caller: source)
      }
      trace(
        stage: previousTurnId == nil ? "main_turn_started" : "main_turn_superseded",
        caller: source,
        values: ["previousTurnId": previousTurnId ?? ""]
      )
      scheduleSafetyTimeout()
      retainBackgroundTurnExecutionIfNeeded(caller: source)
      return pendingTurnId
    }

    if !forceNewTurn, isMainTurnActive, let activeTurnId {
      trace(stage: "main_turn_reused", caller: source)
      retainBackgroundTurnExecutionIfNeeded(caller: source)
      return activeTurnId
    }

    if pendingTurnId != nil {
      // Do not let an expired physical packet leak into a later virtual turn.
      pendingTurnId = nil
      pendingTurnStartedAt = nil
    }
    let previousTurnId = activeTurnId
    turnTimeout?.cancel()
    turnTimeout = nil
    activeTurnId = makeTurnId()
    activeTurnStartedAt = now
    mainAudioInputTarget = audioInputTarget
    sequence = 0
    isMainTurnActive = true
    if !ownership.contains(.mainTurn) {
      acquireSessionOwner(.mainTurn, caller: source)
    }
    trace(
      stage: previousTurnId == nil ? "main_turn_started" : "main_turn_superseded",
      caller: source,
      values: [
        "previousTurnId": previousTurnId ?? "",
        "audioSource": audioInputTarget?.rawValue ?? "automatic",
      ]
    )
    scheduleSafetyTimeout()
    retainBackgroundTurnExecutionIfNeeded(caller: source)
    return activeTurnId!
  }

  func endMainTurn(
    reason: String,
    caller: String,
    expectedTurnId: String? = nil
  ) {
    guard isMainTurnActive else {
      // An initial Dart pause happens after a physical packet and before the
      // actual turn begins. Do not erase that pending packet timeline.
      trace(stage: "main_turn_end_ignored", caller: caller, message: reason)
      return
    }
    if let expectedTurnId, expectedTurnId != activeTurnId {
      trace(
        stage: "main_turn_end_stale_ignored",
        caller: caller,
        message: reason,
        values: [
          "expectedTurnId": expectedTurnId,
          "activeTurnId": activeTurnId ?? "",
        ]
      )
      return
    }
    trace(stage: "main_turn_ended", caller: caller, message: reason)
    backgroundCaptureHandoffDelegate?.cancelBackgroundAudioHandoffConfirmation()
    turnTimeout?.cancel()
    turnTimeout = nil
    isMainTurnActive = false
    releaseSessionOwner(.mainTurn, caller: caller)
    activeTurnId = nil
    activeTurnStartedAt = nil
    mainAudioInputTarget = nil
    sequence = 0
    // A prompt, live capture, or persistent HFP route may still own the same
    // AVAudioSession after the logical MAIN turn ends. Deactivation is safe only
    // when the final owner releases it; otherwise iOS renegotiates HFP mid-flow.
    releaseAudioSessionIfIdle(caller: "IOSAudioSessionCoordinator.endMainTurn")
    endBackgroundTurnExecutionIfIdle(caller: caller)
    // A lesson may begin before MAIN cleanup completes. Keep its input warm
    // so the next screen lock does not require a new background recording.
    if !IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
      backgroundLearningEnabled: isBackgroundLearningEnabled,
      activeLearningRequested: isActiveLearningRequested,
      applicationIsActive: IOSNativeWork.applicationIsActive,
      hasAvailableHfpInput: hasAvailableSelectedHfpInput
    ) {
      requestBackgroundCaptureDisarm(caller: "IOSAudioSessionCoordinator.endMainTurn")
    }
    onMainTurnEnded?()
  }

  func attachTraceSink(_ sink: @escaping ([String: Any]) -> Void) {
    traceSink = sink
    traceBuffer.forEach(sink)
  }

  func detachTraceSink() {
    traceSink = nil
  }

  /// Returns a stable, chronological copy of the native BLE/HFP/audio trace.
  /// The buffer belongs to the coordinator rather than a Flutter screen, so
  /// opening Parent settings cannot create or erase the evidence it displays.
  func diagnosticTimelineSnapshot(limit: Int = 200) -> [[String: Any]] {
    let boundedLimit = min(max(limit, 1), 200)
    return Array(traceBuffer.suffix(boundedLimit))
  }

  func eventMetadata() -> [String: Any] {
    let now = Date()
    let startedAt = activeTurnStartedAt ?? pendingTurnStartedAt ?? now
    var values: [String: Any] = [
      "elapsedMs": max(0, Int(now.timeIntervalSince(startedAt) * 1_000)),
      "audioRoute": routeDescription(),
    ]
    if let turnId = activeTurnId ?? pendingTurnId {
      values["turnId"] = turnId
    }
    return values
  }

  @discardableResult
  func trace(
    stage: String,
    caller: String,
    code: String? = nil,
    message: String? = nil,
    values: [String: Any] = [:]
  ) -> [String: Any] {
    let now = Date()
    sequence += 1
    let startedAt = activeTurnStartedAt ?? pendingTurnStartedAt ?? now
    var payload: [String: Any] = [
      "type": "speech.stage",
      "stage": stage,
      "caller": caller,
      "sequence": sequence,
      "elapsedMs": max(0, Int(now.timeIntervalSince(startedAt) * 1_000)),
      "eventEpochMs": Int(now.timeIntervalSince1970 * 1_000),
      "audioRoute": routeDescription(),
    ]
    if let turnId = activeTurnId ?? pendingTurnId {
      payload["turnId"] = turnId
    }
    if let code { payload["code"] = code }
    if let message { payload["message"] = message }
    payload.merge(values) { _, new in new }
    traceBuffer.append(payload)
    if traceBuffer.count > 200 {
      traceBuffer.removeFirst(traceBuffer.count - 200)
    }
    traceSink?(payload)
    return payload
  }

  func preparePrompt(preferredHfpInput: AVAudioSessionPortDescription?, caller: String) throws -> Bool {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    try requirePassiveAudioPriority(caller: caller)
    acquireSessionOwner(.prompt, caller: caller)
    trace(stage: "prompt_audio_prepare", caller: caller)
    do {
      if isBackgroundCaptureEngineRunning {
        try reconcileBackgroundCaptureMixing(caller: caller)
        let usesHfp = hasTwoWayHfpRoute()
        if mainAudioInputTarget == .hfp && !usesHfp {
          // A previous phone capture may still be draining after Dart's
          // bounded pause. Never speak an HM-D001 MAIN prompt on that graph.
          throw IOSAudioSessionCoordinatorError.mainAudioSourceConflict
        }
        trace(
          stage: "prompt_audio_background_capture_reused",
          caller: caller,
          values: ["usesHfp": usesHfp]
        )
        return usesHfp
      }
      let currentRouteUsesPreferredHfp = preferredHfpInput.map { preferredInput in
        hasSelectedTwoWayHfpRoute(input: preferredInput)
      } ?? (preferredHfpInputUID == nil && preferredHfpInputName == nil)
      if IOSHfpRouteReusePolicy.canReuse(
        hasTwoWayHfpRoute: hasTwoWayHfpRoute(),
        audioSessionActive: isAudioSessionActive
      ), currentRouteUsesPreferredHfp {
        try ensureExclusiveAudioSession(caller: caller)
        trace(stage: "prompt_audio_route_reused", caller: caller)
        return true
      }
      if let preferredHfpInput {
        try ensureCategory(
          mode: .voiceChat,
          options: IOSHfpRoutePolicy.categoryOptions,
          caller: caller
        )
        try ensureActive(caller: caller)
        try ensurePreferredInput(preferredHfpInput, caller: caller)
        try ensureOutputOverride(.none, caller: caller)
        return true
      }
      try ensureCategory(
        mode: .default,
        options: [.defaultToSpeaker],
        caller: caller
      )
      try ensurePreferredInput(nil, caller: caller)
      try ensureActive(caller: caller)
      try ensureOutputOverride(.speaker, caller: caller)
      return false
    } catch {
      releaseSessionOwner(.prompt, caller: "\(caller).failed")
      releaseAudioSessionIfIdle(caller: "\(caller).failed")
      throw error
    }
  }

  /// Forces a short coach prompt to the iPhone speaker even when an HM-D001 HFP
  /// input is paired. The selected HM-D001 UID remains owned by HfpAudioBridge and
  /// can be reactivated for the following sample/capture turn.
  func preparePhoneSpeaker(caller: String) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    try requirePassiveAudioPriority(caller: caller)
    acquireSessionOwner(.prompt, caller: caller)
    trace(stage: "phone_prompt_audio_prepare", caller: caller)
    do {
      if isBackgroundCaptureEngineRunning {
        try reconcileBackgroundCaptureMixing(caller: caller)
        if mainAudioInputTarget == .builtInMic,
          session.currentRoute.inputs.contains(where: { $0.portType == .bluetoothHFP })
        {
          // A bounded Dart pause may leave its old capture draining briefly.
          // Fail this phone prompt instead of playing it on that HFP graph.
          throw IOSAudioSessionCoordinatorError.mainAudioSourceConflict
        }
        trace(stage: "phone_prompt_background_capture_reused", caller: caller)
        return
      }
      try ensureCategory(
        mode: .default,
        options: [.defaultToSpeaker],
        caller: caller
      )
      try ensureActive(caller: caller)
      if let builtInInput = currentOrAvailableInput(portType: .builtInMic) {
        try ensurePreferredInput(builtInInput, caller: caller)
      } else {
        try ensurePreferredInput(nil, caller: caller)
      }
      try ensureOutputOverride(.speaker, caller: caller)
    } catch {
      releaseSessionOwner(.prompt, caller: "\(caller).failed")
      releaseAudioSessionIfIdle(caller: "\(caller).failed")
      throw error
    }
  }

  func releasePrompt(usedHfp _: Bool, caller: String) {
    trace(stage: "prompt_audio_release", caller: caller)
    let promptWasActive = releaseSessionOwner(.prompt, caller: caller)
    if promptWasActive {
      // Prompt playback itself is covered by the audio background mode. Start
      // a fresh bounded lease only after that audio ends, before the native
      // completion is returned to Flutter for the ready cue and Apple Speech.
      refreshBackgroundTurnExecutionForHandoff(caller: caller)
    }
    releaseAudioSessionIfIdle(caller: caller)
    if promptWasActive {
      onPromptEnded?()
    }
  }

  /// Uses iOS media playback only when the selected HM-D001 HFP route is not
  /// available. Callers that have an HM-D001 input must use `preparePrompt` so
  /// assistant speech stays on that device instead of falling back to the
  /// iPhone speaker.
  func prepareMediaPlayback(caller: String) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    try requirePassiveAudioPriority(caller: caller)
    acquireSessionOwner(.prompt, caller: caller)
    trace(stage: "media_prompt_audio_prepare", caller: caller)
    do {
      if isBackgroundCaptureEngineRunning {
        try reconcileBackgroundCaptureMixing(caller: caller)
        trace(stage: "media_prompt_background_capture_reused", caller: caller)
        return
      }
      try ensureCategory(
        category: .playback,
        mode: .spokenAudio,
        options: [],
        caller: caller
      )
      try ensureActive(caller: caller)
    } catch {
      releaseSessionOwner(.prompt, caller: "\(caller).failed")
      releaseAudioSessionIfIdle(caller: "\(caller).failed")
      throw error
    }
  }

  /// Releases a record-capable route when no MAIN turn owns it.
  ///
  /// The selected HFP UID is kept by `HfpAudioBridge`; the live SCO/audio
  /// session is released only when no other owner, including a foreground-armed
  /// background capture, still needs it.
  func releaseAudioSessionIfIdle(caller: String) {
    if isBackgroundCaptureEngineRunning && !isAudioInterruptionSuspended {
      do {
        try reconcileBackgroundCaptureMixing(caller: caller)
      } catch {
        trace(stage: "background_capture_priority_failed", caller: caller, message: error.localizedDescription)
      }
    }
    guard ownership.canDeactivate else {
      trace(
        stage: "audio_session_release_preserved",
        caller: caller,
        values: ["owners": ownership.activeOwners.map(\.rawValue)]
      )
      return
    }
    trace(stage: "audio_session_release_requested", caller: caller)
    do {
      // overrideOutputAudioPort belongs to the play-and-record family. Lesson
      // coach speech now uses the output-only playback category for A2DP, so
      // attempting the override there can fail before setActive(false) runs.
      if session.category == .playAndRecord {
        try ensureOutputOverride(.none, caller: caller)
      } else {
        trace(
          stage: "overrideOutput_skipped",
          caller: caller,
          message: session.category.rawValue
        )
      }
      try setActive(false, notifyOthers: true, caller: caller)
      trace(stage: "audio_session_release_completed", caller: caller)
      // Resume deferred CoreBluetooth recovery only after HFP/SCO has actually
      // released its live voice route. This covers lesson/translation capture,
      // not only the short MAIN assistant turn.
      onAudioSessionReleased?()
    } catch {
      let nsError = error as NSError
      trace(
        stage: "audio_session_release_failed",
        caller: caller,
        code: "\(nsError.domain):\(nsError.code)",
        message: error.localizedDescription
      )
    }
  }

  func configureHfp(activate: Bool, preferredInput: AVAudioSessionPortDescription?, caller: String) throws {
    try ensureCategory(
      mode: .voiceChat,
      options: IOSBackgroundCaptureMixingPolicy.options(
        base: IOSHfpRoutePolicy.categoryOptions, mixing: shouldMixBackgroundCapture
      ),
      caller: caller
    )
    if activate {
      try ensureActive(caller: caller)
      // A previous phone-speaker turn can leave both the built-in microphone
      // and speaker override selected. Merely switching to playAndRecord does
      // not make iOS publish bluetoothHFP in that state, so Settings reports
      // no HFP even though the following lesson can renegotiate it. Clear both
      // stale choices for discovery, or select the exact requested HM-D001 input.
      try ensurePreferredInput(preferredInput, caller: caller)
      try ensureOutputOverride(.none, caller: caller)
    }
  }

  func initializeHfpSession(caller: String) throws {
    // A Settings status lookup must not replace an armed phone/HFP graph or
    // change a session owned by playback, MAIN or a recording utterance.
    guard ownership.canDeactivate,
      !isBackgroundCaptureArmed, !isBackgroundCaptureEngineRunning else {
      trace(stage: "hfp_initialization_session_preserved", caller: caller)
      return
    }
    try configureHfp(activate: false, preferredInput: nil, caller: caller)
  }

  func prepareForHfpSettingsChange(caller: String) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    guard IOSNativeWork.applicationIsActive,
      !ownership.activeOwners.contains(where: {
        $0 == .mainTurn || $0 == .prompt || $0 == .speechCapture
          || $0 == .playback || $0 == .hfpRoute
      }) else {
      throw IOSAudioSessionCoordinatorError.audioRouteChangeBusy
    }
    if isBackgroundCaptureArmed || isBackgroundCaptureEngineRunning {
      requestBackgroundCaptureDisarm(caller: caller)
    }
    guard !isBackgroundCaptureArmed, !isBackgroundCaptureEngineRunning else {
      throw IOSAudioSessionCoordinatorError.audioRouteChangeBusy
    }
    trace(stage: "hfp_settings_route_change_prepared", caller: caller)
  }

  func clearPreferredInput(caller: String) throws {
    try ensurePreferredInput(nil, caller: caller)
  }

  /// Retains the already-configured audio session only while an active lesson
  /// is crossing a background prompt/audio gap. It never starts the mic and is
  /// released as soon as the app becomes foreground again.
  func setBackgroundTransitionLeaseActive(_ active: Bool) {
    if active == isBackgroundTransitionLeaseActive { return }
    if active {
      acquireSessionOwner(
        .backgroundTransition,
        caller: "BackgroundLearningBridge.activeLearning"
      )
      retainBackgroundTurnExecutionIfNeeded(
        caller: "BackgroundLearningBridge.activeLearning"
      )
      return
    }
    releaseSessionOwner(
      .backgroundTransition,
      caller: "BackgroundLearningBridge.activeLearning"
    )
    releaseAudioSessionIfIdle(
      caller: "BackgroundLearningBridge.activeLearningEnded"
    )
    endBackgroundTurnExecutionIfIdle(
      caller: "BackgroundLearningBridge.activeLearningEnded"
    )
  }

  /// Remembers the HFP device explicitly selected by the user. iOS can expose
  /// several Bluetooth inputs at once, so picking the first available device
  /// can send assistant speech to an unrelated headset.
  func rememberPreferredHfpInput(uid: String?, name: String?) {
    preferredHfpInputUID = normalizedPreferredHfpValue(uid)
    preferredHfpInputName = normalizedPreferredHfpValue(name)
    if preferredHfpInputUID == nil && preferredHfpInputName == nil {
      hasVerifiedHfpSelection = false
    }
  }

  func setVerifiedHfpSelection(_ verified: Bool) {
    hasVerifiedHfpSelection = verified
  }

  var hasAvailableSelectedHfpInput: Bool {
    hasVerifiedHfpSelection
      && selectedOrAvailableHfpInput() != nil
  }

  /// Returns the selected HFP input when it remains available. If no HM-D001 has
  /// been selected yet, keep the existing first-HFP behaviour. Once a device
  /// is selected, never silently replace it with a different Bluetooth device.
  func selectedOrAvailableHfpInput() -> AVAudioSessionPortDescription? {
    let availableInputs = (session.availableInputs ?? []).filter {
      IOSHfpRoutePolicy.isHfpInput($0.portType)
    }
    let currentInputs = session.currentRoute.inputs.filter {
      IOSHfpRoutePolicy.isHfpInput($0.portType)
    }
    // iOS may republish HM-D001 with a new UID. Resolve against available inputs
    // before accepting an older currentRoute snapshot with the previous UID.
    // The latter remains a setup hint only when iOS has not populated
    // availableInputs yet; every playback/capture still verifies the live route.
    let liveCurrent = isAudioSessionActive && hasTwoWayHfpRoute() ? currentInputs : []
    let setupHint = availableInputs.isEmpty ? currentInputs : []
    for candidates in [availableInputs, liveCurrent, setupHint] {
      let identities = candidates.map {
        IOSHfpInputIdentity(uid: $0.uid, name: $0.portName)
      }
      if let identity = IOSPreferredHfpInputPolicy.select(
        from: identities,
        selectedUID: preferredHfpInputUID,
        selectedName: preferredHfpInputName
      ), let selected = candidates.first(where: { $0.uid == identity.uid }) {
        return selected
      }
    }
    return nil
  }

  func hasSelectedTwoWayHfpRoute() -> Bool {
    guard let selected = selectedOrAvailableHfpInput() else { return false }
    return hasSelectedTwoWayHfpRoute(input: selected)
  }

  private func hasSelectedTwoWayHfpRoute(input: AVAudioSessionPortDescription) -> Bool {
    guard isAudioSessionActive, hasTwoWayHfpRoute() else { return false }
    let selected = IOSHfpInputIdentity(uid: input.uid, name: input.portName)
    return session.currentRoute.inputs.contains { active in
      IOSHfpRoutePolicy.isHfpInput(active.portType)
        && IOSSelectedHfpRoutePolicy.matches(
          active: IOSHfpInputIdentity(uid: active.uid, name: active.portName),
          selected: selected
        )
    }
  }

  func prepareCapture(target: IOSAudioInputTarget, caller: String) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    try requirePassiveAudioPriority(caller: caller)
    retainBackgroundTurnExecutionIfNeeded(caller: caller)
    let captureWasAlreadyPrepared = ownership.contains(.speechCapture)
    if captureWasAlreadyPrepared {
      trace(stage: "speech_capture_owner_reused", caller: caller)
    } else {
      acquireSessionOwner(.speechCapture, caller: caller)
    }
    trace(stage: "audio_session_prepare", caller: caller, values: ["audioSource": target.rawValue])
    do {
      if isBackgroundCaptureEngineRunning {
        try reconcileBackgroundCaptureMixing(caller: caller)
        guard hasBackgroundCaptureReady(for: target) else {
          throw IOSAudioSessionCoordinatorError.mainAudioSourceConflict
        }
        if !captureWasAlreadyPrepared { onSpeechCaptureStarted?() }
        return
      }
      switch target {
      case .hfp:
        if selectedOrAvailableHfpInput() == nil {
          // A competing media app may leave an A2DP-only route. Publish the
          // record-capable inputs before resolving the selected HM-D001 again.
          try configureHfp(activate: true, preferredInput: nil, caller: caller)
        }
        guard let input = selectedOrAvailableHfpInput() else {
          throw IOSAudioSessionCoordinatorError.hfpInputUnavailable
        }
        if IOSHfpRouteReusePolicy.canReuse(
          hasTwoWayHfpRoute: hasSelectedTwoWayHfpRoute(input: input),
          audioSessionActive: isAudioSessionActive
        ) {
          try ensureExclusiveAudioSession(caller: caller)
          trace(stage: "audio_session_active", caller: caller, values: ["audioSource": target.rawValue])
          trace(stage: "route_confirmed", caller: caller, values: ["audioSource": target.rawValue])
          if !captureWasAlreadyPrepared {
            onSpeechCaptureStarted?()
          }
          return
        }
        try configureHfp(activate: true, preferredInput: input, caller: caller)
      case .builtInMic:
        try ensureCategory(mode: .voiceChat, options: [.defaultToSpeaker], caller: caller)
        try ensureActive(caller: caller)
        guard let input = currentOrAvailableInput(portType: .builtInMic) else {
          throw IOSAudioSessionCoordinatorError.builtInMicUnavailable
        }
        try ensurePreferredInput(input, caller: caller)
      }
      trace(stage: "audio_session_active", caller: caller, values: ["audioSource": target.rawValue])
      if !captureWasAlreadyPrepared {
        onSpeechCaptureStarted?()
      }
    } catch {
      // A failed route/capture preparation can still switch the HM-D001 radio
      // profile and invalidate its BLE notification subscription. Treat it as
      // a real capture end so BLE gets the same deterministic re-arm path.
      releaseCapture(caller: "\(caller).failed")
      throw error
    }
  }

  /// Configures the same two-way route used by Apple Speech without declaring
  /// an active recognition turn. IOSSpeechRecognizerBridge keeps its input tap
  /// running with a closed buffer gate until Flutter explicitly starts speech.
  func prepareBackgroundCapture(target: IOSAudioInputTarget, caller: String) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    if !isBackgroundCaptureArmed {
      acquireSessionOwner(.backgroundCapture, caller: caller)
    }
    trace(
      stage: "background_capture_audio_prepare",
      caller: caller,
      values: ["audioSource": target.rawValue]
    )
    do {
      let mixing = shouldMixBackgroundCapture
      if let driver = backgroundCaptureSessionDriver {
        try driver.prepare(target, mixing, caller)
        isBackgroundCaptureMixing = mixing
        return
      }
      switch target {
      case .hfp:
        if selectedOrAvailableHfpInput() == nil {
          try configureHfp(activate: true, preferredInput: nil, caller: caller)
        }
        guard let input = selectedOrAvailableHfpInput() else {
          throw IOSAudioSessionCoordinatorError.hfpInputUnavailable
        }
        let currentRouteUsesInput = session.currentRoute.inputs.contains {
          $0.uid == input.uid
        }
        if hasTwoWayHfpRoute(), currentRouteUsesInput {
          try ensureCategory(
            mode: .voiceChat,
            options: IOSBackgroundCaptureMixingPolicy.options(base: IOSHfpRoutePolicy.categoryOptions, mixing: mixing),
            caller: caller
          )
          try ensureActive(caller: caller)
        } else {
          try configureHfp(activate: true, preferredInput: input, caller: caller)
        }
      case .builtInMic:
        try ensureCategory(
          mode: .voiceChat,
          options: IOSBackgroundCaptureMixingPolicy.options(base: [.defaultToSpeaker], mixing: mixing),
          caller: caller
        )
        try ensureActive(caller: caller)
        guard let input = currentOrAvailableInput(portType: .builtInMic) else {
          throw IOSAudioSessionCoordinatorError.builtInMicUnavailable
        }
        try ensurePreferredInput(input, caller: caller)
      }
      isBackgroundCaptureMixing = mixing
      trace(
        stage: "background_capture_audio_active",
        caller: caller,
        values: ["audioSource": target.rawValue]
      )
    } catch {
      releaseBackgroundCapture(caller: "\(caller).failed")
      throw error
    }
  }

  func releaseBackgroundCapture(caller: String) {
    guard releaseSessionOwner(.backgroundCapture, caller: caller) else { return }
    setBackgroundCaptureEngineRunning(false, caller: caller)
    isBackgroundCaptureMixing = false
    trace(stage: "background_capture_audio_released", caller: caller)
    releaseAudioSessionIfIdle(caller: caller)
    endBackgroundTurnExecutionIfIdle(caller: caller)
  }

  private var shouldMixBackgroundCapture: Bool {
    IOSBackgroundCaptureMixingPolicy.shouldMix(
      backgroundCaptureArmed: isBackgroundCaptureArmed,
      owners: ownership.activeOwners,
      interrupted: isAudioInterruptionSuspended
    )
  }

  /// Only an explicit MAIN or foreground action may interrupt competing media.
  /// Observing other media is not an OS interruption: retain the valid idle
  /// graph and its closed buffer gate while Flutter pauses its learning flow.
  private func requirePassiveAudioPriority(caller: String) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    let otherAudioPlaying = backgroundCaptureSessionDriver?.isOtherAudioPlaying()
      ?? session.isOtherAudioPlaying
    let mixing = backgroundCaptureSessionDriver == nil
      ? session.categoryOptions.contains(.mixWithOthers) : isBackgroundCaptureMixing
    if !IOSNativeWork.applicationIsActive && !isMainTurnActive
      && isBackgroundCaptureArmed && mixing && otherAudioPlaying {
      trace(stage: "background_passive_audio_denied", caller: caller, code: "EXTERNAL_MEDIA_ACTIVE")
      if let generation = passiveAudioEvents.issue() {
        onBackgroundLearningEvent?([
          "type": "background.interrupted",
          "reason": "external_media_active",
          "passiveAudioGeneration": generation,
        ])
      }
      throw IOSAudioSessionCoordinatorError.externalMediaActive
    }
  }

  /// Claim immediately before the bridge emits on the main thread. A MAIN or
  /// foreground action which superseded this queued pause invalidates it.
  func claimPassiveAudioEvent(generation: Int) -> Bool {
    passiveAudioEvents.claim(generation)
  }

  private func cancelPassiveAudioEvent() {
    passiveAudioEvents.cancel()
  }

  /// Change priority on the existing graph. Never deactivate the session to
  /// notify other apps: doing so destroys the background recording capability.
  func reconcileBackgroundCaptureMixing(caller: String) throws {
    guard isBackgroundCaptureEngineRunning else { return }
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    do {
      guard hasBackgroundCaptureReady(for: nil) else {
        throw IOSAudioSessionCoordinatorError.backgroundGraphUnavailable
      }
      let mixing = shouldMixBackgroundCapture
      let currentlyMixing = backgroundCaptureSessionDriver == nil
        ? session.categoryOptions.contains(.mixWithOthers) : isBackgroundCaptureMixing
      if mixing != currentlyMixing {
        if let driver = backgroundCaptureSessionDriver {
          try driver.applyMixing(mixing, caller)
        } else {
          try ensureCategory(
            category: session.category,
            mode: session.mode,
            options: IOSBackgroundCaptureMixingPolicy.options(base: session.categoryOptions, mixing: mixing),
            caller: caller
          )
          try ensureActive(caller: caller)
        }
        guard hasBackgroundCaptureReady(for: nil) else {
          throw IOSAudioSessionCoordinatorError.backgroundGraphUnavailable
        }
        trace(
          stage: mixing ? "background_capture_idle_mixing" : "background_capture_exclusive",
          caller: caller,
          values: ["owners": ownership.activeOwners.map(\.rawValue)]
        )
      }
      isBackgroundCaptureMixing = mixing
    } catch {
      trace(stage: "background_capture_priority_failed", caller: caller, message: error.localizedDescription)
      // A category change may invalidate the engine or its route. Stop instead
      // of rebuilding a background graph or opening a stale input gate.
      suspendForAudioInterruption(reason: "background_capture_priority_failed")
      throw error
    }
  }

  private func ensureExclusiveAudioSession(caller: String) throws {
    guard backgroundCaptureSessionDriver == nil,
      !isBackgroundCaptureEngineRunning,
      session.categoryOptions.contains(.mixWithOthers)
    else { return }
    try ensureCategory(
      category: session.category,
      mode: session.mode,
      options: IOSBackgroundCaptureMixingPolicy.options(base: session.categoryOptions, mixing: false),
      caller: caller
    )
    try ensureActive(caller: caller)
  }

  func setBackgroundCaptureEngineRunning(_ running: Bool, caller: String) {
    guard running != isBackgroundCaptureEngineRunning else { return }
    if running, !isBackgroundCaptureArmed {
      trace(
        stage: "background_capture_engine_state_ignored",
        caller: caller,
        message: "owner_missing"
      )
      return
    }
    isBackgroundCaptureEngineRunning = running
    trace(
      stage: running
        ? "background_capture_engine_running"
        : "background_capture_engine_stopped",
      caller: caller
    )
  }

  func hasBackgroundCaptureReady(for target: IOSAudioInputTarget?) -> Bool {
    isBackgroundCaptureEngineRunning
      && backgroundCaptureHandoffDelegate?.isBackgroundAudioHandoffReady(for: target) == true
  }

  func routeDescription() -> String {
    let inputs = session.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
    let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
    return "in=[\(inputs.joined(separator: ", "))] out=[\(outputs.joined(separator: ", "))]"
  }

  func hasTwoWayHfpRoute() -> Bool {
    IOSHfpRoutePolicy.isTwoWayHfpRoute(
      inputTypes: session.currentRoute.inputs.map(\.portType),
      outputTypes: session.currentRoute.outputs.map(\.portType)
    )
  }

  func dispose() {
    cancelPassiveAudioEvent()
    turnTimeout?.cancel()
    turnTimeout = nil
    endBackgroundTurnExecution(caller: "IOSAudioSessionCoordinator.dispose")
    if let routeChangeToken {
      NotificationCenter.default.removeObserver(routeChangeToken)
    }
    routeChangeToken = nil
    if let interruptionToken {
      NotificationCenter.default.removeObserver(interruptionToken)
    }
    interruptionToken = nil
    traceSink = nil
    onMainTurnEnded = nil
    onSpeechCaptureStarted = nil
    onSpeechCaptureEnded = nil
    onHfpRouteOwnershipChanged = nil
    onAudioSessionReleased = nil
    onBackgroundLearningEvent = nil
    backgroundCaptureHandoffDelegate = nil
  }

  /// Ends the bounded transition lease once native audio is verifiably active.
  /// Prompt playback and live capture are then kept alive by the declared audio
  /// background mode; their completion paths create a new bounded hand-off.
  func backgroundAudioActivityDidStart(caller: String) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        self?.backgroundAudioActivityDidStart(caller: caller)
      }
      return
    }
    guard !IOSNativeWork.applicationIsActive else { return }
    guard isPromptActive || isSpeechCaptureActive || isBackgroundCaptureEngineRunning else { return }
    trace(
      stage: "background_turn_execution_yielded_to_active_audio",
      caller: caller,
      values: ["owners": ownership.activeOwners.map(\.rawValue)]
    )
    endBackgroundTurnExecution(caller: caller)
  }

  /// Keeps the process alive only across a silent native-to-Flutter hand-off.
  /// Refreshing here avoids spending the original background-task budget while
  /// a long assistant prompt or recording is already protected by audio mode.
  func beginBackgroundAudioHandoff(caller: String) {
    refreshBackgroundTurnExecutionForHandoff(caller: caller)
  }

  private func retainBackgroundTurnExecutionIfNeeded(caller: String) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        self?.retainBackgroundTurnExecutionIfNeeded(caller: caller)
      }
      return
    }
    let shouldRetain = IOSBackgroundTurnExecutionPolicy.shouldRetain(
      backgroundLearningEnabled: isBackgroundLearningEnabled,
      applicationIsActive: IOSNativeWork.applicationIsActive,
      interactionPendingOrActive: pendingTurnId != nil
        || isMainTurnActive
        || isBackgroundTransitionLeaseActive
        || isBackgroundCaptureArmed
    )
    guard shouldRetain, backgroundTurnTask == .invalid else { return }

    backgroundTurnTaskGeneration += 1
    let taskGeneration = backgroundTurnTaskGeneration
    let ender = IOSBackgroundTaskEnder()
    let identifier = UIApplication.shared.beginBackgroundTask(
      withName: "HOMI MAIN prompt-to-microphone"
    ) { [weak self] in
      ender.end()
      guard let self else { return }
      self.expireBackgroundTurnExecution(taskGeneration: taskGeneration)
    }
    ender.set(identifier)
    backgroundTurnTaskEnder = ender
    backgroundTurnTask = identifier
    trace(
      stage: identifier == .invalid
        ? "background_turn_execution_unavailable"
        : "background_turn_execution_started",
      caller: caller
    )
  }

  private func refreshBackgroundTurnExecutionForHandoff(caller: String) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        self?.refreshBackgroundTurnExecutionForHandoff(caller: caller)
      }
      return
    }
    let shouldRetain = IOSBackgroundTurnExecutionPolicy.shouldRetain(
      backgroundLearningEnabled: isBackgroundLearningEnabled,
      applicationIsActive: IOSNativeWork.applicationIsActive,
      interactionPendingOrActive: pendingTurnId != nil
        || isMainTurnActive
        || isBackgroundTransitionLeaseActive
        || isBackgroundCaptureArmed
    )
    guard shouldRetain else { return }
    trace(stage: "background_turn_execution_refresh_requested", caller: caller)
    endBackgroundTurnExecution(caller: "\(caller).refresh")
    retainBackgroundTurnExecutionIfNeeded(caller: caller)
  }

  private func endBackgroundTurnExecutionIfIdle(caller: String) {
    guard pendingTurnId == nil,
      !isMainTurnActive,
      !isBackgroundTransitionLeaseActive,
      !isBackgroundCaptureArmed
    else { return }
    endBackgroundTurnExecution(caller: caller)
  }

  private func endBackgroundTurnExecution(caller: String) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        self?.endBackgroundTurnExecution(caller: caller)
      }
      return
    }
    guard backgroundTurnTask != .invalid else { return }
    backgroundTurnTask = .invalid
    backgroundTurnTaskGeneration += 1
    trace(stage: "background_turn_execution_ended", caller: caller)
    backgroundTurnTaskEnder?.end()
    backgroundTurnTaskEnder = nil
  }

  private func expireBackgroundTurnExecution(taskGeneration: Int) {
    guard IOSNativeWork.isCurrent else {
      IOSNativeWork.queue.async { [weak self] in
        self?.expireBackgroundTurnExecution(taskGeneration: taskGeneration)
      }
      return
    }
    guard taskGeneration == backgroundTurnTaskGeneration,
      backgroundTurnTask != .invalid
    else {
      trace(
        stage: "background_turn_execution_stale_expiration_ignored",
        caller: "UIApplication"
      )
      return
    }
    trace(
      stage: "background_turn_execution_expired",
      caller: "UIApplication"
    )
    endBackgroundTurnExecution(caller: "UIApplication.expiration")
  }

  private func acquireSessionOwner(_ owner: IOSAudioSessionOwner, caller: String) {
    ownership.acquire(owner)
    trace(
      stage: "audio_session_owner_acquired",
      caller: caller,
      message: owner.rawValue,
      values: ["owners": ownership.activeOwners.map(\.rawValue)]
    )
  }

  @discardableResult
  private func releaseSessionOwner(_ owner: IOSAudioSessionOwner, caller: String) -> Bool {
    let released = ownership.release(owner)
    trace(
      stage: "audio_session_owner_released",
      caller: caller,
      message: owner.rawValue,
      values: ["owners": ownership.activeOwners.map(\.rawValue)]
    )
    return released
  }

  private func currentOrAvailableInput(portType: AVAudioSession.Port) -> AVAudioSessionPortDescription? {
    session.currentRoute.inputs.first { $0.portType == portType }
      ?? session.availableInputs?.first { $0.portType == portType }
  }

  private func normalizedPreferredHfpValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }

  private func ensureCategory(
    category: AVAudioSession.Category = .playAndRecord,
    mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions,
    caller: String
  ) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    guard session.category != category || session.mode != mode || session.categoryOptions != options else {
      trace(stage: "setCategory_skipped", caller: caller)
      return
    }
    trace(stage: "setCategory_requested", caller: caller, message: "\(category.rawValue)/\(mode.rawValue)/\(options.rawValue)")
    try session.setCategory(category, mode: mode, options: options)
    trace(stage: "setCategory_completed", caller: caller)
  }

  private func ensureActive(caller: String) throws {
    guard !isAudioInterruptionSuspended else {
      throw IOSAudioSessionCoordinatorError.audioSessionInterrupted
    }
    try setActive(true, notifyOthers: false, caller: caller)
  }

  private func setActive(_ active: Bool, notifyOthers: Bool, caller: String) throws {
    trace(stage: active ? "setActive_true_requested" : "setActive_false_requested", caller: caller)
    try session.setActive(
      active,
      options: notifyOthers ? [.notifyOthersOnDeactivation] : []
    )
    isAudioSessionActive = active
    trace(stage: active ? "setActive_true_completed" : "setActive_false_completed", caller: caller)
  }

  func noteMediaServicesWereReset(caller: String) {
    // A media-services reset invalidates the process audio session even when
    // AVAudioSession still exposes the previous route for a short interval.
    isAudioSessionActive = false
    trace(stage: "media_services_reset", caller: caller)
  }

  private func ensurePreferredInput(_ input: AVAudioSessionPortDescription?, caller: String) throws {
    if session.preferredInput?.uid == input?.uid {
      trace(stage: "setPreferredInput_skipped", caller: caller, message: input?.portName ?? "nil")
      return
    }
    trace(stage: "setPreferredInput_requested", caller: caller, message: input?.portName ?? "nil")
    try session.setPreferredInput(input)
    trace(stage: "setPreferredInput_completed", caller: caller, message: input?.portName ?? "nil")
  }

  private func ensureOutputOverride(_ port: AVAudioSession.PortOverride, caller: String) throws {
    trace(stage: "overrideOutput_requested", caller: caller, message: port == .speaker ? "speaker" : "none")
    try session.overrideOutputAudioPort(port)
    trace(stage: "overrideOutput_completed", caller: caller)
  }

  private func recordRouteChange(_ notification: Notification) {
    let rawReason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
    let previous = (notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
      .map { routeDescription($0) } ?? "unknown"
    trace(
      stage: "routeChange",
      caller: "AVAudioSession",
      message: "reason=\(rawReason) before=\(previous) after=\(routeDescription())"
    )
    // `setActive(false)` may return before `currentRoute` has finished leaving
    // BluetoothHFP. Notify BLE again on the authoritative route-change event so
    // a reconnect deferred by the immediate callback cannot remain stranded.
    if !hasTwoWayHfpRoute() {
      onAudioSessionReleased?()
    }
  }

  private func recordInterruption(_ notification: Notification) {
    let rawType = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue ?? 0
    let rawReason = (notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? NSNumber)?.uintValue ?? 0
    let type = AVAudioSession.InterruptionType(rawValue: rawType)
    trace(
      stage: type == .began ? "audio_interruption_began" : "audio_interruption_ended",
      caller: "AVAudioSession",
      message: "reason=\(rawReason)"
    )
    guard let type else { return }

    switch type {
    case .began:
      // Locking the screen does not emit an AVAudioSession interruption while
      // the background audio mode remains active. Calls, Siri, alarms and
      // competing non-mixable audio do, and must pause the current turn.
      suspendForAudioInterruption(reason: "audio_session_interruption_\(rawReason)")
    case .ended:
      guard isBackgroundLearningEnabled else { return }
      let rawOptions =
        (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?
          .uintValue ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
      guard options.contains(.shouldResume) else { return }
      // Eligibility is not an instruction to resume. Only a fresh MAIN or
      // opening HOMI clears the suspension gate and may prepare audio again.
      onBackgroundLearningEvent?([
        "type": "background.resumable",
        "reason": "audio_session_interruption_ended",
      ])
    @unknown default:
      break
    }
  }

  func suspendForAudioInterruption(reason: String = "audio_session_interruption") {
    cancelPassiveAudioEvent()
    isAudioInterruptionSuspended = true
    isAudioSessionActive = false
    for _ in playbackTokens {
      releaseSessionOwner(.playback, caller: reason)
    }
    playbackTokens.removeAll()
    // Queue global cancellation before individual speech/prompt failures so
    // Flutter cannot interpret an interrupted capture as a reason to retry.
    // Foreground lessons also need this event when background learning is off.
    onBackgroundLearningEvent?([
      "type": "background.interrupted",
      "reason": reason,
    ])
    backgroundCaptureHandoffDelegate?.interruptBackgroundAudioHandoff(
      caller: "IOSAudioSessionCoordinator.interruptionBegan"
    )
    endMainTurn(reason: "audio_session_interrupted", caller: "IOSAudioSessionCoordinator.interruptionBegan")
  }

  private func routeDescription(_ route: AVAudioSessionRouteDescription) -> String {
    let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
    let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
    return "in=[\(inputs.joined(separator: ", "))] out=[\(outputs.joined(separator: ", "))]"
  }

  private func makeTurnId() -> String {
    "ios-main-\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString.prefix(6))"
  }

  private func scheduleSafetyTimeout() {
    turnTimeout?.cancel()
    let expectedTurnId = activeTurnId
    let item = DispatchWorkItem { [weak self] in
      self?.endMainTurn(
        reason: "native_safety_timeout",
        caller: "IOSAudioSessionCoordinator",
        expectedTurnId: expectedTurnId
      )
    }
    turnTimeout = item
    IOSNativeWork.queue.asyncAfter(deadline: .now() + 45, execute: item)
  }
}

private enum IOSAudioSessionCoordinatorError: LocalizedError {
  case audioSessionInterrupted
  case builtInMicUnavailable
  case hfpInputUnavailable
  case mainAudioSourceConflict
  case backgroundGraphUnavailable
  case externalMediaActive
  case audioRouteChangeBusy

  var errorDescription: String? {
    switch self {
    case .audioSessionInterrupted:
      return "Âm thanh HOMI đã tạm dừng vì ứng dụng khác đang sử dụng âm thanh."
    case .builtInMicUnavailable:
      return "Không tìm thấy mic tích hợp của iPhone/iPad."
    case .hfpInputUnavailable:
      return "Không tìm thấy mic HFP đang kết nối."
    case .mainAudioSourceConflict:
      return "Phiên micro HM-D001 trước đang kết thúc. Hãy thử lại."
    case .backgroundGraphUnavailable:
      return "Đường micro đã thay đổi. Mở lại HOMI rồi nhấn MAIN để thử lại."
    case .externalMediaActive:
      return "Âm thanh khác đang phát. Nhấn MAIN để tiếp tục với HOMI."
    case .audioRouteChangeBusy:
      return "Dừng âm thanh HOMI và mở ứng dụng trước khi đổi mic HFP."
    }
  }
}
