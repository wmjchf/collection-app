import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 阅读页修改标题（底部 sheet，对齐感想）
Future<CollectionItem?> showReadingTitleEditDialog(
  BuildContext context, {
  required int itemId,
  required String initialTitle,
}) {
  return showAppBottomSheet<CollectionItem>(
    context: context,
    builder: (context) => _ReadingTitleEditSheet(
      itemId: itemId,
      initialTitle: initialTitle,
    ),
  );
}

class _ReadingTitleEditSheet extends StatefulWidget {
  const _ReadingTitleEditSheet({
    required this.itemId,
    required this.initialTitle,
  });

  final int itemId;
  final String initialTitle;

  @override
  State<_ReadingTitleEditSheet> createState() => _ReadingTitleEditSheetState();
}

class _ReadingTitleEditSheetState extends State<_ReadingTitleEditSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _fieldBg = Color(0xFFF5F7FA);
  static const _handle = Color(0xFFE5E8ED);
  static const _maxLen = 500;

  late final TextEditingController _controller;
  late final FocusNode _focus;
  final _repo = ItemsRepository();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final next = _controller.text.trim();
    if (next.isEmpty) {
      AppToast.show(context, '标题不能为空');
      return;
    }
    if (next == widget.initialTitle.trim()) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      final item = await _repo.updateTitle(widget.itemId, next);
      if (!mounted) return;
      Navigator.pop(context, item);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, '保存失败，请稍后重试');
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
                      '修改标题',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _save,
                    style: TextButton.styleFrom(
                      foregroundColor: _blue,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      _saving ? '保存中…' : '保存',
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: !_saving,
                maxLength: _maxLen,
                maxLines: 4,
                minLines: 2,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_saving) _save();
                },
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 15,
                  color: _text,
                  height: 1.5,
                ),
                cursorColor: _blue,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: '输入标题',
                  hintStyle: const TextStyle(
                    color: _muted,
                    fontSize: 14,
                  ),
                  contentPadding: EdgeInsets.zero,
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_controller.text.characters.length}/$_maxLen',
                style: const TextStyle(
                  fontSize: 11,
                  color: _muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
