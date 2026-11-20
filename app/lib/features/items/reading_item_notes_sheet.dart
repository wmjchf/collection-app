import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/pro_copy.dart';
import 'package:super_collection/features/agent/agent_markdown.dart';
import 'package:super_collection/features/items/annotation_note_style.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_thoughts.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_quote_share.dart';
import 'package:super_collection/features/items/reading_thought_edit_page.dart';
import 'package:super_collection/features/items/transcript_display.dart';

enum ReadingNotesFilter {
  highlight,
  annotation,
  thought,
  article,
  transcript,
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
Future<ReadingItemNotesResult?> showReadingItemNotesSheet(
  BuildContext context, {
  required int itemId,
  required List<ItemAnnotation> annotations,
  String? initialNote,
  /// 已有转写文稿（只读展示）
  String? transcriptText,
  /// 分享海报元数据
  String? shareTitle,
  String? shareLink,
  String? shareCoverUrl,
  String? sharePageUrl,
  /// 视频 / 图集才展示「文章」
  bool showArticleFilter = false,
  /// 仅视频展示「文稿」
  bool showTranscriptFilter = false,
  bool isPro = false,
  ReadingNotesFilter? initialFilter,
}) {
  return showAppBottomSheet<ReadingItemNotesResult>(
    context: context,
    padding: EdgeInsets.zero,
    includeSafeArea: false,
    builder: (context) => _ReadingItemNotesSheet(
      itemId: itemId,
      annotations: annotations,
      initialNote: initialNote,
      transcriptText: transcriptText,
      shareTitle: shareTitle,
      shareLink: shareLink,
      shareCoverUrl: shareCoverUrl,
      sharePageUrl: sharePageUrl,
      showArticleFilter: showArticleFilter,
      showTranscriptFilter: showTranscriptFilter,
      isPro: isPro,
      initialFilter: initialFilter,
    ),
  );
}

class _ReadingItemNotesSheet extends StatefulWidget {
  const _ReadingItemNotesSheet({
    required this.itemId,
    required this.annotations,
    this.initialNote,
    this.transcriptText,
    this.shareTitle,
    this.shareLink,
    this.shareCoverUrl,
    this.sharePageUrl,
    this.showArticleFilter = false,
    this.showTranscriptFilter = false,
    this.isPro = false,
    this.initialFilter,
  });

  final int itemId;
  final List<ItemAnnotation> annotations;
  final String? initialNote;
  final String? transcriptText;
  final String? shareTitle;
  final String? shareLink;
  final String? shareCoverUrl;
  final String? sharePageUrl;
  final bool showArticleFilter;
  final bool showTranscriptFilter;
  final bool isPro;
  final ReadingNotesFilter? initialFilter;

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
  static const _noteBubble = Color(0xFFEAF1FF);
  static const _handle = Color(0xFFE5E8ED);

  final _repo = ItemsRepository();
  late List<ItemAnnotation> _annotations;
  late List<ItemThought> _thoughts;
  late ReadingNotesFilter _filter;
  CollectionItem? _updatedItem;
  bool _saving = false;
  bool _dirtyAnns = false;

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

  String get _transcript => (widget.transcriptText ?? '').trim();

  bool get _showArticle => widget.showArticleFilter;

  bool get _showTranscript => widget.showTranscriptFilter;

  bool get _hasTranscript => _showTranscript && _transcript.isNotEmpty;

  int get _allCount =>
      _highlights.length +
      _notes.length +
      _thoughtTabItems.length +
      (_showArticle ? _articles.length : 0) +
      (_hasTranscript ? 1 : 0);

  bool _isFilterVisible(ReadingNotesFilter f) {
    switch (f) {
      case ReadingNotesFilter.article:
        return _showArticle;
      case ReadingNotesFilter.transcript:
        return _showTranscript;
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
    setState(() => _filter = ReadingNotesFilter.thought);
    final result = await showReadingThoughtEditPage(
      context,
      initialTitle: thought?.title ?? '',
      initialText: thought?.text ?? '',
      initialFormat: thought?.format ?? ItemNoteFormat.plain,
      initialMode: thought == null
          ? ThoughtPageMode.editing
          : ThoughtPageMode.reading,
    );
    if (!mounted || result == null) return;
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

  /// 确认并删除；成功返回 true（供左滑 Dismissible）。
  Future<bool> _deleteThought(ItemThought thought) async {
    final title = thought.isArticle
        ? '删除文章？'
        : thought.isExcerpt
            ? '删除 AI 摘录？'
            : '删除想法？';
    final ok = await showAppConfirmDialog(
      context,
      title: title,
      message: '删除后不可恢复。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return false;
    setState(() => _saving = true);
    try {
      final next = _thoughts.where((t) => t.id != thought.id).toList();
      await _persistThoughts(next);
      if (!mounted) return false;
      AppToast.show(context, '已删除');
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      AppToast.show(context, e.message);
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() => _saving = false);
      AppToast.show(context, '删除失败');
      return false;
    }
  }

  Future<bool> _deleteAnnotation(ItemAnnotation ann) async {
    final highlightOnly = !AnnotationNoteStyle.hasNote(ann);
    final ok = await showAppConfirmDialog(
      context,
      title: deleteAnnotationTitle(
        isPro: widget.isPro,
        highlightOnly: highlightOnly,
      ),
      message: '删除后不可恢复。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return false;
    try {
      await _repo.deleteAnnotation(widget.itemId, ann.id);
      if (!mounted) return false;
      setState(() {
        _annotations = _annotations.where((a) => a.id != ann.id).toList();
        _dirtyAnns = true;
      });
      AppToast.show(context, '已删除');
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      AppToast.show(context, e.message);
      return false;
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

  static const _danger = Color(0xFFE34D59);

  Future<void> _shareNote({
    required String quote,
    String? note,
    ReadingShareKind kind = ReadingShareKind.quote,
    Rect? shareOrigin,
  }) async {
    final body = quote.trim();
    if (body.isEmpty) return;
    try {
      await shareReadingQuote(
        context: context,
        quote: body,
        note: note,
        kind: kind,
        title: (widget.shareTitle ?? '').trim(),
        link: widget.shareLink,
        coverUrl: widget.shareCoverUrl,
        pageUrl: widget.sharePageUrl,
        sharePositionOrigin: shareOrigin,
        screenSize: MediaQuery.sizeOf(context),
      );
    } catch (error, stack) {
      debugPrint('notes share failed: $error\n$stack');
      if (mounted) AppToast.show(context, '分享失败，请稍后重试');
    }
  }

  /// 每条独立白卡；右下角分享 + 删除图标。
  Widget _itemCard({
    required Widget child,
    required VoidCallback onShare,
    required VoidCallback onDelete,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: child,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onShare,
                  tooltip: '分享',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(
                    Icons.ios_share_rounded,
                    size: 18,
                    color: _muted,
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: _danger.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quoteRow({
    required Color barColor,
    required String text,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                height: 1.55,
                color: _text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _annotationBlock(ItemAnnotation ann) {
    final quote = ann.selectedText.trim();
    final note = (ann.note ?? '').trim();
    return _itemCard(
      onShare: () => unawaited(
        _shareNote(
          quote: quote,
          note: note.isEmpty ? null : note,
        ),
      ),
      onDelete: () => unawaited(_deleteAnnotation(ann)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _quoteRow(
            barColor: _blue,
            text: quote,
            onTap: () => _pop(locate: ann),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pop(locate: ann),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: _noteBubble,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  note,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: _text,
                  ),
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
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else if (thought.isArticle) {
      // 助手成文：按 Markdown 渲染（与 Agent 气泡一致）
      body = AgentMarkdown(thought.text);
    } else {
      body = Text(
        thought.text,
        style: const TextStyle(
          fontSize: 15,
          height: 1.55,
          color: _text,
        ),
      );
    }
    // 存量摘录 / 文章只读；想法点进编辑页
    final content = !thought.isThought
        ? body
        : GestureDetector(
            onTap: () => unawaited(_openThoughtEditor(thought: thought)),
            behavior: HitTestBehavior.opaque,
            child: body,
          );
    final shareQuote = thought.isThought && thought.titleTrimmed.isNotEmpty
        ? '${thought.displayTitle}\n\n${thought.text}'
        : thought.text;
    return _itemCard(
      onShare: () => unawaited(
        _shareNote(
          quote: shareQuote,
          kind: ReadingShareKind.note,
        ),
      ),
      onDelete: () => unawaited(_deleteThought(thought)),
      child: content,
    );
  }

  Widget _transcriptCard() {
    final polished = TranscriptDisplay.polishForReading(_transcript);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8EB)),
      ),
      child: Text(
        polished,
        style: const TextStyle(
          fontSize: 15,
          height: 1.55,
          color: _text,
        ),
      ),
    );
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
    final showTranscript = _filter == ReadingNotesFilter.transcript;

    final out = <Widget>[];
    if (showHi && _highlights.isNotEmpty) {
      for (final a in _highlights) {
        final text = a.selectedText.trim();
        out.add(
          _itemCard(
            onShare: () => unawaited(_shareNote(quote: text)),
            onDelete: () => unawaited(_deleteAnnotation(a)),
            child: _quoteRow(
              barColor: _yellowBar,
              text: text,
              onTap: () => _pop(locate: a),
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
    if (showTranscript && _hasTranscript) {
      out.add(_transcriptCard());
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height * 0.88;
    final safeBottom = media.padding.bottom;

    return Material(
      color: _pageBg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: Column(
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
            SizedBox(
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
                  if (_showTranscript) ...[
                    const SizedBox(width: 8),
                    _chip(
                      label: '文稿',
                      selected: _filter == ReadingNotesFilter.transcript,
                      onTap: () => _setFilter(ReadingNotesFilter.transcript),
                    ),
                  ],
                ],
              ),
            ),
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
                          : 12 + safeBottom,
                    ),
                    children: content,
                  );
                },
              ),
            ),
            if (_filter == ReadingNotesFilter.thought)
              _thoughtComposerAffordance(),
          ],
        ),
      ),
    );
  }
}
