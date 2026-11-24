import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/onboarding/home_coach_overlay.dart';
import 'package:super_collection/features/onboarding/reading_tags_long_press_tip_prefs.dart';

class _TagsSheetSession {
  final Set<int> selectedIds = {};
}

Future<void> showReadingTagsSheet(
  BuildContext context, {
  required int itemId,
  required AiTagsMeta tagsMeta,
  bool aiSuggestEnabled = true,
  bool transcriptPending = false,
  bool autoStartAiSuggest = false,
  bool needsAutoTranscript = false,
  void Function(AiTagsMeta tagsMeta)? onTagsMetaChanged,
}) async {
  final session = _TagsSheetSession();
  var meta = tagsMeta;

  if (!context.mounted) return;
  await showAppBottomSheet<void>(
    context: context,
    padding: EdgeInsets.zero,
    includeSafeArea: false,
    builder: (context) => _ReadingTagsSheet(
      itemId: itemId,
      session: session,
      initialTagsMeta: meta,
      aiSuggestEnabled: aiSuggestEnabled,
      transcriptPending: transcriptPending,
      autoStartAiSuggest: autoStartAiSuggest,
      needsAutoTranscript: needsAutoTranscript,
      onTagsMetaChanged: (updated) {
        meta = updated;
        onTagsMetaChanged?.call(updated);
      },
    ),
  );
}

class _ReadingTagsSheet extends StatefulWidget {
  const _ReadingTagsSheet({
    required this.itemId,
    required this.session,
    required this.initialTagsMeta,
    required this.aiSuggestEnabled,
    required this.transcriptPending,
    required this.autoStartAiSuggest,
    this.needsAutoTranscript = false,
    this.onTagsMetaChanged,
  });

  final int itemId;
  final _TagsSheetSession session;
  final AiTagsMeta initialTagsMeta;
  final bool aiSuggestEnabled;
  final bool transcriptPending;
  final bool autoStartAiSuggest;
  final bool needsAutoTranscript;
  final void Function(AiTagsMeta tagsMeta)? onTagsMetaChanged;

  @override
  State<_ReadingTagsSheet> createState() => _ReadingTagsSheetState();
}

class _ReadingTagsSheetState extends State<_ReadingTagsSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _pathMuted = Color(0xFF8B929C);
  static const _blue = Color(0xFF2F6FED);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _surface = Color(0xFFF3F6FA);
  static const _handle = Color(0xFFE5E8ED);

  final _modulesRepo = TagModulesRepository();
  final _tagsRepo = TagsRepository();
  final _itemsRepo = ItemsRepository();
  final _auth = AuthRepository();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final GlobalKey _drillSampleKey = GlobalKey();
  List<TagModule> _modules = const [];
  List<Tag> _ungrouped = const [];
  final Set<int> _selected = {};
  /// AI 建议名（生成后默认全选；可点掉）
  final Set<String> _aiSelected = {};
  /// 选标下钻路径；空=顶层分区浏览
  final List<Tag> _browsePath = [];
  bool _loading = true;
  bool _saving = false;
  bool _creating = false;
  String? _error;
  late AiTagsMeta _tagsMeta;
  OverlayEntry? _longPressTipOverlay;
  int? _tipUserId;
  bool _tipStarting = false;
  bool _tipFinished = false;

  @override
  void initState() {
    super.initState();
    _tagsMeta = widget.initialTagsMeta;
    if (_tagsMeta.hasSuggestions) {
      _aiSelected.addAll(_tagsMeta.items.map((e) => e.name));
    }
    _load();
  }

  @override
  void dispose() {
    _removeLongPressTip();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim();

  String get _queryKey => _query.toLowerCase().replaceFirst(RegExp(r'^#'), '');

  bool _tagMatches(Tag tag) {
    final q = _queryKey;
    if (q.isEmpty) return true;
    return tag.name.toLowerCase().contains(q);
  }

  List<Tag> get _allTags => [
        ..._ungrouped,
        for (final m in _modules) ...m.tags,
      ];

  List<Tag> get _selectedTags {
    final byId = {for (final t in _allTags) t.id: t};
    return [
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 已选展示顺序：先跟 AI 推荐顺序，再接其余手选标签。
  List<({String name, int? tagId})> get _selectedDisplayItems {
    final byId = {for (final t in _allTags) t.id: t};
    final byName = {
      for (final t in _allTags) t.name.toLowerCase(): t,
    };
    final shown = <String>{};
    final out = <({String name, int? tagId})>[];

    if (_tagsMeta.hasSuggestions) {
      for (final item in _tagsMeta.items) {
        if (!_aiSelected.contains(item.name)) continue;
        final key = item.name.toLowerCase();
        if (!shown.add(key)) continue;
        final tag = item.existingTagId != null
            ? byId[item.existingTagId!]
            : byName[key];
        out.add((name: item.name, tagId: tag?.id));
      }
    }

    for (final id in _selected) {
      final tag = byId[id];
      if (tag == null) continue;
      final key = tag.name.toLowerCase();
      if (!shown.add(key)) continue;
      out.add((name: tag.name, tagId: tag.id));
    }

    return out;
  }

  int get _selectedCount {
    final names = <String>{
      for (final t in _selectedTags) t.name.toLowerCase(),
      for (final n in _aiSelected) n.toLowerCase(),
    };
    return names.length;
  }

  bool get _canCreateFromQuery {
    final q = _queryKey;
    if (q.isEmpty) return false;
    return !_allTags.any((t) => t.name.toLowerCase() == q);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final modulesResult = await _modulesRepo.listModules();
      final current = await _itemsRepo.listItemTags(widget.itemId);
      if (!mounted) return;
      setState(() {
        _modules = modulesResult.modules
            .map(
              (m) => m.copyWith(
                tags: m.tags.where((t) => !t.isSystem).toList(),
              ),
            )
            .toList();
        _ungrouped =
            modulesResult.ungrouped.where((t) => !t.isSystem).toList();
        _selected
          ..clear()
          ..addAll(
            widget.session.selectedIds.isNotEmpty
                ? widget.session.selectedIds
                : current.map((t) => t.id),
          );
        if (_tagsMeta.hasSuggestions) {
          for (final item in _tagsMeta.items) {
            final id = item.existingTagId;
            if (id != null && _aiSelected.contains(item.name)) {
              _selected.add(id);
            }
          }
        }
        final byId = {
          for (final t in [
            ..._ungrouped,
            for (final m in _modules) ...m.tags,
          ])
            t.id: t,
        };
        _browsePath.removeWhere((t) => !byId.containsKey(t.id));
        for (var i = 0; i < _browsePath.length; i++) {
          _browsePath[i] = byId[_browsePath[i].id]!;
        }
        _loading = false;
      });
      _syncSession();
      unawaited(_maybeShowLongPressTip());
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

  void _syncSession() {
    widget.session.selectedIds
      ..clear()
      ..addAll(_selected);
  }

  void _dismissSearchFocus() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
    }
  }

  void _toggleTag(int id) {
    _dismissSearchFocus();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        final tag = _allTags.cast<Tag?>().firstWhere(
              (t) => t?.id == id,
              orElse: () => null,
            );
        if (tag != null) _aiSelected.remove(tag.name);
      } else {
        _selected.add(id);
      }
      _syncSession();
    });
  }

  Future<void> _createFromQuery() async {
    final name = _queryKey;
    if (name.isEmpty || _creating) return;
    final parentId = _browsePath.isEmpty ? null : _browsePath.last.id;
    setState(() => _creating = true);
    try {
      final created = await _tagsRepo.createTag(name, moduleId: parentId);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      _searchController.clear();
      _searchFocus.unfocus();
      await _load();
      if (!mounted) return;
      setState(() {
        _selected.add(created.id);
        _syncSession();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '创建失败');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final desiredNames = <String>{
        for (final t in _selectedTags) t.name,
        ..._aiSelected,
      };

      if (_aiSelected.isNotEmpty && _tagsMeta.hasSuggestions) {
        final updated = await _itemsRepo.applyAiSuggest(
          widget.itemId,
          _aiSelected.toList(),
        );
        Analytics.instance.aiTagsApply(
          itemId: widget.itemId,
          count: _aiSelected.length,
        );
        if (!mounted) return;
        _tagsMeta = updated.aiMeta.tags;
        widget.onTagsMetaChanged?.call(_tagsMeta);
      }

      final modulesResult = await _modulesRepo.listModules();
      if (!mounted) return;
      final all = <Tag>[
        ...modulesResult.ungrouped.where((t) => !t.isSystem),
        for (final m in modulesResult.modules)
          ...m.tags.where((t) => !t.isSystem),
      ];
      final byName = {
        for (final t in all) t.name.toLowerCase(): t.id,
      };
      final descByName = {
        for (final item in _tagsMeta.items)
          if ((item.description ?? '').trim().isNotEmpty)
            item.name.toLowerCase(): item.description!.trim(),
      };
      final ids = <int>{};
      for (final name in desiredNames) {
        final key = name.toLowerCase();
        var id = byName[key];
        if (id == null) {
          final created = await _tagsRepo.createTag(
            name,
            description: descByName[key],
          );
          id = created.id;
          byName[key] = id;
        }
        ids.add(id);
      }

      await _itemsRepo.setItemTags(widget.itemId, ids.toList());
      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, '保存失败');
    }
  }

  static String _hashLabel(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  void _removeLongPressTip() {
    _longPressTipOverlay?.remove();
    _longPressTipOverlay = null;
  }

  Future<void> _finishLongPressTip() async {
    if (_tipFinished) return;
    _tipFinished = true;
    _removeLongPressTip();
    await ReadingTagsLongPressTipPrefs.markSeen(userId: _tipUserId);
  }

  Future<void> _maybeShowLongPressTip() async {
    if (!mounted ||
        _tipStarting ||
        _tipFinished ||
        _loading ||
        _error != null ||
        _queryKey.isNotEmpty) {
      return;
    }
    if (!_levelTags.any(_hasChildren)) return;
    _tipStarting = true;
    try {
      final session = await _auth.readSession();
      _tipUserId = session?.userId;
      final seen =
          await ReadingTagsLongPressTipPrefs.isSeen(userId: _tipUserId);
      if (!mounted || seen || _tipFinished) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _tipFinished) return;
        _syncLongPressTipOverlay();
        // 再等一帧，确保 chip 已布局出 hole
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_tipFinished) {
            _longPressTipOverlay?.markNeedsBuild();
          }
        });
      });
    } finally {
      _tipStarting = false;
    }
  }

  void _syncLongPressTipOverlay() {
    _removeLongPressTip();
    if (!mounted || _tipFinished) return;
    _longPressTipOverlay = OverlayEntry(
      builder: (context) {
        final hole = rectForKey(_drillSampleKey, inflate: 8);
        final tipTop = hole == null
            ? null
            : (hole.bottom + 14).clamp(
                80.0,
                MediaQuery.sizeOf(context).height - 220,
              );
        return CoachHoleOverlay(
          hole: hole,
          holeRadius: 14,
          tooltipTop: tipTop,
          onHoleTap: () {},
          onHoleLongPress: () {
            Tag? sample;
            for (final t in _levelTags) {
              if (_hasChildren(t)) {
                sample = t;
                break;
              }
            }
            if (sample != null) _toggleTag(sample.id);
            unawaited(_finishLongPressTip());
          },
          tooltip: CoachTooltipCard(
            stepLabel: '选标签',
            title: '长按可选中这一层',
            message: '点带 › 的标签进入下一层；想勾选这一层本身，请长按。',
            confirmLabel: '知道了',
            showSkip: false,
            onConfirm: () => unawaited(_finishLongPressTip()),
          ),
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_longPressTipOverlay!);
  }

  Widget _pill({
    required String label,
    required bool selected,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    VoidCallback? onRemove,
    bool showDrillChevron = false,
    bool isNew = false,
    GlobalKey? key,
  }) {
    final fg = selected ? Colors.white : _text;
    final rightPad =
        onRemove != null || showDrillChevron ? 6.0 : 10.0;
    return GestureDetector(
      key: key,
      onTap: onTap,
      onLongPress: onLongPress == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onLongPress();
            },
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 略放大但仍保证常见「三个四字标签」一排放下
        padding: EdgeInsets.fromLTRB(isNew ? 6 : 10, 7, rightPad, 7),
        decoration: BoxDecoration(
          color: selected ? _blue : _chipBg,
          borderRadius: BorderRadius.circular(999),
          border: selected
              ? null
              : Border.all(color: const Color(0xFFE8EAF0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isNew) ...[
              Container(
                width: 17,
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: selected ? Colors.white : _blue,
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              _hashLabel(label),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
                color: fg,
              ),
            ),
            if (showDrillChevron) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: selected ? Colors.white : _muted,
              ),
            ],
            if (onRemove != null) ...[
              const SizedBox(width: 3),
              GestureDetector(
                onTap: onRemove,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: selected ? Colors.white : _muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitleRow() {
    return const Text(
      '选择标签',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: _text,
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _dismissSearchFocus(),
        onTapOutside: (_) => _dismissSearchFocus(),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, color: _text),
        decoration: InputDecoration(
          hintText: '搜索或新建标签',
          hintStyle: const TextStyle(fontSize: 14, color: _muted),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: _muted,
            size: 20,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: _muted,
                    size: 18,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: _surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(
              color: Color(0xFFB8CCFA),
              width: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedSection() {
    final items = _selectedDisplayItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '已选标签',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const Text(
            '从下方选择或搜索新建',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              for (final item in items)
                _pill(
                  label: item.name,
                  selected: true,
                  onRemove: () {
                    final id = item.tagId;
                    if (id != null) {
                      _toggleTag(id);
                    } else {
                      setState(() => _aiSelected.remove(item.name));
                    }
                  },
                ),
            ],
          ),
      ],
    );
  }

  Map<int?, List<Tag>> _childrenMap() {
    final byId = {for (final t in _allTags) t.id: t};
    final children = <int?, List<Tag>>{};
    for (final t in _allTags) {
      final p = t.effectiveParentId;
      final key = (p != null && byId.containsKey(p)) ? p : null;
      children.putIfAbsent(key, () => []).add(t);
    }
    for (final list in children.values) {
      list.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.id.compareTo(b.id);
      });
    }
    return children;
  }

  bool _hasChildren(Tag tag) {
    final kids = _childrenMap()[tag.id];
    return kids != null && kids.isNotEmpty;
  }

  String _ancestryPath(Tag tag) {
    final byId = {for (final t in _allTags) t.id: t};
    final names = <String>[];
    var cursor = tag.effectiveParentId;
    final seen = <int>{};
    while (cursor != null && byId.containsKey(cursor) && seen.add(cursor)) {
      names.insert(0, byId[cursor]!.name);
      cursor = byId[cursor]!.effectiveParentId;
    }
    if (names.isEmpty) return '';
    return names.join(' / ');
  }

  void _drillInto(Tag tag) {
    if (!_hasChildren(tag)) return;
    setState(() {
      _browsePath.add(tag);
      _searchController.clear();
      _searchFocus.unfocus();
    });
  }

  void _browseBack() {
    if (_browsePath.isEmpty) return;
    setState(() => _browsePath.removeLast());
  }

  void _browseToRoot() {
    if (_browsePath.isEmpty) return;
    setState(() => _browsePath.clear());
  }

  /// 点到路径第 index 段（0=全部；1..=_browsePath[i-1]）
  void _browseToPathIndex(int index) {
    if (index <= 0) {
      _browseToRoot();
      return;
    }
    final keep = index.clamp(1, _browsePath.length);
    if (keep == _browsePath.length) return;
    setState(() => _browsePath.removeRange(keep, _browsePath.length));
  }

  List<Tag> get _levelTags {
    final map = _childrenMap();
    if (_browsePath.isEmpty) return map[null] ?? const [];
    return map[_browsePath.last.id] ?? const [];
  }

  Widget _buildLevelChips(List<Tag> tags) {
    if (tags.isEmpty) {
      return const Text(
        '这一层还没有子标签',
        style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
      );
    }
    int? sampleId;
    for (final t in tags) {
      if (_hasChildren(t)) {
        sampleId = t.id;
        break;
      }
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in tags)
          _pill(
            key: tag.id == sampleId ? _drillSampleKey : null,
            label: tag.name,
            selected: _selected.contains(tag.id),
            showDrillChevron: _hasChildren(tag),
            // 有下级：点击进入；长按勾选。无下级：点击勾选。
            onTap: _hasChildren(tag)
                ? () {
                    unawaited(_finishLongPressTip());
                    _drillInto(tag);
                  }
                : () => _toggleTag(tag.id),
            onLongPress: _hasChildren(tag)
                ? () {
                    unawaited(_finishLongPressTip());
                    _toggleTag(tag.id);
                  }
                : null,
          ),
      ],
    );
  }

  Widget _buildFullPathBar() {
    // 全部 / a / b / c —— 末段可点选当前父级，前面各段点按返回
    final segments = <({String label, int pathIndex, bool isCurrent})>[
      (label: '全部', pathIndex: 0, isCurrent: false),
      for (var i = 0; i < _browsePath.length; i++)
        (
          label: _browsePath[i].name,
          pathIndex: i + 1,
          isCurrent: i == _browsePath.length - 1,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _browseBack,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(right: 2),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: _pathMuted,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var s = 0; s < segments.length; s++) ...[
                    if (s > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '/',
                          style: TextStyle(
                            fontSize: 13,
                            color: _pathMuted,
                          ),
                        ),
                      ),
                    GestureDetector(
                      onTap: () {
                        final seg = segments[s];
                        if (seg.isCurrent) {
                          _toggleTag(_browsePath.last.id);
                        } else {
                          _browseToPathIndex(seg.pathIndex);
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        segments[s].label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: segments[s].isCurrent
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: segments[s].isCurrent &&
                                  _selected.contains(_browsePath.last.id)
                              ? _blue
                              : (segments[s].isCurrent ? _text : _pathMuted),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 默认只平铺当前层（顶层=根标签）；有 › 再进下一层。
  Widget _buildBrowseLevel() {
    final level = _levelTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_browsePath.isNotEmpty) _buildFullPathBar(),
        _buildLevelChips(level),
      ],
    );
  }

  Widget _buildSearchHits() {
    final hits = _allTags.where(_tagMatches).toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.id.compareTo(b.id);
      });
    if (hits.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in hits)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_ancestryPath(tag).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 2),
                  child: SizedBox(
                    width: 160,
                    child: Text(
                      _ancestryPath(tag),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: _pathMuted,
                      ),
                    ),
                  ),
                ),
              _pill(
                label: tag.name,
                selected: _selected.contains(tag.id),
                showDrillChevron: _hasChildren(tag),
                onTap: _hasChildren(tag)
                    ? () => _drillInto(tag)
                    : () => _toggleTag(tag.id),
                onLongPress:
                    _hasChildren(tag) ? () => _toggleTag(tag.id) : null,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMyTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '我的标签',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        const SizedBox(height: 12),
        if (_canCreateFromQuery)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: _creating ? null : () => unawaited(_createFromQuery()),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 20,
                      color: _creating ? _muted : _blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _creating
                            ? '创建中…'
                            : (_browsePath.isEmpty
                                ? '新建 ${_hashLabel(_queryKey)}'
                                : '在「${_browsePath.last.name}」下新建 ${_hashLabel(_queryKey)}'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _creating ? _muted : _blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_allTags.isEmpty)
          const Text(
            '还没有标签，可搜索新建',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
          )
        else if (!_allTags.any(_tagMatches) && !_canCreateFromQuery)
          Text(
            '没有「$_query」相关的标签',
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
          )
        else if (_queryKey.isNotEmpty)
          _buildSearchHits()
        else
          _buildBrowseLevel(),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_error!, style: const TextStyle(color: _muted)),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSelectedSection(),
        const SizedBox(height: 20),
        _buildMyTags(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxSheetHeight = media.size.height * 0.68;
    final safeBottom = media.padding.bottom;

    final tablet = AppOrientation.isTablet(context);
    final sheetRadius = tablet
        ? BorderRadius.circular(20)
        : const BorderRadius.vertical(top: Radius.circular(20));

    return Material(
      color: Colors.white,
      borderRadius: sheetRadius,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: maxSheetHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _handle,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTitleRow(),
                    const SizedBox(height: 12),
                    _buildSearchField(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n is ScrollStartNotification &&
                              n.dragDetails != null) {
                            _dismissSearchFocus();
                          }
                          return false;
                        },
                        child: GestureDetector(
                          onTap: _dismissSearchFocus,
                          behavior: HitTestBehavior.translucent,
                          child: SingleChildScrollView(
                            child: _buildBody(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        onPressed: _loading || _saving
                            ? null
                            : () {
                                _dismissSearchFocus();
                                unawaited(_save());
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _saving ? '保存中…' : '完成 ($_selectedCount)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12 + safeBottom),
          ],
        ),
      ),
    );
  }
}
