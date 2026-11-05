import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/core/ui/pro_copy.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';

/// 首页「未读」三格预览（未读+漫游模式）。
class HomeUnreadSection extends StatelessWidget {
  const HomeUnreadSection({
    super.key,
    required this.isPro,
    required this.items,
    required this.onMore,
    required this.onOpen,
  });

  final bool isPro;
  final List<CollectionItem> items;
  final VoidCallback onMore;
  final ValueChanged<CollectionItem> onOpen;

  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);
  static const _muted = Color(0xFF737A85);
  static const _iconMuted = Color(0xFFC5CAD3);

  static const tileH = 88.0;
  static const tileGap = 8.0;
  static const slotCount = 3;
  static const bodyH = tileH * slotCount + tileGap * (slotCount - 1);

  String _subtitle(CollectionItem item) {
    final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
        ? item.canonicalUrl
        : item.url;
    final platform = platformLabel(item.platform, url: pageUrl);
    final status = switch (item.status) {
      'pending' => '解析中',
      'failed' => '解析失败',
      'success' => '已解析',
      _ => item.status,
    };
    return '$platform · $status';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              unreadSectionTitle(isPro: isPro),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _text,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                AppHaptics.select();
                onMore();
              },
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '查看更多 ›',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _blue,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: bodyH + 2,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6E8ED)),
          ),
          child: items.isEmpty
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 42,
                      color: _iconMuted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      unreadEmptyText(isPro: isPro),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: _muted),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length && i < slotCount; i++) ...[
                      if (i > 0) const SizedBox(height: tileGap),
                      ItemListTile.fromItem(
                        items[i],
                        subtitle: _subtitle(items[i]),
                        onTap: () {
                          AppHaptics.select();
                          onOpen(items[i]);
                        },
                      ),
                    ],
                    if (items.length < slotCount)
                      const Expanded(
                        child: Center(
                          child: Text(
                            '未读就这些了',
                            style: TextStyle(fontSize: 13, color: _muted),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
