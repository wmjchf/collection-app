/// 从文本中提取首个 http(s) URL。
String? extractHttpUrl(String text) {
  final match = RegExp(
    r'https?://\S+',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) return null;
  return match.group(0)?.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
}

bool isValidHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.isScheme('http') || uri.isScheme('https')) &&
      uri.host.isNotEmpty;
}
