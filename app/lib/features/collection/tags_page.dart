import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/shell/user_avatar_button.dart';

/// 我的标签 Tab：一层分组整理；选标签 / 打标仍用扁平列表。
class TagsPage extends StatefulWidget {
  const TagsPage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
    this.onOpenAccount,
  });

  final bool isActive;
  final int refreshTick;
  final VoidCallback? onOpenAccount;

  @override
  State<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends State<TagsPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _inputBg = Color(0xFFF5F7FA);
  static const _card = Colors.white;
  static const _divider = Color(0xFFF0F2F5);

  final _tagsRepo = TagsRepository();
  final _searchController = TextEditingController();

  List<Tag> _tags = const [];
  bool _loading = true;
  String? _error;
  bool _savingLayout = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  List<Tag> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _tags;
    return _tags.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  List<Tag> get _displayRows {
    if (_searchController.text.trim().isNotEmpty) {
      return List<Tag>.from(_filtered)
        ..sort((a, b) => a.name.compareTo(b.name));
    }
    return flattenTagsForDisplay(_tags);
  }

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  bool _hasChildren(int id) => _tags.any((t) => t.parentId == id);

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final tags = await _tagsRepo.listTags();
      if (!mounted) return;
      setState(() {
        _tags = tags;
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
        if (!quiet) _error = '加载失败';
      });
    }
  }

  Future<void> _persist(List<Tag> next) async {
    if (_savingLayout) return;
    setState(() {
      _tags = next;
      _savingLayout = true;
    });
    try {
      final ordered = flattenTagsForDisplay(next);
      final items = <({int id, int? parentId, int sortOrder})>[
        for (var i = 0; i < ordered.length; i++)
          (
            id: ordered[i].id,
            parentId: ordered[i].parentId,
            sortOrder: (i + 1) * 10,
          ),
      ];
      final seen = items.map((e) => e.id).toSet();
      for (final t in next) {
        if (!seen.contains(t.id)) {
          items.add((
            id: t.id,
            parentId: t.parentId,
            sortOrder: (items.length + 1) * 10,
          ));
        }
      }
      final saved = await _tagsRepo.reorderTags(items);
      if (!mounted) return;
      setState(() {
        _tags = saved;
        _savingLayout = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _savingLayout = false);
      AppToast.show(context, e.message);
      await _load(quiet: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingLayout = false);
      AppToast.show(context, '保存失败');
      await _load(quiet: true);
    }
  }

  void _openTag(Tag tag) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => ItemsBrowsePage(
          title: tag.name,
          tagId: tag.isSystem ? null : tag.id,
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

  Future<void> _createTag() async {
    final created = await showCreateTagSheet(context);
    if (created != null && mounted) await _load(quiet: true);
  }

  Future<void> _moveToGroup(Tag tag) async {
    if (_hasChildren(tag.id)) {
      AppToast.show(context, '请先移出子标签');
      return;
    }
    final candidates = _tags
        .where((t) => t.parentId == null && t.id != tag.id)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (candidates.isEmpty) {
      AppToast.show(context, '暂无可用分组');
      return;
    }
    final picked = await showModalBottomSheet<Tag>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '归入分组',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
              ),
              for (final r in candidates)
                ListTile(
                  title: Text('#${r.name}'),
                  onTap: () => Navigator.pop(context, r),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    await _persist([
      for (final t in _tags)
        if (t.id == tag.id) t.copyWith(parentId: picked.id) else t,
    ]);
  }

  Future<void> _unnest(int tagId) async {
    await _persist([
      for (final t in _tags)
        if (t.id == tagId) t.copyWith(clearParentId: true) else t,
    ]);
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_isSearching || _savingLayout) return;
    final rows = List<Tag>.from(_displayRows);
    if (newIndex > oldIndex) newIndex -= 1;

    final moved = rows[oldIndex];
    final block = <Tag>[moved];
    if (moved.parentId == null) {
      block.addAll(rows.where((t) => t.parentId == moved.id));
    }
    final blockIds = block.map((t) => t.id).toSet();
    final remaining = rows.where((t) => !blockIds.contains(t.id)).toList();

    var insertAt = newIndex.clamp(0, remaining.length);
    // 移除块后校正插入点
    final removedBefore = rows
        .take(newIndex + (newIndex > oldIndex ? 1 : 0))
        .where((t) => blockIds.contains(t.id))
        .length;
    if (oldIndex < newIndex) {
      insertAt = (newIndex - removedBefore + 1).clamp(0, remaining.length);
    } else {
      insertAt = newIndex.clamp(0, remaining.length);
    }

    final nextRows = [...remaining]..insertAll(insertAt, block);

    final result = <Tag>[];
    for (var i = 0; i < nextRows.length; i++) {
      final t = nextRows[i];
      // 跟随父节点移动的子节点
      if (moved.parentId == null &&
          t.id != moved.id &&
          blockIds.contains(t.id)) {
        result.add(t.copyWith(parentId: moved.id, sortOrder: (i + 1) * 10));
        continue;
      }

      var parentId = _inferParent(nextRows, i);
      if (t.id == moved.id && _hasChildren(moved.id)) {
        parentId = null;
      }
      if (parentId != null && _hasChildren(t.id)) {
        parentId = null;
      }

      result.add(
        t.copyWith(
          parentId: parentId,
          clearParentId: parentId == null,
          sortOrder: (i + 1) * 10,
        ),
      );
    }

    final seen = result.map((t) => t.id).toSet();
    for (final t in _tags) {
      if (!seen.contains(t.id)) result.add(t);
    }
    await _persist(result);
  }

  int? _inferParent(List<Tag> rows, int index) {
    if (index <= 0) return null;
    final prev = rows[index - 1];
    final next = index + 1 < rows.length ? rows[index + 1] : null;
    if (prev.parentId != null) return prev.parentId;
    if (next != null && next.parentId == prev.id) return prev.id;
    return null;
  }

  Future<void> _showRowActions(Tag tag) async {
    final isChild = tag.parentId != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '#${tag.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                ),
              ),
              if (!isChild)
                ListTile(
                  leading: const Icon(Icons.subdirectory_arrow_right_rounded),
                  title: const Text('归入分组'),
                  onTap: () => Navigator.pop(context, 'nest'),
                ),
              if (isChild)
                ListTile(
                  leading: const Icon(Icons.undo_rounded),
                  title: const Text('移出分组'),
                  onTap: () => Navigator.pop(context, 'unnest'),
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('取消'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (action == 'nest') await _moveToGroup(tag);
    if (action == 'unnest') await _unnest(tag.id);
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12),
        child: Row(
          children: [
            UserAvatarButton(onPressed: widget.onOpenAccount ?? () {}),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 15, color: _text, height: 1.2),
                  decoration: InputDecoration(
                    hintText: '搜索标签',
                    hintStyle: const TextStyle(fontSize: 15, color: _muted),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _muted,
                      size: 22,
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: _muted,
                              size: 20,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                    filled: true,
                    fillColor: _inputBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: Color(0xFFB8CCFA),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Text('标签分组', style: TextStyle(fontSize: 13, color: _muted)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '拖动手柄排序',
              style: TextStyle(fontSize: 12, color: _muted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: _createTag,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE8ECF0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: _text),
                  SizedBox(width: 2),
                  Text(
                    '新建',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(Tag tag, {required bool isChild, required int index}) {
    return Material(
      color: _card,
      child: InkWell(
        onTap: () => _openTag(tag),
        onLongPress: _isSearching ? null : () => _showRowActions(tag),
        child: Padding(
          padding: EdgeInsets.only(
            left: isChild ? 38 : 14,
            right: 4,
            top: 14,
            bottom: 14,
          ),
          child: Row(
            children: [
              if (isChild)
                Container(
                  width: 2,
                  height: 18,
                  margin: const EdgeInsets.only(right: 10),
                  color: const Color(0xFFE5E8ED),
                ),
              Expanded(
                child: Text(
                  '#${tag.name}',
                  style: TextStyle(
                    fontSize: isChild ? 14 : 15,
                    fontWeight: isChild ? FontWeight.w400 : FontWeight.w500,
                    color: _text,
                  ),
                ),
              ),
              Text(
                tag.countLabel,
                style: const TextStyle(fontSize: 14, color: _muted),
              ),
              if (!_isSearching)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: Color(0xFFB8BFC8),
                    ),
                  ),
                )
              else
                const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _tags.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_error != null && _tags.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _muted)),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final rows = _displayRows;
    if (rows.isEmpty) {
      return _EmptyState(onCreate: _createTag);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _isSearching
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final tag = rows[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.vertical(
                            top: index == 0
                                ? const Radius.circular(14)
                                : Radius.zero,
                            bottom: index == rows.length - 1
                                ? const Radius.circular(14)
                                : Radius.zero,
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildRow(tag, isChild: false, index: index),
                            if (index < rows.length - 1)
                              const Divider(
                                height: 1,
                                indent: 14,
                                endIndent: 14,
                                color: _divider,
                              ),
                          ],
                        ),
                      );
                    },
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    buildDefaultDragHandles: false,
                    itemCount: rows.length,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        child: child,
                      );
                    },
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final tag = rows[index];
                      final isChild = tag.parentId != null;
                      return Container(
                        key: ValueKey(tag.id),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.vertical(
                            top: index == 0
                                ? const Radius.circular(14)
                                : Radius.zero,
                            bottom: index == rows.length - 1
                                ? const Radius.circular(14)
                                : Radius.zero,
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildRow(tag, isChild: isChild, index: index),
                            if (index < rows.length - 1)
                              Divider(
                                height: 1,
                                indent: isChild ? 38 : 14,
                                endIndent: 14,
                                color: _divider,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        if (!_isSearching)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '拖动手柄排序；长按标签可归入 / 移出分组。给链接选标签时仍为扁平列表，勾选什么就记什么。',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '还没有标签',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '给收藏打标签，方便按主题找回',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onCreate,
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(120, 44),
              ),
              child: const Text('新建标签'),
            ),
          ],
        ),
      ),
    );
  }
}

