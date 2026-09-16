import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

enum ReadingTagsSheetResult { createTag }

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

  while (true) {
    if (!context.mounted) return;
    final result = await showModalBottomSheet<ReadingTagsSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x59000000),
      useSafeArea: false,
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
    if (result != ReadingTagsSheetResult.createTag) {
      return;
    }
    if (!context.mounted) return;
    final created = await showCreateTagSheet(context);
    if (created != null) {
      session.selectedIds.add(created.id);
    }
  }
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
  static const _ungroupedTag = Color(0xFF5C6675);
  static const _ungroupedTagSoft = Color(0xFFECEEF2);
  static const _handle = Color(0xFFE5E8ED);

  final _modulesRepo = TagModulesRepository();
  final _itemsRepo = ItemsRepository();
  final _searchController = TextEditingController();
  List<TagModule> _modules = const [];
  List<Tag> _ungrouped = const [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late AiTagsMeta _tagsMeta;
  final _aiSelected = <String>{};
  bool _aiApplying = false;
  Timer? _aiPollTimer;

  @override
  void initState() {
    super.initState();
    _tagsMeta = widget.initialTagsMeta;
    _aiSelected.addAll(_tagsMeta.items.map((e) => e.name));
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
    } catch (_) {
      // ignore poll errors
    }
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

  Future<void> _applyAiSelected() async {
    if (_aiApplying || _aiSelected.isEmpty) return;
    setState(() => _aiApplying = true);
    try {
      final updated = await _itemsRepo.applyAiSuggest(
        widget.itemId,
        _aiSelected.toList(),
      );
      Analytics.instance.aiTagsApply(
        itemId: widget.itemId,
        count: _aiSelected.length,
      );
      if (!mounted) return;
      _syncTagsMeta(updated.aiMeta.tags);

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
          ..addAll(current.map((t) => t.id));
      });

      if (!mounted) return;
      AppToast.show(context, '已采纳标签');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } finally {
      if (mounted) setState(() => _aiApplying = false);
    }
  }

  Future<void> _dismissAi() async {
    try {
      final updated = await _itemsRepo.dismissAiSuggest(widget.itemId);
      if (!mounted) return;
      _syncTagsMeta(updated.aiMeta.tags);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
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
    super.dispose();
  }

  String get _query => _searchController.text.trim().toLowerCase();

  bool _tagMatches(Tag tag) {
    final q = _query;
    if (q.isEmpty) return true;
    return tag.name.toLowerCase().contains(q);
  }

  List<Tag> get _allTags => [
        ..._ungrouped,
        for (final m in _modules) ...m.tags,
      ];

  List<Tag> get _selectedTags {
    final byId = {for (final t in _allTags) t.id: t};
    final tags = [
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
    ];
    tags.sort((a, b) => a.name.compareTo(b.name));
    return tags;
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

  void _createTag() {
    _syncSession();
    Navigator.pop(context, ReadingTagsSheetResult.createTag);
  }

  void _toggleTag(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
      _syncSession();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _itemsRepo.setItemTags(widget.itemId, _selected.toList());
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

  void _onAiSuggest() {
    unawaited(_triggerAiSuggest());
  }

  String get _aiSuggestButtonLabel {
    if (widget.transcriptPending) return '转写中…';
    if (_tagsMeta.isPending) return 'AI 生成中…';
    return 'AI 建议标签';
  }

  bool get _aiSuggestTapEnabled =>
      widget.aiSuggestEnabled || _tagsMeta.isPending;

  Widget _buildAiSuggestSection() {
    final meta = _tagsMeta;
    if (meta.status == 'none' || meta.status == 'skipped') {
      return const SizedBox.shrink();
    }

    if (meta.isPending) {
      final title = meta.awaitTranscript
          ? '正在转写，完成后生成标签建议…'
          : '正在生成标签建议…';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _blue.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: _muted),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (meta.isFailed) {
      final err = (meta.error ?? '').trim();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                err.isEmpty ? '标签建议生成失败' : '标签建议失败：$err',
                style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => unawaited(_triggerAiSuggest(force: true)),
                child: const Text(
                  '重试',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (meta.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI 建议标签',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '本篇标签已较完整，暂无新的建议',
                style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => unawaited(_dismissAi()),
                child: const Text(
                  '知道了',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!meta.hasSuggestions) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI 建议标签',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in meta.items)
                  GestureDetector(
                    onTap: _aiApplying
                        ? null
                        : () => setState(() {
                              if (_aiSelected.contains(item.name)) {
                                _aiSelected.remove(item.name);
                              } else {
                                _aiSelected.add(item.name);
                              }
                            }),
                    child: _AiSuggestChip(
                      label: item.name,
                      isExisting: item.existingTagId != null,
                      selected: _aiSelected.contains(item.name),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: _aiApplying || _aiSelected.isEmpty
                      ? null
                      : () => unawaited(_applyAiSelected()),
                  child: Text(
                    _aiApplying ? '采纳中…' : '采纳所选',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _aiSelected.isEmpty || _aiApplying
                          ? _muted
                          : _blue,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _aiApplying ? null : () => unawaited(_dismissAi()),
                  child: const Text(
                    '忽略',
                    style: TextStyle(fontSize: 14, color: _muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '带 ＋ 为新建建议，其余为已有标签（可复用）',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  static String _hashLabel(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  Widget _tagChip(
    Tag tag, {
    VoidCallback? onRemove,
    bool muted = false,
  }) {
    final on = _selected.contains(tag.id);
    final Color fg;
    final Color bg;
    if (on) {
      fg = Colors.white;
      bg = _blue;
    } else if (muted) {
      fg = _ungroupedTag;
      bg = _ungroupedTagSoft;
    } else {
      fg = _blue;
      bg = _chipBg;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _hashLabel(tag.name),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: fg,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: on ? Colors.white : _muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索标签',
        hintStyle: const TextStyle(fontSize: 15, color: _muted),
        prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 24),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: _muted, size: 22),
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: _chipBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
          borderSide: const BorderSide(color: Color(0xFFB8CCFA), width: 1),
        ),
      ),
    );
  }

  Widget _buildSelectableChip(Tag tag, {bool muted = false}) {
    return GestureDetector(
      onTap: () => _toggleTag(tag.id),
      behavior: HitTestBehavior.opaque,
      child: _tagChip(tag, muted: muted),
    );
  }

  Widget _buildModuleSection({
    required String title,
    required List<Tag> tags,
    bool muted = false,
  }) {
    final visible = tags.where(_tagMatches).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                if (muted) ...[
                  const Icon(
                    Icons.inbox_outlined,
                    size: 16,
                    color: _sectionMuted,
                  ),
                  const SizedBox(width: 6),
                ] else
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: _blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: muted ? 0.2 : 0.4,
                      color: muted
                          ? _sectionMuted
                          : _text.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in visible)
                _buildSelectableChip(tag, muted: muted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedTags() {
    if (_allTags.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text(
          '还没有标签，可点「新建」或使用 AI 建议',
          style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
        ),
      );
    }

    final hasMatch = _allTags.any(_tagMatches);
    if (!hasMatch) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '没有「${_searchController.text.trim()}」相关的标签',
          style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildModuleSection(
          title: '未归类',
          tags: _ungrouped,
          muted: true,
        ),
        for (final m in _modules)
          _buildModuleSection(
            title: m.name,
            tags: m.tags,
          ),
      ],
    );
  }

  Widget _buildSelectedTagsRow(List<Tag> selected) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        primary: false,
        physics: const ClampingScrollPhysics(),
        itemCount: selected.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tag = selected[index];
          final muted = tag.moduleId == null;
          return _tagChip(
            tag,
            muted: muted,
            onRemove: () => _toggleTag(tag.id),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_error!, style: const TextStyle(color: _muted)),
      );
    }

    final selected = _selectedTags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAiSuggestSection(),
        if (selected.isNotEmpty) ...[
          const Text(
            '已选',
            style: TextStyle(fontSize: 12, color: _muted, height: 1.2),
          ),
          const SizedBox(height: 8),
          _buildSelectedTagsRow(selected),
          const SizedBox(height: 12),
        ],
        _buildSearchField(),
        const SizedBox(height: 12),
        _buildGroupedTags(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;
    final bottomInset = 16 +
        MediaQuery.paddingOf(context).bottom +
        MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomInset,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        '选择标签',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _HeaderActionButton(
                        icon: Icons.tips_and_updates_outlined,
                        label: _aiSuggestButtonLabel,
                        onTap: _aiSuggestTapEnabled
                            ? _onAiSuggest
                            : _toastDisabledAi,
                        foreground:
                            _aiSuggestTapEnabled ? _blue : _muted,
                        borderColor: _aiSuggestTapEnabled
                            ? const Color(0xFFB8CCFA)
                            : const Color(0xFFE8ECF0),
                      ),
                      const SizedBox(width: 6),
                      _HeaderActionButton(
                        icon: Icons.add,
                        label: '新建',
                        onTap: _createTag,
                        foreground: _text,
                        borderColor: const Color(0xFFE8ECF0),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          '关闭',
                          style: TextStyle(
                            fontSize: 14,
                            color: _muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildBody(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading || _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_saving ? '保存中…' : '完成'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.foreground,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color foreground;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiSuggestChip extends StatelessWidget {
  const _AiSuggestChip({
    required this.label,
    required this.isExisting,
    required this.selected,
  });

  final String label;
  final bool isExisting;
  final bool selected;

  static const _chipOn = Color(0xFFE5EDFF);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _chipNewBorder = Color(0xFFD9DBE0);
  static const _brand = Color(0xFF2F6FED);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? _chipOn
        : (isExisting ? _chipBg : Colors.white);
    final fg = selected ? _brand : _text;
    final borderColor = selected
        ? _chipOn
        : (isExisting ? _chipBg : _chipNewBorder);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (!isExisting)
              const TextSpan(
                text: '＋ ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
