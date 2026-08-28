import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/collection/tags_search_page.dart';

/// 我的标签 Tab：chip 列表（每行 4 个，超宽行可横滑）
class TagsPage extends StatefulWidget {
  const TagsPage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
  });

  final bool isActive;
  final int refreshTick;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);

  final _tagsRepo = TagsRepository();

  List<Tag> _all = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TagsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(quiet: true);
    }
    if (widget.refreshTick != oldWidget.refreshTick) {
      _load(quiet: true);
    }
  }

  List<Tag> get _visibleTags => List<Tag>.from(_all);

  Future<void> _load({bool quiet = false}) async {
    final showSpinner = !quiet || _all.isEmpty;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final all = await _tagsRepo.listTags();
      if (!mounted) return;
      setState(() {
        _all = all;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet) _error = '加载失败，请检查网络或后端是否启动';
      });
    }
  }

  void _openSearch() {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => TagsSearchPage(tags: _visibleTags),
      ),
    )
        .then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  void _openTag(Tag tag) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => ItemsBrowsePage(
          title: tag.name,
          loader: ({required limit, required offset}) => _tagsRepo.listTagItems(
            tag.id,
            limit: limit,
            offset: offset,
          ),
        ),
      ),
    )
        .then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  Future<void> _onCreateTag() async {
    final tag = await showCreateTagSheet(context);
    if (!mounted || tag == null) return;
    await _load();
    if (!mounted) return;
    AppToast.show(context, '已创建标签「${tag.name}」');
  }

  Future<void> _onDeleteTag(Tag tag) async {
    if (tag.isSystem) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除标签',
      message: '确定删除标签「${tag.name}」？仅解除关联，不会删除条目。',
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;

    try {
      await _tagsRepo.deleteTag(tag.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      AppToast.show(context, '已删除标签「${tag.name}」');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '删除失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTags;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        titleSpacing: 20,
        title: const Text(
          '我的标签',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _text,
            height: 1.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: _openSearch,
            icon: SvgPicture.asset(
              'assets/icons/search.svg',
              width: 22,
              height: 22,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: '新建标签',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _onCreateTag,
              icon: const Icon(Icons.add, size: 24, color: _text),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_loading && _all.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
                ],
              );
            }
            if (_error != null && _all.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: Center(
                      child: _ErrorCard(message: _error!, onRetry: _load),
                    ),
                  ),
                ],
              );
            }
            if (visible.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: const Center(
                      child: Text(
                        '暂无标签，点右上角 ＋ 新建',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF737A85),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _TagChipWrap(
                  tags: visible,
                  onTap: _openTag,
                  onRemove: _onDeleteTag,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TagChipWrap extends StatelessWidget {
  const _TagChipWrap({
    required this.tags,
    required this.onTap,
    required this.onRemove,
  });

  final List<Tag> tags;
  final ValueChanged<Tag> onTap;
  final ValueChanged<Tag> onRemove;

  static const _blue = Color(0xFF2F6FED);
  static const _chipOn = Color(0xFFE5EDFF);
  static const _perRow = 4;
  static const _gap = 7.0;
  static const _chipPadH = 12.0;

  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: _blue,
  );

  List<List<Tag>> _chunkRows(List<Tag> all) {
    final rows = <List<Tag>>[];
    for (var i = 0; i < all.length; i += _perRow) {
      rows.add(
        all.sublist(i, i + _perRow > all.length ? all.length : i + _perRow),
      );
    }
    return rows;
  }

  double _chipWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width + _chipPadH * 2;
  }

  double _rowWidth(List<Tag> row) {
    if (row.isEmpty) return 0;
    var total = 0.0;
    for (var i = 0; i < row.length; i++) {
      if (i > 0) total += _gap;
      total += _chipWidth('${row[i].name} ${row[i].countLabel}');
    }
    return total;
  }

  Widget _buildChip(Tag tag) {
    return GestureDetector(
      onTap: () => onTap(tag),
      onLongPress: tag.isSystem ? null : () => onRemove(tag),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: _chipPadH, vertical: 6),
        decoration: BoxDecoration(
          color: _chipOn,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '${tag.name} ${tag.countLabel}',
          style: _labelStyle,
        ),
      ),
    );
  }

  Widget _buildRow(List<Tag> row, double maxWidth) {
    final chips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < row.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          _buildChip(row[i]),
        ],
      ],
    );

    if (_rowWidth(row) <= maxWidth) return chips;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: chips,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _chunkRows(tags);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: _gap),
              _buildRow(rows[r], maxWidth),
            ],
          ],
        );
      },
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 14, color: Color(0xFF737A85)),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
