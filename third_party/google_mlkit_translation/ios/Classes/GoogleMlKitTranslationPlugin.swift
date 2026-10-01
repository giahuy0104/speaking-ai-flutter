import Flutter
import Foundation

#if HOMI_TRANSLATION_SIMULATOR_STUB
#if !targetEnvironment(simulator)
#error("Simulator translation adapter cannot be compiled for an iPhone/IPA. Reinstall device Pods.")
#endif
#else
import MLKitCommon
import MLKitTranslate
#endif

/// HOMI's on-device Vietnamese/English adapter. Translation never initiates a
/// download: only the parent-authorized model download method can do so.
@objc
public final class GoogleMlKitTranslationPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "google_mlkit_on_device_translator",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(GoogleMlKitTranslationPlugin(), channel: channel)
  }

  public static func supportsLanguage(_ tag: String) -> Bool {
    return tag == "vi" || tag == "en"
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if HOMI_TRANSLATION_SIMULATOR_STUB
    switch call.method {
    case "nlp#closeLanguageTranslator": result(nil)
    case "nlp#manageLanguageModelModels":
      if (call.arguments as? [String: Any])?["task"] as? String == "check" {
        result(false)
      } else {
        result(Self.simulatorUnavailable())
      }
    case "nlp#startLanguageTranslator": result(Self.simulatorUnavailable())
    default: result(FlutterMethodNotImplemented)
    }
    #else
    switch call.method {
    case "nlp#manageLanguageModelModels": manageModel(call, result: result)
    case "nlp#startLanguageTranslator": translate(call, result: result)
    case "nlp#closeLanguageTranslator":
      if let uid = (call.arguments as? [String: Any])?["id"] as? String {
        instances.removeValue(forKey: uid)
      }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
    #endif
  }

  #if HOMI_TRANSLATION_SIMULATOR_STUB
  private static func simulatorUnavailable() -> FlutterError {
    return FlutterError(
      code: "OFFLINE_TRANSLATION_SIMULATOR_UNAVAILABLE",
      message: "On-device translation requires a physical iPhone.", details: nil
    )
  }
  #else
  private var instances: [String: Translator] = [:]
  private struct Download {
    let translator: Translator
    var results: [FlutterResult]
  }
  private var downloads: [String: Download] = [:]

  private func modelReady(_ tag: String) -> Bool {
    // English is built into ML Kit; creating an English RemoteModel is invalid.
    if tag == "en" { return true }
    let model = TranslateRemoteModel.translateRemoteModel(language: TranslateLanguage(rawValue: tag))
    return ModelManager.modelManager().isModelDownloaded(model)
  }

  private func manageModel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let tag = args["model"] as? String, Self.supportsLanguage(tag),
      let task = args["task"] as? String
    else {
      result(FlutterError(code: "invalid_args", message: "Invalid language model request.", details: nil))
      return
    }
    switch task {
    case "check": result(modelReady(tag))
    case "download":
      if modelReady(tag) { result("success"); return }
      if var active = downloads[tag] {
        active.results.append(result)
        downloads[tag] = active
        return
      }
      let translator = Translator.translator(options: TranslatorOptions(
        sourceLanguage: TranslateLanguage(rawValue: tag), targetLanguage: .english
      ))
      downloads[tag] = Download(translator: translator, results: [result])
      let conditions = ModelDownloadConditions(
        allowsCellularAccess: !(args["wifi"] as? Bool ?? true),
        allowsBackgroundDownloading: true
      )
      translator.downloadModelIfNeeded(with: conditions) { [weak self] error in
        DispatchQueue.main.async {
          guard let self = self, let active = self.downloads.removeValue(forKey: tag) else { return }
          // Do not expose source text or provider diagnostics in bridge errors.
          let response: Any = error == nil && self.modelReady(tag)
            ? "success" : "error"
          for callback in active.results { callback(response) }
        }
      }
    case "delete":
      guard tag != "en" else { result("error"); return }
      let model = TranslateRemoteModel.translateRemoteModel(language: TranslateLanguage(rawValue: tag))
      ModelManager.modelManager().deleteDownloadedModel(model) { error in
        DispatchQueue.main.async { result(error == nil ? "success" : "error") }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func translate(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let uid = args["id"] as? String, let text = args["text"] as? String,
      let source = args["source"] as? String, let target = args["target"] as? String,
      Self.supportsLanguage(source), Self.supportsLanguage(target), source != target
    else {
      result(FlutterError(code: "invalid_args", message: "Invalid translation request.", details: nil))
      return
    }
    guard modelReady(source), modelReady(target) else {
      result(FlutterError(
        code: "OFFLINE_TRANSLATION_MODEL_UNAVAILABLE",
        message: "Download the language packs over Wi-Fi before translating.", details: nil
      ))
      return
    }
    let translator = instances[uid] ?? Translator.translator(options: TranslatorOptions(
      sourceLanguage: TranslateLanguage(rawValue: source), targetLanguage: TranslateLanguage(rawValue: target)
    ))
    instances[uid] = translator
    translator.translate(text) { translatedText, error in
      DispatchQueue.main.async {
        if error != nil || translatedText == nil {
          result(FlutterError(code: "OFFLINE_TRANSLATION_FAILED", message: "On-device translation failed.", details: nil))
        } else {
          result(translatedText)
        }
      }
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    let pending = downloads.values.flatMap { $0.results }
    downloads.removeAll()
    instances.removeAll()
    for result in pending {
      result(FlutterError(code: "cancelled", message: "Translation bridge detached.", details: nil))
    }
  }
  #endif
}
