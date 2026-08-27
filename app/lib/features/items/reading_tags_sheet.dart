import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/core/ui/app_toast.dart';

enum ReadingTagsSheetResult { aiSuggest, createTag }

class _TagsSheetSession {
  final Set<int> selectedIds = {};
}

Future<ReadingTagsSheetResult?> showReadingTagsSheet(
  BuildContext context, {
  required int itemId,
  bool aiSuggestEnabled = true,
  bool aiSuggestPending = false,
  bool transcriptPending = false,
}) async {
  final session = _TagsSheetSession();

  while (true) {
    final result = await showModalBottomSheet<ReadingTagsSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x59000000),
      builder: (context) => _ReadingTagsSheet(
        itemId: itemId,
        session: session,
        aiSuggestEnabled: aiSuggestEnabled,
        aiSuggestPending: aiSuggestPending,
        transcriptPending: transcriptPending,
      ),
    );
    if (result != ReadingTagsSheetResult.createTag) {
      return result;
    }
    if (!context.mounted) return null;
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
    required this.aiSuggestEnabled,
    required this.aiSuggestPending,
    required this.transcriptPending,
  });

  final int itemId;
  final _TagsSheetSession session;
  final bool aiSuggestEnabled;
  final bool aiSuggestPending;
  final bool transcriptPending;

  @override
  State<_ReadingTagsSheet> createState() => _ReadingTagsSheetState();
}

class _ReadingTagsSheetState extends State<_ReadingTagsSheet> {
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
  final _searchOverlayController = OverlayPortalController(debugLabel: 'tagSearch');
  List<Tag> _all = const [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchOverlayController.hide();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _syncSearchOverlayVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showSearchOverlay) {
        _searchOverlayController.show();
      } else {
        _searchOverlayController.hide();
      }
    });
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _syncSearchOverlayVisibility();
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

  bool get _showSearchOverlay {
    final query = _searchController.text.trim();
    return query.isNotEmpty &&
        !_loading &&
        _error == null &&
        _all.isNotEmpty;
  }

  List<Tag> get _filteredTags {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _all
        .where((t) => t.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

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
      _syncSearchOverlayVisibility();
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
    if (widget.aiSuggestEnabled) {
      Navigator.pop(context, ReadingTagsSheetResult.aiSuggest);
      return;
    }
    AppToast.show(
      context,
      widget.transcriptPending
          ? '转写进行中，请稍候再生成标签建议'
          : widget.aiSuggestPending
              ? '标签建议生成中，请稍候'
              : '内容不足，无法生成标签建议',
    );
  }

  String get _aiSuggestButtonLabel {
    if (widget.transcriptPending) return '转写中…';
    if (widget.aiSuggestPending) return 'AI 生成中…';
    return 'AI 建议标签';
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
                size: 16,
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
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索标签',
        hintStyle: const TextStyle(fontSize: 15, color: _muted),
        prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 22),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: _muted, size: 20),
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

  Widget _buildSearchArea() {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _searchOverlayController,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: (context, info) {
        if (!_showSearchOverlay) return const SizedBox.shrink();

        final query = _searchController.text.trim();
        final filtered = _filteredTags;
        final targetRect = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );

        return SizedBox(
          width: info.overlaySize.width,
          height: info.overlaySize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: targetRect.left,
                width: info.childSize.width,
                bottom: info.overlaySize.height - targetRect.top + 8,
                child: _buildSearchOverlay(query, filtered),
              ),
            ],
          ),
        );
      },
      child: _buildSearchField(),
    );
  }

  Widget _buildSearchResultRow(Tag tag) {
    final on = _selected.contains(tag.id);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _toggleTag(tag.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tag.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _text,
                  ),
                ),
              ),
              if (on)
                const Icon(Icons.check_rounded, size: 20, color: _blue),
            ],
          ),
        ),
      ),
    );
  }

  static const _overlayMaxHeight = 200.0;

  Widget _buildSearchResultsList(List<Tag> filtered) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _overlayMaxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        primary: false,
        physics: const ClampingScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (context, _) =>
            const Divider(height: 1, color: Color(0xFFF0F2F5)),
        itemBuilder: (context, index) =>
            _buildSearchResultRow(filtered[index]),
      ),
    );
  }

  Widget _buildSearchOverlay(String query, List<Tag> filtered) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                  '没有「$query」相关的标签',
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
              '还没有标签，可点「新建」或使用 AI 建议',
              style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.none,
          borderRadius: BorderRadius.circular(24),
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
                        icon: Icons.auto_awesome_outlined,
                        label: _aiSuggestButtonLabel,
                        onTap: _onAiSuggest,
                        foreground:
                            widget.aiSuggestEnabled ? _blue : _muted,
                        borderColor: widget.aiSuggestEnabled
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
            Icon(icon, size: 12, color: foreground),
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
