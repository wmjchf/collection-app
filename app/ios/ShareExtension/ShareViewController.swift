import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

/// 系统分享面板入口：提取链接后打开主 App（`supercollection://save?url=`）。
final class ShareViewController: UIViewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    view.backgroundColor = .clear
    Task { await processShare() }
  }

  private func processShare() async {
    guard let urlString = await extractSharedUrl() else {
      finish()
      return
    }
    openHostApp(with: urlString)
  }

  private func extractSharedUrl() async -> String? {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      return nil
    }
    // 先扫一遍 URL（B 站等常把缩略图排在链接前面）
    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if let url = await loadUrl(from: provider) {
          return url
        }
      }
    }
    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if let text = await loadText(from: provider),
           let url = firstHttpUrl(in: text) {
          return url
        }
      }
      if let text = item.attributedContentText?.string,
         let url = firstHttpUrl(in: text) {
        return url
      }
    }
    return nil
  }

  private func loadUrl(from provider: NSItemProvider) async -> String? {
    let typeIds: [String] = {
      if #available(iOS 14.0, *) {
        return [UTType.url.identifier, "public.url"]
      }
      return [kUTTypeURL as String, "public.url"]
    }()
    for typeId in typeIds where provider.hasItemConformingToTypeIdentifier(typeId) {
      let item = await loadItem(provider: provider, typeId: typeId)
      if let url = item as? URL, isHttp(url) {
        return url.absoluteString
      }
      if let url = item as? NSURL, let absolute = url.absoluteString, isHttp(URL(string: absolute)) {
        return absolute
      }
      if let text = item as? String, let found = firstHttpUrl(in: text) {
        return found
      }
    }
    return nil
  }

  private func loadText(from provider: NSItemProvider) async -> String? {
    let typeIds: [String] = {
      if #available(iOS 14.0, *) {
        return [UTType.plainText.identifier, "public.plain-text", "public.text"]
      }
      return [kUTTypePlainText as String, "public.plain-text", "public.text"]
    }()
    for typeId in typeIds where provider.hasItemConformingToTypeIdentifier(typeId) {
      let item = await loadItem(provider: provider, typeId: typeId)
      if let text = item as? String {
        return text
      }
      if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
        return text
      }
    }
    return nil
  }

  private func loadItem(provider: NSItemProvider, typeId: String) async -> NSSecureCoding? {
    await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: typeId, options: nil) { item, _ in
        continuation.resume(returning: item as? NSSecureCoding)
      }
    }
  }

  private func firstHttpUrl(in text: String) -> String? {
    let pattern = #"https?://\S+"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let swiftRange = Range(match.range, in: text) else {
      return nil
    }
    var url = String(text[swiftRange])
    while let last = url.last, ".,;:!?)》」』】".contains(last) {
      url.removeLast()
    }
    return isHttp(URL(string: url)) ? url : nil
  }

  private func isHttp(_ url: URL?) -> Bool {
    guard let url else { return false }
    let scheme = url.scheme?.lowercased()
    return (scheme == "http" || scheme == "https") && !(url.host?.isEmpty ?? true)
  }

  private func openHostApp(with urlString: String) {
    var components = URLComponents()
    components.scheme = "supercollection"
    components.host = "save"
    components.queryItems = [URLQueryItem(name: "url", value: urlString)]
    guard let openUrl = components.url else {
      finish()
      return
    }

    openContainingApp(openUrl)
    // 扩展立刻 complete 会被系统杀掉，主 App 来不及被拉起
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
      self?.finish()
    }
  }

  /// iOS 18+：`extensionContext.open` 和已废弃的 `openURL:` 在分享扩展里经常失败。
  /// 沿 responder 找到 UIApplication 再 `open`。
  private func openContainingApp(_ url: URL) {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:], completionHandler: nil)
        return
      }
      responder = current.next
    }
    if let application = sharedApplication() {
      application.open(url, options: [:], completionHandler: nil)
      return
    }
    extensionContext?.open(url, completionHandler: nil)
  }

  /// 扩展里不能直接用 `UIApplication.shared`，运行时取。
  private func sharedApplication() -> UIApplication? {
    let selector = NSSelectorFromString("sharedApplication")
    guard UIApplication.responds(to: selector),
          let unmanaged = UIApplication.perform(selector) else {
      return nil
    }
    return unmanaged.takeUnretainedValue() as? UIApplication
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
