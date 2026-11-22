import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/wiki_relate_models.dart';

/// 划选「关联」：按选中文字匹配 Wiki 实体与相关收藏。
/// 手机底部 sheet；iPad 居中（[showAppBottomSheet]）。
Future<void> showReadingWikiRelateSheet(
  BuildContext context, {
  required String selectedText,
  int? excludeItemId,
  ItemsRepository? repository,
}) {
  return showAppBottomSheet<void>(
    context: context,
    barrierColor: const Color(0x66000000),
    padding: EdgeInsets.zero,
    includeSafeArea: false,
    isScrollControlled: true,
    builder: (context) => _ReadingWikiRelateSheet(
      selectedText: selectedText,
      excludeItemId: excludeItemId,
      repository: repository ?? ItemsRepository(),
    ),
  );
}

class _ReadingWikiRelateSheet extends StatefulWidget {
  const _ReadingWikiRelateSheet({
    required this.selectedText,
    required this.repository,
    this.excludeItemId,
  });

  final String selectedText;
  final int? excludeItemId;
  final ItemsRepository repository;

  @override
  State<_ReadingWikiRelateSheet> createState() =>
      _ReadingWikiRelateSheetState();
}

class _ReadingWikiRelateSheetState extends State<_ReadingWikiRelateSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _handle = Color(0xFFD9DBE0);
  static const _rowBg = Color(0xFFF7F8FA);

  bool _loading = true;
  String? _error;
  WikiRelatePayload _data = const WikiRelatePayload();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.fetchWikiRelate(
        widget.selectedText,
        excludeItemId: widget.excludeItemId,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  Future<void> _openItem(WikiRelateItem hit) async {
    Navigator.of(context).pop();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ItemReadingPage(
          itemId: hit.itemId,
          openEntry: 'related',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablet = AppOrientation.isTablet(context);
    final radius = tablet
        ? BorderRadius.circular(20)
        : const BorderRadius.vertical(top: Radius.circular(20));
    final maxH = MediaQuery.sizeOf(context).height * (tablet ? 0.72 : 0.58);
    final quote = widget.selectedText.trim();
    final quotePreview =
        quote.length > 36 ? '${quote.substring(0, 36)}…' : quote;

    return Material(
      color: Colors.white,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _handle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '关联',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                if (quotePreview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '「$quotePreview」',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _muted,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: _muted)),
      );
    }
    if (_data.items.isEmpty) {
      return const Center(
        child: Text(
          '暂无相关收藏',
          style: TextStyle(color: _muted, fontSize: 14),
        ),
      );
    }

    return ListView(
      children: [
        for (final hit in _data.items) ...[
          Material(
            color: _rowBg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openItem(hit),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    CoverImage(
                      url: hit.coverImageUrl,
                      height: 48,
                      width: 48,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hit.title.isNotEmpty
                                ? hit.title
                                : '条目 ${hit.itemId}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _text,
                              height: 1.3,
                            ),
                          ),
                          if ((hit.viaTitle ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '经由 ${hit.viaTitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
