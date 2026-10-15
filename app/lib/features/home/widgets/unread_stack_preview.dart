import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/cover_image.dart';

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
  static const height = 196.0;
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
            // 最底层：再往下错开一截
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
            // 前卡贴顶，底下露出后卡白底/圆角边
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: frontH,
              child: IgnorePointer(
                child: UnreadStackCard(
                  item: show.first,
                  elevation: 8,
                  showMeta: true,
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
        child: UnreadStackCard(
          item: item,
          elevation: 0,
          showMeta: false,
        ),
      ),
    );
  }
}

/// 未读叠卡单张：封面铺上半 + 标题/副文案
class UnreadStackCard extends StatelessWidget {
  const UnreadStackCard({
    super.key,
    required this.item,
    this.elevation = 0,
    this.showMeta = true,
  });

  final HomeItemPreview item;
  final double elevation;
  final bool showMeta;

  static const _text = Color(0xFF1F242E);
  static const _meta = Color(0xFF9AA0A8);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: elevation,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6E8ED)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CoverImage(
                  key: ValueKey('unread-stack-cover-${item.id}'),
                  url: item.coverImageUrl,
                  pageUrl: item.pageUrl,
                  borderRadius: 0,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                );
              },
            ),
          ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: showMeta ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: _text,
                      ),
                    ),
                  ),
                  if (showMeta && item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _meta),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
