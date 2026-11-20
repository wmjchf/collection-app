import 'package:flutter/material.dart';
import 'package:super_collection/features/items/article_markdown.dart';

/// 助手划选工具条：anchors + 选中纯文本 + 清除选区。
typedef AgentSelectionMenuBuilder = Widget Function(
  BuildContext context,
  TextSelectionToolbarAnchors anchors,
  String selected,
  VoidCallback clearSelection,
);

/// 助手回复轻量 Markdown：标题 / 加粗斜体 / 行内代码 / 列表 / 引用 / 分隔线 / 代码块 / GFM 表格。
///
/// [selectionMenuBuilder] 非空时用 [SelectionArea] 包整篇，块内为普通 Text，
/// 划选可跨段落 / 标题 / 列表（引用条、代码块、表格单元格等同区域）。
class AgentMarkdown extends StatelessWidget {
  const AgentMarkdown(
    this.source, {
    super.key,
    this.style = const TextStyle(
      fontSize: 16,
      color: Color(0xFF1F242E),
      height: 1.55,
    ),
    this.selectionMenuBuilder,
  });

  final String source;
  final TextStyle style;
  final AgentSelectionMenuBuilder? selectionMenuBuilder;

  static final _heading = RegExp(r'^(#{1,3})\s+(.+)$');
  static final _ul = RegExp(r'^[-*•]\s+(.+)$');
  static final _ol = RegExp(r'^(\d+)[.)、]\s+(.+)$');
  static final _quote = RegExp(r'^>\s?(.*)$');
  static final _fence = RegExp(r'^```');
  /// `---` / `***` / `___` 水平分隔线（整行）
  static final _hr = RegExp(r'^(-{3,}|\*{3,}|_{3,})\s*$');
  /// 至少两列的管道表行：`| a | b |`
  static final _tableRow = RegExp(r'^\|(.+)\|$');
  /// `|---|:---:|---|` 一类分隔行
  static final _tableSep = RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$');

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(source);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blocks.isEmpty)
          Text('', style: style)
        else
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) ...[
              SizedBox(height: blocks[i].gapBefore),
              // 可选中换行，让跨段划选的 plainText 带结构（视觉高度靠上方 SizedBox）
              Text(
                blocks[i - 1] is _ListItemBlock && blocks[i] is _ListItemBlock
                    ? '\n'
                    : '\n\n',
                style: const TextStyle(
                  fontSize: 0.1,
                  height: 0.1,
                  color: Color(0x00000000),
                ),
              ),
            ],
            blocks[i].build(style),
          ],
      ],
    );
    final menu = selectionMenuBuilder;
    if (menu == null) return column;
    return _AgentSelectableMarkdown(
      selectionMenuBuilder: menu,
      child: column,
    );
  }

  static bool _isTableRow(String line) {
    final t = line.trim();
    if (!_tableRow.hasMatch(t)) return false;
    if (_tableSep.hasMatch(t)) return true;
    return t.contains('|');
  }

  static List<String> _splitCells(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return [for (final c in t.split('|')) c.trim()];
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

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
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

      // GFM 表格：连续管道行（含可选分隔行）
      if (_isTableRow(trimmed)) {
        final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
        final looksLikeTable =
            _tableSep.hasMatch(next) ||
            (_isTableRow(next) && !_tableSep.hasMatch(trimmed.trim()));
        if (looksLikeTable || _tableSep.hasMatch(trimmed.trim())) {
          flushPara();
          final rows = <List<String>>[];
          while (i < lines.length && _isTableRow(lines[i])) {
            final rowLine = lines[i].trim();
            if (!_tableSep.hasMatch(rowLine)) {
              rows.add(_splitCells(rowLine));
            }
            i++;
          }
          i--; // for 循环还会 +1
          if (rows.isNotEmpty) {
            out.add(_TableBlock(rows));
          }
          continue;
        }
      }

      if (_hr.hasMatch(trimmed.trim())) {
        flushPara();
        out.add(_HrBlock());
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
        final quoteText = (qm.group(1) ?? '').trim();
        // 空 `>` 行常见于引用内换段，不渲成空白灰条
        if (quoteText.isEmpty) {
          flushPara(gap: 8);
          continue;
        }
        flushPara(gap: 8);
        out.add(_QuoteBlock(quoteText));
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
        out.add(
          _ListItemBlock(om.group(2)!, bullet: '${om.group(1)}.'),
        );
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

/// [SelectionArea] 无公开 getSelectedContent，用 onSelectionChanged 缓存选中文。
class _AgentSelectableMarkdown extends StatefulWidget {
  const _AgentSelectableMarkdown({
    required this.selectionMenuBuilder,
    required this.child,
  });

  final AgentSelectionMenuBuilder selectionMenuBuilder;
  final Widget child;

  @override
  State<_AgentSelectableMarkdown> createState() =>
      _AgentSelectableMarkdownState();
}

class _AgentSelectableMarkdownState extends State<_AgentSelectableMarkdown> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) {
        _selected = content?.plainText ?? '';
      },
      contextMenuBuilder: (context, state) {
        final selected = _selected;
        if (selected.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        return widget.selectionMenuBuilder(
          context,
          state.contextMenuAnchors,
          selected,
          () {
            ContextMenuController.removeAny();
            state.hideToolbar();
            state.clearSelection();
          },
        );
      },
      child: widget.child,
    );
  }
}

abstract class _Block {
  double get gapBefore => 10;
  Widget build(TextStyle base);
}

Widget _richText(TextSpan span, {required TextStyle base}) {
  return Text.rich(span, style: base);
}

class _HrBlock extends _Block {
  _HrBlock();

  @override
  double get gapBefore => 14;
  @override
  Widget build(TextStyle base) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Color(0xFFE6E8EB),
      ),
    );
  }
}

class _ParagraphBlock extends _Block {
  _ParagraphBlock(this.text, {this.gapBefore = 10});
  final String text;
  @override
  final double gapBefore;
  @override
  Widget build(TextStyle base) {
    return _richText(
      TextSpan(children: ArticleMarkdown.inlineSpans(text, style: base)),
      base: base,
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
  Widget build(TextStyle base) {
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
  Widget build(TextStyle base) {
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
  Widget build(TextStyle base) {
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
      ),
    );
  }
}

class _CodeBlock extends _Block {
  _CodeBlock(this.text);
  final String text;
  @override
  Widget build(TextStyle base) {
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
      child: Text(text, style: s),
    );
  }
}

class _TableBlock extends _Block {
  _TableBlock(this.rows);
  final List<List<String>> rows;

  static const _border = Color(0xFFE6E8EB);
  static const _headerBg = Color(0xFFF5F7FA);

  @override
  double get gapBefore => 12;

  @override
  Widget build(TextStyle base) {
    final colCount = rows.fold<int>(
      0,
      (m, r) => r.length > m ? r.length : m,
    );
    if (colCount == 0) return const SizedBox.shrink();

    final cellStyle = base.copyWith(
      fontSize: (base.fontSize ?? 16) - 1,
      height: 1.4,
    );
    final headerStyle = cellStyle.copyWith(fontWeight: FontWeight.w600);

    Widget cell(String text, {required bool header, required bool lastCol}) {
      return Container(
        constraints: const BoxConstraints(minWidth: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: header ? _headerBg : null,
          border: Border(
            right: lastCol
                ? BorderSide.none
                : const BorderSide(color: _border, width: 1),
            bottom: const BorderSide(color: _border, width: 1),
          ),
        ),
        child: _richText(
          TextSpan(
            children: ArticleMarkdown.inlineSpans(
              text,
              style: header ? headerStyle : cellStyle,
            ),
          ),
          base: header ? headerStyle : cellStyle,
        ),
      );
    }

    final table = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (var r = 0; r < rows.length; r++)
          TableRow(
            children: [
              for (var c = 0; c < colCount; c++)
                cell(
                  c < rows[r].length ? rows[r][c] : '',
                  header: r == 0,
                  lastCol: c == colCount - 1,
                ),
            ],
          ),
      ],
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: table,
      ),
    );
  }
}
