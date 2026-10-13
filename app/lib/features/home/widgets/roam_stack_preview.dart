import 'package:flutter/material.dart';
import 'package:super_collection/features/home/roam_models.dart';
import 'package:super_collection/features/home/widgets/roam_quote_card.dart';

/// 首页叠卡：最多三张错落，点整叠进入播放。
class RoamStackPreview extends StatelessWidget {
  const RoamStackPreview({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<RoamSnippet> items;
  final VoidCallback onTap;

  static const _height = 232.0;

  @override
  Widget build(BuildContext context) {
    final show = items.take(3).toList();
    if (show.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: _height,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            if (show.length >= 3)
              Positioned(
                top: 22,
                left: 20,
                right: 20,
                child: _PeekCard(snippet: show[2], dim: 0.55),
              ),
            if (show.length >= 2)
              Positioned(
                top: 11,
                left: 10,
                right: 10,
                child: _PeekCard(snippet: show[1], dim: 0.28),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: RoamQuoteCard(
                  snippet: show.first,
                  maxLines: 3,
                  elevation: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeekCard extends StatelessWidget {
  const _PeekCard({required this.snippet, required this.dim});

  final RoamSnippet snippet;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 1 - dim,
      child: IgnorePointer(
        child: RoamQuoteCard(
          snippet: snippet,
          maxLines: 2,
          showMeta: false,
          elevation: 3,
        ),
      ),
    );
  }
}
