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
    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if let url = await loadUrl(from: provider) {
          return url
        }
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

    let complete = { [weak self] in
      self?.finish()
    }

    if let context = extensionContext {
      context.open(openUrl) { success in
        if success {
          complete()
          return
        }
        self.openViaResponderChain(openUrl)
        complete()
      }
      return
    }

    openViaResponderChain(openUrl)
    complete()
  }

  private func openViaResponderChain(_ url: URL) {
    var responder: UIResponder? = self
    let selector = sel_registerName("openURL:")
    while let current = responder {
      if current.responds(to: selector) {
        _ = current.perform(selector, with: url)
        break
      }
      if #available(iOS 18.0, *), let app = current as? UIApplication {
        app.open(url, options: [:], completionHandler: nil)
        break
      }
      responder = current.next
    }
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
