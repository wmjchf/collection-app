import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/item_cover_card.dart';

/// 首页未读叠卡：最多三张错落，点整叠进入首条阅读页。
class UnreadStackPreview extends StatelessWidget {
  const UnreadStackPreview({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<HomeItemPreview> items;
  final VoidCallback onTap;

  /// 空态占位与有数据叠卡共用此高度，避免切换抖动
  static const height = ItemCoverCard.defaultHeight;
  /// 后卡从底部探出，比顶边错开更明显（封面图不易看出上层叠）
  static const _peekStep = 14.0;
  static const _sideStep = 14.0;

  @override
  Widget build(BuildContext context) {
    final show = items.take(3).toList();
    if (show.isEmpty) return const SizedBox(height: height);

    final peekCount = (show.length - 1).clamp(0, 2);
    final frontH = height - peekCount * _peekStep;

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
                top: _peekStep * 2,
                left: _sideStep * 2,
                right: _sideStep * 2,
                height: frontH,
                child: _PeekCard(item: show[2], dim: 0.55),
              ),
            if (show.length >= 2)
              Positioned(
                top: _peekStep,
                left: _sideStep,
                right: _sideStep,
                height: frontH,
                child: _PeekCard(item: show[1], dim: 0.28),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: frontH,
              child: IgnorePointer(
                child: ItemCoverCard(
                  title: show.first.title,
                  subtitle: show.first.subtitle,
                  coverUrl: show.first.coverImageUrl,
                  pageUrl: show.first.pageUrl,
                  coverKey: ValueKey('unread-stack-cover-${show.first.id}'),
                  tags: show.first.tags,
                  elevation: 8,
                  showMeta: true,
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
  const _PeekCard({required this.item, required this.dim});

  final HomeItemPreview item;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 1 - dim,
      child: IgnorePointer(
        child: ItemCoverCard(
          title: item.title,
          subtitle: item.subtitle,
          coverUrl: item.coverImageUrl,
          pageUrl: item.pageUrl,
          coverKey: ValueKey('unread-stack-cover-${item.id}'),
          tags: item.tags,
          elevation: 0,
          showMeta: false,
          fillHeight: true,
        ),
      ),
    );
  }
}
