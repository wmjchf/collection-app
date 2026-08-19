import 'package:flutter/material.dart';
import 'package:super_collection/features/items/article_content_blocks.dart';
import 'package:super_collection/features/items/article_markdown.dart';

/// 正文段落排版：标题 / 加粗 / 斜体 / 内嵌图随文展示。
class ArticleBodyText extends StatelessWidget {
  const ArticleBodyText({
    super.key,
    required this.content,
    this.maxChars,
    this.fontSize = 15,
    this.lineHeight = 1.85,
    this.paragraphGap,
    this.color = const Color(0xFF1F242E),
  });

  final String content;

  /// 预览时可截断总字数；按完整段落截断，末尾加省略号。不计图片标记。
  final int? maxChars;
  final double fontSize;
  final double lineHeight;
  final double? paragraphGap;
  final Color color;

  static List<String> splitParagraphs(String content) {
    final normalized =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final parts = <String>[];
    for (final chunk in normalized.split('\n')) {
      final t = chunk.trim();
      if (t.isEmpty) continue;
      if (ArticleContentBlocks.imageLine.hasMatch(t)) continue;
      if (ArticleContentBlocks.videoLine.hasMatch(t)) continue;
      if (ArticleContentBlocks.headingLine.hasMatch(t)) continue;
      parts.add(t);
    }
    if (parts.isEmpty && content.trim().isNotEmpty) {
      final plain = ArticleContentBlocks.plainText(content);
      if (plain.isNotEmpty) return [plain];
    }
    return parts;
  }

  /// 详情预览导语：取正文开头若干段，遇小标题即停（避免站点烂摘要）。
  static String ledePreview(
    String content, {
    int maxParagraphs = 3,
  }) {
    final normalized =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final out = <String>[];
    for (final chunk in normalized.split('\n')) {
      final t = chunk.trim();
      if (t.isEmpty) continue;
      if (ArticleContentBlocks.imageLine.hasMatch(t)) continue;
      if (ArticleContentBlocks.videoLine.hasMatch(t)) continue;
      if (ArticleContentBlocks.headingLine.hasMatch(t)) break;
      out.add(t);
      if (out.length >= maxParagraphs) break;
    }
    return out.join('\n\n').trim();
  }

  List<ArticleBlock> _visibleBlocks() {
    final all = ArticleContentBlocks.parse(content);
    final limit = maxChars;
    if (limit == null || limit <= 0) return all;

    final out = <ArticleBlock>[];
    var used = 0;
    for (final b in all) {
      if (b is ArticleImageBlock || b is ArticleVideoBlock) {
        // 文章阅读/预览不展示插图 / 视频
        continue;
      }
      if (b is ArticleHeadingBlock) {
        if (used >= limit) break;
        final t = b.text;
        if (used + t.length <= limit) {
          out.add(b);
          used += t.length;
        } else {
          final remain = limit - used;
          if (remain > 8) {
            out.add(ArticleHeadingBlock(
              level: b.level,
              text: '${t.substring(0, remain)}…',
            ));
          }
          break;
        }
        continue;
      }
      if (b is! ArticleTextBlock) continue;
      if (used >= limit) break;
      final paragraphs = ArticleBodyText.splitParagraphs(b.text);
      final buf = StringBuffer();
      for (final p in paragraphs) {
        if (used >= limit) break;
        final visibleLen = ArticleMarkdown.visiblePlain(p).length;
        if (used + visibleLen <= limit) {
          if (buf.isNotEmpty) buf.writeln();
          buf.write(p);
          used += visibleLen;
        } else {
          break;
        }
      }
      final t = buf.toString().trim();
      if (t.isNotEmpty) out.add(ArticleTextBlock(t));
      if (used >= limit) break;
    }
    return out;
  }

  TextStyle _headingStyle(int level) {
    final size = switch (level) {
      1 => fontSize + 6,
      2 => fontSize + 4,
      3 => fontSize + 2,
      _ => fontSize + 1,
    };
    return TextStyle(
      fontSize: size,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: color,
      letterSpacing: 0.2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _visibleBlocks();
    if (blocks.isEmpty) {
      return Text(
        '暂无正文',
        style: TextStyle(fontSize: fontSize, color: const Color(0xFF737A85)),
      );
    }

    final gap = paragraphGap ?? fontSize * lineHeight;
    final style = TextStyle(
      fontSize: fontSize,
      height: lineHeight,
      letterSpacing: 0.2,
      color: color,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (blocks[i] is ArticleImageBlock)
            const SizedBox.shrink()
          else ...[
            if (i > 0 &&
                blocks.take(i).any((b) => b is! ArticleImageBlock))
              SizedBox(height: gap * 0.55),
            if (blocks[i] is ArticleHeadingBlock)
              Builder(
                builder: (_) {
                  final h = blocks[i] as ArticleHeadingBlock;
                  final style = _headingStyle(h.level);
                  final spans =
                      ArticleMarkdown.inlineSpans(h.text, style: style);
                  return Text.rich(
                    TextSpan(
                      style: style,
                      children: spans.isEmpty
                          ? [
                              TextSpan(
                                text: ArticleMarkdown.stripMarkers(h.text),
                              ),
                            ]
                          : spans,
                    ),
                  );
                },
              )
            else if (blocks[i] is ArticleTextBlock)
              _TextParagraphs(
                text: (blocks[i] as ArticleTextBlock).text,
                style: style,
                gap: gap,
              ),
          ],
        ],
      ],
    );
  }
}

class _TextParagraphs extends StatelessWidget {
  const _TextParagraphs({
    required this.text,
    required this.style,
    required this.gap,
  });

  final String text;
  final TextStyle style;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final paragraphs = ArticleBodyText.splitParagraphs(text);
    if (paragraphs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == paragraphs.length - 1 ? 0 : gap,
            ),
            child: Text.rich(
              TextSpan(
                style: style,
                children: ArticleMarkdown.inlineSpans(
                  paragraphs[i],
                  style: style,
                ),
              ),
              textAlign: TextAlign.justify,
            ),
          ),
      ],
    );
  }
}
