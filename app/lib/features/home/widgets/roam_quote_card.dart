import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/roam_models.dart';

class RoamQuoteCard extends StatelessWidget {
  const RoamQuoteCard({
    super.key,
    required this.snippet,
    this.onTap,
    this.onMute,
    this.maxLines = 4,
    this.showMeta = true,
    this.elevation = 0,
    this.color = Colors.white,
    this.fillHeight = false,
    this.scrollBody = false,
  });

  final RoamSnippet snippet;
  final VoidCallback? onTap;
  /// 弹层：元信息右侧「不再回顾」
  final VoidCallback? onMute;
  final int maxLines;
  final bool showMeta;
  final double elevation;
  final Color color;

  /// 叠卡预览等：铺满父级高度，多余正文裁切
  final bool fillHeight;

  /// 弹层：铺满高度，正文/批注完整可滚、不省略
  final bool scrollBody;

  static const _text = Color(0xFF1F242E);
  static const _note = Color(0xFF5C6370);
  static const _meta = Color(0xFF9AA0A8);
  static const _quote = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE5EDFF);
  static const _noteBg = Color(0xFFF5F7FA);
  static const _bodySize = 16.0;
  static const _bodyHeight = 1.55;

  @override
  Widget build(BuildContext context) {
    final quote = snippet.quote;
    final hasQuote = quote != null && quote.isNotEmpty;
    final expand = fillHeight || scrollBody;
    // 叠卡预览批注少行；列表给更多行；弹层滚动则不限行
    final noteLines = scrollBody
        ? null
        : !hasQuote
            ? 0
            : fillHeight
                ? 1
                : (maxLines >= 10
                    ? 8
                    : (maxLines >= 6 ? 4 : 2));
    final quoteLines = scrollBody
        ? null
        : !hasQuote
            ? maxLines
            : fillHeight
                ? (maxLines - (noteLines ?? 1)).clamp(1, maxLines)
                : (maxLines - (noteLines ?? 2)).clamp(2, maxLines);
    final primary = hasQuote ? quote! : snippet.text;
    final timeStr = formatRelativeTime(snippet.createdAt);
    final titleStr = (snippet.itemTitle ?? '').trim();

    Widget? noteBlock({int? lines}) {
      if (!hasQuote || snippet.text.isEmpty) return null;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
          decoration: BoxDecoration(
            color: _noteBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _brandSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  snippet.kindLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: _quote,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  snippet.text,
                  maxLines: lines,
                  overflow: lines == null
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: _note,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final metaParts = [
      if (!hasQuote) snippet.kindLabel,
      timeStr,
      if (titleStr.isNotEmpty) titleStr,
    ];
    final metaText = metaParts.where((e) => e.isNotEmpty).join(' · ');
    final showMetaRow =
        showMeta && (metaText.isNotEmpty || onMute != null);
    final metaBlock = showMetaRow
        ? Padding(
            padding: EdgeInsets.only(top: hasQuote ? 12 : 10),
            child: Row(
              children: [
                Expanded(
                  child: metaText.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          metaText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: _meta),
                        ),
                ),
                if (onMute != null) ...[
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: onMute,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE8EBF0),
                      foregroundColor: _note,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.standard,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '不再回顾',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          )
        : null;

    Widget bodyText({int? lines}) {
      return Text(
        primary,
        maxLines: lines,
        overflow:
            lines == null ? TextOverflow.visible : TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: _bodySize,
          height: _bodyHeight,
          color: _text,
        ),
      );
    }

    final quoteMark = Text(
      '“',
      style: TextStyle(
        fontSize: expand ? 28 : 36,
        height: 0.85,
        fontWeight: FontWeight.w600,
        color: _quote,
      ),
    );

    late final Widget body;
    if (scrollBody) {
      final note = noteBlock(lines: null);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          quoteMark,
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bodyText(lines: null),
                  if (note != null) note,
                ],
              ),
            ),
          ),
          if (metaBlock != null) metaBlock,
        ],
      );
    } else if (fillHeight) {
      final note = noteBlock(lines: noteLines);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          quoteMark,
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final lineH = _bodySize * _bodyHeight;
                final fit = (constraints.maxHeight / lineH).floor();
                // 叠卡高度由首页剩余空间决定，行数跟高度走，不再卡在两三行。
                final lines = fit < 1 ? 1 : fit;
                return Align(
                  alignment: Alignment.topLeft,
                  child: bodyText(lines: lines),
                );
              },
            ),
          ),
          if (note != null) note,
          if (metaBlock != null) metaBlock,
        ],
      );
    } else {
      final note = noteBlock(lines: noteLines);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          quoteMark,
          const SizedBox(height: 6),
          bodyText(lines: quoteLines),
          if (note != null) note,
          if (metaBlock != null) metaBlock,
        ],
      );
    }

    return Material(
      color: color,
      elevation: elevation,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6E8ED)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            expand ? 14 : 16,
            18,
            expand ? 14 : 16,
          ),
          child: expand ? SizedBox.expand(child: body) : body,
        ),
      ),
    );
  }
}
