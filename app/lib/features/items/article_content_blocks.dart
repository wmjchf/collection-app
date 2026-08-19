import 'package:super_collection/core/network/qq_video_resolve.dart';

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
  const ArticleImageBlock(this.url, {this.width, this.height});
  final String url;
  /// 原文声明的展示宽高（CSS 像素）；解码后可再校正。
  final double? width;
  final double? height;
}

/// 正文内嵌视频：`!v[posterUrl](playUrl)`
class ArticleVideoBlock extends ArticleBlock {
  const ArticleVideoBlock(this.url, {this.posterUrl});
  final String url;
  final String? posterUrl;
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

  /// `!v[poster](playUrl)` 单独一行。
  static final RegExp videoLine = RegExp(
    r'^[ \t]*!v\[([^\]]*)\]\(([^)\s]+)\)[ \t]*$',
    multiLine: true,
  );

  static final RegExp headingLine = RegExp(r'^(#{1,4})\s+(.+)$');
  static final RegExp _altSize = RegExp(r'^(\d+)x(\d+)$');

  static ArticleImageBlock _imageFromMatch(RegExpMatch m) {
    final url = (m.group(2) ?? '').trim();
    final size = _sizeFromAlt(m.group(1));
    return ArticleImageBlock(url, width: size.$1, height: size.$2);
  }

  /// 生产解不出直链时曾把视频封面写成普通图；阅读页按封面 CDN 还原成播放器。
  static ArticleBlock _mediaFromImageMatch(RegExpMatch m) {
    final img = _imageFromMatch(m);
    final vid = QqVideoResolver.vidFrom(img.url);
    if (vid != null) {
      return ArticleVideoBlock('qqvid:$vid', posterUrl: img.url);
    }
    return img;
  }

  static (double?, double?) _sizeFromAlt(String? alt) {
    final m = _altSize.firstMatch((alt ?? '').trim());
    if (m == null) return (null, null);
    final w = double.parse(m.group(1)!);
    final h = double.parse(m.group(2)!);
    return (w > 0 ? w : null, h > 0 ? h : null);
  }

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
      if (videoLine.hasMatch(trimmed)) continue;
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
      final vm = videoLine.firstMatch(trimmed);
      if (vm != null) {
        flushText();
        final url = (vm.group(2) ?? '').trim();
        final poster = (vm.group(1) ?? '').trim();
        if (url.isNotEmpty) {
          blocks.add(
            ArticleVideoBlock(
              url,
              posterUrl: poster.isEmpty ? null : poster,
            ),
          );
        }
        continue;
      }

      final m = imageLine.firstMatch(trimmed);
      if (m != null) {
        flushText();
        final media = _mediaFromImageMatch(m);
        if (media is ArticleImageBlock) {
          if (media.url.isNotEmpty) blocks.add(media);
        } else {
          blocks.add(media);
        }
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
          final media = _mediaFromImageMatch(im);
          if (media is ArticleImageBlock) {
            if (media.url.isNotEmpty) blocks.add(media);
          } else {
            blocks.add(media);
          }
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

  static bool hasInlineVideos(String content) =>
      videoLine.hasMatch(content) ||
      QqVideoResolver.vidFrom(content) != null;

  static List<String> inlineVideoUrls(String content) {
    return parse(content)
        .whereType<ArticleVideoBlock>()
        .map((b) => b.url)
        .where((u) => u.trim().isNotEmpty)
        .toList(growable: false);
  }

  static bool hasRichMarkup(String content) =>
      hasInlineImages(content) ||
      hasInlineVideos(content) ||
      headingLine.hasMatch(content) ||
      content.contains('**') ||
      content.contains('{{') ||
      RegExp(r'(?<!\*)\*(?!\*)').hasMatch(content);
}
