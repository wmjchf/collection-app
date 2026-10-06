import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';

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
    return Material(
      color: AppColors.of(context).card,
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
                color: AppColors.of(context).iconMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '编辑感想',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.of(context).ink,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    '关闭',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.of(context).muted,
                    ),
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
              style: TextStyle(
                fontSize: 15,
                color: AppColors.of(context).ink,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: '写下读后的感想，方便以后找回…',
                hintStyle: TextStyle(
                  color: AppColors.of(context).muted,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: AppColors.of(context).inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(14),
                counterStyle: TextStyle(
                  fontSize: 11,
                  color: AppColors.of(context).muted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.of(context).brand,
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
    );
  }
}
