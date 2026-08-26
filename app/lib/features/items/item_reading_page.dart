import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/article_body_text.dart';
import 'package:super_collection/features/items/article_content_blocks.dart';
import 'package:super_collection/features/items/article_markdown.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_video_player.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_media_controller.dart';
import 'package:super_collection/features/items/reading_annotation_sheet.dart';
import 'package:super_collection/features/items/reading_delete_confirm_dialog.dart';
import 'package:super_collection/features/items/reading_folder_sheet.dart';
import 'package:super_collection/features/items/reading_more_sheet.dart';
import 'package:super_collection/features/items/reading_note_sheet.dart';
import 'package:super_collection/features/items/reading_tags_sheet.dart';
import 'package:super_collection/features/items/transcript_models.dart';
import 'package:super_collection/features/items/transcript_picker_sheet.dart';
import 'package:super_collection/features/items/transcript_segment_panel.dart';

/// 本地阅读页：标题 + 可读正文（含标注高亮）；底栏 星标 / 标签 / 备注 / 更多。
class ItemReadingPage extends StatefulWidget {
  const ItemReadingPage({super.key, required this.item});

  final CollectionItem item;

  @override
  State<ItemReadingPage> createState() => _ItemReadingPageState();
}

class _ItemReadingPageState extends State<ItemReadingPage> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _border = Color(0xFFE5E5EB);
  static const _starActive = Color(0xFFE6A817);
  static const _blue = Color(0xFF2F6FED);
  static const _highlight = Color(0xFFFFF2C7);

  static const _chromeAnim = Duration(milliseconds: 240);
  static const _topBarHeight = 52.0;
  static const _bottomBarHeight = 56.0;

  final _repo = ItemsRepository();
  late CollectionItem _item;
  List<ItemAnnotation> _annotations = const [];
  bool _starring = false;
  bool _loadingAnns = true;
  bool _chromeVisible = true;
  bool _bodyHasSelection = false;
  DateTime? _lastChromeToggleAt;
  late final ReadingMediaController _pageAudio = ReadingMediaController();

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadAnnotations();
    unawaited(ReadingMediaController.ensureAudioSession());
    if (_item.hasAnyTranscriptPending) {
      _pollTranscript();
    }
  }

  @override
  void dispose() {
    _pageAudio.dispose();
    super.dispose();
  }

  void _toggleReadingChrome() {
    if (_bodyHasSelection) return;
    final now = DateTime.now();
    if (_lastChromeToggleAt != null &&
        now.difference(_lastChromeToggleAt!) <
            const Duration(milliseconds: 80)) {
      return;
    }
    _lastChromeToggleAt = now;
    setState(() => _chromeVisible = !_chromeVisible);
  }

  void _onBodySelectionChanged(TextSelection selection) {
    _bodyHasSelection = selection.isValid && !selection.isCollapsed;
  }

  String get _rawBody => (_item.content ?? _item.summary ?? '').trim();

  /// 标注 / 选区用的可见纯文字（去掉图标记与 ** / # 等）
  String get _bodyText {
    final plain = ArticleMarkdown.visiblePlain(_rawBody);
    return ArticleBodyText.splitParagraphs(plain).join('\n\n');
  }

  List<ArticleBlock> get _bodyBlocks => ArticleContentBlocks.parse(_rawBody);

  /// 阅读页顶部轮播：仅真图集；普通文章图插在正文对应位置
  bool get _showReadingImages => _readingImageUrls.isNotEmpty;

  List<String> get _readingImageUrls {
    if (!_item.isImageGallery) return const [];
    return _item.imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  bool get _hasInlineVideos =>
      ArticleContentBlocks.hasInlineVideos(_rawBody);

  bool get _platformNeedsVideoRefresh {
    final p = (_item.platform ?? '').toLowerCase();
    final v = (_item.videoUrl ?? '').toLowerCase();
    final body = (_item.content ?? '').toLowerCase();
    return p == 'bilibili' ||
        p == 'toutiao' ||
        p == 'qqnews' ||
        p == 'sina' ||
        v.contains('bilivideo') ||
        v.contains('bilibili') ||
        v.contains('toutiaovod') ||
        v.contains('gtimg.com') ||
        v.contains('weibocdn') ||
        body.contains('gtimg.com') ||
        body.contains('weibocdn');
  }

  Future<String?> _refreshVideoUrl() async {
    final updated = await _repo.refreshVideo(_item.id);
    // 不 setState：避免 url 变化触发播放器重建死循环；由播放器内部换链
    _item = updated;
    return updated.videoUrl;
  }

  Future<String?> _refreshInlineVideo(int index) async {
    final updated = await _repo.refreshVideo(_item.id);
    if (!mounted) return null;
    setState(() => _item = updated);
    final urls = ArticleContentBlocks.inlineVideoUrls(_rawBody);
    if (index >= 0 && index < urls.length) return urls[index];
    return updated.videoUrl;
  }

  String _metaLine() {
    final date = _item.createdAt?.toLocal();
    final dateStr = date == null
        ? ''
        : '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
    return [
      platformLabel(_item.platform),
      dateStr,
    ].where((e) => e.isNotEmpty).join(' · ');
  }

  Future<void> _loadAnnotations() async {
    setState(() => _loadingAnns = true);
    try {
      final list = await _repo.listAnnotations(_item.id);
      if (!mounted) return;
      setState(() {
        _annotations = list;
        _loadingAnns = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAnns = false);
    }
  }

  Future<void> _toggleStar() async {
    if (_starring) return;
    setState(() => _starring = true);
    final next = !_item.isStarred;
    try {
      final updated = await _repo.setStarred(_item.id, starred: next);
      if (!mounted) return;
      setState(() {
        _item = updated;
        _starring = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _starring = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _starring = false);
    }
  }

  void _clearToolbar(EditableTextState state) {
    ContextMenuController.removeAny();
    state.hideToolbar();
    final value = state.textEditingValue;
    final end = value.selection.isValid ? value.selection.end : 0;
    state.userUpdateTextEditingValue(
      value.copyWith(selection: TextSelection.collapsed(offset: end)),
      SelectionChangedCause.toolbar,
    );
  }

  Future<ItemAnnotation?> _createHighlight(
    String text,
    int start,
    int end, {
    String? note,
  }) async {
    final selected = text.trim();
    if (selected.isEmpty) return null;
    try {
      final ann = await _repo.createAnnotation(
        _item.id,
        selectedText: selected,
        startOffset: start,
        endOffset: end,
        note: note,
      );
      if (!mounted) return null;
      setState(() => _annotations = [..._annotations, ann]);
      return ann;
    } on ApiException catch (e) {
      if (!mounted) return null;
      AppToast.show(context, e.message);
      return null;
    }
  }

  Future<void> _onHighlight(
    EditableTextState state,
    String text,
    int start,
    int end,
  ) async {
    _clearToolbar(state);
    final ann = await _createHighlight(text, start, end);
    if (ann != null && mounted) {
      AppToast.show(context, '已高亮');
    }
  }

  Future<void> _onAddNote(
    EditableTextState state,
    String text,
    int start,
    int end,
  ) async {
    _clearToolbar(state);
    final ann = await showCreateAnnotationNoteSheet(
      context,
      itemId: _item.id,
      selectedText: text,
      startOffset: start,
      endOffset: end,
    );
    if (ann != null && mounted) {
      setState(() => _annotations = [..._annotations, ann]);
      AppToast.show(
        context,
        '短注已保存',
        actionLabel: '查看',
        onAction: _showAnnotationList,
      );
    }
  }

  Future<void> _onCopy(
    EditableTextState state,
    String text,
  ) async {
    await Clipboard.setData(ClipboardData(text: text));
    _clearToolbar(state);
    if (!mounted) return;
    AppToast.show(context, '已复制');
  }

  void _openAnnotation(ItemAnnotation ann) {
    showAnnotationDetailSheet(
      context,
      itemId: _item.id,
      annotation: ann,
      onChanged: _loadAnnotations,
    );
  }

  void _showAnnotationList() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.6,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const Text(
                  '本篇标注',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '点一条可查看或编辑短注',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 12),
                for (final ann in _annotations) ...[
                  Material(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(context);
                        _openAnnotation(ann);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _highlight,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    ann.selectedText,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: _text,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                if (ann.note != null &&
                                    ann.note!.trim().isNotEmpty)
                                  const Positioned(
                                    right: 6,
                                    top: 4,
                                    child: Icon(
                                      Icons.sticky_note_2_outlined,
                                      size: 14,
                                      color: _blue,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              (ann.note != null && ann.note!.trim().isNotEmpty)
                                  ? ann.note!
                                  : '暂无短注 · 点击可添加',
                              style: const TextStyle(
                                fontSize: 13,
                                color: _muted,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onNote() async {
    final updated = await showReadingNoteSheet(
      context,
      itemId: _item.id,
      initialNote: _item.note,
    );
    if (updated != null && mounted) setState(() => _item = updated);
  }

  Future<void> _onMore() async {
    final action = await showReadingMoreSheet(
      context,
      showTranscript:
          _item.canRequestTranscript ||
          _item.hasAnyTranscriptPending ||
          _item.hasAnyTranscript,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case ReadingMoreAction.moveFolder:
        final updated = await showReadingFolderSheet(
          context,
          itemId: _item.id,
          currentFolderId: _item.folderId,
        );
        if (updated != null && mounted) setState(() => _item = updated);
      case ReadingMoreAction.transcript:
        await _onTranscript();
      case ReadingMoreAction.delete:
        await _confirmDelete();
    }
  }

  Future<void> _onTranscript() async {
    if (_item.hasAnyTranscriptPending) {
      AppToast.show(context, '请等当前转写完成');
      return;
    }

    List<TranscriptTarget> targets;
    try {
      targets = await _repo.getTranscriptTargets(_item.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
      return;
    }

    if (targets.isEmpty) {
      if (!mounted) return;
      AppToast.show(context, '该条目没有可转写的音视频');
      return;
    }

    TranscriptTarget? chosen;
    if (targets.length == 1) {
      chosen = targets.first;
    } else {
      if (!mounted) return;
      chosen = await showTranscriptPickerSheet(context, targets: targets);
    }
    if (chosen == null || !mounted) return;

    final existing = _item.segmentTranscript(chosen.segmentKey);
    if (existing?.hasText == true) {
      final retry = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重新转写'),
          content: const Text('该段已有文稿，是否重新转写并覆盖？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重新转写'),
            ),
          ],
        ),
      );
      if (retry != true || !mounted) return;
    }

    try {
      String? mediaUrl;
      if (chosen.needsClientResolve) {
        if (chosen.segmentKey.startsWith('inline:')) {
          final idx = int.tryParse(chosen.segmentKey.split(':').last);
          if (idx != null) mediaUrl = await _refreshInlineVideo(idx);
        } else {
          mediaUrl = await _refreshVideoUrl();
        }
        if (mediaUrl == null || mediaUrl.trim().isEmpty) {
          if (!mounted) return;
          AppToast.show(context, '无法获取音视频直链，请先播放或刷新视频');
          return;
        }
      }

      final updated = await _repo.requestTranscript(
        _item.id,
        segmentKey: chosen.segmentKey,
        force: existing?.hasText == true,
        mediaUrl: mediaUrl,
      );
      if (!mounted) return;
      setState(() => _item = updated);
      AppToast.show(context, '已开始转写，请稍候');
      _pollTranscript();
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    }
  }

  Future<void> _pollTranscript() async {
    String? lastPhaseFingerprint;
    for (var i = 0; i < 90; i++) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      try {
        final st = await _repo.getTranscriptStatus(_item.id);
        if (st.hasPending) {
          // pending 期间合并 segments，让 phaseLabel 刷新到面板
          final merged = Map<String, TranscriptSegment>.from(
            _item.transcriptSegments,
          );
          st.segments.forEach((key, seg) {
            merged[key] = seg;
          });
          final fp = st.segments.entries
              .map((e) => '${e.key}:${e.value.phase}:${e.value.phaseLabel}')
              .join('|');
          if (fp != lastPhaseFingerprint) {
            lastPhaseFingerprint = fp;
            if (!mounted) return;
            setState(() => _item = _item.withTranscriptSegments(merged));
          }
          continue;
        }
        final item = await _repo.getItem(_item.id);
        if (!mounted) return;
        setState(() => _item = item);
        final anySuccess = st.segments.values.any((s) => s.isSuccess);
        if (anySuccess) {
          AppToast.show(context, '文稿已生成');
        } else {
          String? errMsg;
          for (final s in st.segments.values) {
            final e = s.error?.trim();
            if (e != null && e.isNotEmpty) {
              errMsg = e;
              break;
            }
          }
          if (errMsg != null) AppToast.show(context, errMsg);
        }
        return;
      } catch (_) {
        // ignore poll errors
      }
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showReadingDeleteConfirmDialog(context);
    if (ok != true || !mounted) return;
    try {
      await _repo.softDelete(_item.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    }
  }

  List<({int start, int end, ItemAnnotation ann})> _annotationRanges(
    String text,
  ) {
    final ranges = <({int start, int end, ItemAnnotation ann})>[];
    for (final ann in _annotations) {
      int? start = ann.startOffset;
      int? end = ann.endOffset;
      if (start == null ||
          end == null ||
          start < 0 ||
          end > text.length ||
          start >= end) {
        final idx = text.indexOf(ann.selectedText);
        if (idx < 0) continue;
        start = idx;
        end = idx + ann.selectedText.length;
      }
      ranges.add((start: start, end: end, ann: ann));
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  List<InlineSpan> _bodySpans(String text) {
    return _bodySpansForRange(text, 0, text.length);
  }

  /// [globalStart, globalEnd) 对应 plainText 切片，生成带高亮的 spans（本地坐标）。
  List<InlineSpan> _bodySpansForRange(
    String plainText,
    int globalStart,
    int globalEnd,
  ) {
    if (globalStart >= globalEnd ||
        globalStart < 0 ||
        globalEnd > plainText.length) {
      return [TextSpan(text: '')];
    }
    final localText = plainText.substring(globalStart, globalEnd);
    final ranges = _annotationRanges(plainText)
        .where((r) => r.end > globalStart && r.start < globalEnd)
        .map(
          (r) => (
            start: (r.start - globalStart).clamp(0, localText.length),
            end: (r.end - globalStart).clamp(0, localText.length),
            ann: r.ann,
          ),
        )
        .where((r) => r.start < r.end)
        .toList();

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      if (r.start < cursor) continue;
      if (r.start > cursor) {
        spans.add(TextSpan(text: localText.substring(cursor, r.start)));
      }
      spans.add(
        TextSpan(
          text: localText.substring(r.start, r.end),
          style: const TextStyle(
            backgroundColor: _highlight,
            color: _text,
          ),
        ),
      );
      cursor = r.end;
    }
    if (cursor < localText.length) {
      spans.add(TextSpan(text: localText.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: localText));
    }
    return spans;
  }

  Widget _selectionToolbar(
    BuildContext context,
    EditableTextState editableTextState, {
    int baseOffset = 0,
  }) {
    final value = editableTextState.textEditingValue;
    final sel = value.selection;
    if (!sel.isValid || sel.isCollapsed) {
      return const SizedBox.shrink();
    }
    final selected = sel.textInside(value.text);
    if (selected.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final anchors = editableTextState.contextMenuAnchors;
    final start = sel.start + baseOffset;
    final end = sel.end + baseOffset;
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
        _ToolbarAction(
          label: '高亮',
          onTap: () => _onHighlight(
            editableTextState,
            selected,
            start,
            end,
          ),
        ),
        _ToolbarAction(
          label: '加短注',
          onTap: () => _onAddNote(
            editableTextState,
            selected,
            start,
            end,
          ),
        ),
        _ToolbarAction(
          label: '复制',
          onTap: () => _onCopy(editableTextState, selected),
        ),
      ],
    );
  }

  EditableTextContextMenuBuilder _toolbarAt(int baseOffset) {
    return (context, state) =>
        _selectionToolbar(context, state, baseOffset: baseOffset);
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _item.title?.isNotEmpty == true ? _item.title! : _item.url;
    final body = _bodyText;

    final mq = MediaQuery.of(context);
    final topChrome = mq.padding.top + _topBarHeight;
    final bottomChrome = mq.padding.bottom + _bottomBarHeight;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          AnimatedPadding(
            duration: _chromeAnim,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              top: _chromeVisible ? topChrome : mq.padding.top,
              bottom: _chromeVisible ? bottomChrome : mq.padding.bottom,
            ),
            child: GestureDetector(
              onTap: _toggleReadingChrome,
              behavior: HitTestBehavior.translucent,
              child: ListView(
                // 避免播放器滚出视口后被 Platform View 回收/暂停（尤其播客音频）
                cacheExtent: mq.size.height * 2,
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _text,
                      height: 1.4,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _metaLine(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_item.hasVideo && !_hasInlineVideos) ...[
                    ItemVideoPlayer(
                      key: ValueKey('item-video-${_item.id}'),
                      url: _item.videoUrl!.trim(),
                      coverUrl: _item.coverImageUrl ??
                          (_item.displayImages.isNotEmpty
                              ? _item.displayImages.first
                              : null),
                      pageUrl: _item.sourcePageUrl,
                      platform: _item.platform,
                      pageAudio: _pageAudio,
                      onRefreshUrl: _platformNeedsVideoRefresh
                          ? _refreshVideoUrl
                          : null,
                    ),
                    TranscriptSegmentPanel(
                      segment: _item.segmentTranscript(
                        TranscriptTargets.segmentVideoUrl,
                      ),
                    ),
                    const SizedBox(height: 18),
                  ] else if (_showReadingImages) ...[
                    ItemImageGallery(
                      urls: _readingImageUrls,
                      pageUrl: _item.sourcePageUrl,
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_rawBody.isEmpty)
                    const Text(
                      '暂无正文',
                      style: TextStyle(fontSize: 15, color: _muted),
                    )
                  else if (ArticleContentBlocks.hasRichMarkup(_rawBody))
                    _InlineArticleBody(
                      blocks: _bodyBlocks,
                      plainText: body,
                      annotationRanges: _annotationRanges(body),
                      toolbarAt: _toolbarAt,
                      onTapAnnotation: _openAnnotation,
                      onBodyTap: _toggleReadingChrome,
                      onSelectionChanged: _onBodySelectionChanged,
                      itemId: _item.id,
                      pageUrl: _item.sourcePageUrl,
                      transcriptSegments: _item.transcriptSegments,
                      platform: _item.platform,
                      pageAudio: _pageAudio,
                      onRefreshInlineVideo: _platformNeedsVideoRefresh
                          ? _refreshInlineVideo
                          : null,
                    )
                  else
                    _AnnotatedBodyStack(
                      text: body,
                      spans: _bodySpans(body),
                      annotations: _annotationRanges(body),
                      contextMenuBuilder: _selectionToolbar,
                      onTapAnnotation: _openAnnotation,
                      onBodyTap: _toggleReadingChrome,
                      onSelectionChanged: _onBodySelectionChanged,
                    ),
                  if (_loadingAnns) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: ClipRect(
                child: AnimatedSlide(
                  duration: _chromeAnim,
                  curve: Curves.easeOutCubic,
                  offset:
                      _chromeVisible ? Offset.zero : const Offset(0, -1),
                  child: _ReadingTopBar(
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: ClipRect(
                child: AnimatedSlide(
                  duration: _chromeAnim,
                  curve: Curves.easeOutCubic,
                  offset:
                      _chromeVisible ? Offset.zero : const Offset(0, 1),
                  child: Material(
                    color: Colors.white,
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: _border)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: SizedBox(
                          height: _bottomBarHeight,
                          child: Row(
                            children: [
                              _ActionItem(
                                icon: _item.isStarred
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                label: '星标',
                                iconColor: _item.isStarred
                                    ? _starActive
                                    : _text,
                                onTap: _toggleStar,
                              ),
                              _ActionItem(
                                icon: Icons.tag_outlined,
                                label: '标签',
                                onTap: () => showReadingTagsSheet(
                                  context,
                                  itemId: _item.id,
                                ),
                              ),
                              _ActionItem(
                                icon: Icons.edit_note_outlined,
                                label: '备注',
                                iconColor: (_item.note != null &&
                                        _item.note!.trim().isNotEmpty)
                                    ? _blue
                                    : _text,
                                onTap: _onNote,
                              ),
                              _ActionItem(
                                icon: Icons.more_vert,
                                label: '更多',
                                onTap: _onMore,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 普通文章：标题 / 加粗 / 图片随正文混排；文字段可标注。
class _InlineArticleBody extends StatelessWidget {
  const _InlineArticleBody({
    required this.blocks,
    required this.plainText,
    required this.annotationRanges,
    required this.toolbarAt,
    required this.onTapAnnotation,
    this.onBodyTap,
    this.onSelectionChanged,
    this.itemId,
    this.pageUrl,
    this.transcriptSegments = const {},
    this.platform,
    this.pageAudio,
    this.onRefreshInlineVideo,
  });

  final List<ArticleBlock> blocks;
  final String plainText;
  final List<({int start, int end, ItemAnnotation ann})> annotationRanges;
  final EditableTextContextMenuBuilder Function(int baseOffset) toolbarAt;
  final ValueChanged<ItemAnnotation> onTapAnnotation;
  final VoidCallback? onBodyTap;
  final ValueChanged<TextSelection>? onSelectionChanged;
  final int? itemId;
  final String? pageUrl;
  final Map<String, TranscriptSegment> transcriptSegments;
  final String? platform;
  final ReadingMediaController? pageAudio;
  final Future<String?> Function(int index)? onRefreshInlineVideo;

  static const _text = Color(0xFF1F242E);
  static const _highlight = Color(0xFFFFF2C7);

  static const _bodyStyle = TextStyle(
    fontSize: 15,
    height: 1.85,
    letterSpacing: 0.2,
    color: _text,
  );

  TextStyle _headingStyle(int level) {
    final size = switch (level) {
      1 => 21.0,
      2 => 19.0,
      3 => 17.0,
      _ => 16.0,
    };
    return TextStyle(
      fontSize: size,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: _text,
      letterSpacing: 0.2,
    );
  }

  ({int start, int end, String visible}) _advance(
    String visible,
    int cursor,
  ) {
    if (visible.isEmpty) {
      return (start: cursor, end: cursor, visible: visible);
    }
    var start = plainText.indexOf(visible, cursor);
    if (start < 0) start = cursor;
    final end = (start + visible.length).clamp(0, plainText.length);
    var next = end;
    if (next + 2 <= plainText.length &&
        plainText.substring(next, next + 2) == '\n\n') {
      next += 2;
    } else if (next + 1 <= plainText.length &&
        plainText.substring(next, next + 1) == '\n') {
      next += 1;
    }
    return (start: start, end: end, visible: visible);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var cursor = 0;
    var videoIndex = 0;

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];

      if (block is ArticleVideoBlock) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 18));
        final index = videoIndex++;
        final segmentKey = 'inline:$index';
        children.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = (w * 9 / 16).clamp(180.0, 280.0);
                  return ItemVideoPlayer(
                    key: ValueKey('body-video-${itemId ?? 0}-$index'),
                    url: block.url,
                    coverUrl: block.posterUrl,
                    pageUrl: pageUrl,
                    platform: platform,
                    pageAudio: pageAudio,
                    height: h,
                    onRefreshUrl: onRefreshInlineVideo == null
                        ? null
                        : () => onRefreshInlineVideo!(index),
                  );
                },
              ),
              TranscriptSegmentPanel(
                segment: transcriptSegments[segmentKey],
              ),
            ],
          ),
        );
        continue;
      }

      if (block is ArticleImageBlock) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 18));
        children.add(
          _ReadingInlineImage(
            url: block.url,
            pageUrl: pageUrl,
            hintWidth: block.width,
            hintHeight: block.height,
          ),
        );
        continue;
      }

      if (children.isNotEmpty) children.add(const SizedBox(height: 14));

      if (block is ArticleHeadingBlock) {
        final md = block.text.trim();
        final visible = ArticleMarkdown.stripMarkers(md);
        if (visible.isEmpty) continue;
        final pos = _advance(visible, cursor);
        cursor = pos.end;
        if (cursor + 2 <= plainText.length &&
            plainText.substring(cursor, cursor + 2) == '\n\n') {
          cursor += 2;
        } else if (cursor < plainText.length && plainText[cursor] == '\n') {
          cursor += 1;
        }

        final localAnns = annotationRanges
            .where((r) => r.end > pos.start && r.start < pos.end)
            .map(
              (r) => (
                start: (r.start - pos.start).clamp(0, visible.length),
                end: (r.end - pos.start).clamp(0, visible.length),
                ann: r.ann,
              ),
            )
            .where((r) => r.start < r.end)
            .toList();

        final style = _headingStyle(block.level);
        final spans = ArticleMarkdown.inlineSpans(
          md,
          style: style,
          highlights: [
            for (final a in localAnns) (start: a.start, end: a.end),
          ],
          highlightColor: _highlight,
        );

        children.add(
          _AnnotatedBodyStack(
            text: visible,
            spans: spans.isEmpty
                ? [TextSpan(text: visible, style: style)]
                : spans,
            annotations: localAnns,
            contextMenuBuilder: toolbarAt(pos.start),
            onTapAnnotation: onTapAnnotation,
            onBodyTap: onBodyTap,
            onSelectionChanged: onSelectionChanged,
            textStyle: style,
          ),
        );
        continue;
      }

      if (block is! ArticleTextBlock) continue;

      final mdParagraphs = ArticleBodyText.splitParagraphs(block.text);
      for (var pi = 0; pi < mdParagraphs.length; pi++) {
        if (pi > 0) children.add(const SizedBox(height: 14));
        final md = mdParagraphs[pi];
        final visible = ArticleMarkdown.visiblePlain(md);
        if (visible.isEmpty) continue;

        final pos = _advance(visible, cursor);
        cursor = pos.end;
        if (cursor + 2 <= plainText.length &&
            plainText.substring(cursor, cursor + 2) == '\n\n') {
          cursor += 2;
        }

        final localAnns = annotationRanges
            .where((r) => r.end > pos.start && r.start < pos.end)
            .map(
              (r) => (
                start: (r.start - pos.start).clamp(0, visible.length),
                end: (r.end - pos.start).clamp(0, visible.length),
                ann: r.ann,
              ),
            )
            .where((r) => r.start < r.end)
            .toList();

        final spans = ArticleMarkdown.inlineSpans(
          md,
          style: _bodyStyle,
          highlights: [
            for (final a in localAnns) (start: a.start, end: a.end),
          ],
          highlightColor: _highlight,
        );

        children.add(
          _AnnotatedBodyStack(
            text: visible,
            spans: spans.isEmpty
                ? [const TextSpan(text: '', style: _bodyStyle)]
                : spans,
            annotations: localAnns,
            contextMenuBuilder: toolbarAt(pos.start),
            onTapAnnotation: onTapAnnotation,
            onBodyTap: onBodyTap,
            onSelectionChanged: onSelectionChanged,
          ),
        );
      }
    }

    if (children.isEmpty) {
      return const Text(
        '暂无正文',
        style: TextStyle(fontSize: 15, color: Color(0xFF737A85)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// 正文插图：与正文同宽（含左右边距对齐），按比例定高。
class _ReadingInlineImage extends StatefulWidget {
  const _ReadingInlineImage({
    required this.url,
    this.pageUrl,
    this.hintWidth,
    this.hintHeight,
  });

  final String url;
  final String? pageUrl;
  final double? hintWidth;
  final double? hintHeight;

  @override
  State<_ReadingInlineImage> createState() => _ReadingInlineImageState();
}

class _ReadingInlineImageState extends State<_ReadingInlineImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _decodedW;
  double? _decodedH;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _ReadingInlineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.pageUrl != widget.pageUrl) {
      _stop();
      _decodedW = null;
      _decodedH = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _listen() {
    final provider = NetworkImage(
      widget.url,
      headers: mediaHttpHeadersFor(widget.url, pageUrl: widget.pageUrl),
    );
    _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _decodedW = info.image.width.toDouble();
          _decodedH = info.image.height.toDouble();
        });
      },
      onError: (_, __) {},
    );
    _stream!.addListener(_listener!);
  }

  void _stop() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final declaredW = widget.hintWidth;
        final aspect = (declaredW != null &&
                widget.hintHeight != null &&
                declaredW > 0 &&
                widget.hintHeight! > 0)
            ? widget.hintHeight! / declaredW
            : (_decodedW != null &&
                    _decodedH != null &&
                    _decodedW! > 0)
                ? _decodedH! / _decodedW!
                : null;
        final height = aspect != null ? width * aspect : null;
        return Image.network(
          widget.url,
          width: width,
          height: height,
          fit: BoxFit.fitWidth,
          alignment: Alignment.center,
          headers: mediaHttpHeadersFor(widget.url, pageUrl: widget.pageUrl),
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 72,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Color(0xFFB2B8BF),
                size: 28,
              ),
            ),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: width,
              height: height ?? 160,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 正文可选中；标注热区与短注图标用 Stack 绝对定位，不抢 SelectableText 手势状态。
class _AnnotatedBodyStack extends StatefulWidget {
  const _AnnotatedBodyStack({
    required this.text,
    required this.spans,
    required this.annotations,
    required this.contextMenuBuilder,
    required this.onTapAnnotation,
    this.onBodyTap,
    this.onSelectionChanged,
    this.textStyle,
  });

  final String text;
  final List<InlineSpan> spans;
  final List<({int start, int end, ItemAnnotation ann})> annotations;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final ValueChanged<ItemAnnotation> onTapAnnotation;
  final VoidCallback? onBodyTap;
  final ValueChanged<TextSelection>? onSelectionChanged;
  final TextStyle? textStyle;

  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);
  static const _highlight = Color(0xFFFFF2C7);

  static const bodyStyle = TextStyle(
    fontSize: 15,
    height: 1.85,
    letterSpacing: 0.2,
    color: _text,
  );

  @override
  State<_AnnotatedBodyStack> createState() => _AnnotatedBodyStackState();
}

class _AnnotatedBodyStackState extends State<_AnnotatedBodyStack> {
  final GlobalKey _textKey = GlobalKey();
  final List<({Rect rect, ItemAnnotation ann, bool showNoteIcon})> _hits = [];
  double? _laidOutWidth;
  int _measureToken = 0;
  int _measureMisses = 0;

  @override
  void didUpdateWidget(covariant _AnnotatedBodyStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.annotations.length != widget.annotations.length ||
        oldWidget.spans.length != widget.spans.length ||
        !_sameAnnotationIds(oldWidget.annotations, widget.annotations)) {
      _laidOutWidth = null;
      _measureMisses = 0;
    }
  }

  bool _sameAnnotationIds(
    List<({int start, int end, ItemAnnotation ann})> a,
    List<({int start, int end, ItemAnnotation ann})> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].ann.id != b[i].ann.id) return false;
      final aNote = a[i].ann.note?.trim() ?? '';
      final bNote = b[i].ann.note?.trim() ?? '';
      if (aNote != bNote) return false;
      if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
    }
    return true;
  }

  void _scheduleMeasure() {
    final token = ++_measureToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _measureToken) return;
      _measure();
    });
  }

  RenderEditable? _findRenderEditable() {
    final root = _textKey.currentContext?.findRenderObject();
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  /// 去掉选区末尾换行/空白对应的空盒子，避免图标落到段间距里。
  List<TextBox> _meaningfulBoxes(List<TextBox> boxes) {
    return boxes
        .where((b) => (b.right - b.left) > 1.0 && (b.bottom - b.top) > 1.0)
        .toList(growable: false);
  }

  void _measure() {
    if (widget.annotations.isEmpty) {
      if (_hits.isNotEmpty) {
        setState(() => _hits.clear());
      }
      return;
    }

    final editable = _findRenderEditable();
    final stackBox = context.findRenderObject() as RenderBox?;
    if (editable == null || stackBox == null || !stackBox.hasSize) {
      if (_measureMisses < 10) {
        _measureMisses++;
        _scheduleMeasure();
      }
      return;
    }
    _measureMisses = 0;

    // RenderEditable 相对 Stack 的偏移（SelectableText 内部可能有 inset）
    final origin = editable.localToGlobal(Offset.zero, ancestor: stackBox);

    final next = <({Rect rect, ItemAnnotation ann, bool showNoteIcon})>[];
    for (final r in widget.annotations) {
      final raw = editable.getBoxesForSelection(
        TextSelection(baseOffset: r.start, extentOffset: r.end),
      );
      final boxes = _meaningfulBoxes(raw);
      if (boxes.isEmpty) continue;

      final hasNote =
          r.ann.note != null && r.ann.note!.trim().isNotEmpty;
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        next.add((
          rect: Rect.fromLTRB(
            origin.dx + box.left,
            origin.dy + box.top,
            origin.dx + box.right,
            origin.dy + box.bottom,
          ),
          ann: r.ann,
          showNoteIcon: hasNote && i == boxes.length - 1,
        ));
      }
    }

    if (!_hits.equal(next) && mounted) {
      setState(() {
        _hits
          ..clear()
          ..addAll(next);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (_laidOutWidth != w) {
          _laidOutWidth = w;
        }
        // 每帧后按真实 RenderEditable 量一次，避免 TextPainter 与真机排版不一致
        _scheduleMeasure();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            TextSelectionTheme(
              data: const TextSelectionThemeData(
                selectionColor: _AnnotatedBodyStack._highlight,
                selectionHandleColor: _AnnotatedBodyStack._blue,
              ),
              child: SelectableText.rich(
                TextSpan(
                  style: widget.textStyle ?? _AnnotatedBodyStack.bodyStyle,
                  children: widget.spans,
                ),
                key: _textKey,
                textAlign: TextAlign.justify,
                contextMenuBuilder: widget.contextMenuBuilder,
                onTap: widget.onBodyTap,
                onSelectionChanged: widget.onSelectionChanged == null
                    ? null
                    : (selection, _) =>
                        widget.onSelectionChanged!(selection),
              ),
            ),
            // 透明热区盖住高亮，稳定响应点击（不与选区手势打架）
            for (final hit in _hits)
              Positioned(
                left: hit.rect.left,
                top: hit.rect.top,
                width: hit.rect.width,
                height: hit.rect.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTapAnnotation(hit.ann),
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),
            for (final hit in _hits)
              if (hit.showNoteIcon)
                Positioned(
                  left: hit.rect.right - 2,
                  top: hit.rect.top + (hit.rect.height - 12) / 2,
                  child: const IgnorePointer(
                    child: Icon(
                      Icons.sticky_note_2_outlined,
                      size: 12,
                      color: _AnnotatedBodyStack._blue,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

extension on List<({Rect rect, ItemAnnotation ann, bool showNoteIcon})> {
  bool equal(
    List<({Rect rect, ItemAnnotation ann, bool showNoteIcon})> other,
  ) {
    if (length != other.length) return false;
    for (var i = 0; i < length; i++) {
      final a = this[i];
      final b = other[i];
      if (a.ann.id != b.ann.id || a.showNoteIcon != b.showNoteIcon) {
        return false;
      }
      if ((a.rect.left - b.rect.left).abs() > 0.5 ||
          (a.rect.top - b.rect.top).abs() > 0.5 ||
          (a.rect.width - b.rect.width).abs() > 0.5 ||
          (a.rect.height - b.rect.height).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }
}

/// Figma：深色圆角工具条「高亮 / 加短注 / 复制」
class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

class _ReadingTopBar extends StatelessWidget {
  const _ReadingTopBar({required this.onBack});

  final VoidCallback onBack;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 16),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    foregroundColor: _text,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.chevron_left, size: 26),
                  label: const Text(
                    '返回',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
                  ),
                ),
                const Spacer(),
                const Text(
                  '阅读',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: iconColor ?? _text),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

