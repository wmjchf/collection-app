import 'package:flutter/material.dart';
import 'package:super_collection/features/items/article_content_blocks.dart';

/// 轻量 Markdown：标题 / 加粗 / 斜体 / 字号 / 图片（与后端 htmlToRichText 对齐）。
class ArticleMarkdown {
  ArticleMarkdown._();

  static final RegExp _headingLine = RegExp(r'^(#{1,4})\s+(.+)$');
  static final RegExp _size = RegExp(r'\{\{(\d+)\|([\s\S]*?)\}\}');
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _italic = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');

  /// 剥掉一层标记后的可见文字。
  static String stripMarkers(String body) {
    var t = body;
    // 反复剥，处理嵌套 {{18|**x**}}
    for (var i = 0; i < 8; i++) {
      final next = t
          .replaceAllMapped(_size, (m) => m.group(2)!)
          .replaceAllMapped(_bold, (m) => m.group(1)!)
          .replaceAllMapped(_italic, (m) => m.group(1)!);
      if (next == t) break;
      t = next;
    }
    return t;
  }

  /// 可见纯文字：去掉标题标记、加粗/斜体/字号标记、图片行（供标注偏移）。
  static String visiblePlain(String content) {
    final normalized =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final buf = StringBuffer();
    for (final line in normalized.split('\n')) {
      final t = line.trimRight();
      if (ArticleContentBlocks.imageLine.hasMatch(t.trim())) {
        continue;
      }
      if (ArticleContentBlocks.videoLine.hasMatch(t.trim())) {
        continue;
      }
      final hm = _headingLine.firstMatch(t.trim());
      final body = hm != null ? hm.group(2)! : t;
      final visible = stripMarkers(body);
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(visible);
    }
    return buf
        .toString()
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static int? headingLevel(String line) {
    final m = _headingLine.firstMatch(line.trim());
    return m?.group(1)?.length;
  }

  static String headingText(String line) {
    final m = _headingLine.firstMatch(line.trim());
    return stripMarkers((m?.group(2) ?? line).trim());
  }

  /// 将一段 Markdown 转为 InlineSpan（可见文字，不含标记符）。
  static List<InlineSpan> inlineSpans(
    String markdown, {
    required TextStyle style,
    List<({int start, int end})> highlights = const [],
    Color highlightColor = const Color(0xFFFFF2C7),
  }) {
    final visible = StringBuffer();
    final runs = <({int start, int end, TextStyle style})>[];

    void append(String text, TextStyle s) {
      if (text.isEmpty) return;
      final start = visible.length;
      visible.write(text);
      runs.add((start: start, end: visible.length, style: s));
    }

    void parseChunk(String chunk, TextStyle base) {
      if (chunk.isEmpty) return;
      var rest = chunk;
      while (rest.isNotEmpty) {
        final size = _size.firstMatch(rest);
        final bold = _bold.firstMatch(rest);
        final italic = _italic.firstMatch(rest);

        Match? next;
        var kind = '';
        void consider(Match? m, String k) {
          if (m == null) return;
          if (next == null || m.start < next!.start) {
            next = m;
            kind = k;
          }
        }

        consider(size, 's');
        consider(bold, 'b');
        consider(italic, 'i');

        if (next == null) {
          append(rest, base);
          break;
        }
        final m = next!;
        if (m.start > 0) {
          append(rest.substring(0, m.start), base);
        }
        if (kind == 's') {
          final px = double.tryParse(m.group(1)!) ?? base.fontSize ?? 15;
          final inner = m.group(2)!;
          final sized = base.copyWith(
            fontSize: px.clamp(12, 36),
            height: 1.45,
          );
          parseChunk(inner, sized);
        } else if (kind == 'b') {
          parseChunk(
            m.group(1)!,
            base.copyWith(fontWeight: FontWeight.w700),
          );
        } else {
          parseChunk(
            m.group(1)!,
            base.copyWith(fontStyle: FontStyle.italic),
          );
        }
        rest = rest.substring(m.end);
      }
    }

    parseChunk(markdown, style);

    final plain = visible.toString();
    if (plain.isEmpty) return const [];

    final cut = <int>{0, plain.length};
    for (final h in highlights) {
      cut.add(h.start.clamp(0, plain.length));
      cut.add(h.end.clamp(0, plain.length));
    }
    for (final r in runs) {
      cut.add(r.start);
      cut.add(r.end);
    }
    final points = cut.toList()..sort();

    TextStyle styleAt(int i) {
      var s = style;
      for (final r in runs) {
        if (i >= r.start && i < r.end) {
          s = r.style;
          break;
        }
      }
      for (final h in highlights) {
        if (i >= h.start && i < h.end) {
          s = s.copyWith(backgroundColor: highlightColor);
          break;
        }
      }
      return s;
    }

    final spans = <InlineSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a >= b) continue;
      spans.add(TextSpan(text: plain.substring(a, b), style: styleAt(a)));
    }
    return spans;
  }
}
