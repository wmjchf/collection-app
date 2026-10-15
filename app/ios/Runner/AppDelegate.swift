import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let clipboard = FlutterMethodChannel(
      name: "super_collection/clipboard",
      binaryMessenger: messenger
    )
    clipboard.setMethodCallHandler { call, result in
      switch call.method {
      case "hasProbableUrl":
        Self.detectProbableUrl(result: result)
      case "pasteboardChangeCount":
        result(UIPasteboard.general.changeCount)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // AudioToolbox Taptic：不依赖「系统触感反馈」开关；手感异于 UIKit FeedbackGenerator
    // 1519 peek / 1520 pop / 1521 三重（现代 iPhone 无提示音、仅震感）
    let haptics = FlutterMethodChannel(
      name: "super_collection/haptics",
      binaryMessenger: messenger
    )
    haptics.setMethodCallHandler { call, result in
      guard call.method == "taptic" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let style = (call.arguments as? [String: Any])?["style"] as? String
      let id: SystemSoundID
      switch style {
      case "heavy":
        id = 1521
      case "medium":
        id = 1520
      default:
        id = 1519
      }
      AudioServicesPlaySystemSound(id)
      result(nil)
    }
  }

  /// iOS 16+：用 detectPatterns 判断是否像链接，不弹出「允许粘贴」
  private static func detectProbableUrl(result: @escaping FlutterResult) {
    if #available(iOS 16.0, *) {
      UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { detection in
        DispatchQueue.main.async {
          switch detection {
          case .success(let patterns):
            result(patterns.contains(.probableWebURL))
          case .failure:
            result(false)
          }
        }
      }
      return
    }
    // 旧系统无粘贴授权弹窗；有字符串再交给 Dart 解析
    result(UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs)
  }
}
