import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/cover_image.dart';

/// 首页条目叠卡（未读 / 最近阅读）：封面定高；标题单行省略；整卡等高，底下错开露边。
class UnreadStackPreview extends StatelessWidget {
  const UnreadStackPreview({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<HomeItemPreview> items;
  final VoidCallback onTap;

  static const coverHeight = 200.0;
  static const _peekStep = 14.0;
  static const _sideStep = 14.0;
  /// 标题槽：单行标题 + 副文案 + padding（槽高固定，叠层才齐）
  /// 15×1.3 + 4 + 12×1.2 + 上下各 10 ≈ 62
  static const metaHeight = 64.0;

  static const cardHeight = coverHeight + metaHeight;

  /// 空态占位：前卡 + 最多两层底下错开
  static const height = cardHeight + _peekStep * 2;

  static const _text = Color(0xFF1F242E);
  static const _meta = Color(0xFF9AA0A8);

  @override
  Widget build(BuildContext context) {
    final show = items.take(3).toList();
    if (show.isEmpty) return const SizedBox(height: height);

    final peekCount = (show.length - 1).clamp(0, 2);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: cardHeight + peekCount * _peekStep,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (show.length >= 3)
              Positioned(
                top: _peekStep * 2,
                left: _sideStep * 2,
                right: _sideStep * 2,
                height: cardHeight,
                child: _StackCard(item: show[2], dim: 0.55, showMeta: false),
              ),
            if (show.length >= 2)
              Positioned(
                top: _peekStep,
                left: _sideStep,
                right: _sideStep,
                height: cardHeight,
                child: _StackCard(item: show[1], dim: 0.28, showMeta: false),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: cardHeight,
              child: _StackCard(
                item: show.first,
                dim: 0,
                showMeta: true,
                elevation: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StackCard extends StatelessWidget {
  const _StackCard({
    required this.item,
    required this.dim,
    required this.showMeta,
    this.elevation = 0,
  });

  final HomeItemPreview item;
  final double dim;
  final bool showMeta;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final card = Material(
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
          CoverImage(
            key: ValueKey('unread-stack-cover-${item.id}'),
            url: item.coverImageUrl,
            pageUrl: item.pageUrl,
            borderRadius: 0,
            width: double.infinity,
            height: UnreadStackPreview.coverHeight,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: showMeta
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                            color: UnreadStackPreview._text,
                          ),
                        ),
                        if (item.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.2,
                              color: UnreadStackPreview._meta,
                            ),
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );

    if (dim <= 0) return card;
    return Opacity(opacity: 1 - dim, child: card);
  }
}
