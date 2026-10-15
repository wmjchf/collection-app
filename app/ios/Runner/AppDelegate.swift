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

    let channel = FlutterMethodChannel(
      name: "super_collection/clipboard",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "hasProbableUrl":
        Self.detectProbableUrl(result: result)
      case "pasteboardChangeCount":
        result(UIPasteboard.general.changeCount)
      default:
        result(FlutterMethodNotImplemented)
      }
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
