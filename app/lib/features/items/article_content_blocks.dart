/// 正文块：纯文字、标题或内嵌图（由轻量 Markdown 拆出）。
sealed class ArticleBlock {
  const ArticleBlock();
}

class ArticleTextBlock extends ArticleBlock {
  const ArticleTextBlock(this.text);
  final String text;
}

class ArticleHeadingBlock extends ArticleBlock {
  const ArticleHeadingBlock({required this.level, required this.text});
  final int level;
  final String text;
}

class ArticleImageBlock extends ArticleBlock {
  const ArticleImageBlock(this.url);
  final String url;
}

/// 解析正文中的 Markdown 图片 / 标题，按阅读顺序拆块。
class ArticleContentBlocks {
  ArticleContentBlocks._();

  static final RegExp imageLine = RegExp(
    r'^[ \t]*!\[([^\]]*)\]\(([^)\s]+)\)[ \t]*$',
    multiLine: true,
  );

  static final RegExp imageInline = RegExp(
    r'!\[([^\]]*)\]\(([^)\s]+)\)',
  );

  static final RegExp headingLine = RegExp(r'^(#{1,4})\s+(.+)$');

  /// 去掉图片与 Markdown 标记后的可见纯文字（标注偏移用）。
  static String plainText(String content) {
    // 延迟依赖避免循环：visiblePlain 在 article_markdown 里实现完整逻辑
    return _plainFallback(content);
  }

  static String _plainFallback(String content) {
    final normalized =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final buf = StringBuffer();
    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (buf.isNotEmpty) buf.write('\n');
        continue;
      }
      if (imageLine.hasMatch(trimmed)) continue;
      final hm = headingLine.firstMatch(trimmed);
      var body = hm != null ? hm.group(2)! : line;
      body = body
          .replaceAllMapped(RegExp(r'\{\{(\d+)\|([\s\S]*?)\}\}'), (m) => m.group(2)!)
          .replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1)!)
          .replaceAllMapped(
            RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)'),
            (m) => m.group(1)!,
          );
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(body);
    }
    return buf
        .toString()
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static List<ArticleBlock> parse(String content) {
    final normalized =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (normalized.isEmpty) return const [];

    final blocks = <ArticleBlock>[];
    final buffer = StringBuffer();

    void flushText() {
      final t = buffer.toString().trim();
      buffer.clear();
      if (t.isNotEmpty) blocks.add(ArticleTextBlock(t));
    }

    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      final m = imageLine.firstMatch(trimmed);
      if (m != null) {
        flushText();
        final url = m.group(2)!.trim();
        if (url.isNotEmpty) blocks.add(ArticleImageBlock(url));
        continue;
      }

      final hm = headingLine.firstMatch(trimmed);
      if (hm != null) {
        flushText();
        blocks.add(
          ArticleHeadingBlock(
            level: hm.group(1)!.length,
            text: hm.group(2)!.trim(),
          ),
        );
        continue;
      }

      if (imageInline.hasMatch(line)) {
        var rest = line;
        while (true) {
          final im = imageInline.firstMatch(rest);
          if (im == null) {
            buffer.writeln(rest);
            break;
          }
          final before = rest.substring(0, im.start);
          if (before.trim().isNotEmpty) {
            buffer.write(before);
            flushText();
          } else if (buffer.isNotEmpty) {
            flushText();
          }
          final url = im.group(2)!.trim();
          if (url.isNotEmpty) blocks.add(ArticleImageBlock(url));
          rest = rest.substring(im.end);
        }
        continue;
      }
      buffer.writeln(line);
    }
    flushText();
    return blocks;
  }

  static bool hasInlineImages(String content) =>
      imageInline.hasMatch(content);

  static bool hasRichMarkup(String content) =>
      hasInlineImages(content) ||
      headingLine.hasMatch(content) ||
      content.contains('**') ||
      content.contains('{{') ||
      RegExp(r'(?<!\*)\*(?!\*)').hasMatch(content);
}
