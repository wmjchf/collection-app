import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/pro_copy.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_annotation_sheet.dart';
import 'package:super_collection/features/items/reading_font_prefs.dart';
import 'package:super_collection/features/items/transcript_display.dart';
import 'package:super_collection/features/items/transcript_models.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 单段转写文稿全屏阅读（可划线高亮 / 批注 / 复制 / 删除）
class ItemTranscriptPage extends StatefulWidget {
  const ItemTranscriptPage({
    super.key,
    required this.text,
    this.cues = const [],
    this.fontSize = ReadingFontPrefs.defaultSize,
    this.itemId,
    this.segmentKey,
    this.focusAnnotationId,
  });

  final String text;
  final List<TranscriptCue> cues;
  final double fontSize;
  /// 有 itemId + segmentKey 时支持持久化高亮/批注
  final int? itemId;
  final String? segmentKey;
  /// 打开后滚动到该高亮/批注（如漫游进入）
  final int? focusAnnotationId;

  @override
  State<ItemTranscriptPage> createState() => _ItemTranscriptPageState();
}

class _ItemTranscriptPageState extends State<ItemTranscriptPage> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _highlight = Color(0xFFFFF2C7);

  final _repo = ItemsRepository();
  final _scrollController = ScrollController();
  List<ItemAnnotation> _annotations = const [];
  bool _isPro = false;
  bool _focusScrollDone = false;
  static int _optimisticAnnId = -1;

  String get _body => widget.text.trim();

  String? get _source {
    final key = (widget.segmentKey ?? '').trim();
    if (widget.itemId == null || key.isEmpty) return null;
    return 'transcript:$key';
  }

  bool get _canAnnotate => _source != null;

  TextStyle get _bodyTextStyle {
    final size = ReadingFontPrefs.clamp(widget.fontSize);
    return TextStyle(
      fontSize: size,
      height: 1.85,
      letterSpacing: 0.2,
      color: _text,
    );
  }

  @override
  void initState() {
    super.initState();
    final cached = UsageRefresh.snapshot;
    if (cached != null) {
      _isPro = cached.isPro;
    }
    _load();
    _scheduleFocusScrollFallback();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final usage = await UsageRefresh.ensure();
      if (mounted) {
        setState(() => _isPro = usage.isPro);
      }
    } catch (_) {}
    if (!_canAnnotate) return;
    try {
      final list = await _repo.listAnnotations(widget.itemId!);
      if (!mounted) return;
      final source = _source!;
      setState(() {
        _annotations = list
            .where((a) => a.source == source)
            .toList(growable: false);
      });
      _scheduleFocusScrollFallback();
    } catch (_) {}
  }

  void _onFocusAnnotationRect(Rect localRect, RenderBox stackBox) {
    if (_focusScrollDone || !mounted) return;
    if (!_scrollController.hasClients) return;
    _focusScrollDone = true;

    final scrollCtx =
        _scrollController.position.context.notificationContext;
    final scrollBox = scrollCtx?.findRenderObject() as RenderBox?;
    if (scrollBox == null || !scrollBox.hasSize) return;

    final global = stackBox.localToGlobal(localRect.topLeft);
    final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;
    const align = 0.22;
    final desired = scrollBox.size.height * align;
    final delta = (global.dy - viewportTop) - desired;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  void _scheduleFocusScrollFallback() {
    final id = widget.focusAnnotationId;
    if (id == null || _focusScrollDone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 480), () {
        if (!mounted || _focusScrollDone) return;
        _focusScrollByPainter(id);
      });
    });
  }

  void _focusScrollByPainter(int annotationId) {
    if (_focusScrollDone || !_scrollController.hasClients) return;
    final body = _body;
    if (body.isEmpty) return;
    ({int start, int end, ItemAnnotation ann})? target;
    for (final r in _ranges(body)) {
      if (r.ann.id == annotationId) {
        target = r;
        break;
      }
    }
    if (target == null) return;

    final width = MediaQuery.sizeOf(context).width - 44;
    final painter = TextPainter(
      text: TextSpan(
        text: body.substring(0, target.start),
        style: _bodyTextStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

    final targetOffset = (painter.height - 80)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _focusScrollDone = true;
    _scrollController.jumpTo(targetOffset);
  }

  List<({int start, int end, ItemAnnotation ann})> _ranges(String text) {
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
      final trimmed = _trimRange(text, start, end);
      if (trimmed.start >= trimmed.end) continue;
      ranges.add((start: trimmed.start, end: trimmed.end, ann: ann));
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  static final _speakerLabelRe = RegExp(r'说话人\s*\d+\s*[：:]');

  List<({int start, int end})> _speakerLabelRanges(String text) {
    return [
      for (final m in _speakerLabelRe.allMatches(text))
        (start: m.start, end: m.end),
    ];
  }

  TextStyle _speakerLabelStyle(TextStyle body) {
    final size = body.fontSize ?? 15;
    return body.copyWith(
      fontSize: (size - 2).clamp(12, size),
      height: 1.45,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF3D5A80),
      letterSpacing: 0.15,
      backgroundColor: null,
    );
  }

  List<InlineSpan> _spans(String text, TextStyle style) {
    if (text.isEmpty) return const [];
    final highlights = _ranges(text);
    final labels = _speakerLabelRanges(text);
    if (highlights.isEmpty && labels.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    final cuts = <int>{0, text.length};
    for (final h in highlights) {
      cuts.add(h.start);
      cuts.add(h.end);
    }
    for (final l in labels) {
      cuts.add(l.start);
      cuts.add(l.end);
    }
    final points = cuts.toList()..sort();
    final labelStyle = _speakerLabelStyle(style);
    final spans = <InlineSpan>[];

    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a >= b) continue;
      final mid = (a + b) ~/ 2;
      final inLabel = labels.any((l) => mid >= l.start && mid < l.end);
      final inHi = highlights.any((h) => mid >= h.start && mid < h.end);
      var s = inLabel ? labelStyle : style;
      if (inHi) s = s.copyWith(backgroundColor: _highlight);
      spans.add(TextSpan(text: text.substring(a, b), style: s));
    }
    return spans;
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
    int? replaceOptimisticId,
  }) async {
    final selected = text.trim();
    final source = _source;
    if (selected.isEmpty || widget.itemId == null || source == null) {
      return null;
    }
    try {
      final ann = await _repo.createAnnotation(
        widget.itemId!,
        selectedText: selected,
        startOffset: start,
        endOffset: end,
        note: note,
        source: source,
      );
      if (!mounted) return null;
      setState(() {
        if (replaceOptimisticId != null) {
          _annotations = [
            for (final a in _annotations)
              if (a.id == replaceOptimisticId) ann else a,
          ];
        } else {
          _annotations = [..._annotations, ann];
        }
      });
      return ann;
    } on ApiException catch (e) {
      if (!mounted) return null;
      if (replaceOptimisticId != null) {
        setState(() {
          _annotations = [
            for (final a in _annotations)
              if (a.id != replaceOptimisticId) a,
          ];
        });
      }
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
    final selected = text.trim();
    if (selected.isEmpty || !_canAnnotate) {
      _clearToolbar(state);
      return;
    }
    final optimisticId = _optimisticAnnId--;
    final optimistic = ItemAnnotation(
      id: optimisticId,
      itemId: widget.itemId!,
      source: _source!,
      selectedText: selected,
      startOffset: start,
      endOffset: end,
    );
    setState(() => _annotations = [..._annotations, optimistic]);
    _clearToolbar(state);
    final ann = await _createHighlight(
      text,
      start,
      end,
      replaceOptimisticId: optimisticId,
    );
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
    if (!_canAnnotate) return;
    final ann = await showCreateAnnotationNoteSheet(
      context,
      itemId: widget.itemId!,
      selectedText: text,
      startOffset: start,
      endOffset: end,
      source: _source,
      isPro: _isPro,
    );
    if (ann != null && mounted) {
      setState(() => _annotations = [..._annotations, ann]);
      AppToast.show(context, annotationSavedToast(isPro: _isPro));
    }
  }

  Future<void> _onCopy(EditableTextState state, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _clearToolbar(state);
    if (!mounted) return;
    AppToast.show(context, '已复制');
  }

  void _openAnnotation(ItemAnnotation ann) {
    if (widget.itemId == null || ann.id < 0) return;
    showAnnotationDetailSheet(
      context,
      itemId: widget.itemId!,
      annotation: ann,
      onChanged: _load,
      isPro: _isPro,
    );
  }

  Widget _selectionToolbar(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final value = editableTextState.textEditingValue;
    final sel = _trimSelection(value.text, value.selection);
    if (!sel.isValid || sel.isCollapsed) {
      return const SizedBox.shrink();
    }
    final selected = sel.textInside(value.text);
    if (selected.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final anchors = editableTextState.contextMenuAnchors;
    final start = sel.start;
    final end = sel.end;
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
        if (_canAnnotate) ...[
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
            label: addAnnotationLabel(isPro: _isPro),
            onTap: () => _onAddNote(
              editableTextState,
              selected,
              start,
              end,
            ),
          ),
        ],
        _ToolbarAction(
          label: '复制',
          onTap: () => _onCopy(editableTextState, selected),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _body;
    final size = ReadingFontPrefs.clamp(widget.fontSize);
    final bodyStyle = _bodyTextStyle;
    final ranges = _ranges(body);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const AppSubpageAppBar(title: '文稿'),
      body: body.isEmpty
          ? Center(
              child: Text(
                '暂无文稿',
                style: TextStyle(fontSize: size, color: _muted),
              ),
            )
          : ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              children: [
                if (_canAnnotate)
                  _TranscriptAnnotatedBody(
                    text: body,
                    spans: _spans(body, bodyStyle),
                    textStyle: bodyStyle,
                    annotations: ranges,
                    contextMenuBuilder: _selectionToolbar,
                    onTapAnnotation: _openAnnotation,
                    focusAnnotationId: widget.focusAnnotationId,
                    onFocusAnnotationRect: _onFocusAnnotationRect,
                  )
                else
                  TranscriptDisplay(
                    text: body,
                    cues: widget.cues,
                    bodyStyle: bodyStyle,
                  ),
              ],
            ),
    );
  }
}

/// 文稿可选中；高亮区域可点开详情（编辑批注 / 删除）。
class _TranscriptAnnotatedBody extends StatefulWidget {
  const _TranscriptAnnotatedBody({
    required this.text,
    required this.spans,
    required this.textStyle,
    required this.annotations,
    required this.contextMenuBuilder,
    required this.onTapAnnotation,
    this.focusAnnotationId,
    this.onFocusAnnotationRect,
  });

  final String text;
  final List<InlineSpan> spans;
  final TextStyle textStyle;
  final List<({int start, int end, ItemAnnotation ann})> annotations;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final ValueChanged<ItemAnnotation> onTapAnnotation;
  final int? focusAnnotationId;
  final void Function(Rect localRect, RenderBox stackBox)? onFocusAnnotationRect;

  @override
  State<_TranscriptAnnotatedBody> createState() =>
      _TranscriptAnnotatedBodyState();
}

class _TranscriptAnnotatedBodyState extends State<_TranscriptAnnotatedBody> {
  final GlobalKey _textKey = GlobalKey();
  final List<({Rect rect, ItemAnnotation ann, bool showNoteIcon})> _hits = [];
  int _measureToken = 0;
  int _measureMisses = 0;

  static const _blue = Color(0xFF2F6FED);
  static const _highlight = Color(0xFFFFF2C7);

  @override
  void didUpdateWidget(covariant _TranscriptAnnotatedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.annotations.length != widget.annotations.length ||
        oldWidget.spans.length != widget.spans.length) {
      _measureMisses = 0;
      _scheduleMeasure();
    }
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

  void _measure() {
    if (widget.annotations.isEmpty) {
      if (_hits.isNotEmpty) setState(() => _hits.clear());
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
    final origin = editable.localToGlobal(Offset.zero, ancestor: stackBox);
    final next = <({Rect rect, ItemAnnotation ann, bool showNoteIcon})>[];
    for (final r in widget.annotations) {
      if (r.ann.id < 0) continue;
      final trimmed = _trimRange(widget.text, r.start, r.end);
      if (trimmed.start >= trimmed.end) continue;
      final boxes = editable
          .getBoxesForSelection(
            TextSelection(
              baseOffset: trimmed.start,
              extentOffset: trimmed.end,
            ),
          )
          .where((b) => (b.right - b.left) > 1 && (b.bottom - b.top) > 1)
          .toList(growable: false);
      if (boxes.isEmpty) continue;
      final hasNote = (r.ann.note ?? '').trim().isNotEmpty;
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
    if (!mounted) return;
    setState(() {
      _hits
        ..clear()
        ..addAll(next);
    });

    final focusId = widget.focusAnnotationId;
    final onFocus = widget.onFocusAnnotationRect;
    if (focusId != null && onFocus != null) {
      for (final h in next) {
        if (h.ann.id == focusId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            onFocus(h.rect, stackBox);
          });
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    // 与阅读页一致：占满内容栏宽度 + 两端对齐，避免左宽右窄
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              TextSelectionTheme(
                data: const TextSelectionThemeData(
                  selectionColor: _highlight,
                  selectionHandleColor: _blue,
                ),
                child: SelectableText.rich(
                  TextSpan(style: widget.textStyle, children: widget.spans),
                  key: _textKey,
                  textAlign: TextAlign.justify,
                  contextMenuBuilder: widget.contextMenuBuilder,
                  selectionWidthStyle: BoxWidthStyle.tight,
                  selectionHeightStyle:
                      BoxHeightStyle.includeLineSpacingMiddle,
                ),
              ),
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
                        size: 16,
                        color: _blue,
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

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

({int start, int end}) _trimRange(String text, int start, int end) {
  var s = start.clamp(0, text.length);
  var e = end.clamp(0, text.length);
  while (s < e && _isTrimChar(text.codeUnitAt(s))) {
    s++;
  }
  while (e > s && _isTrimChar(text.codeUnitAt(e - 1))) {
    e--;
  }
  return (start: s, end: e);
}

TextSelection _trimSelection(String text, TextSelection sel) {
  if (!sel.isValid || sel.isCollapsed) return sel;
  final t = _trimRange(text, sel.start, sel.end);
  if (t.start == sel.start && t.end == sel.end) return sel;
  if (sel.baseOffset <= sel.extentOffset) {
    return TextSelection(baseOffset: t.start, extentOffset: t.end);
  }
  return TextSelection(baseOffset: t.end, extentOffset: t.start);
}

bool _isTrimChar(int code) {
  return code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0D ||
      code == 0x3000;
}
