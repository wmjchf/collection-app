import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/agent/agent_markdown.dart';
import 'package:super_collection/features/items/annotation_note_style.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_thoughts.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_thought_edit_page.dart';
import 'package:super_collection/features/items/reading_wiki_relate_sheet.dart';

enum ReadingNotesFilter {
  highlight,
  annotation,
  thought,
  article,
}

class ReadingItemNotesResult {
  const ReadingItemNotesResult({
    this.item,
    this.annotations,
    this.locateAnnotation,
  });

  final CollectionItem? item;
  final List<ItemAnnotation>? annotations;
  final ItemAnnotation? locateAnnotation;
}

/// 阅读页「笔记」：汇入高亮 / 批注，原感想改为「想法」。
/// 手机全屏页；iPad 保持居中浮卡 sheet。
Future<ReadingItemNotesResult?> showReadingItemNotesSheet(
  BuildContext context, {
  required int itemId,
  required List<ItemAnnotation> annotations,
  String? initialNote,
  /// 视频 / 图集才展示「文章」
  bool showArticleFilter = false,
  bool isPro = false,
  ReadingNotesFilter? initialFilter,
}) {
  final page = _ReadingItemNotesSheet(
    itemId: itemId,
    annotations: annotations,
    initialNote: initialNote,
    showArticleFilter: showArticleFilter,
    isPro: isPro,
    initialFilter: initialFilter,
    fullScreen: !AppOrientation.isTablet(context),
  );
  if (AppOrientation.isTablet(context)) {
    return showAppBottomSheet<ReadingItemNotesResult>(
      context: context,
      padding: EdgeInsets.zero,
      includeSafeArea: false,
      builder: (context) => page,
    );
  }
  return Navigator.of(context).push<ReadingItemNotesResult>(
    MaterialPageRoute(builder: (_) => page),
  );
}

class _ReadingItemNotesSheet extends StatefulWidget {
  const _ReadingItemNotesSheet({
    required this.itemId,
    required this.annotations,
    this.initialNote,
    this.showArticleFilter = false,
    this.isPro = false,
    this.initialFilter,
    this.fullScreen = false,
  });

  final int itemId;
  final List<ItemAnnotation> annotations;
  final String? initialNote;
  final bool showArticleFilter;
  final bool isPro;
  final ReadingNotesFilter? initialFilter;
  /// 手机全屏；iPad sheet 为 false
  final bool fullScreen;

  @override
  State<_ReadingItemNotesSheet> createState() => _ReadingItemNotesSheetState();
}

class _ReadingItemNotesSheetState extends State<_ReadingItemNotesSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _pageBg = Colors.white;
  static const _chipIdle = Color(0xFFF5F7FA);
  static const _yellowBar = Color(0xFFE8B84A);
  /// 想法竖线（区别于高亮黄 / 批注蓝）
  static const _thoughtBar = Color(0xFF2FA88A);
  static const _noteBubble = Color(0xFFEAF1FF);
  static const _handle = Color(0xFFE5E8ED);

  final _repo = ItemsRepository();
  late List<ItemAnnotation> _annotations;
  late List<ItemThought> _thoughts;
  late ReadingNotesFilter _filter;
  CollectionItem? _updatedItem;
  bool _saving = false;
  bool _dirtyAnns = false;
  /// iPad：想法嵌在本浮卡内，避免叠第二层弹框。
  ItemThought? _embeddedThought;
  bool _embeddedThoughtOpen = false;
  Completer<ThoughtEditResult?>? _embeddedThoughtCompleter;

  List<ItemAnnotation> get _highlights =>
      _annotations.where((a) => !AnnotationNoteStyle.hasNote(a)).toList();

  List<ItemAnnotation> get _notes =>
      _annotations.where(AnnotationNoteStyle.hasNote).toList();

  /// 想法筛：手写想法 + 存量 AI 摘录（只读，不再单独成筛）
  List<ItemThought> get _thoughtTabItems => _thoughts
      .where((t) => t.isThought || t.isExcerpt)
      .toList();

  List<ItemThought> get _articles =>
      _thoughts.where((t) => t.isArticle).toList();

  bool get _showArticle => widget.showArticleFilter;

  int get _allCount =>
      _highlights.length +
      _notes.length +
      _thoughtTabItems.length +
      (_showArticle ? _articles.length : 0);

  bool _isFilterVisible(ReadingNotesFilter f) {
    switch (f) {
      case ReadingNotesFilter.article:
        return _showArticle;
      default:
        return true;
    }
  }

  /// 打开笔记始终落在第一个筛（高亮）；不按「谁有内容」跳转。
  ReadingNotesFilter _defaultFilter() => ReadingNotesFilter.highlight;

  @override
  void initState() {
    super.initState();
    _annotations = List<ItemAnnotation>.from(widget.annotations);
    _thoughts = parseItemThoughts(widget.initialNote);
    final initial = widget.initialFilter;
    _filter = (initial != null && _isFilterVisible(initial))
        ? initial
        : _defaultFilter();
  }

  @override
  void dispose() {
    final c = _embeddedThoughtCompleter;
    if (c != null && !c.isCompleted) c.complete(null);
    super.dispose();
  }

  void _pop({ItemAnnotation? locate}) {
    Navigator.pop(
      context,
      ReadingItemNotesResult(
        item: _updatedItem,
        annotations: _dirtyAnns ? _annotations : null,
        locateAnnotation: locate,
      ),
    );
  }

  Future<void> _persistThoughts(List<ItemThought> next) async {
    final payload = serializeItemThoughts(next);
    final item = await _repo.updateNote(widget.itemId, payload);
    if (!mounted) return;
    setState(() {
      _thoughts = List<ItemThought>.from(next);
      _updatedItem = item;
      _saving = false;
    });
  }

  Future<void> _openThoughtEditor({ItemThought? thought}) async {
    if (_saving) return;
    if (thought != null && !thought.isThought) return;
    if (_embeddedThoughtOpen) return;
    setState(() => _filter = ReadingNotesFilter.thought);

    final ThoughtEditResult? result;
    if (AppOrientation.isTablet(context)) {
      // 同一张笔记浮卡内打开，不另叠居中弹框
      final completer = Completer<ThoughtEditResult?>();
      setState(() {
        _embeddedThought = thought;
        _embeddedThoughtOpen = true;
        _embeddedThoughtCompleter = completer;
      });
      result = await completer.future;
      if (mounted) {
        setState(() {
          _embeddedThoughtOpen = false;
          _embeddedThought = null;
          _embeddedThoughtCompleter = null;
        });
      }
    } else {
      result = await showReadingThoughtEditPage(
        context,
        initialTitle: thought?.title ?? '',
        initialText: thought?.text ?? '',
        initialFormat: thought?.format ?? ItemNoteFormat.plain,
        initialMode: thought == null
            ? ThoughtPageMode.editing
            : ThoughtPageMode.reading,
        relateItemId: widget.itemId,
        repository: _repo,
        canDelete: thought != null,
      );
    }
    if (!mounted || result == null) return;
    if (result.deleted) {
      if (thought == null) return;
      setState(() => _saving = true);
      try {
        final next = _thoughts.where((t) => t.id != thought.id).toList();
        await _persistThoughts(next);
        if (!mounted) return;
        setState(() => _filter = ReadingNotesFilter.thought);
        AppToast.show(context, '已删除');
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        AppToast.show(context, e.message);
      } catch (_) {
        if (!mounted) return;
        setState(() => _saving = false);
        AppToast.show(context, '删除失败');
      }
      return;
    }
    final trimmed = result.text.trim();
    if (trimmed.isEmpty) return;
    final title = result.title.trim();
    setState(() => _saving = true);
    try {
      final List<ItemThought> next;
      if (thought != null) {
        next = [
          for (final t in _thoughts)
            if (t.id == thought.id)
              t.copyWith(
                text: trimmed,
                title: title,
                format: result.format,
                clearTitle: title.isEmpty,
              )
            else
              t,
        ];
      } else {
        next = [
          ..._thoughts,
          newItemThought(trimmed, title: title, format: result.format),
        ];
      }
      await _persistThoughts(next);
      if (!mounted) return;
      setState(() => _filter = ReadingNotesFilter.thought);
      AppToast.show(
        context,
        thought == null ? '想法已保存' : '想法已更新',
      );
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

  void _setFilter(ReadingNotesFilter next) {
    if (_filter == next) return;
    setState(() => _filter = next);
  }

  Widget _chip({
    required String label,
    int? count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final text = count == null ? label : '$label $count';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F0FF) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _blue.withValues(alpha: 0.35) : const Color(0xFFE6E8ED),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? _blue : _muted,
          ),
        ),
      ),
    );
  }

  Future<void> _onWikiRelate(String text, VoidCallback clearSelection) async {
    final selected = text.trim();
    clearSelection();
    if (selected.isEmpty || !mounted) return;
    await showReadingWikiRelateSheet(
      context,
      selectedText: selected,
      excludeItemId: widget.itemId,
      repository: _repo,
    );
  }

  /// 划选工具条：关联 / 复制（与阅读页口径一致）。
  Widget _notesSelectionToolbar({
    required TextSelectionToolbarAnchors anchors,
    required String selected,
    required VoidCallback clearSelection,
  }) {
    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (context, child) {
        return Material(
          color: const Color(0xFF1F242E),
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          child: child,
        );
      },
      children: [
        _NotesToolbarAction(
          label: '关联',
          onTap: () => unawaited(_onWikiRelate(selected, clearSelection)),
        ),
        _NotesToolbarAction(
          label: '复制',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: selected));
            clearSelection();
            if (mounted) AppToast.show(context, '已复制');
          },
        ),
      ],
    );
  }

  EditableTextContextMenuBuilder get _selectableContextMenu {
    return (context, state) {
      final value = state.textEditingValue;
      final sel = value.selection;
      if (!sel.isValid || sel.isCollapsed) {
        return const SizedBox.shrink();
      }
      final selected = sel.textInside(value.text);
      if (selected.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      final anchors = state.contextMenuAnchors;
      return _notesSelectionToolbar(
        anchors: anchors,
        selected: selected,
        clearSelection: () {
          ContextMenuController.removeAny();
          state.hideToolbar();
          state.userUpdateTextEditingValue(
            value.copyWith(
              selection: TextSelection.collapsed(offset: sel.end),
            ),
            SelectionChangedCause.toolbar,
          );
        },
      );
    };
  }

  AgentSelectionMenuBuilder get _markdownSelectionMenu {
    return (context, anchors, selected, clearSelection) {
      return _notesSelectionToolbar(
        anchors: anchors,
        selected: selected,
        clearSelection: clearSelection,
      );
    };
  }

  Widget _selectablePlain(
    String text, {
    TextStyle? style,
    int? maxLines,
  }) {
    return SelectableText(
      text,
      style: style,
      maxLines: maxLines,
      contextMenuBuilder: _selectableContextMenu,
    );
  }

  /// 每条独立白卡（无分享 / 删除；划选工具条可关联、复制）。
  Widget _itemCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EB)),
      ),
      child: child,
    );
  }

  Widget _quoteRow({
    required Color barColor,
    required String text,
    VoidCallback? onBarTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onBarTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _selectablePlain(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: _text,
            ),
          ),
        ),
      ],
    );
  }

  Widget _annotationBlock(ItemAnnotation ann) {
    final quote = ann.selectedText.trim();
    final note = (ann.note ?? '').trim();
    return _itemCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _quoteRow(
            barColor: _blue,
            text: quote,
            onBarTap: () => _pop(locate: ann),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: _noteBubble,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _selectablePlain(
                note,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: _text,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thoughtBlock(ItemThought thought) {
    final Widget body;
    if (thought.isThought) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thought.displayTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: _text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            thought.text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: _text,
            ),
          ),
        ],
      );
    } else if (thought.isArticle) {
      // 助手成文：按 Markdown 渲染；可划选关联
      body = AgentMarkdown(
        thought.text,
        selectionMenuBuilder: _markdownSelectionMenu,
      );
    } else {
      body = _selectablePlain(
        thought.text,
        style: const TextStyle(
          fontSize: 15,
          height: 1.55,
          color: _text,
        ),
      );
    }
    // 想法：整卡点进详情，到里面划选关联；摘录 / 文章在列表划选
    final content = thought.isThought
        ? GestureDetector(
            onTap: () => unawaited(_openThoughtEditor(thought: thought)),
            behavior: HitTestBehavior.opaque,
            child: body,
          )
        : body;
    final withBar = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 18,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: _thoughtBar,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: content),
      ],
    );
    return _itemCard(child: withBar);
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 36,
            color: _muted.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无数据',
            style: TextStyle(
              fontSize: 14,
              color: _muted.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// 当前筛选项内容；空则返回 null（由外层垂直居中空态）。
  List<Widget>? _buildContent() {
    if (_allCount == 0) return null;

    final showHi = _filter == ReadingNotesFilter.highlight;
    final showAnn = _filter == ReadingNotesFilter.annotation;
    final showThought = _filter == ReadingNotesFilter.thought;
    final showArticle = _filter == ReadingNotesFilter.article;

    final out = <Widget>[];
    if (showHi && _highlights.isNotEmpty) {
      for (final a in _highlights) {
        final text = a.selectedText.trim();
        out.add(
          _itemCard(
            child: _quoteRow(
              barColor: _yellowBar,
              text: text,
              onBarTap: () => _pop(locate: a),
            ),
          ),
        );
      }
    }
    if (showAnn && _notes.isNotEmpty) {
      for (final a in _notes) {
        out.add(_annotationBlock(a));
      }
    }
    if (showThought && _thoughtTabItems.isNotEmpty) {
      for (final t in _thoughtTabItems) {
        out.add(_thoughtBlock(t));
      }
    }
    if (showArticle && _articles.isNotEmpty) {
      for (final t in _articles) {
        out.add(_thoughtBlock(t));
      }
    }

    return out.isEmpty ? null : out;
  }

  Widget _thoughtComposerAffordance() {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          10 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Material(
          color: _chipIdle,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: _saving ? null : () => unawaited(_openThoughtEditor()),
            borderRadius: BorderRadius.circular(18),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 16, 14, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '写下你的想法…',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip(
            label: '高亮',
            count: _highlights.length,
            selected: _filter == ReadingNotesFilter.highlight,
            onTap: () => _setFilter(ReadingNotesFilter.highlight),
          ),
          const SizedBox(width: 8),
          _chip(
            label: widget.isPro ? '朱批' : '批注',
            count: _notes.length,
            selected: _filter == ReadingNotesFilter.annotation,
            onTap: () => _setFilter(ReadingNotesFilter.annotation),
          ),
          const SizedBox(width: 8),
          _chip(
            label: '想法',
            count: _thoughtTabItems.length,
            selected: _filter == ReadingNotesFilter.thought,
            onTap: () => _setFilter(ReadingNotesFilter.thought),
          ),
          if (_showArticle) ...[
            const SizedBox(width: 8),
            _chip(
              label: '文章',
              selected: _filter == ReadingNotesFilter.article,
              onTap: () => _setFilter(ReadingNotesFilter.article),
            ),
          ],
        ],
      ),
    );
  }

  /// 笔记列表壳（筛选项 + 列表）；iPad sheet / 手机全屏共用。
  Widget _buildNotesChrome({required bool fullScreen}) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Column(
      children: [
        if (!fullScreen) ...[
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '这篇的笔记',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '划线、批注与整理文章，也可写想法',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => _pop(),
                  icon: const Icon(Icons.close, size: 22, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '划线、批注与整理文章，也可写想法',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: _muted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _filterChips(),
        const SizedBox(height: 12),
        Expanded(
          child: Builder(
            builder: (context) {
              final content = _buildContent();
              if (content == null) return _emptyState();
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  _filter == ReadingNotesFilter.thought
                      ? 12
                      : 12 + (fullScreen ? 0 : safeBottom),
                ),
                children: content,
              );
            },
          ),
        ),
        if (_filter == ReadingNotesFilter.thought) _thoughtComposerAffordance(),
      ],
    );
  }

  void _finishEmbeddedThought(ThoughtEditResult? result) {
    final c = _embeddedThoughtCompleter;
    if (c == null || c.isCompleted) return;
    c.complete(result);
  }

  @override
  Widget build(BuildContext context) {
    final fullScreen = widget.fullScreen;
    final tablet = AppOrientation.isTablet(context);
    final thought = _embeddedThought;

    if (fullScreen) {
      return Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: '返回',
            onPressed: () => _pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          title: const Text(
            '这篇的笔记',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
          centerTitle: true,
          foregroundColor: _text,
        ),
        body: _buildNotesChrome(fullScreen: true),
      );
    }

    final height = MediaQuery.sizeOf(context).height * 0.88;
    final sheetRadius = BorderRadius.circular(20);
    final body = tablet
        ? Stack(
            children: [
              _buildNotesChrome(fullScreen: false),
              if (_embeddedThoughtOpen)
                Positioned.fill(
                  child: ReadingThoughtEditPage(
                    initialTitle: thought?.title ?? '',
                    initialText: thought?.text ?? '',
                    initialFormat: thought?.format ?? ItemNoteFormat.plain,
                    initialMode: thought == null
                        ? ThoughtPageMode.editing
                        : ThoughtPageMode.reading,
                    relateItemId: widget.itemId,
                    repository: _repo,
                    canDelete: thought != null,
                    onClose: _finishEmbeddedThought,
                  ),
                ),
            ],
          )
        : _buildNotesChrome(fullScreen: false);

    return Material(
      color: _pageBg,
      borderRadius: sheetRadius,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: body,
      ),
    );
  }
}

class _NotesToolbarAction extends StatelessWidget {
  const _NotesToolbarAction({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
