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

  /// 空态占位与有数据叠卡共用此高度，避免切换抖动
  static const height = 196.0;
  static const _peekStep = 10.0;
  static const _sideStep = 12.0;

  @override
  Widget build(BuildContext context) {
    final show = items.take(3).toList();
    if (show.isEmpty) return const SizedBox(height: height);

    final peekCount = (show.length - 1).clamp(0, 2);
    final frontTop = peekCount * _peekStep;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (show.length >= 3)
              Positioned(
                top: 0,
                left: _sideStep * 2,
                right: _sideStep * 2,
                height: height - frontTop,
                child: _PeekCard(snippet: show[2], dim: 0.55),
              ),
            if (show.length >= 2)
              Positioned(
                top: peekCount >= 2 ? _peekStep : 0,
                left: _sideStep,
                right: _sideStep,
                height: height - frontTop,
                child: _PeekCard(snippet: show[1], dim: 0.28),
              ),
            Positioned(
              top: frontTop,
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: RoamQuoteCard(
                  snippet: show.first,
                  maxLines: 3,
                  elevation: 8,
                  fillHeight: true,
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
          elevation: 0,
          fillHeight: true,
        ),
      ),
    );
  }
}
