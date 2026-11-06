import Flutter
import Foundation
import UIKit

final class BackgroundLearningBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let audioSessionCoordinator: IOSAudioSessionCoordinator
  private var eventSink: FlutterEventSink?
  private var willResignActiveToken: NSObjectProtocol?
  private var didEnterBackgroundToken: NSObjectProtocol?
  private var willEnterForegroundToken: NSObjectProtocol?
  private var didBecomeActiveToken: NSObjectProtocol?

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionCoordinator: IOSAudioSessionCoordinator
  ) {
    self.audioSessionCoordinator = audioSessionCoordinator
    methodChannel = FlutterMethodChannel(
      name: "ailingo_background_learning",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "ailingo_background_learning/events",
      binaryMessenger: messenger
    )
    super.init()

    willResignActiveToken = NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.prepareForInactivity(caller: "BackgroundLearningBridge.willResignActive")
    }
    didEnterBackgroundToken = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      IOSNativeWork.markApplicationInactive()
      IOSNativeWork.sync {
        self?.audioSessionCoordinator.applicationDidEnterBackground()
        self?.reconcileBackgroundTransitionLease()
      }
    }
    willEnterForegroundToken = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: IOSNativeWork.operationQueue
    ) { [weak self] _ in
      self?.audioSessionCoordinator.applicationWillEnterForeground()
      self?.audioSessionCoordinator.setBackgroundTransitionLeaseActive(false)
    }
    didBecomeActiveToken = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: IOSNativeWork.operationQueue
    ) { [weak self] _ in
      guard let self else { return }
      let shouldKeepEngineRunning = IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
        backgroundLearningEnabled: self.audioSessionCoordinator.isBackgroundLearningEnabled,
        activeLearningRequested: self.audioSessionCoordinator.isActiveLearningRequested,
        applicationIsActive: IOSNativeWork.applicationIsActive,
        hasAvailableHfpInput: self.audioSessionCoordinator.hasAvailableSelectedHfpInput
      )
      if shouldKeepEngineRunning {
        self.audioSessionCoordinator.requestBackgroundCaptureArm(
          caller: "BackgroundLearningBridge.didBecomeActive"
        )
      } else {
        self.audioSessionCoordinator.requestBackgroundCaptureDisarm(
          caller: "BackgroundLearningBridge.didBecomeActive"
        )
      }
    }

    methodChannel.setMethodCallHandler(IOSNativeWork.handler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "start":
        self.audioSessionCoordinator.setBackgroundLearningEnabled(true)
        if IOSNativeWork.applicationIsActive,
          self.audioSessionCoordinator.isActiveLearningRequested
            || self.audioSessionCoordinator.hasAvailableSelectedHfpInput
        {
          self.audioSessionCoordinator.requestBackgroundCaptureArm(
            caller: "BackgroundLearningBridge.start"
          )
        }
        result(true)
      case "stop":
        self.audioSessionCoordinator.setActiveLearningRequested(false)
        self.audioSessionCoordinator.setBackgroundTransitionLeaseActive(false)
        self.audioSessionCoordinator.setBackgroundLearningEnabled(false)
        result(nil)
      case "setActiveLearning":
        let arguments = call.arguments as? [String: Any]
        let requested = arguments?["active"] as? Bool ?? false
        self.audioSessionCoordinator.setActiveLearningRequested(requested)
        let hasAvailableHfpInput = self.audioSessionCoordinator.hasAvailableSelectedHfpInput
        if requested || (IOSNativeWork.applicationIsActive && hasAvailableHfpInput) {
          self.audioSessionCoordinator.requestBackgroundCaptureArm(
            caller: "BackgroundLearningBridge.setActiveLearning"
          )
        } else if !IOSBackgroundAudioHandoffPolicy.shouldKeepEngineRunning(
          backgroundLearningEnabled: self.audioSessionCoordinator.isBackgroundLearningEnabled,
          activeLearningRequested: requested,
          applicationIsActive: IOSNativeWork.applicationIsActive,
          hasAvailableHfpInput: hasAvailableHfpInput
        ) {
          self.audioSessionCoordinator.requestBackgroundCaptureDisarm(
            caller: "BackgroundLearningBridge.setActiveLearningEnded"
          )
        }
        self.reconcileBackgroundTransitionLease()
        result(nil)
      case "isActive":
        result(self.audioSessionCoordinator.isBackgroundLearningEnabled)
      case "resumeForegroundAudio":
        do {
          try self.audioSessionCoordinator.resumeForegroundAudio(
            caller: "BackgroundLearningBridge.resumeForegroundAudio"
          )
          result(true)
        } catch {
          result(FlutterError(
            code: "FOREGROUND_AUDIO_RESUME_DENIED",
            message: error.localizedDescription,
            details: nil
          ))
        }
      case "beginAudioPlayback":
        let arguments = call.arguments as? [String: Any]
        guard let token = arguments?["token"] as? String, !token.isEmpty else {
          result(FlutterError(code: "INVALID_PLAYBACK_TOKEN", message: "Missing playback token", details: nil))
          return
        }
        do {
          result(try self.audioSessionCoordinator.beginAudioPlayback(
            token: token, caller: "BackgroundLearningBridge.beginAudioPlayback"
          ))
        } catch {
          result(FlutterError(code: "AUDIO_PLAYBACK_PRIORITY_DENIED", message: error.localizedDescription, details: nil))
        }
      case "endAudioPlayback":
        let arguments = call.arguments as? [String: Any]
        if let token = arguments?["token"] as? String {
          self.audioSessionCoordinator.endAudioPlayback(
            token: token, caller: "BackgroundLearningBridge.endAudioPlayback"
          )
        }
        result(nil)
      case "isAudioHandoffActive":
        // Flutter audio players share this process-wide AVAudioSession. While
        // native speech, a continuous HFP lease, or the prearmed background
        // engine owns the live play-and-record session, changing its category
        // from Dart can fail with '!pri' (insufficient priority). Callers use
        // this value only to reuse the existing native session; it is never
        // inferred from the background-learning or BLE flag alone.
        result(
          self.audioSessionCoordinator.isBackgroundCaptureArmed
            || self.audioSessionCoordinator.isBackgroundCaptureEngineRunning
            || self.audioSessionCoordinator.isSpeechCaptureActive
            || self.audioSessionCoordinator.isHfpRouteActive
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    eventChannel.setStreamHandler(self)
    audioSessionCoordinator.onBackgroundLearningEvent = { [weak self] payload in
      self?.eventSink?(payload)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    IOSNativeWork.queue.async { [weak self] in
      self?.eventSink = { [weak self] payload in
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if let event = payload as? [String: Any],
            let generation = event["passiveAudioGeneration"] as? Int {
            let current = self.audioSessionCoordinator.claimPassiveAudioEvent(generation: generation)
            guard current else { return }
          }
          events(payload)
        }
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    IOSNativeWork.queue.async { [weak self] in
      self?.eventSink = nil
    }
    return nil
  }

  func dispose() {
    audioSessionCoordinator.setActiveLearningRequested(false)
    audioSessionCoordinator.setBackgroundTransitionLeaseActive(false)
    audioSessionCoordinator.setBackgroundLearningEnabled(false)
    audioSessionCoordinator.onBackgroundLearningEvent = nil
    let methodChannel = methodChannel
    let eventChannel = eventChannel
    IOSNativeWork.onMain {
      methodChannel.setMethodCallHandler(nil)
      eventChannel.setStreamHandler(nil)
    }
    eventSink = nil
    if let willResignActiveToken {
      NotificationCenter.default.removeObserver(willResignActiveToken)
    }
    willResignActiveToken = nil
    if let didEnterBackgroundToken {
      NotificationCenter.default.removeObserver(didEnterBackgroundToken)
    }
    didEnterBackgroundToken = nil
    if let willEnterForegroundToken {
      NotificationCenter.default.removeObserver(willEnterForegroundToken)
    }
    willEnterForegroundToken = nil
    if let didBecomeActiveToken {
      NotificationCenter.default.removeObserver(didBecomeActiveToken)
    }
    didBecomeActiveToken = nil
  }

  /// Start input while the scene is still foregrounded. UIApplication's
  /// notification can arrive after the scene has already become inactive.
  func prepareForInactivity(caller: String) {
    IOSNativeWork.markApplicationInactive()
    IOSNativeWork.sync {
      audioSessionCoordinator.requestBackgroundCaptureArm(caller: caller)
      reconcileBackgroundTransitionLease()
    }
  }

  private func reconcileBackgroundTransitionLease() {
    let shouldRetain = audioSessionCoordinator.isActiveLearningRequested
      && !IOSNativeWork.applicationIsActive
    audioSessionCoordinator.setBackgroundTransitionLeaseActive(shouldRetain)
  }
}
