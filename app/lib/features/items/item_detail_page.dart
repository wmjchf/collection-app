import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/article_body_text.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 内容详情：头部元信息 + 随解析状态变化的内容区；成功时底部固定「进入阅读」。
class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({
    super.key,
    required this.itemId,
    this.initialItem,
  });

  final int itemId;
  final CollectionItem? initialItem;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  static const _bg = Color(0xFFF5F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  final _repo = ItemsRepository();
  CollectionItem? _item;
  String? _error;
  Timer? _pollTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    _bootstrap();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final item = await _repo.getItem(widget.itemId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
        _error = null;
      });
      _syncPolling(item);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  void _syncPolling(CollectionItem item) {
    _pollTimer?.cancel();
    if (!item.isPending) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      _pollOnce();
    });
  }

  Future<void> _pollOnce() async {
    try {
      final item = await _repo.getItem(widget.itemId);
      if (!mounted) return;
      setState(() => _item = item);
      if (!item.isPending) {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // 轮询失败不打断页面
    }
  }

  Future<void> _reparse() async {
    try {
      ParseProgressTracker.begin();
      final item = await _repo.reparse(widget.itemId);
      if (!mounted) return;
      setState(() => _item = item);
      _syncPolling(item);
      // ignore: unawaited_futures
      ParseProgressTracker.watchItem(
        item.id,
        initialStatus: item.status,
        platform: item.platform,
        url: item.canonicalUrl ?? item.url,
        onSettled: () async {
          if (!mounted) return;
          try {
            final refreshed = await _repo.getItem(widget.itemId);
            if (!mounted) return;
            setState(() => _item = refreshed);
            _syncPolling(refreshed);
          } catch (_) {}
        },
      );
    } on ApiException catch (e) {
      ParseProgressTracker.cancel();
      if (!mounted) return;
      AppToast.show(context, e.message);
    }
  }

  Future<void> _enterReading() async {
    final current = _item;
    if (current == null || !current.isSuccess) return;

    CollectionItem item = current;
    try {
      item = await _repo.markAsRead(widget.itemId);
      if (mounted) setState(() => _item = item);
    } catch (_) {
      // 标已读失败仍允许进入阅读
    }

    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ItemReadingPage(item: item),
      ),
    );
    if (!mounted) return;
    // 从阅读页返回后刷新（星标等可能已变）
    try {
      final refreshed = await _repo.getItem(widget.itemId);
      if (!mounted) return;
      setState(() => _item = refreshed);
    } catch (_) {}
  }

  String _formatCreatedAt(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _previewText(CollectionItem item) {
    final content = (item.content ?? '').trim();
    if (content.isNotEmpty) {
      // 用正文开头几段作导语（如 36氪「谁比谁高贵？」这类摘要不适合详情展示）
      final lede = ArticleBodyText.ledePreview(content, maxParagraphs: 3);
      if (lede.isNotEmpty) return lede;
    }
    return (item.summary ?? '').trim();
  }

  /// 详情预览：图集出轮播；普通文章只留一张封面
  List<String> _previewImages(CollectionItem item) {
    if (item.isImageGallery) {
      return item.imageUrls
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    final cover = item.coverImageUrl?.trim();
    if (cover != null && cover.isNotEmpty) return [cover];
    // 无独立封面时，退回展示图第一张
    for (final u in item.displayImages) {
      final t = u.trim();
      if (t.isNotEmpty) return [t];
    }
    return const [];
  }

  String get _linkToCopy {
    final item = _item;
    if (item == null) return '';
    final canonical = item.canonicalUrl?.trim();
    if (canonical != null && canonical.isNotEmpty) return canonical;
    return item.url.trim();
  }

  Future<void> _copyLink() async {
    final link = _linkToCopy;
    if (link.isEmpty) {
      AppToast.show(context, '暂无链接');
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    AppToast.show(context, '链接已复制');
  }

  Future<void> _confirmDelete() async {
    final item = _item;
    if (item == null) return;
    final ok = await showAppConfirmDialog(
      context,
      title: '彻底删除？',
      message: '删除后不可恢复。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.purgeFromTrash(item.id);
      if (!mounted) return;
      AppToast.show(context, '已彻底删除');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final showEnterReading = item?.isSuccess == true;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _TopBar(
            onBack: () => Navigator.of(context).maybePop(),
            enabled: item != null,
            onCopyLink: _copyLink,
            onDelete: _confirmDelete,
          ),
          Expanded(
            child: _loading && item == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null && item == null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: _muted),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          16,
                          20,
                          showEnterReading ? 16 : 32,
                        ),
                        children: [
                          Text(
                            item?.title?.isNotEmpty == true
                                ? item!.title!
                                : (item?.url ?? ''),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _text,
                              height: 32 / 22,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            [
                              platformLabel(item?.platform),
                              _formatCreatedAt(item?.createdAt),
                            ].where((e) => e.isNotEmpty).join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: _muted,
                              height: 17 / 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _StatusChip(status: item?.status ?? 'pending'),
                          const SizedBox(height: 10),
                          Text(
                            item?.url ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _blue,
                              height: 17 / 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (item?.isPending == true)
                            const _PendingCard()
                          else if (item?.isFailed == true)
                            _FailedCard(
                              message: item?.errorMessage,
                              onRetry: _reparse,
                            )
                          else if (item != null)
                            _SuccessCard(
                              imageUrls: _previewImages(item),
                              content: _previewText(item),
                            ),
                        ],
                      ),
          ),
          if (showEnterReading)
            _EnterReadingBar(onPressed: _enterReading),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onCopyLink,
    required this.onDelete,
    this.enabled = true,
  });

  final VoidCallback onBack;
  final VoidCallback onCopyLink;
  final VoidCallback onDelete;
  final bool enabled;

  static const _text = Color(0xFF1F242E);
  static const _danger = Color(0xFFE34D59);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    foregroundColor: _text,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.chevron_left, size: 26),
                  label: const Text(
                    '返回',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  enabled: enabled,
                  tooltip: '更多',
                  offset: const Offset(0, 40),
                  elevation: 8,
                  color: Colors.white,
                  shadowColor: Colors.black.withValues(alpha: 0.14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE6E8EB)),
                  ),
                  constraints: const BoxConstraints(minWidth: 148, maxWidth: 168),
                  onSelected: (value) {
                    if (value == 'copy') onCopyLink();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'copy',
                      height: 44,
                      child: Text(
                        '复制链接',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _text,
                        ),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      height: 44,
                      child: Text(
                        '删除',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _danger,
                        ),
                      ),
                    ),
                  ],
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Text(
                        '⋯',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _text,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (status) {
      case 'success':
        bg = const Color(0xFFE5F7EB);
        fg = const Color(0xFF26804D);
        label = '解析完成';
      case 'failed':
        bg = const Color(0xFFFDECEC);
        fg = const Color(0xFFE34D59);
        label = '解析失败';
      default:
        bg = const Color(0xFFFFF3E6);
        fg = const Color(0xFFD97706);
        label = '正在解析…';
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: fg,
            height: 17 / 12,
          ),
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skel(height: 14, width: double.infinity),
          const SizedBox(height: 12),
          _skel(height: 14, width: 220),
          const SizedBox(height: 12),
          _skel(height: 14, width: 160),
          const SizedBox(height: 20),
          _skel(height: 14, width: double.infinity),
          const SizedBox(height: 12),
          _skel(height: 14, width: 200),
        ],
      ),
    );
  }

  Widget _skel({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0F5),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  const _FailedCard({this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  static const _blue = Color(0xFF2F6FED);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '无法解析该链接的正文',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (message != null && message!.isNotEmpty)
                ? message!
                : '请稍后重试。第一期不支持打开原文。',
            style: const TextStyle(
              fontSize: 14,
              color: _muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '重试解析',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({this.imageUrls = const [], required this.content});

  final List<String> imageUrls;
  final String content;

  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    final body = content.trim().isEmpty ? '正文已解析，可进入阅读。' : content;
    final images = imageUrls;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty) ...[
            ItemImageGallery(
              urls: images.take(12).toList(),
              height: images.length == 1 ? 200 : 220,
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            '正文',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _muted,
              height: 19 / 13,
            ),
          ),
          const SizedBox(height: 10),
          ArticleBodyText(
            content: body,
            fontSize: 14,
            lineHeight: 1.8,
          ),
        ],
      ),
    );
  }
}

class _EnterReadingBar extends StatelessWidget {
  const _EnterReadingBar({required this.onPressed});

  final VoidCallback onPressed;

  static const _blue = Color(0xFF2F6FED);
  static const _border = Color(0xFFE5E5EB);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '进入阅读',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
