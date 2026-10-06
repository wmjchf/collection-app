import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
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
  bool isPro = false,
}) {
  return showAppBottomSheet<ItemAnnotation>(
    context: context,
    builder: (context) => _AnnotationNoteSheet(
      itemId: itemId,
      selectedText: selectedText,
      startOffset: startOffset,
      endOffset: endOffset,
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
    this.onChanged,
    this.isCreate = false,
    this.isPro = false,
  });

  final int itemId;
  final ItemAnnotation? annotation;
  final String selectedText;
  final String? initialNote;
  final int? startOffset;
  final int? endOffset;
  final VoidCallback? onChanged;
  final bool isCreate;
  final bool isPro;

  @override
  State<_AnnotationNoteSheet> createState() => _AnnotationNoteSheetState();
}

class _AnnotationNoteSheetState extends State<_AnnotationNoteSheet> {
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

  Future<void> _delete() async {
    if (widget.isCreate || widget.annotation == null) {
      Navigator.pop(context);
      return;
    }
    final ok = await showAppConfirmDialog(
      context,
      title: deleteAnnotationTitle(isPro: widget.isPro),
      message: '删除后不可恢复。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteAnnotation(widget.itemId, widget.annotation!.id);
      if (!mounted) return;
      widget.onChanged?.call();
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.card,
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
                  color: colors.iconMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  annotationSheetTitle(
                    isPro: widget.isPro,
                    isCreate: widget.isCreate,
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.ink,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    '关闭',
                    style: TextStyle(fontSize: 14, color: colors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _quotePreview,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.muted,
                  height: 1.4,
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
              style: TextStyle(
                fontSize: 14,
                color: colors.ink,
                height: 1.45,
              ),
              decoration: InputDecoration(
                hintText: annotationNoteHint(isPro: widget.isPro),
                hintStyle: TextStyle(color: colors.muted, fontSize: 14),
                filled: true,
                fillColor: colors.inputBg,
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
                      onPressed: _delete,
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.inputBg,
                        foregroundColor: colors.ink,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.isCreate
                            ? '取消'
                            : deleteAnnotationLabel(isPro: widget.isPro),
                        style: const TextStyle(
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
                        backgroundColor: colors.brand,
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
