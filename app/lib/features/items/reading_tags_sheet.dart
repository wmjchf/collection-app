import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

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
  static const _sectionMuted = Color(0xFF8B929C);
  static const _blue = Color(0xFF2F6FED);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _surface = Color(0xFFF3F6FA);
  static const _handle = Color(0xFFE5E8ED);

  final _modulesRepo = TagModulesRepository();
  final _tagsRepo = TagsRepository();
  final _itemsRepo = ItemsRepository();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  List<TagModule> _modules = const [];
  List<Tag> _ungrouped = const [];
  final Set<int> _selected = {};
  /// AI 建议名（生成后默认全选；可点掉）
  final Set<String> _aiSelected = {};
  bool _loading = true;
  bool _saving = false;
  bool _creating = false;
  String? _error;
  late AiTagsMeta _tagsMeta;
  Timer? _aiPollTimer;

  @override
  void initState() {
    super.initState();
    _tagsMeta = widget.initialTagsMeta;
    if (_tagsMeta.hasSuggestions) {
      _aiSelected.addAll(_tagsMeta.items.map((e) => e.name));
    }
    _load();
    if (_tagsMeta.isPending) {
      _startAiPoll();
    } else if (widget.autoStartAiSuggest && widget.aiSuggestEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_triggerAiSuggest());
      });
    }
  }

  void _syncTagsMeta(AiTagsMeta meta) {
    setState(() {
      _tagsMeta = meta;
      if (meta.hasSuggestions) {
        _aiSelected
          ..clear()
          ..addAll(meta.items.map((e) => e.name));
        for (final item in meta.items) {
          final id = item.existingTagId;
          if (id != null) _selected.add(id);
        }
      }
    });
    widget.onTagsMetaChanged?.call(meta);
  }

  void _startAiPoll() {
    _aiPollTimer?.cancel();
    _aiPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollAiOnce());
    });
  }

  Future<void> _pollAiOnce() async {
    if (!mounted) return;
    try {
      final st = await _itemsRepo.getAiSuggestStatus(widget.itemId);
      if (st.tags.isPending) {
        if (_tagsMeta.status != st.tags.status ||
            _tagsMeta.awaitTranscript != st.tags.awaitTranscript) {
          _syncTagsMeta(st.tags);
        }
        return;
      }
      _aiPollTimer?.cancel();
      _syncTagsMeta(st.tags);
    } catch (_) {}
  }

  Future<void> _triggerAiSuggest({bool force = false}) async {
    if (!_tagsMeta.isPending && !widget.aiSuggestEnabled) {
      _toastDisabledAi();
      return;
    }
    if (_tagsMeta.isPending) return;

    final needs = <PlanFeatureRequirement>[
      (has: (f) => f.aiTags, tier: UsagePlan.prince),
    ];
    if (widget.needsAutoTranscript) {
      needs.add((has: (f) => f.transcript, tier: UsagePlan.emperor));
    }
    final allowed = await ensurePlanFeatures(
      context,
      hasResultOrPending: _tagsMeta.hasSuggestions || _tagsMeta.isFailed,
      requirements: needs,
    );
    if (!allowed || !mounted) return;

    if (force || (_tagsMeta.isSuccess && _tagsMeta.hasSuggestions)) {
      force = true;
    }

    try {
      Analytics.instance.aiTagsRequest(
        itemId: widget.itemId,
        force: force,
      );
      final updated = await _itemsRepo.requestAiSuggest(
        widget.itemId,
        force: force,
      );
      if (!mounted) return;
      _syncTagsMeta(updated.aiMeta.tags);
      _startAiPoll();
    } on ApiException catch (e) {
      if (!mounted) return;
      await handleApiException(context, e);
    }
  }

  void _toastDisabledAi() {
    AppToast.show(
      context,
      widget.transcriptPending
          ? '转写进行中，请稍候再生成标签建议'
          : _tagsMeta.isPending
              ? '标签建议生成中，请稍候'
              : '内容不足，无法生成标签建议',
    );
  }

  @override
  void dispose() {
    _aiPollTimer?.cancel();
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
        _loading = false;
      });
      _syncSession();
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

  void _toggleAiSuggestion(AiTagSuggestion item) {
    _dismissSearchFocus();
    setState(() {
      if (_aiSelected.contains(item.name)) {
        _aiSelected.remove(item.name);
        final id = item.existingTagId;
        if (id != null) _selected.remove(id);
      } else {
        _aiSelected.add(item.name);
        final id = item.existingTagId;
        if (id != null) _selected.add(id);
      }
      _syncSession();
    });
  }

  Future<void> _createFromQuery() async {
    final name = _queryKey;
    if (name.isEmpty || _creating) return;
    setState(() => _creating = true);
    try {
      final created = await _tagsRepo.createTag(name);
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

  bool _isNewSuggestionName(String name) {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return false;
    return !_allTags.any((t) => t.name.toLowerCase() == key);
  }

  Widget _pill({
    required String label,
    required bool selected,
    VoidCallback? onTap,
    VoidCallback? onRemove,
    bool isNew = false,
  }) {
    final fg = selected ? Colors.white : _text;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 略放大但仍保证常见「三个四字标签」一排放下
        padding: EdgeInsets.fromLTRB(isNew ? 6 : 10, 7, onRemove != null ? 7 : 10, 7),
        decoration: BoxDecoration(
          color: selected ? _blue : _chipBg,
          borderRadius: BorderRadius.circular(999),
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
    return Row(
      children: [
        const Expanded(
          child: Text(
            '选择标签',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text(
            '关闭',
            style: TextStyle(fontSize: 14, color: _muted),
          ),
        ),
      ],
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
        Row(
          children: [
            const Text(
              '已选标签',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const Spacer(),
            Text(
              '$_selectedCount',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
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
        const SizedBox(height: 14),
        _buildAiRecommendBlock(),
      ],
    );
  }

  Widget _buildAiRecommendBlock() {
    final meta = _tagsMeta;
    final enabled = widget.aiSuggestEnabled || meta.isPending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: !enabled
                    ? _toastDisabledAi
                    : meta.isPending
                        ? null
                        : () => unawaited(
                              _triggerAiSuggest(
                                force: meta.hasSuggestions || meta.isFailed,
                              ),
                            ),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _chipBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE8ECF0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 16,
                        color: enabled ? _blue : _muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        meta.isPending
                            ? (meta.awaitTranscript ? '转写中…' : '生成中…')
                            : meta.hasSuggestions || meta.isFailed
                                ? '重新推荐'
                                : 'AI 推荐',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: enabled ? _blue : _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '点击生成 AI 推荐标签，生成后默认为选择，可点击相应标签取消选择',
                style: TextStyle(
                  fontSize: 12,
                  color: _muted,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        if (meta.isPending) ...[
          const SizedBox(height: 10),
          const Text(
            '正在生成推荐…',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ] else if (meta.isFailed) ...[
          const SizedBox(height: 10),
          Text(
            (meta.error ?? '').trim().isEmpty
                ? '推荐生成失败，可重试'
                : '推荐失败：${meta.error}',
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
          ),
        ] else if (meta.isEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            '暂无新的推荐',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ] else if (meta.hasSuggestions) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              for (final item in meta.items)
                _pill(
                  label: item.name,
                  selected: _aiSelected.contains(item.name),
                  isNew: item.existingTagId == null &&
                      _isNewSuggestionName(item.name),
                  onTap: () => _toggleAiSuggestion(item),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildModuleSection({
    required String title,
    required List<Tag> tags,
  }) {
    final visible = tags.where(_tagMatches).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _sectionMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              for (final tag in visible)
                _pill(
                  label: tag.name,
                  selected: _selected.contains(tag.id),
                  onTap: () => _toggleTag(tag.id),
                ),
            ],
          ),
        ],
      ),
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
                            : '新建 ${_hashLabel(_queryKey)}',
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
            '还没有标签，可搜索新建或使用 AI 推荐',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
          )
        else if (!_allTags.any(_tagMatches) && !_canCreateFromQuery)
          Text(
            '没有「$_query」相关的标签',
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
          )
        else ...[
          _buildModuleSection(title: '未归类', tags: _ungrouped),
          for (final m in _modules)
            _buildModuleSection(title: m.name, tags: m.tags),
        ],
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
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: maxSheetHeight,
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
              const SizedBox(height: 12),
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
    );
  }
}
