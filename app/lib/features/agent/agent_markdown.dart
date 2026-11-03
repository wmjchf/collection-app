import 'package:flutter/material.dart';
import 'package:super_collection/features/items/article_markdown.dart';

/// 助手回复轻量 Markdown：标题 / 加粗斜体 / 列表 / 引用 / 代码块。
/// [contextMenuBuilder] 非空时正文可划选（复制 / 分享工具条）。
class AgentMarkdown extends StatelessWidget {
  const AgentMarkdown(
    this.source, {
    super.key,
    this.style = const TextStyle(
      fontSize: 16,
      color: Color(0xFF1F242E),
      height: 1.55,
    ),
    this.contextMenuBuilder,
  });

  final String source;
  final TextStyle style;
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  static final _heading = RegExp(r'^(#{1,3})\s+(.+)$');
  static final _ul = RegExp(r'^[-*•]\s+(.+)$');
  static final _ol = RegExp(r'^(\d+)[.)、]\s+(.+)$');
  static final _quote = RegExp(r'^>\s?(.*)$');
  static final _fence = RegExp(r'^```');

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(source);
    if (blocks.isEmpty) {
      return _textWidget('', style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: blocks[i].gapBefore),
          blocks[i].build(style, contextMenuBuilder),
        ],
      ],
    );
  }

  Widget _textWidget(String text, TextStyle s) {
    final menu = contextMenuBuilder;
    if (menu == null) {
      return Text(text, style: s);
    }
    return SelectableText(
      text,
      style: s,
      contextMenuBuilder: menu,
    );
  }

  static List<_Block> _parseBlocks(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
    if (text.isEmpty) return const [];

    final lines = text.split('\n');
    final out = <_Block>[];
    final para = <String>[];
    var inCode = false;
    final code = <String>[];

    void flushPara({double gap = 10}) {
      final joined = para.join('\n').trim();
      para.clear();
      if (joined.isEmpty) return;
      out.add(_ParagraphBlock(joined, gapBefore: gap));
    }

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (inCode) {
        if (_fence.hasMatch(trimmed.trim())) {
          out.add(_CodeBlock(code.join('\n')));
          code.clear();
          inCode = false;
        } else {
          code.add(line);
        }
        continue;
      }
      if (_fence.hasMatch(trimmed.trim())) {
        flushPara();
        inCode = true;
        continue;
      }
      if (trimmed.trim().isEmpty) {
        flushPara();
        continue;
      }

      final hm = _heading.firstMatch(trimmed.trim());
      if (hm != null) {
        flushPara();
        out.add(
          _HeadingBlock(level: hm.group(1)!.length, text: hm.group(2)!),
        );
        continue;
      }
      final qm = _quote.firstMatch(trimmed.trim());
      if (qm != null) {
        flushPara(gap: 8);
        out.add(_QuoteBlock(qm.group(1) ?? ''));
        continue;
      }
      final um = _ul.firstMatch(trimmed.trim());
      if (um != null) {
        flushPara(gap: 8);
        out.add(_ListItemBlock(um.group(1)!, bullet: '•'));
        continue;
      }
      final om = _ol.firstMatch(trimmed.trim());
      if (om != null) {
        flushPara(gap: 8);
        out.add(_ListItemBlock(om.group(2)!, bullet: '${om.group(1)}.'));
        continue;
      }
      para.add(trimmed);
    }
    if (inCode && code.isNotEmpty) {
      out.add(_CodeBlock(code.join('\n')));
    }
    flushPara();
    return out;
  }
}

abstract class _Block {
  double get gapBefore => 10;
  Widget build(
    TextStyle base,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  );
}

Widget _richText(
  TextSpan span, {
  required TextStyle base,
  EditableTextContextMenuBuilder? contextMenuBuilder,
}) {
  if (contextMenuBuilder == null) {
    return Text.rich(span, style: base);
  }
  return SelectableText.rich(
    span,
    style: base,
    contextMenuBuilder: contextMenuBuilder,
  );
}

class _ParagraphBlock extends _Block {
  _ParagraphBlock(this.text, {this.gapBefore = 10});
  final String text;
  @override
  final double gapBefore;

  @override
  Widget build(
    TextStyle base,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  ) {
    return _richText(
      TextSpan(children: ArticleMarkdown.inlineSpans(text, style: base)),
      base: base,
      contextMenuBuilder: contextMenuBuilder,
    );
  }
}

class _HeadingBlock extends _Block {
  _HeadingBlock({required this.level, required this.text});
  final int level;
  final String text;

  @override
  double get gapBefore => 14;

  @override
  Widget build(
    TextStyle base,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  ) {
    final size = switch (level) {
      1 => 20.0,
      2 => 17.0,
      _ => 16.0,
    };
    final s = base.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.35,
    );
    return _richText(
      TextSpan(children: ArticleMarkdown.inlineSpans(text, style: s)),
      base: s,
      contextMenuBuilder: contextMenuBuilder,
    );
  }
}

class _ListItemBlock extends _Block {
  _ListItemBlock(this.text, {required this.bullet});
  final String text;
  final String bullet;

  @override
  double get gapBefore => 4;

  @override
  Widget build(
    TextStyle base,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(bullet, style: base),
        ),
        Expanded(
          child: _richText(
            TextSpan(children: ArticleMarkdown.inlineSpans(text, style: base)),
            base: base,
            contextMenuBuilder: contextMenuBuilder,
          ),
        ),
      ],
    );
  }
}

class _QuoteBlock extends _Block {
  _QuoteBlock(this.text);
  final String text;

  @override
  Widget build(
    TextStyle base,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  ) {
    final s = base.copyWith(color: const Color(0xFF5C6675));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFD0D5DD), width: 3),
        ),
        color: Color(0xFFF5F7FA),
      ),
      child: _richText(
        TextSpan(
          children: ArticleMarkdown.inlineSpans(text, style: s),
        ),
        base: s,
        contextMenuBuilder: contextMenuBuilder,
      ),
    );
  }
}

class _CodeBlock extends _Block {
  _CodeBlock(this.text);
  final String text;

  @override
  Widget build(
    TextStyle base,
    EditableTextContextMenuBuilder? contextMenuBuilder,
  ) {
    final s = base.copyWith(
      fontFamily: 'Menlo',
      fontSize: (base.fontSize ?? 15) - 1,
      height: 1.45,
      color: const Color(0xFF1F242E),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE6E8EB)),
      ),
      child: contextMenuBuilder == null
          ? Text(text, style: s)
          : SelectableText(
              text,
              style: s,
              contextMenuBuilder: contextMenuBuilder,
            ),
    );
  }
}
