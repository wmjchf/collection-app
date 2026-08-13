import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/core/ui/app_toast.dart';

Future<CollectionItem?> showReadingNoteSheet(
  BuildContext context, {
  required int itemId,
  String? initialNote,
}) {
  return showModalBottomSheet<CollectionItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _ReadingNoteSheet(
        itemId: itemId,
        initialNote: initialNote,
      ),
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
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _handle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      '编辑备注',
                      style: TextStyle(
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
                TextField(
                  controller: _controller,
                  maxLines: 5,
                  maxLength: 2000,
                  autofocus: true,
                  style: const TextStyle(fontSize: 15, color: _text, height: 1.5),
                  decoration: InputDecoration(
                    hintText: '写一点备忘，方便以后找回…',
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
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_saving ? '保存中…' : '保存'),
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
