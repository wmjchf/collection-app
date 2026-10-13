import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

Future<CollectionItem?> showReadingNoteSheet(
  BuildContext context, {
  required int itemId,
  String? initialNote,
}) {
  return showAppBottomSheet<CollectionItem>(
    context: context,
    builder: (context) => _ReadingNoteSheet(
      itemId: itemId,
      initialNote: initialNote,
    ),
  );
}

class _ReadingNoteSheet extends StatefulWidget {
  const _ReadingNoteSheet({
    required this.itemId,
    this.initialNote,
  });

  final int itemId;
  final String? initialNote;

  @override
  State<_ReadingNoteSheet> createState() => _ReadingNoteSheetState();
}

class _ReadingNoteSheetState extends State<_ReadingNoteSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _fieldBg = Color(0xFFF5F7FA);
  static const _handle = Color(0xFFE5E8ED);

  late final TextEditingController _controller;
  final _repo = ItemsRepository();
  bool _saving = false;
  late bool _editing;

  String get _savedNote => (widget.initialNote ?? '').trim();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote ?? '');
    // 已有内容先看；空白才直接编辑
    _editing = _savedNote.isEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final item = await _repo.updateNote(
        widget.itemId,
        _controller.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, item);
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _handle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '感想',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _editing
                        ? (_saving ? null : _save)
                        : _startEdit,
                    style: TextButton.styleFrom(
                      foregroundColor: _blue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      _editing ? (_saving ? '保存中…' : '保存') : '编辑',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (_editing)
              TextField(
                controller: _controller,
                maxLines: 5,
                maxLength: 2000,
                autofocus: true,
                style: const TextStyle(fontSize: 15, color: _text, height: 1.5),
                decoration: InputDecoration(
                  hintText: '写下读后的感想，方便以后找回…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 14),
                  filled: true,
                  fillColor: _fieldBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                  counterStyle: const TextStyle(fontSize: 11, color: _muted),
                ),
              )
            else
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 120),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _fieldBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _savedNote,
                  style: const TextStyle(
                    fontSize: 15,
                    color: _text,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
