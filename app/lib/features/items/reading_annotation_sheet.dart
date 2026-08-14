import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';


Future<void> showAnnotationDetailSheet(
  BuildContext context, {
  required int itemId,
  required ItemAnnotation annotation,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _AnnotationNoteSheet(
        itemId: itemId,
        annotation: annotation,
        selectedText: annotation.selectedText,
        initialNote: annotation.note,
        onChanged: onChanged,
      ),
    ),
  );
}

/// 选中文字后「加短注」：创建标注并写入短注。
Future<ItemAnnotation?> showCreateAnnotationNoteSheet(
  BuildContext context, {
  required int itemId,
  required String selectedText,
  int? startOffset,
  int? endOffset,
}) {
  return showModalBottomSheet<ItemAnnotation>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _AnnotationNoteSheet(
        itemId: itemId,
        selectedText: selectedText,
        startOffset: startOffset,
        endOffset: endOffset,
        isCreate: true,
      ),
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
  });

  final int itemId;
  final ItemAnnotation? annotation;
  final String selectedText;
  final String? initialNote;
  final int? startOffset;
  final int? endOffset;
  final VoidCallback? onChanged;
  final bool isCreate;

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
      title: '删除标注？',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Material(
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
                Row(
                  children: [
                    Text(
                      widget.isCreate ? '添加短注' : '标注短注',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        '关闭',
                        style: TextStyle(fontSize: 14, color: _muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _fieldBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _quotePreview,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _muted,
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
                  style: const TextStyle(
                    fontSize: 14,
                    color: _text,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    hintText: '可选：写一句短注',
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
                          onPressed: _delete,
                          style: FilledButton.styleFrom(
                            backgroundColor: _fieldBg,
                            foregroundColor: _text,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            widget.isCreate ? '取消' : '删除标注',
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
        ),
      ),
    );
  }
}
