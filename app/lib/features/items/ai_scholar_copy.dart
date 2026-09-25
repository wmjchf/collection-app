/// Pro（太子/帝王）AI 生成中文案：前缀「AI大学士」
String aiScholarGeneratingLabel(
  String subject, {
  required bool isPro,
}) {
  final text = '正在生成$subject…';
  return isPro ? 'AI大学士$text' : text;
}
