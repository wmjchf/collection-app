import AudioToolbox
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 必须强引用；局部创建 后立刻释放会导致触感发不出来
  private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
  private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
  private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
  private static let selectionGen = UISelectionFeedbackGenerator()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    Self.lightImpact.prepare()
    Self.mediumImpact.prepare()
    Self.heavyImpact.prepare()
    Self.selectionGen.prepare()
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

    // 触感：常驻 UIImpactFeedbackGenerator + AudioToolbox 兜底
    let haptics = FlutterMethodChannel(
      name: "super_collection/haptics",
      binaryMessenger: messenger
    )
    haptics.setMethodCallHandler { call, result in
      DispatchQueue.main.async {
        switch call.method {
        case "impact":
          let styleName = (call.arguments as? [String: Any])?["style"] as? String
          Self.impact(styleName: styleName)
          result(nil)
        case "selection":
          Self.selectionGen.prepare()
          Self.selectionGen.selectionChanged()
          AudioServicesPlaySystemSound(1519)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private static func impact(styleName: String?) {
    let gen: UIImpactFeedbackGenerator
    let tapticId: SystemSoundID
    switch styleName {
    case "heavy":
      gen = heavyImpact
      tapticId = 1521
    case "medium":
      gen = mediumImpact
      tapticId = 1520
    default:
      gen = lightImpact
      tapticId = 1519
    }
    gen.prepare()
    gen.impactOccurred()
    // iPhone Taptic：不依赖 UIFeedback 生命周期；静音下仍有震感、无提示音
    AudioServicesPlaySystemSound(tapticId)
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
