import AVFoundation
import Flutter
import Foundation

/// Always visible in Console.app/Xcode's device log, unlike `print()` in a
/// release-style archive build. Temporary: remove once the native streaming
/// path has been confirmed working on a real device.
func streamingAudioLog(_ message: String) {
  NSLog("[StreamingAudio] %@", message)
}

/// Feeds `AVPlayer` a network audio response that has no `Content-Length` and
/// does not support byte-range requests (a TTS clip streamed to the client
/// while it is still being synthesized). AVPlayer's own HTTP loader rejects
/// such a response with AVFoundationErrorDomain -11850
/// ("Operation Stopped" / server incorrectly configured): it expects a
/// well-formed streaming server (Content-Length or range support), which this
/// backend deliberately does not send because the final size is not yet
/// known when the response starts.
///
/// Standard technique: `AVURLAsset` is created with a fake scheme so
/// `AVAssetResourceLoader` hands every load to this delegate instead of its
/// built-in HTTP loader; the real `https` URL is recovered before the real
/// network request is made.
///
/// Every `AVAssetResourceLoadingRequest` is held unanswered until the network
/// response is fully downloaded, then answered all at once with the real,
/// final byte count. AVFoundation has no documented placeholder for "length
/// not known yet" (an estimated or -1 length both risk reproducing the same
/// -11850 this bridge exists to avoid, or AVPlayer never recognizing the
/// resource as finished once real data runs short of an estimate) — a true
/// length removes that ambiguity entirely. This still starts the network
/// request as soon as play() is called (synthesis and transfer overlap, same
/// as true streaming), it just does not hand audio to AVPlayer until the
/// whole clip has arrived; TTS clips this short download in well under a
/// second once synthesis itself is done.
final class StreamingResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate,
  URLSessionDataDelegate
{
  static let fakeScheme = "ailingo-streaming"

  private let realUrl: URL
  private let lock = NSLock()
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var buffer = Data()
  private var contentType: String?
  private var finished = false
  private var failure: Error?
  private var pendingRequests: [AVAssetResourceLoadingRequest] = []

  init(realUrl: URL) {
    self.realUrl = realUrl
    super.init()
  }

  static func fakeUrl(for url: URL) -> URL? {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.scheme = fakeScheme
    return components?.url
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
  ) -> Bool {
    streamingAudioLog(
      "loading request: hasDataRequest=\(loadingRequest.dataRequest != nil) "
        + "hasContentInfoRequest=\(loadingRequest.contentInformationRequest != nil) "
        + "offset=\(loadingRequest.dataRequest.map { Int($0.currentOffset) } ?? -1)"
    )
    lock.lock()
    if let failure {
      lock.unlock()
      loadingRequest.finishLoading(with: failure)
      return true
    }
    if finished {
      // The real length is already known: answer immediately and fully,
      // exactly like a loaded local file (see the resolved branch in
      // didCompleteWithError below for the first time this becomes true).
      if let contentType {
        applyContentInformation(loadingRequest, contentType: contentType)
      }
      drain(loadingRequest)
      lock.unlock()
      loadingRequest.finishLoading()
      return true
    }
    pendingRequests.append(loadingRequest)
    let needsStart = task == nil
    lock.unlock()
    if needsStart { start() }
    return true
  }

  func resourceLoader(
    _ resourceLoader: AVAssetResourceLoader,
    didCancel loadingRequest: AVAssetResourceLoadingRequest
  ) {
    lock.lock()
    pendingRequests.removeAll { $0 === loadingRequest }
    lock.unlock()
  }

  /// Stops the underlying network task. Any loading request still pending at
  /// this point belongs to a player being torn down and is left to AVPlayer
  /// to cancel on its own (it owns the `AVAssetResourceLoadingRequest`).
  func cancel() {
    lock.lock()
    let activeTask = task
    task = nil
    lock.unlock()
    activeTask?.cancel()
  }

  private func start() {
    streamingAudioLog("starting network request: \(realUrl.absoluteString)")
    let configuration = URLSessionConfiguration.default
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    var request = URLRequest(url: realUrl)
    request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let task = session.dataTask(with: request)
    self.task = task
    task.resume()
  }

  /// Delivers everything currently buffered beyond this request's own
  /// offset. Must be called with `lock` held.
  private func drain(_ loadingRequest: AVAssetResourceLoadingRequest) {
    guard let dataRequest = loadingRequest.dataRequest else { return }
    let offset = Int(dataRequest.currentOffset)
    guard offset >= 0, offset < buffer.count else { return }
    let chunk = buffer.subdata(in: offset..<buffer.count)
    dataRequest.respond(with: chunk)
  }

  /// Must be called with `lock` held, and only once `finished` is true: the
  /// real, final `buffer.count` is what makes this unambiguous for
  /// AVFoundation, unlike any estimated or unknown length.
  private func applyContentInformation(
    _ loadingRequest: AVAssetResourceLoadingRequest,
    contentType: String
  ) {
    guard let info = loadingRequest.contentInformationRequest else { return }
    info.contentType = contentType
    info.isByteRangeAccessSupported = false
    info.contentLength = Int64(buffer.count)
  }

  // MARK: URLSessionDataDelegate

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    let http = response as? HTTPURLResponse
    streamingAudioLog(
      "received response: status=\(http?.statusCode ?? -1) "
        + "contentType=\(response.mimeType ?? "nil") "
        + "contentLength=\(response.expectedContentLength)"
    )
    // The content type is recorded now, but every loadingRequest (including
    // a pure content-information probe) stays parked in pendingRequests
    // until didCompleteWithError, when the real length is finally known.
    lock.lock()
    contentType = StreamingAudioBridge.utiForMimeType(response.mimeType ?? "audio/wav")
    lock.unlock()
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    lock.lock()
    buffer.append(data)
    lock.unlock()
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    finished = true
    failure = error
    let requests = pendingRequests
    pendingRequests = []
    let totalBytes = buffer.count
    if error == nil, let contentType {
      for request in requests {
        applyContentInformation(request, contentType: contentType)
        drain(request)
      }
    }
    lock.unlock()
    streamingAudioLog(
      error == nil
        ? "network request finished, total=\(totalBytes) bytes, answering \(requests.count) loading request(s)"
        : "network request failed: \(error!.localizedDescription)"
    )
    for request in requests {
      if let error {
        request.finishLoading(with: error)
      } else {
        request.finishLoading()
      }
    }
  }
}

/// Plays a single network audio clip whose response has no `Content-Length`
/// and does not support HTTP range requests, via a custom
/// `AVAssetResourceLoaderDelegate` (`StreamingResourceLoaderDelegate` above).
/// Reports play/completion/error back to Dart over an `EventChannel` so
/// `JustAudioPlaybackService` can treat this as just another backend for the
/// same `AudioPlaybackService` interface.
///
/// This bridge does not itself acquire the iOS playback-priority token: the
/// Dart orchestration layer (`JustAudioPlaybackService.play`) already holds
/// one via `ailingo_background_learning`'s `beginAudioPlayback` for the whole
/// duration of any iOS playback, native-stream or not.
final class StreamingAudioBridge: NSObject, FlutterStreamHandler {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private var player: AVPlayer?
  private var playerItem: AVPlayerItem?
  private var loaderDelegate: StreamingResourceLoaderDelegate?
  private var statusObservation: NSKeyValueObservation?
  private var rateObservation: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var failureObserver: NSObjectProtocol?
  private var desiredRate: Float = 1.0

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: "ailingo_streaming_audio", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "ailingo_streaming_audio/events", binaryMessenger: messenger)
    super.init()

    methodChannel.setMethodCallHandler(IOSNativeWork.handler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "play":
        let arguments = call.arguments as? [String: Any]
        guard let urlString = arguments?["url"] as? String, let url = URL(string: urlString) else {
          result(FlutterError(code: "INVALID_URL", message: "Missing or invalid url", details: nil))
          return
        }
        IOSNativeWork.onMain { self.play(url: url) }
        result(nil)
      case "stop":
        IOSNativeWork.onMain { self.stop() }
        result(nil)
      case "setRate":
        let rate = Float((call.arguments as? [String: Any])?["rate"] as? Double ?? 1.0)
        IOSNativeWork.onMain { self.setRate(rate) }
        result(nil)
      case "setVolume":
        let volume = Float((call.arguments as? [String: Any])?["volume"] as? Double ?? 1.0)
        IOSNativeWork.onMain { self.player?.volume = volume }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    })
    eventChannel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    IOSNativeWork.queue.async { [weak self] in
      self?.eventSink = { payload in
        DispatchQueue.main.async { events(payload) }
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
    stop()
    IOSNativeWork.onMain { [methodChannel, eventChannel] in
      methodChannel.setMethodCallHandler(nil)
      eventChannel.setStreamHandler(nil)
    }
    eventSink = nil
  }

  /// Must run on the main thread: `AVPlayer`/KVO are not thread-safe.
  private func play(url: URL) {
    streamingAudioLog("play requested: \(url.absoluteString)")
    stop()
    guard let fakeUrl = StreamingResourceLoaderDelegate.fakeUrl(for: url) else {
      streamingAudioLog("could not build a fake-scheme URL, aborting")
      send(["type": "error", "code": -1, "message": "Invalid streaming URL"])
      return
    }
    let delegate = StreamingResourceLoaderDelegate(realUrl: url)
    loaderDelegate = delegate
    let asset = AVURLAsset(url: fakeUrl)
    asset.resourceLoader.setDelegate(delegate, queue: DispatchQueue(label: "ailingo.streaming-audio.loader"))
    let item = AVPlayerItem(asset: asset)
    playerItem = item
    let player = self.player ?? AVPlayer()
    self.player = player

    statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
      guard let self else { return }
      streamingAudioLog("AVPlayerItem.status -> \(observedItem.status.rawValue)")
      guard observedItem.status == .failed else { return }
      let error = observedItem.error
      self.send([
        "type": "error",
        "code": (error as NSError?)?.code ?? -1,
        "message": error?.localizedDescription ?? "Playback failed",
      ])
    }
    rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
      streamingAudioLog("AVPlayer.timeControlStatus -> \(observedPlayer.timeControlStatus.rawValue)")
      self?.send(["type": "playing", "value": observedPlayer.timeControlStatus == .playing])
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      self?.send(["type": "completed"])
    }
    failureObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] notification in
      let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
      self?.send([
        "type": "error",
        "code": (error as NSError?)?.code ?? -1,
        "message": error?.localizedDescription ?? "Playback stopped",
      ])
    }
    player.automaticallyWaitsToMinimizeStalling = false
    player.replaceCurrentItem(with: item)
    player.rate = desiredRate
  }

  private func setRate(_ rate: Float) {
    desiredRate = rate
    if player?.timeControlStatus != .paused {
      player?.rate = rate
    }
  }

  /// Must run on the main thread: `AVPlayer`/KVO are not thread-safe.
  private func stop() {
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    loaderDelegate?.cancel()
    loaderDelegate = nil
    playerItem = nil
    statusObservation?.invalidate()
    statusObservation = nil
    rateObservation?.invalidate()
    rateObservation = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    endObserver = nil
    if let failureObserver {
      NotificationCenter.default.removeObserver(failureObserver)
    }
    failureObserver = nil
  }

  private func send(_ payload: [String: Any]) {
    IOSNativeWork.queue.async { [weak self] in
      self?.eventSink?(payload)
    }
  }

  static func utiForMimeType(_ mimeType: String) -> String {
    switch mimeType.lowercased() {
    case "audio/wav", "audio/x-wav", "audio/wave":
      return "com.microsoft.waveform-audio"
    case "audio/mpeg", "audio/mp3":
      return "public.mp3"
    default:
      return "public.audio"
    }
  }
}
