import 'package:flutter/material.dart';
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
  static const _muted = Color(0xFF737A85);
  static const _quote = Color(0xFFFFC84A);

  @override
  Widget build(BuildContext context) {
    final quote = snippet.quote;
    final hasQuote = quote != null && quote.isNotEmpty;
    // 批注：原文与批注文案分摊行数，避免叠成一张特别高的卡
    final quoteLines =
        hasQuote ? (maxLines / 2).ceil().clamp(1, maxLines) : maxLines;
    final noteLines = hasQuote
        ? (maxLines - quoteLines + 1).clamp(1, maxLines >= 6 ? 4 : 2)
        : 0;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
      children: [
        const Text(
          '“',
          style: TextStyle(
            fontSize: 36,
            height: 0.85,
            fontWeight: FontWeight.w600,
            color: _quote,
          ),
        ),
        const SizedBox(height: 6),
        if (fillHeight)
          Expanded(
            child: Text(
              hasQuote ? quote : snippet.text,
              maxLines: quoteLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                height: 1.55,
                color: _text,
              ),
            ),
          )
        else
          Text(
            hasQuote ? quote : snippet.text,
            maxLines: quoteLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              height: 1.55,
              color: _text,
            ),
          ),
        if (hasQuote && snippet.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            snippet.text,
            maxLines: noteLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: _muted,
            ),
          ),
        ],
        if (showMeta) ...[
          const SizedBox(height: 12),
          Text(
            [
              snippet.kindLabel,
              if ((snippet.itemTitle ?? '').trim().isNotEmpty)
                snippet.itemTitle!.trim(),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ],
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
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: fillHeight ? SizedBox.expand(child: body) : body,
        ),
      ),
    );
  }
}
