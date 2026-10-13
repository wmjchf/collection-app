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
  });

  final RoamSnippet snippet;
  final VoidCallback? onTap;
  final int maxLines;
  final bool showMeta;
  final double elevation;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _quote = Color(0xFFFFC84A);

  @override
  Widget build(BuildContext context) {
    final quote = snippet.quote;
    final hasQuote = quote != null && quote.isNotEmpty;

    return Material(
      color: Colors.white,
      elevation: elevation,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                hasQuote ? quote : snippet.text,
                maxLines: maxLines,
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
                  maxLines: 2,
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
          ),
        ),
      ),
    );
  }
}
