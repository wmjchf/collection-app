import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/create_folder_sheet.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/folder_models.dart';
import 'package:super_collection/features/collection/folders_repository.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/collection/system_filter_models.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/collection/trash_page.dart';

/// 我的收藏（对齐 Figma：系统分类 / 收藏夹 / 标签 / 其他）
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, this.isActive = true});

  /// 是否为当前 Tab；切回时静默刷新数量。
  final bool isActive;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _headerBg = Color(0xFFF5F7FA);
  static const _text = Color(0xFF1F242E);

  final _foldersRepo = FoldersRepository();
  final _tagsRepo = TagsRepository();
  final _systemFiltersRepo = SystemFiltersRepository();

  List<Folder> _folders = const [];
  List<Tag> _tags = const [];
  List<SystemFilter> _systemFilters = const [];
  List<SystemFilter> _otherFilters = const [];
  bool _loading = true;
  String? _error;

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
  }

  Future<void> _load({bool quiet = false}) async {
    final showSpinner = !quiet ||
        (_systemFilters.isEmpty && _folders.isEmpty && _tags.isEmpty);
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _foldersRepo.listFolders(),
        _tagsRepo.listTags(),
        _systemFiltersRepo.listFilters(),
      ]);
      if (!mounted) return;
      final filterResult =
          results[2] as ({List<SystemFilter> filters, List<SystemFilter> others});
      setState(() {
        _folders = results[0] as List<Folder>;
        _tags = results[1] as List<Tag>;
        _systemFilters = filterResult.filters;
        _otherFilters = filterResult.others;
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

  void _openFolder(Folder folder) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => ItemsBrowsePage(
          title: folder.name,
          loader: () => _foldersRepo.listFolderItems(folder.id),
        ),
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
          loader: () => _tagsRepo.listTagItems(tag.id),
        ),
      ),
    )
        .then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  Future<void> _onCreateFolder() async {
    final folder = await showCreateFolderSheet(context);
    if (!mounted || folder == null) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已创建「${folder.name}」')),
    );
  }

  Future<void> _onCreateTag() async {
    final tag = await showCreateTagSheet(context);
    if (!mounted || tag == null) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已创建标签「${tag.name}」')),
    );
  }

  Future<void> _onDeleteFolder(Folder folder) async {
    if (folder.isSystem) return;
    final confirmed = await _confirmDelete(
      title: '删除收藏夹',
      message: '确定删除「${folder.name}」？夹内条目将移回「未分类」，不会删除条目。',
    );
    if (confirmed != true || !mounted) return;

    try {
      await _foldersRepo.deleteFolder(folder.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除「${folder.name}」')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除标签「${tag.name}」')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败')),
      );
    }
  }

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                '删除',
                style: TextStyle(color: Color(0xFFE34D59)),
              ),
            ),
          ],
        );
      },
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
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _SectionLabel('系统分类'),
            const SizedBox(height: 8),
            if (_systemFilters.isEmpty)
              const SizedBox.shrink()
            else ...[
              _EntityGroup(
                entries: [
                  for (final f in _systemFilters.where((e) => e.code == 'unread'))
                    _EntityEntry(
                      title: f.name,
                      countLabel: f.countLabel,
                      isSystem: true,
                      onTap: () => _openSystemFilter(f),
                    ),
                ],
              ),
              if (_systemFilters.any((f) => f.code != 'unread')) ...[
                const SizedBox(height: 16),
                _EntityGroup(
                  entries: [
                    for (final f
                        in _systemFilters.where((e) => e.code != 'unread'))
                      _EntityEntry(
                        title: f.name,
                        countLabel: f.countLabel,
                        isSystem: true,
                        onTap: () => _openSystemFilter(f),
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 16),
            _SectionLabel(
              '收藏夹',
              trailing: '＋',
              onTrailingTap: _onCreateFolder,
            ),
            const SizedBox(height: 8),
            if (_loading &&
                _folders.isEmpty &&
                _tags.isEmpty &&
                _systemFilters.isEmpty)
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
            else if (_error != null &&
                _folders.isEmpty &&
                _tags.isEmpty &&
                _systemFilters.isEmpty)
              _ErrorCard(message: _error!, onRetry: _load)
            else ...[
              _EntityGroup(
                entries: [
                  for (final f in _folders)
                    _EntityEntry(
                      title: f.name,
                      countLabel: f.countLabel,
                      isSystem: f.isSystem,
                      onTap: () => _openFolder(f),
                      onLongPress: f.isSystem ? null : () => _onDeleteFolder(f),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _SectionLabel(
                '标签',
                trailing: '＋',
                onTrailingTap: _onCreateTag,
              ),
              const SizedBox(height: 8),
              _EntityGroup(
                entries: [
                  for (final t in _tags)
                    _EntityEntry(
                      title: t.name,
                      countLabel: t.countLabel,
                      isSystem: t.isSystem,
                      onTap: () => _openTag(t),
                      onLongPress: t.isSystem ? null : () => _onDeleteTag(t),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const _SectionLabel('其他'),
            const SizedBox(height: 8),
            _EntityGroup(
              entries: [
                for (final f in _otherFilters)
                  _EntityEntry(
                    title: f.name,
                    countLabel: f.countLabel,
                    isSystem: true,
                    onTap: () => _openSystemFilter(f),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityEntry {
  const _EntityEntry({
    required this.title,
    required this.countLabel,
    required this.isSystem,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String countLabel;
  final bool isSystem;
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
  const _SectionLabel(this.title, {this.trailing, this.onTrailingTap});

  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _CollectionColors.muted,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
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
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.title,
    required this.countLabel,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String countLabel;
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
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _CollectionColors.blue,
                  shape: BoxShape.circle,
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
  static const blue = Color(0xFF2F6FED);
  static const divider = Color(0xFFEDEDF0);
}
