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

    // 触感：直接走 UIKit，比 Flutter HapticFeedback 更稳（与响铃/静音无关）
    let haptics = FlutterMethodChannel(
      name: "super_collection/haptics",
      binaryMessenger: messenger
    )
    haptics.setMethodCallHandler { call, result in
      switch call.method {
      case "impact":
        let styleName = (call.arguments as? [String: Any])?["style"] as? String
        Self.impact(styleName: styleName)
        result(nil)
      case "selection":
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func impact(styleName: String?) {
    let style: UIImpactFeedbackGenerator.FeedbackStyle
    switch styleName {
    case "heavy":
      style = .heavy
    case "medium":
      style = .medium
    case "rigid":
      if #available(iOS 13.0, *) {
        style = .rigid
      } else {
        style = .medium
      }
    case "soft":
      if #available(iOS 13.0, *) {
        style = .soft
      } else {
        style = .light
      }
    default:
      style = .light
    }
    let gen = UIImpactFeedbackGenerator(style: style)
    gen.prepare()
    gen.impactOccurred()
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
