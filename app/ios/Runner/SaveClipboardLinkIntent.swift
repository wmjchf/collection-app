import AppIntents
import Foundation
import UIKit

/// 桌面 / 快捷指令：不打开 App，保存链接并尽量在本机完成解析（微信可抓页；抖音需打开 App 用 WebView）。
///
/// 注意：iOS 16+ 后台直接读剪贴板常被隐私拦截。
/// 推荐快捷指令：获取剪贴板 → 本 Intent（填入「链接」）→ 拷贝到剪贴板（留空）。
/// 进度条需 iOS 17+（ProgressReportingIntent）。
@available(iOS 17.0, *)
struct SaveClipboardLinkIntent: AppIntent, ProgressReportingIntent {
  static var title: LocalizedStringResource = "保存剪贴板链接"
  static var description = IntentDescription(
    "保存链接到超级收藏夹并尽量完成解析（不打开 App）。建议先「获取剪贴板」再传入「链接」。"
  )

  static var openAppWhenRun: Bool = false

  @Parameter(
    title: "链接",
    description: "优先传入；留空才会尝试直接读剪贴板（后台可能被系统拦截）",
    requestValueDialog: IntentDialog("要保存的链接")
  )
  var url: String?

  func perform() async throws -> some IntentResult & ProvidesDialog {
    progress.totalUnitCount = 100
    reportProgress(5, "准备中…")

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

    reportProgress(15, "正在保存…")
    let created = try await ShortcutAuthStore.createItem(baseUrl: base, token: token, url: link)
    await ShortcutAuthStore.clearClipboard()

    if created.existed, (created.status ?? "").lowercased() == "success" {
      reportProgress(100, "完成")
      return .result(dialog: IntentDialog("该链接已收藏"))
    }

    let pageUrl = created.canonicalUrl ?? created.url ?? link
    let dialog = try await ShortcutAuthStore.ensureParsed(
      baseUrl: base,
      token: token,
      itemId: created.itemId,
      pageUrl: pageUrl,
      platform: created.platform,
      existed: created.existed,
      onProgress: { [progress] completed, label in
        progress.completedUnitCount = completed
        progress.localizedDescription = label
      }
    )
    reportProgress(100, "完成")
    return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
  }

  private func reportProgress(_ completed: Int64, _ label: String) {
    progress.completedUnitCount = completed
    progress.localizedDescription = label
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
      return "剪贴板里没有可用链接"
    case .api(let message):
      return "\(message)"
    }
  }
}

enum ShortcutAuthStore {
  private static let flutterPrefix = "flutter."

  private static let mobileUA =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 "
    + "Mobile/15E148 Safari/604.1"

  static var accessToken: String? {
    UserDefaults.standard.string(forKey: flutterPrefix + "auth.accessToken")
  }

  static var apiBaseUrl: String? {
    UserDefaults.standard.string(forKey: flutterPrefix + "shortcut.apiBaseUrl")
  }

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

  static func clearClipboard() async {
    await MainActor.run {
      let pb = UIPasteboard.general
      pb.setItems([["public.utf8-plain-text": Data()]], options: [:])
      pb.string = ""
      pb.url = nil
      pb.items = []
    }
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
    let itemId: Int
    let platform: String?
    let status: String?
    let url: String?
    let canonicalUrl: String?
  }

  private static func apiRoot(_ baseUrl: String) -> String {
    baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
  }

  @available(iOS 16.0, *)
  static func createItem(baseUrl: String, token: String, url: String) async throws -> CreateResult {
    let root = apiRoot(baseUrl)
    guard let endpoint = URL(string: "\(root)/api/items") else {
      throw ShortcutSaveError.api("接口地址无效")
    }

    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["url": url])
    req.timeoutInterval = 45

    let (data, response) = try await URLSession.shared.data(for: req)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if statusCode == 401 {
      throw ShortcutSaveError.notLoggedIn
    }
    if statusCode < 200 || statusCode >= 300 {
      let message = (json?["message"] as? String) ?? "保存失败（\(statusCode)）"
      throw ShortcutSaveError.api(message)
    }

    let item = json?["item"] as? [String: Any] ?? [:]
    guard let itemId = (item["id"] as? Int) ?? (item["id"] as? NSNumber)?.intValue else {
      throw ShortcutSaveError.api("保存成功但未返回条目 ID")
    }
    let existed = json?["existed"] as? Bool ?? (statusCode == 200)
    return CreateResult(
      existed: existed,
      itemId: itemId,
      platform: item["platform"] as? String,
      status: item["status"] as? String,
      url: item["url"] as? String,
      canonicalUrl: item["canonicalUrl"] as? String
    )
  }

  /// 微信 / 抖音：本机抓 HTML 回传；其它：短轮询服务端解析，若需本机抓再补。
  /// 抖音图文依赖 JS/WebView，Intent 里纯 HTTP 常拿到壳页并误判视频 → 只入库，等打开 App 用 WebView 补齐。
  @available(iOS 16.0, *)
  static func ensureParsed(
    baseUrl: String,
    token: String,
    itemId: Int,
    pageUrl: String,
    platform: String?,
    existed: Bool,
    onProgress: ((Int64, String) -> Void)? = nil
  ) async throws -> String {
    let plat = (platform ?? "").lowercased()
    let isWeixin = plat == "weixin" || plat == "wechat"
    let isDouyin = plat == "douyin" || pageUrl.lowercased().contains("douyin.com")
      || pageUrl.lowercased().contains("iesdouyin.com")

    if isDouyin {
      onProgress?(40, "已入库，打开 App 完成解析…")
      // 不在此用 HTTP 硬抓：短链图文易变成错误视频；留给主 App WebView + 补齐队列
      return existed
        ? "已收藏。打开超级收藏夹即可自动补齐解析"
        : "已保存。打开超级收藏夹即可自动补齐解析"
    }

    if isWeixin {
      return try await clientFetchAndParse(
        baseUrl: baseUrl,
        token: token,
        itemId: itemId,
        pageUrl: pageUrl,
        existed: existed,
        onProgress: onProgress
      )
    }

    onProgress?(25, "正在解析…")
    // 非微信：等服务端异步解析；若中途变为需本机抓页则补抓
    for i in 0..<20 {
      try await Task.sleep(nanoseconds: 700_000_000)
      let pct = min(Int64(25 + i * 2), 70)
      onProgress?(pct, "正在解析…")
      let st = try await getParseStatus(baseUrl: baseUrl, token: token, itemId: itemId)
      let status = st.status.lowercased()
      if status == "success" {
        onProgress?(95, "即将完成…")
        return existed ? "该链接已收藏" : "已保存并解析完成"
      }
      if status == "failed" {
        let tip = st.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tip, !tip.isEmpty {
          return existed ? "已收藏，解析失败：\(tip)" : "已保存，解析失败：\(tip)"
        }
        return existed ? "已收藏，解析失败" : "已保存，解析失败"
      }
      if st.needsClientFetch {
        let fetchUrl = (st.url ?? pageUrl).lowercased()
        if fetchUrl.contains("douyin.com") || fetchUrl.contains("iesdouyin.com") {
          return existed
            ? "已收藏。打开超级收藏夹即可自动补齐解析"
            : "已保存。打开超级收藏夹即可自动补齐解析"
        }
        return try await clientFetchAndParse(
          baseUrl: baseUrl,
          token: token,
          itemId: itemId,
          pageUrl: st.url ?? pageUrl,
          existed: existed,
          onProgress: onProgress
        )
      }
    }

    // 超时仍 pending：尝试本机抓一次兜底（抖音已在上方排除）
    return try await clientFetchAndParse(
      baseUrl: baseUrl,
      token: token,
      itemId: itemId,
      pageUrl: pageUrl,
      existed: existed,
      onProgress: onProgress
    )
  }

  @available(iOS 16.0, *)
  private static func clientFetchAndParse(
    baseUrl: String,
    token: String,
    itemId: Int,
    pageUrl: String,
    existed: Bool,
    onProgress: ((Int64, String) -> Void)? = nil
  ) async throws -> String {
    onProgress?(35, "正在抓取页面…")
    let html = try await fetchHtml(pageUrl)
    onProgress?(70, "正在解析正文…")
    let item = try await parseWithHtml(
      baseUrl: baseUrl,
      token: token,
      itemId: itemId,
      html: html
    )
    onProgress?(92, "即将完成…")
    let status = (item["status"] as? String ?? "").lowercased()
    if status == "success" {
      return existed ? "已收藏并补齐解析" : "已保存并解析完成"
    }
    if status == "failed" {
      let tip = (item["errorMessage"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if let tip, !tip.isEmpty {
        return existed ? "已收藏，解析失败：\(tip)" : "已保存，解析失败：\(tip)"
      }
      return existed ? "已收藏，解析失败" : "已保存，解析失败"
    }
    return existed ? "已收藏，解析仍在进行" : "已保存，解析仍在进行"
  }

  @available(iOS 16.0, *)
  private static func fetchHtml(_ urlString: String) async throws -> String {
    guard let url = URL(string: urlString) else {
      throw ShortcutSaveError.api("链接无效")
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.setValue(mobileUA, forHTTPHeaderField: "User-Agent")
    req.setValue(
      "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
      forHTTPHeaderField: "Accept"
    )
    req.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
    req.timeoutInterval = 30

    let (data, response) = try await URLSession.shared.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    if code < 200 || code >= 400 {
      throw ShortcutSaveError.api("本机抓页失败（\(code)）")
    }
    let html = String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .isoLatin1)
      ?? ""
    if html.trimmingCharacters(in: .whitespacesAndNewlines).count < 80 {
      throw ShortcutSaveError.api("页面内容过短，无法解析")
    }
    return html
  }

  @available(iOS 16.0, *)
  private static func parseWithHtml(
    baseUrl: String,
    token: String,
    itemId: Int,
    html: String
  ) async throws -> [String: Any] {
    let root = apiRoot(baseUrl)
    guard let endpoint = URL(string: "\(root)/api/items/\(itemId)/parse-with-html") else {
      throw ShortcutSaveError.api("接口地址无效")
    }
    var req = URLRequest(url: endpoint)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["html": html])
    req.timeoutInterval = 60

    let (data, response) = try await URLSession.shared.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if code == 401 {
      throw ShortcutSaveError.notLoggedIn
    }
    if code < 200 || code >= 300 {
      let message = (json?["message"] as? String) ?? "回传解析失败（\(code)）"
      throw ShortcutSaveError.api(message)
    }
    return (json?["item"] as? [String: Any]) ?? [:]
  }

  @available(iOS 16.0, *)
  private static func getParseStatus(
    baseUrl: String,
    token: String,
    itemId: Int
  ) async throws -> (status: String, needsClientFetch: Bool, url: String?, errorMessage: String?) {
    let root = apiRoot(baseUrl)
    guard let endpoint = URL(string: "\(root)/api/items/\(itemId)/parse-status") else {
      throw ShortcutSaveError.api("接口地址无效")
    }
    var req = URLRequest(url: endpoint)
    req.httpMethod = "GET"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.timeoutInterval = 15

    let (data, response) = try await URLSession.shared.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    if code == 401 {
      throw ShortcutSaveError.notLoggedIn
    }
    if code < 200 || code >= 300 {
      let message = (json?["message"] as? String) ?? "查询解析状态失败"
      throw ShortcutSaveError.api(message)
    }
    return (
      status: json?["status"] as? String ?? "pending",
      needsClientFetch: json?["needsClientFetch"] as? Bool ?? false,
      url: json?["url"] as? String,
      errorMessage: json?["errorMessage"] as? String
    )
  }
}

@available(iOS 17.0, *)
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
