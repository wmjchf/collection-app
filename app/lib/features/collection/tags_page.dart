import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/shell/user_avatar_button.dart';

/// 我的标签 Tab：多层分组整理；选标签 / 打标仍用扁平列表。
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
  static const _brand = Color(0xFF2F6FED);
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

  Map<int, Tag> get _byId => {for (final t in _tags) t.id: t};

  Map<int, List<Tag>> get _childrenByParent => tagChildrenByParent(_tags);

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
    final blocked = {
      tag.id,
      ...tagDescendantIds(tag.id, _childrenByParent),
    };
    final candidates = flattenTagsForDisplay(_tags)
        .where((t) => !blocked.contains(t.id))
        .toList();
    if (candidates.isEmpty) {
      AppToast.show(context, '暂无可用上级');
      return;
    }
    final picked = await showModalBottomSheet<Tag>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final allById = _byId;
        final maxH = MediaQuery.sizeOf(context).height * 0.72;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
                    itemCount: candidates.length,
                    separatorBuilder: (_, i) {
                      final depth = tagDepth(candidates[i], allById);
                      return Divider(
                        height: 1,
                        indent: 16.0 + depth * 22.0,
                        endIndent: 16,
                        color: _divider,
                      );
                    },
                    itemBuilder: (context, index) {
                      final r = candidates[index];
                      final depth = tagDepth(r, allById);
                      return InkWell(
                        onTap: () => Navigator.pop(context, r),
                        child: _buildTreeLabel(
                          r,
                          depth: depth,
                          showCount: false,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
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

  /// 与列表行一致的树形标签文案（缩进 + 竖条 + 字号字重）。
  Widget _buildTreeLabel(
    Tag tag, {
    required int depth,
    Widget? trailing,
    EdgeInsetsGeometry? padding,
    bool showCount = true,
  }) {
    final isNested = depth > 0;
    return Padding(
      padding: padding ??
          EdgeInsets.only(
            left: 16.0 + depth * 22.0,
            right: 16,
            top: 14,
            bottom: 14,
          ),
      child: Row(
        children: [
          if (isNested)
            Container(
              width: 2,
              height: 18,
              margin: const EdgeInsets.only(right: 10),
              color: const Color(0xFFE5E8ED),
            ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '#${tag.name}',
                    style: TextStyle(
                      fontSize: isNested ? 14 : 15,
                      fontWeight: isNested ? FontWeight.w400 : FontWeight.w500,
                      color: _text,
                    ),
                  ),
                  if (showCount)
                    TextSpan(
                      text: ' (${tag.countLabel})',
                      style: TextStyle(
                        fontSize: isNested ? 13 : 14,
                        fontWeight: FontWeight.w400,
                        color: _muted,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  /// 升一级：父级改为祖父；已在根下则变根。
  Future<void> _promoteOneLevel(int tagId) async {
    final tag = _byId[tagId];
    if (tag == null || tag.parentId == null) return;
    final parent = _byId[tag.parentId!];
    final newParentId = parent?.parentId;
    await _persist([
      for (final t in _tags)
        if (t.id == tagId)
          t.copyWith(
            parentId: newParentId,
            clearParentId: newParentId == null,
          )
        else
          t,
    ]);
  }

  Future<void> _deleteTag(Tag tag) async {
    final hasChildren = _childrenByParent[tag.id]?.isNotEmpty == true;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除标签',
      message: hasChildren
          ? '确定删除标签「${tag.name}」？仅解除与条目的关联，不会删除条目；其子标签将接到上一级。'
          : '确定删除标签「${tag.name}」？仅解除与条目的关联，不会删除条目。',
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;
    try {
      await _tagsRepo.deleteTag(tag.id);
      if (!mounted) return;
      AppToast.show(context, '已删除标签「${tag.name}」');
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '删除失败');
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_isSearching || _savingLayout) return;
    final rows = List<Tag>.from(_displayRows);
    if (oldIndex < 0 || oldIndex >= rows.length) return;

    final moved = rows[oldIndex];
    final parentId = moved.parentId;

    // 同级头节点（相同 parentId）在展示行中的下标
    final heads = <int>[
      for (var i = 0; i < rows.length; i++)
        if (rows[i].parentId == parentId) i,
    ];
    if (heads.length < 2) {
      if (mounted) setState(() {});
      return;
    }

    final fromRank = heads.indexOf(oldIndex);
    if (fromRank < 0) {
      if (mounted) setState(() {});
      return;
    }

    final starts = heads;
    final ends = [
      for (final h in heads) h + tagSubtreeBlock(rows, h).length,
    ];
    final bandStart = starts.first;
    final bandEnd = ends.last;

    var dest = newIndex;
    if (dest > oldIndex) dest -= 1;

    // 拖出同级区间 → 不改层级，直接还原
    if (dest < bandStart || dest >= bandEnd) {
      if (mounted) setState(() {});
      return;
    }

    // 映射为同级插入位：0..heads.length（length = 插到末尾）
    var toRank = heads.length;
    for (var i = 0; i < heads.length; i++) {
      if (dest < starts[i]) {
        toRank = i;
        break;
      }
      if (dest < ends[i]) {
        if (fromRank == i) {
          if (mounted) setState(() {});
          return;
        }
        // 落在某同级子树内：从上往下 → 插到其后；从下往上 → 插到其前
        toRank = fromRank < i ? i + 1 : i;
        break;
      }
    }

    final siblings = [for (final h in heads) rows[h]];
    final reordered = List<Tag>.from(siblings);
    final item = reordered.removeAt(fromRank);
    var insertAt = toRank;
    if (fromRank < insertAt) insertAt -= 1;
    insertAt = insertAt.clamp(0, reordered.length);
    reordered.insert(insertAt, item);

    var unchanged = true;
    for (var i = 0; i < reordered.length; i++) {
      if (reordered[i].id != siblings[i].id) {
        unchanged = false;
        break;
      }
    }
    if (unchanged) {
      if (mounted) setState(() {});
      return;
    }

    final orderById = <int, int>{
      for (var i = 0; i < reordered.length; i++)
        reordered[i].id: (i + 1) * 10,
    };
    await _persist([
      for (final t in _tags)
        if (orderById.containsKey(t.id))
          t.copyWith(sortOrder: orderById[t.id])
        else
          t,
    ]);
  }

  Future<void> _showRowActions(Tag tag) async {
    final hasParent = tag.parentId != null;
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
              ListTile(
                leading: const Icon(Icons.subdirectory_arrow_right_rounded),
                title: const Text('归入分组'),
                onTap: () => Navigator.pop(context, 'nest'),
              ),
              if (hasParent)
                ListTile(
                  leading: const Icon(Icons.undo_rounded),
                  title: const Text('升一级'),
                  onTap: () => Navigator.pop(context, 'promote'),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFBF3333)),
                title: const Text(
                  '删除标签',
                  style: TextStyle(color: Color(0xFFBF3333)),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
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
    if (action == 'promote') await _promoteOneLevel(tag.id);
    if (action == 'delete') await _deleteTag(tag);
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
                      size: 24,
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: _muted,
                              size: 22,
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
                      borderSide: const BorderSide(
                        color: Color(0xFFB8CCFA),
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: Color(0xFFB8CCFA),
                        width: 1,
                      ),
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
              '长按调整层级 · 拖动手柄同级排序',
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
                color: _brand,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: Colors.white),
                  SizedBox(width: 2),
                  Text(
                    '新建',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
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

  Widget _buildRow(Tag tag, {required int depth, required int index}) {
    return Material(
      color: _card,
      child: InkWell(
        onTap: () => _openTag(tag),
        onLongPress: _isSearching ? null : () => _showRowActions(tag),
        child: _buildTreeLabel(
          tag,
          depth: depth,
          padding: EdgeInsets.only(
            left: 14.0 + depth * 22.0,
            right: 4,
            top: 14,
            bottom: 14,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isSearching)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: _DragGrip(),
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
      if (_isSearching) {
        return const Center(
          child: Text(
            '没有相关标签',
            style: TextStyle(fontSize: 14, color: _muted),
          ),
        );
      }
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
                    itemCount: rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == rows.length) {
                        return const _ListEndTip();
                      }
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
                            _buildRow(tag, depth: 0, index: index),
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
                    footer: const _ListEndTip(),
                    itemBuilder: (context, index) {
                      final tag = rows[index];
                      final depth = tagDepth(tag, _byId);
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
                            _buildRow(tag, depth: depth, index: index),
                            if (index < rows.length - 1)
                              Divider(
                                height: 1,
                                indent: 14.0 + depth * 22.0,
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

class _ListEndTip extends StatelessWidget {
  const _ListEndTip();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          '没有更多了',
          style: TextStyle(fontSize: 12, color: Color(0xFF737A85)),
        ),
      ),
    );
  }
}

class _DragGrip extends StatelessWidget {
  const _DragGrip();

  static const _color = Color(0xFFB8BFC8);

  @override
  Widget build(BuildContext context) {
    Widget line() => Container(
          width: 12,
          height: 1.5,
          decoration: BoxDecoration(
            color: _color,
            borderRadius: BorderRadius.circular(1),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        line(),
        const SizedBox(height: 3),
        line(),
        const SizedBox(height: 3),
        line(),
      ],
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

