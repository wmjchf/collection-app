import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_models.dart';

/// 首页未读叠卡：封面定高、底下错开；标题 1～2 行自适应。
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
  /// 标题区按两行 + 副文案预留（空态高度）
  static const _metaReserve = 78.0;

  /// 空态占位：封面 + 两层错开 + 标题区
  static const height = coverHeight + _peekStep * 2 + _metaReserve;

  static const _text = Color(0xFF1F242E);
  static const _meta = Color(0xFF9AA0A8);
  static const _tag = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    final show = items.take(3).toList();
    if (show.isEmpty) return const SizedBox(height: height);

    final peekCount = (show.length - 1).clamp(0, 2);
    final stackCoverH = coverHeight + peekCount * _peekStep;
    final front = show.first;
    final tagsLine = _tagsLine(front.tags);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.white,
        elevation: 8,
        shadowColor: const Color(0x33000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE6E8ED)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: stackCoverH,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (show.length >= 3)
                    Positioned(
                      top: _peekStep * 2,
                      left: _sideStep * 2,
                      right: _sideStep * 2,
                      height: coverHeight,
                      child: _PeekCover(item: show[2], dim: 0.55),
                    ),
                  if (show.length >= 2)
                    Positioned(
                      top: _peekStep,
                      left: _sideStep,
                      right: _sideStep,
                      height: coverHeight,
                      child: _PeekCover(item: show[1], dim: 0.28),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: coverHeight,
                    child: CoverImage(
                      key: ValueKey('unread-stack-cover-${front.id}'),
                      url: front.coverImageUrl,
                      pageUrl: front.pageUrl,
                      borderRadius: 0,
                      width: double.infinity,
                      height: coverHeight,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    front.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: _text,
                    ),
                  ),
                  if (tagsLine != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      tagsLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _tag,
                      ),
                    ),
                  ],
                  if (front.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      front.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _meta),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _tagsLine(List<ItemTagBrief> tags) {
    final labels = <String>[];
    for (final tag in tags) {
      final n = tag.name.trim();
      if (n.isEmpty) continue;
      labels.add(n.startsWith('#') ? n : '#$n');
    }
    if (labels.isEmpty) return null;
    if (labels.length <= 3) return labels.join('  ');
    return '${labels.take(3).join('  ')}  +${labels.length - 3}';
  }
}

class _PeekCover extends StatelessWidget {
  const _PeekCover({required this.item, required this.dim});

  final HomeItemPreview item;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 1 - dim,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CoverImage(
          key: ValueKey('unread-stack-cover-${item.id}'),
          url: item.coverImageUrl,
          pageUrl: item.pageUrl,
          borderRadius: 0,
          width: double.infinity,
          height: UnreadStackPreview.coverHeight,
        ),
      ),
    );
  }
}
