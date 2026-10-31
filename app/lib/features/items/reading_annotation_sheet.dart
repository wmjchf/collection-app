import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/pro_copy.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

Future<void> showAnnotationDetailSheet(
  BuildContext context, {
  required int itemId,
  required ItemAnnotation annotation,
  required VoidCallback onChanged,
  bool isPro = false,
  Future<void> Function(String quote, Rect? shareOrigin, {String? note})? onShare,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (context) => _AnnotationNoteSheet(
      itemId: itemId,
      annotation: annotation,
      selectedText: annotation.selectedText,
      initialNote: annotation.note,
      onChanged: onChanged,
      isPro: isPro,
      onShare: onShare,
    ),
  );
}

/// 选中文字后「加批注」：创建标注并写入批注。
Future<ItemAnnotation?> showCreateAnnotationNoteSheet(
  BuildContext context, {
  required int itemId,
  required String selectedText,
  int? startOffset,
  int? endOffset,
  String? source,
  bool isPro = false,
}) {
  return showAppBottomSheet<ItemAnnotation>(
    context: context,
    builder: (context) => _AnnotationNoteSheet(
      itemId: itemId,
      selectedText: selectedText,
      startOffset: startOffset,
      endOffset: endOffset,
      source: source,
      isCreate: true,
      isPro: isPro,
    ),
  );
}

class _AnnotationNoteSheet extends StatefulWidget {
  const _AnnotationNoteSheet({
    required this.itemId,
    required this.selectedText,
    this.annotation,
    this.initialNote,
    this.startOffset,
    this.endOffset,
    this.source,
    this.onChanged,
    this.onShare,
    this.isCreate = false,
    this.isPro = false,
  });

  final int itemId;
  final ItemAnnotation? annotation;
  final String selectedText;
  final String? initialNote;
  final int? startOffset;
  final int? endOffset;
  final String? source;
  final VoidCallback? onChanged;
  final Future<void> Function(String quote, Rect? shareOrigin, {String? note})?
      onShare;
  final bool isCreate;
  final bool isPro;

  @override
  State<_AnnotationNoteSheet> createState() => _AnnotationNoteSheetState();
}

class _AnnotationNoteSheetState extends State<_AnnotationNoteSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _fieldBg = Color(0xFFF5F7FA);
  static const _handle = Color(0xFFE5E8ED);

  late final TextEditingController _controller;
  final _repo = ItemsRepository();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _quotePreview {
    final q = widget.selectedText.trim();
    if (q.length <= 36) return '「$q」';
    return '「${q.substring(0, 36)}…」';
  }

  /// 已有高亮记录、但还没有批注正文（影响弹框标题）
  bool get _highlightOnly {
    if (widget.isCreate || widget.annotation == null) return false;
    return (widget.annotation!.note ?? '').trim().isEmpty;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final note = _controller.text.trim();
    try {
      if (widget.isCreate) {
        final ann = await _repo.createAnnotation(
          widget.itemId,
          selectedText: widget.selectedText.trim(),
          startOffset: widget.startOffset,
          endOffset: widget.endOffset,
          note: note.isEmpty ? null : note,
          source: widget.source,
        );
        if (!mounted) return;
        Navigator.pop(context, ann);
        return;
      }
      await _repo.updateAnnotationNote(
        widget.itemId,
        widget.annotation!.id,
        note.isEmpty ? null : note,
      );
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final share = widget.onShare;
    final quote = widget.selectedText.trim();
    if (share == null || quote.isEmpty) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize && !box.size.isEmpty
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final note = (widget.annotation?.note ?? widget.initialNote ?? '').trim();
    Navigator.pop(context);
    await share(quote, origin, note: note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
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
            Text(
              annotationSheetTitle(
                isPro: widget.isPro,
                isCreate: widget.isCreate,
                highlightOnly: _highlightOnly,
              ),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(text: _quotePreview),
                    if (!widget.isCreate && widget.onShare != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Builder(
                          builder: (buttonContext) => GestureDetector(
                            onTap: () => _share(buttonContext),
                            child: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.ios_share_rounded,
                                    size: 14,
                                    color: _blue,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    '分享',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600,
                                      color: _blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 3,
              maxLength: 500,
              autofocus: true,
              style: const TextStyle(
                fontSize: 14,
                color: _text,
                height: 1.45,
              ),
              decoration: InputDecoration(
                hintText: annotationNoteHint(isPro: widget.isPro),
                hintStyle: const TextStyle(color: _muted, fontSize: 14),
                filled: true,
                fillColor: _fieldBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: _fieldBg,
                        foregroundColor: _text,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _saving ? '保存中…' : '保存',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
