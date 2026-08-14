import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/article_body_text.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_annotation_sheet.dart';
import 'package:super_collection/features/items/reading_delete_confirm_dialog.dart';
import 'package:super_collection/features/items/reading_folder_sheet.dart';
import 'package:super_collection/features/items/reading_more_sheet.dart';
import 'package:super_collection/features/items/reading_note_sheet.dart';
import 'package:super_collection/features/items/reading_tags_sheet.dart';

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

  final _repo = ItemsRepository();
  late CollectionItem _item;
  List<ItemAnnotation> _annotations = const [];
  bool _starring = false;
  bool _loadingAnns = true;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadAnnotations();
  }

  String get _bodyText {
    final raw = (_item.content ?? _item.summary ?? '').trim();
    return ArticleBodyText.splitParagraphs(raw).join('\n\n');
  }

  /// 阅读页仅小红书展示图集（其余平台只读正文）
  bool get _showReadingImages {
    final platform = (_item.platform ?? '').toLowerCase();
    return platform == 'xiaohongshu' && _item.displayImages.isNotEmpty;
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
    final action = await showReadingMoreSheet(context);
    if (!mounted || action == null) return;
    switch (action) {
      case ReadingMoreAction.moveFolder:
        final updated = await showReadingFolderSheet(
          context,
          itemId: _item.id,
          currentFolderId: _item.folderId,
        );
        if (updated != null && mounted) setState(() => _item = updated);
      case ReadingMoreAction.delete:
        await _confirmDelete();
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
    final ranges = _annotationRanges(text);
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      if (r.start < cursor) continue;
      if (r.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r.start)));
      }
      final chunk = text.substring(r.start, r.end);
      spans.add(
        TextSpan(
          text: chunk,
          style: const TextStyle(
            backgroundColor: _highlight,
            color: _text,
          ),
        ),
      );
      cursor = r.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: text));
    }
    return spans;
  }

  Widget _selectionToolbar(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
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
            sel.start,
            sel.end,
          ),
        ),
        _ToolbarAction(
          label: '加短注',
          onTap: () => _onAddNote(
            editableTextState,
            selected,
            sel.start,
            sel.end,
          ),
        ),
        _ToolbarAction(
          label: '复制',
          onTap: () => _onCopy(editableTextState, selected),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _item.title?.isNotEmpty == true ? _item.title! : _item.url;
    final body = _bodyText;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _ReadingTopBar(
            onBack: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: ListView(
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
                if (_showReadingImages) ...[
                  ItemImageGallery(urls: _item.displayImages),
                  const SizedBox(height: 18),
                ],
                if (body.isEmpty)
                  const Text(
                    '暂无正文',
                    style: TextStyle(fontSize: 15, color: _muted),
                  )
                else
                  _AnnotatedBodyStack(
                    text: body,
                    spans: _bodySpans(body),
                    annotations: _annotationRanges(body),
                    contextMenuBuilder: _selectionToolbar,
                    onTapAnnotation: _openAnnotation,
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
          Material(
            color: Colors.white,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _border)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      _ActionItem(
                        icon: _item.isStarred
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        label: '星标',
                        iconColor:
                            _item.isStarred ? _starActive : _text,
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
        ],
      ),
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
  });

  final String text;
  final List<InlineSpan> spans;
  final List<({int start, int end, ItemAnnotation ann})> annotations;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final ValueChanged<ItemAnnotation> onTapAnnotation;

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
                  style: _AnnotatedBodyStack.bodyStyle,
                  children: widget.spans,
                ),
                key: _textKey,
                textAlign: TextAlign.justify,
                contextMenuBuilder: widget.contextMenuBuilder,
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

