import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/quota_gate.dart';

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
  void Function(AiTagsMeta tagsMeta)? onTagsMetaChanged,
}) async {
  final session = _TagsSheetSession();

  await showAppBottomSheet<void>(
    context: context,
    builder: (context) => _ReadingTagsSheet(
      itemId: itemId,
      session: session,
      initialTagsMeta: tagsMeta,
      aiSuggestEnabled: aiSuggestEnabled,
      transcriptPending: transcriptPending,
      autoStartAiSuggest: autoStartAiSuggest,
      onTagsMetaChanged: onTagsMetaChanged,
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
    this.onTagsMetaChanged,
  });

  final int itemId;
  final _TagsSheetSession session;
  final AiTagsMeta initialTagsMeta;
  final bool aiSuggestEnabled;
  final bool transcriptPending;
  final bool autoStartAiSuggest;
  final void Function(AiTagsMeta tagsMeta)? onTagsMetaChanged;

  @override
  State<_ReadingTagsSheet> createState() => _ReadingTagsSheetState();
}

class _ReadingTagsSheetState extends State<_ReadingTagsSheet> {
  static final Object _searchTapGroup = Object();

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _chipOn = Color(0xFFE5EDFF);
  static const _handle = Color(0xFFE5E8ED);

  final _tagsRepo = TagsRepository();
  final _itemsRepo = ItemsRepository();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchFieldKey = GlobalKey();
  final _layerLink = LayerLink();
  final _overlayPortal = OverlayPortalController();
  double _fieldWidth = 0;
  List<Tag> _all = const [];
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
    _searchFocus.addListener(_onSearchFocusChanged);
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

      final all = await _tagsRepo.listTags();
      final current = await _itemsRepo.listItemTags(widget.itemId);
      if (!mounted) return;
      setState(() {
        _all = all.where((t) => !t.isSystem).toList();
        _selected
          ..clear()
          ..addAll(current.map((t) => t.id));
      });
      _syncSession();

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

  void _unfocusSearch() {
    _searchFocus.unfocus();
  }

  void _onSearchFocusChanged() {
    if (_searchFocus.hasFocus) {
      _overlayPortal.show();
      _scheduleSyncFieldWidth();
    } else {
      _overlayPortal.hide();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _aiPollTimer?.cancel();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _scheduleSyncFieldWidth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFieldWidth();
    });
  }

  void _syncFieldWidth() {
    final box =
        _searchFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final w = box.size.width;
    if ((_fieldWidth - w).abs() < 0.5) return;
    setState(() => _fieldWidth = w);
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _scheduleSyncFieldWidth();
  }

  List<Tag> get _selectedTags {
    final byId = {for (final t in _all) t.id: t};
    final tags = [
      for (final id in _selected)
        if (byId[id] != null) byId[id]!,
    ];
    tags.sort((a, b) => a.name.compareTo(b.name));
    return tags;
  }

  List<Tag> get _filteredTags {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return flattenTagsForDisplay(_all);

    // 命中项 + 祖先，保持树形可读
    final byId = {for (final t in _all) t.id: t};
    final keep = <int>{};
    for (final t in _all) {
      if (!t.name.toLowerCase().contains(q)) continue;
      keep.add(t.id);
      var cur = t.parentId;
      while (cur != null && keep.add(cur)) {
        cur = byId[cur]?.parentId;
      }
    }
    final subset = [for (final t in _all) if (keep.contains(t.id)) t];
    return flattenTagsForDisplay(subset);
  }

  Map<int, Tag> get _tagById => {for (final t in _all) t.id: t};

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _tagsRepo.listTags();
      final current = await _itemsRepo.listItemTags(widget.itemId);
      if (!mounted) return;
      setState(() {
        _all = all.where((t) => !t.isSystem).toList();
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
      _scheduleSyncFieldWidth();
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

  /// 建议 chip 只用短名；已有项靠「无 ＋」区分，路径不进展示。
  String _aiSuggestDisplayLabel(AiTagSuggestion item) => item.name;

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
                      label: _aiSuggestDisplayLabel(item),
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
              '按内容建议；优先复用已有标签。采纳后自动关联父级。带 ＋ 为新建建议。',
              style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
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

  Widget _tagChip(Tag tag, {VoidCallback? onRemove}) {
    final on = _selected.contains(tag.id);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: on ? _chipOn : _chipBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tag.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: on ? _blue : _text,
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
                color: on ? _blue : _muted,
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
      focusNode: _searchFocus,
      onChanged: _onSearchChanged,
      onSubmitted: (_) => _unfocusSearch(),
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
                  _onSearchChanged('');
                },
              ),
        filled: true,
        fillColor: _chipBg,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFB8CCFA), width: 1),
        ),
      ),
    );
  }

  static const _searchFieldHeight = 48.0;
  static const _overlayGap = 8.0;

  Widget _buildSearchArea() {
    return OverlayPortal(
      controller: _overlayPortal,
      overlayChildBuilder: (context) {
        final query = _searchController.text.trim();
        final filtered = _filteredTags;
        final width = _fieldWidth > 0 ? _fieldWidth : 280.0;
        // Overlay 默认给最大约束，白底 Container 会被撑满全屏；必须松约束
        return UnconstrainedBox(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(0, -_overlayGap),
            child: SizedBox(
              width: width,
              child: TapRegion(
                groupId: _searchTapGroup,
                onTapOutside: (_) => _unfocusSearch(),
                child: Material(
                  type: MaterialType.transparency,
                  child: _buildSearchOverlay(query, filtered),
                ),
              ),
            ),
          ),
        );
      },
      child: TapRegion(
        groupId: _searchTapGroup,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: SizedBox(
            key: _searchFieldKey,
            height: _searchFieldHeight,
            width: double.infinity,
            child: _buildSearchField(),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResultRow(Tag tag) {
    final on = _selected.contains(tag.id);
    final depth = tagDepth(tag, _tagById);
    final isNested = depth > 0;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _toggleTag(tag.id),
        child: Padding(
          padding: EdgeInsets.only(
            left: 14.0 + depth * 16.0,
            right: 14,
            top: 12,
            bottom: 12,
          ),
          child: Row(
            children: [
              if (isNested)
                Container(
                  width: 2,
                  height: 16,
                  margin: const EdgeInsets.only(right: 8),
                  color: const Color(0xFFE5E8ED),
                ),
              Expanded(
                child: Text(
                  '#${tag.name}',
                  style: TextStyle(
                    fontSize: isNested ? 14 : 15,
                    fontWeight: isNested ? FontWeight.w400 : FontWeight.w500,
                    color: _text,
                  ),
                ),
              ),
              if (on)
                const Icon(Icons.check_rounded, size: 22, color: _blue),
            ],
          ),
        ),
      ),
    );
  }

  static const _overlayMaxHeight = 200.0;
  static const _overlayRowHeight = 45.0;

  double _overlayListHeight(int count) {
    if (count <= 0) return 0;
    final natural = count * _overlayRowHeight + (count - 1);
    return natural > _overlayMaxHeight ? _overlayMaxHeight : natural;
  }

  Widget _buildSearchResultsList(List<Tag> filtered) {
    final height = _overlayListHeight(filtered.length);
    final scrollable = filtered.length * _overlayRowHeight + (filtered.length - 1) >
        _overlayMaxHeight;
    final byId = _tagById;

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        primary: false,
        shrinkWrap: !scrollable,
        physics: scrollable
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (context, index) {
          final depth = tagDepth(filtered[index], byId);
          return Divider(
            height: 1,
            indent: 14.0 + depth * 16.0,
            endIndent: 12,
            color: const Color(0xFFF0F2F5),
          );
        },
        itemBuilder: (context, index) =>
            _buildSearchResultRow(filtered[index]),
      ),
    );
  }

  Widget _buildSearchOverlay(String query, List<Tag> filtered) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        // 浮在白底 sheet 上：用四周阴影区分，不加深描边
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1F242E).withValues(alpha: 0.16),
            blurRadius: 20,
            spreadRadius: 0,
            offset: Offset.zero,
          ),
          BoxShadow(
            color: const Color(0xFF1F242E).withValues(alpha: 0.10),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: filtered.isEmpty
            ? Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                child: Text(
                  query.isEmpty ? '暂无标签' : '没有「$query」相关的标签',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
              )
            : _buildSearchResultsList(filtered),
      ),
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
          return _tagChip(
            tag,
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
        _buildSearchArea(),
        if (_all.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '还没有标签，请先在「我的标签」中新建',
              style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;
    if (_searchFocus.hasFocus) {
      _scheduleSyncFieldWidth();
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                    foreground: _aiSuggestTapEnabled ? _blue : _muted,
                    borderColor: _aiSuggestTapEnabled
                        ? const Color(0xFFB8CCFA)
                        : const Color(0xFFE8ECF0),
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
              _buildBody(),
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
