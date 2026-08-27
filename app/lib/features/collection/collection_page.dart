import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/collection/system_filter_models.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/collection/trash_page.dart';
import 'package:super_collection/features/settings/settings_page.dart';

/// 我的收藏（系统分类 / 标签）
class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
  });

  /// 是否为当前 Tab；切回时静默刷新数量。
  final bool isActive;

  /// 外部递增时静默刷新（分享入库、解析完成）。
  final int refreshTick;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _headerBg = Color(0xFFF5F7FA);
  static const _text = Color(0xFF1F242E);

  final _tagsRepo = TagsRepository();
  final _systemFiltersRepo = SystemFiltersRepository();

  List<Tag> _tags = const [];
  List<SystemFilter> _systemFilters = const [];
  bool _loading = true;
  String? _error;
  bool _systemExpanded = true;
  bool _tagsExpanded = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(quiet: true);
    }
    if (widget.refreshTick != oldWidget.refreshTick) {
      _load(quiet: true);
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final showSpinner =
        !quiet || (_systemFilters.isEmpty && _tags.isEmpty);
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _tagsRepo.listTags(),
        _systemFiltersRepo.listFilters(),
      ]);
      if (!mounted) return;
      final filterResult =
          results[1] as ({List<SystemFilter> filters, List<SystemFilter> others});
      setState(() {
        _tags = results[0] as List<Tag>;
        _systemFilters = filterResult.filters;
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

  void _openSystemFilter(SystemFilter filter) {
    final page = filter.code == 'trash'
        ? const TrashPage()
        : SystemFilterListPage(
            code: filter.code,
            title: filter.name,
          );
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => page,
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
    final confirmed = await _confirmDelete(
      title: '删除标签',
      message: '确定删除标签「${tag.name}」？仅解除关联，不会删除条目。',
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

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showAppConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: '删除',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _headerBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        titleSpacing: 20,
        title: const Text(
          '我的收藏',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _text,
            height: 1.2,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: '设置',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
              icon: const Icon(
                Icons.settings_outlined,
                size: 22,
                color: _text,
              ),
            ),
          ),
        ],
      ),      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _SectionLabel(
              '系统分类',
              expanded: _systemExpanded,
              onToggleExpand: () {
                setState(() => _systemExpanded = !_systemExpanded);
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _systemExpanded && _systemFilters.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        children: [
                          if (_systemFilters.any((e) => e.code == 'unread'))
                            _EntityGroup(
                              entries: [
                                for (final f in _systemFilters
                                    .where((e) => e.code == 'unread'))
                                  _EntityEntry(
                                    title: f.name,
                                    countLabel: f.countLabel,
                                    icon:
                                        _CollectionNavIcon.forSystemCode(f.code),
                                    onTap: () => _openSystemFilter(f),
                                  ),
                              ],
                            ),
                          if (_systemFilters.any((f) => f.code != 'unread')) ...[
                            if (_systemFilters.any((e) => e.code == 'unread'))
                              const SizedBox(height: 16),
                            _EntityGroup(
                              entries: [
                                for (final f in _systemFilters
                                    .where((e) => e.code != 'unread'))
                                  _EntityEntry(
                                    title: f.name,
                                    countLabel: f.countLabel,
                                    icon:
                                        _CollectionNavIcon.forSystemCode(f.code),
                                    onTap: () => _openSystemFilter(f),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 16),
            if (_loading && _tags.isEmpty && _systemFilters.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              )
            else if (_error != null && _tags.isEmpty && _systemFilters.isEmpty)
              _ErrorCard(message: _error!, onRetry: _load)
            else ...[
              _SectionLabel(
                '标签',
                expanded: _tagsExpanded,
                onToggleExpand: () {
                  setState(() => _tagsExpanded = !_tagsExpanded);
                },
                trailing: '＋',
                onTrailingTap: _onCreateTag,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _tagsExpanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _EntityGroup(
                          entries: [
                            for (final t in _tags)
                              _EntityEntry(
                                title: t.name,
                                countLabel: t.countLabel,
                                icon: t.isSystem
                                    ? _CollectionNavIcon.tagSystem
                                    : _CollectionNavIcon.tagUser,
                                onTap: () => _openTag(t),
                                onLongPress: t.isSystem
                                    ? null
                                    : () => _onDeleteTag(t),
                              ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollectionNavIcon {
  const _CollectionNavIcon({
    required this.icon,
    required this.background,
  });

  final IconData icon;
  final Color background;

  static const tagSystem = _CollectionNavIcon(
    icon: Icons.local_offer_rounded,
    background: Color(0xFF788CAA),
  );

  static const tagUser = _CollectionNavIcon(
    icon: Icons.local_offer_rounded,
    background: Color(0xFFFF8C64),
  );

  static _CollectionNavIcon forSystemCode(String code) {
    switch (code) {
      case 'unread':
        return const _CollectionNavIcon(
          icon: Icons.adjust,
          background: Color(0xFF5B8FF9),
        );
      case 'all':
        return const _CollectionNavIcon(
          icon: Icons.format_list_bulleted_rounded,
          background: Color(0xFF6E788C),
        );
      case 'today':
        return const _CollectionNavIcon(
          icon: Icons.calendar_today_rounded,
          background: Color(0xFFFF9F43),
        );
      case 'starred':
        return const _CollectionNavIcon(
          icon: Icons.star_rounded,
          background: Color(0xFFFFC43D),
        );
      case 'parsed':
        return const _CollectionNavIcon(
          icon: Icons.article_rounded,
          background: Color(0xFF56CC8C),
        );
      case 'annotated':
        return const _CollectionNavIcon(
          icon: Icons.edit_rounded,
          background: Color(0xFFA270F5),
        );
      case 'recent_read':
        return const _CollectionNavIcon(
          icon: Icons.schedule_rounded,
          background: Color(0xFF40BAC4),
        );
      case 'archived':
        return const _CollectionNavIcon(
          icon: Icons.inventory_2_rounded,
          background: Color(0xFF96A0AF),
        );
      case 'trash':
        return const _CollectionNavIcon(
          icon: Icons.delete_outline_rounded,
          background: Color(0xFFF56C6C),
        );
      default:
        return const _CollectionNavIcon(
          icon: Icons.circle,
          background: Color(0xFF5B8FF9),
        );
    }
  }
}

class _EntityEntry {
  const _EntityEntry({
    required this.title,
    required this.countLabel,
    required this.icon,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String countLabel;
  final _CollectionNavIcon icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
}

class _EntityGroup extends StatelessWidget {
  const _EntityGroup({required this.entries});

  final List<_EntityEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          '暂无内容',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: _CollectionColors.muted),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _NavRow(
              title: entries[i].title,
              countLabel: entries[i].countLabel,
              icon: entries[i].icon,
              onTap: entries[i].onTap,
              onLongPress: entries[i].onLongPress,
            ),
            if (i < entries.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: _CollectionColors.divider,
              ),
          ],
        ],
      ),
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
            style: const TextStyle(fontSize: 14, color: _CollectionColors.muted),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
    this.title, {
    this.trailing,
    this.onTrailingTap,
    this.expanded,
    this.onToggleExpand,
  });

  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;
  final bool? expanded;
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final canToggle = onToggleExpand != null && expanded != null;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: canToggle ? onToggleExpand : null,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _CollectionColors.muted,
                  ),
                ),
                if (canToggle) ...[
                  const SizedBox(width: 2),
                  Icon(
                    expanded!
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: _CollectionColors.muted,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (trailing != null)
          GestureDetector(
            onTap: onTrailingTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Text(
                trailing!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: _CollectionColors.muted,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.title,
    required this.countLabel,
    required this.icon,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String countLabel;
  final _CollectionNavIcon icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: icon.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon.icon,
                  size: 13,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: _CollectionColors.text,
                  ),
                ),
              ),
              Text(
                countLabel,
                style: const TextStyle(
                  fontSize: 14,
                  color: _CollectionColors.muted,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '›',
                style: TextStyle(
                  fontSize: 18,
                  color: _CollectionColors.muted,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _CollectionColors {
  static const text = Color(0xFF1F242E);
  static const muted = Color(0xFF737A85);
  static const divider = Color(0xFFEDEDF0);
}
