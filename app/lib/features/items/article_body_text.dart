import 'package:flutter/material.dart';

/// 正文段落排版：按换行拆段，段间空一行。
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

  /// 预览时可截断总字数；按完整段落截断，末尾加省略号。
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
      if (t.isNotEmpty) parts.add(t);
    }
    if (parts.isEmpty && content.trim().isNotEmpty) {
      return [content.trim()];
    }
    return parts;
  }

  List<String> _visibleParagraphs() {
    final all = splitParagraphs(content);
    final limit = maxChars;
    if (limit == null || limit <= 0) return all;

    final out = <String>[];
    var used = 0;
    for (final p in all) {
      if (used >= limit) break;
      if (used + p.length <= limit) {
        out.add(p);
        used += p.length;
      } else {
        final remain = limit - used;
        if (remain > 12) {
          out.add('${p.substring(0, remain)}…');
        } else if (out.isNotEmpty) {
          out[out.length - 1] = '${out.last}…';
        }
        break;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final paragraphs = _visibleParagraphs();
    if (paragraphs.isEmpty) {
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
        for (var i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == paragraphs.length - 1 ? 0 : gap,
            ),
            child: Text(
              paragraphs[i],
              style: style,
              textAlign: TextAlign.justify,
            ),
          ),
      ],
    );
  }
}
