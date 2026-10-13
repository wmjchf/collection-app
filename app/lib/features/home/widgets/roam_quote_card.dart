import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/roam_models.dart';

class RoamQuoteCard extends StatelessWidget {
  const RoamQuoteCard({
    super.key,
    required this.snippet,
    this.onTap,
    this.maxLines = 4,
    this.showMeta = true,
    this.elevation = 0,
    this.color = Colors.white,
    this.fillHeight = false,
  });

  final RoamSnippet snippet;
  final VoidCallback? onTap;
  final int maxLines;
  final bool showMeta;
  final double elevation;
  final Color color;

  /// 叠卡预览等：铺满父级高度，多余正文裁切
  final bool fillHeight;

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
    // 叠卡预览批注少行；弹层/列表给批注更多行，避免动不动省略号
    final noteLines = !hasQuote
        ? 0
        : fillHeight
            ? 1
            : (maxLines >= 10
                ? 8
                : (maxLines >= 6 ? 4 : 2));
    final quoteLines = !hasQuote
        ? maxLines
        : fillHeight
            ? (maxLines - noteLines).clamp(1, maxLines)
            : (maxLines - noteLines).clamp(2, maxLines);
    final primary = hasQuote ? quote! : snippet.text;
    final timeStr = formatRelativeTime(snippet.createdAt);
    final titleStr = (snippet.itemTitle ?? '').trim();

    // 批注：浅底+标签，色阶介于正文与底部元信息之间
    final noteBlock = hasQuote && snippet.text.isNotEmpty
        ? Padding(
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
                      maxLines: noteLines,
                      overflow: TextOverflow.ellipsis,
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
          )
        : null;

    final metaParts = [
      if (!hasQuote) snippet.kindLabel,
      timeStr,
      if (titleStr.isNotEmpty) titleStr,
    ];
    final metaBlock = showMeta && metaParts.any((e) => e.isNotEmpty)
        ? Padding(
            padding: EdgeInsets.only(top: hasQuote ? 12 : 10),
            child: Text(
              metaParts.where((e) => e.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _meta),
            ),
          )
        : null;

    Widget bodyText({required int lines}) {
      return Text(
        primary,
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: _bodySize,
          height: _bodyHeight,
          color: _text,
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Text(
          '“',
          style: TextStyle(
            fontSize: fillHeight ? 28 : 36,
            height: 0.85,
            fontWeight: FontWeight.w600,
            color: _quote,
          ),
        ),
        SizedBox(height: fillHeight ? 4 : 6),
        if (fillHeight)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final lineH = _bodySize * _bodyHeight;
                final fit = (constraints.maxHeight / lineH).floor();
                final lines = fit.clamp(1, quoteLines);
                return Align(
                  alignment: Alignment.topLeft,
                  child: bodyText(lines: lines),
                );
              },
            ),
          )
        else
          bodyText(lines: quoteLines),
        if (noteBlock != null) noteBlock,
        if (metaBlock != null) metaBlock,
      ],
    );

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
            fillHeight ? 14 : 16,
            18,
            fillHeight ? 14 : 16,
          ),
          child: fillHeight ? SizedBox.expand(child: body) : body,
        ),
      ),
    );
  }
}
