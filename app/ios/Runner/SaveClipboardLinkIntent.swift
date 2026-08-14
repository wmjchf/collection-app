import AppIntents
import Foundation
import UIKit

/// 桌面 / 快捷指令：不打开 App 界面，保存链接并触发服务端解析。
///
/// 注意：iOS 16+ 后台直接读剪贴板常被隐私拦截（返回空且不弹授权）。
/// 推荐快捷指令链路：获取剪贴板 → 本 Intent（把内容填入「链接」参数）。
@available(iOS 16.0, *)
struct SaveClipboardLinkIntent: AppIntent {
  static var title: LocalizedStringResource = "保存剪贴板链接"
  static var description = IntentDescription(
    "保存链接到超级收藏夹（不打开 App）。建议在快捷指令中先用「获取剪贴板」再传入「链接」。"
  )

  /// 关键：不拉起 App 界面
  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "链接",
    description: "优先传入；留空才会尝试直接读剪贴板（后台可能被系统拦截）",
    requestValueDialog: IntentDialog("要保存的链接")
  )
  var url: String?

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let token = ShortcutAuthStore.accessToken
    let base = ShortcutAuthStore.apiBaseUrl
    guard let token, !token.isEmpty, let base, !base.isEmpty else {
      throw ShortcutSaveError.notLoggedIn
    }

    let fromParam = url?.trimmingCharacters(in: .whitespacesAndNewlines)
    let raw: String?
    if let fromParam, !fromParam.isEmpty {
      raw = fromParam
    } else {
      raw = ShortcutAuthStore.clipboardRawText()
    }

    guard let raw, let link = ShortcutAuthStore.extractHttpUrl(raw) else {
      throw ShortcutSaveError.noLink
    }

    let result = try await ShortcutAuthStore.createItem(baseUrl: base, token: token, url: link)
    ShortcutAuthStore.clearClipboard()
    if result.existed {
      return .result(dialog: "该链接已收藏")
    }
    return .result(dialog: "已保存，正在解析")
  }
}

@available(iOS 16.0, *)
enum ShortcutSaveError: Error, CustomLocalizedStringResourceConvertible {
  case notLoggedIn
  case noLink
  case api(String)

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notLoggedIn:
      return "请先打开超级收藏夹并登录"
    case .noLink:
      return "读不到链接。请在快捷指令中：①获取剪贴板 ②把内容填入「链接」参数后再运行"
    case .api(let message):
      return "\(message)"
    }
  }
}

enum ShortcutAuthStore {
  /// shared_preferences 默认前缀
  private static let flutterPrefix = "flutter."

  static var accessToken: String? {
    UserDefaults.standard.string(forKey: flutterPrefix + "auth.accessToken")
  }

  static var apiBaseUrl: String? {
    UserDefaults.standard.string(forKey: flutterPrefix + "shortcut.apiBaseUrl")
  }

  /// 尽量从剪贴板取出文本/URL（后台仍可能因隐私返回 nil）
  static func clipboardRawText() -> String? {
    let pb = UIPasteboard.general

    if let url = pb.url?.absoluteString,
       let trimmed = optionalTrim(url) {
      return trimmed
    }
    if let urls = pb.urls {
      for u in urls {
        if let s = optionalTrim(u.absoluteString) { return s }
      }
    }
    if let s = optionalTrim(pb.string) { return s }

    // 部分 App（含微信）可能只写了 public.url / utf8 plain-text item
    if let items = pb.items as? [[String: Any]] {
      for item in items {
        if let data = item["public.url"] as? Data,
           let s = String(data: data, encoding: .utf8),
           let trimmed = optionalTrim(s) {
          return trimmed
        }
        if let s = item["public.url"] as? String,
           let trimmed = optionalTrim(s) {
          return trimmed
        }
        if let data = item["public.utf8-plain-text"] as? Data,
           let s = String(data: data, encoding: .utf8),
           let trimmed = optionalTrim(s) {
          return trimmed
        }
        if let s = item["public.utf8-plain-text"] as? String,
           let trimmed = optionalTrim(s) {
          return trimmed
        }
      }
    }
    return nil
  }

  static func clearClipboard() {
    UIPasteboard.general.items = []
  }

  private static func optionalTrim(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
      return nil
    }
    return t
  }

  static func extractHttpUrl(_ text: String) -> String? {
    let pattern = #"https?://[^\s<>\"\u3000]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let swiftRange = Range(match.range, in: text) else {
      return nil
    }
    var url = String(text[swiftRange])
    while let last = url.last, ".,;:!?)」』】".contains(last) {
      url.removeLast()
    }
    guard let uri = URL(string: url), let scheme = uri.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          uri.host != nil else {
      return nil
    }
    return url
  }

  struct CreateResult {
    let existed: Bool
  }

  @available(iOS 16.0, *)
  static func createItem(baseUrl: String, token: String, url: String) async throws -> CreateResult {
    let root = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
    guard let endpoint = URL(string: "\(root)/api/items") else {
      throw ShortcutSaveError.api("接口地址无效")
    }

    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["url": url])
    req.timeoutInterval = 30

    let (data, response) = try await URLSession.shared.data(for: req)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if status == 401 {
      throw ShortcutSaveError.notLoggedIn
    }
    if status < 200 || status >= 300 {
      let message = (json?["message"] as? String) ?? "保存失败（\(status)）"
      throw ShortcutSaveError.api(message)
    }
    let existed = json?["existed"] as? Bool ?? (status == 200)
    return CreateResult(existed: existed)
  }
}

@available(iOS 16.0, *)
struct SuperCollectionShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: SaveClipboardLinkIntent(),
      phrases: [
        "用\(.applicationName)保存链接",
        "保存剪贴板到\(.applicationName)",
      ],
      shortTitle: "保存剪贴板链接",
      systemImageName: "link.badge.plus"
    )
  }
}
