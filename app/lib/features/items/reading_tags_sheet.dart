import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/core/ui/app_toast.dart';

enum ReadingTagsSheetResult { aiSuggest, createTag }

class _TagsSheetSession {
  final Set<int> selectedIds = {};
}

Future<ReadingTagsSheetResult?> showReadingTagsSheet(
  BuildContext context, {
  required int itemId,
  bool aiSuggestEnabled = true,
  bool aiSuggestPending = false,
}) async {
  final session = _TagsSheetSession();

  while (true) {
    final result = await showModalBottomSheet<ReadingTagsSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x59000000),
      builder: (context) => _ReadingTagsSheet(
        itemId: itemId,
        session: session,
        aiSuggestEnabled: aiSuggestEnabled,
        aiSuggestPending: aiSuggestPending,
      ),
    );
    if (result != ReadingTagsSheetResult.createTag) {
      return result;
    }
    if (!context.mounted) return null;
    final created = await showCreateTagSheet(context);
    if (created != null) {
      session.selectedIds.add(created.id);
    }
  }
}

class _ReadingTagsSheet extends StatefulWidget {
  const _ReadingTagsSheet({
    required this.itemId,
    required this.session,
    required this.aiSuggestEnabled,
    required this.aiSuggestPending,
  });

  final int itemId;
  final _TagsSheetSession session;
  final bool aiSuggestEnabled;
  final bool aiSuggestPending;

  @override
  State<_ReadingTagsSheet> createState() => _ReadingTagsSheetState();
}

class _ReadingTagsSheetState extends State<_ReadingTagsSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _chipOn = Color(0xFFE5EDFF);
  static const _handle = Color(0xFFE5E8ED);

  final _tagsRepo = TagsRepository();
  final _itemsRepo = ItemsRepository();
  List<Tag> _all = const [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await _tagsRepo.listTags();
      final current = await _itemsRepo.listItemTags(widget.itemId);
      if (!mounted) return;
      setState(() {
        _all = all.where((t) => !t.isSystem).toList();
        _selected
          ..clear()
          ..addAll(
            widget.session.selectedIds.isNotEmpty
                ? widget.session.selectedIds
                : current.map((t) => t.id),
          );
        _loading = false;
      });
      _syncSession();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  void _syncSession() {
    widget.session.selectedIds
      ..clear()
      ..addAll(_selected);
  }

  void _createTag() {
    _syncSession();
    Navigator.pop(context, ReadingTagsSheetResult.createTag);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _itemsRepo.setItemTags(widget.itemId, _selected.toList());
      if (!mounted) return;
      Navigator.pop(context);
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

  void _onAiSuggest() {
    if (widget.aiSuggestEnabled) {
      Navigator.pop(context, ReadingTagsSheetResult.aiSuggest);
      return;
    }
    AppToast.show(
      context,
      widget.aiSuggestPending
          ? '标签建议生成中，请稍候'
          : '内容不足，无法生成标签建议',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      '选择标签',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HeaderActionButton(
                      icon: Icons.auto_awesome_outlined,
                      label: widget.aiSuggestPending
                          ? 'AI 生成中…'
                          : 'AI 建议标签',
                      onTap: _onAiSuggest,
                      foreground:
                          widget.aiSuggestEnabled ? _blue : _muted,
                      borderColor: widget.aiSuggestEnabled
                          ? const Color(0xFFB8CCFA)
                          : const Color(0xFFE8ECF0),
                    ),
                    const SizedBox(width: 6),
                    _HeaderActionButton(
                      icon: Icons.add,
                      label: '新建',
                      onTap: _createTag,
                      foreground: _text,
                      borderColor: const Color(0xFFE8ECF0),
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
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_error!, style: const TextStyle(color: _muted)),
                  )
                else if (_all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '还没有标签，可点「新建」或使用 AI 建议',
                      style: TextStyle(
                        fontSize: 13,
                        color: _muted,
                        height: 1.4,
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.start,
                    children: [
                      for (final tag in _all)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_selected.contains(tag.id)) {
                                _selected.remove(tag.id);
                              } else {
                                _selected.add(tag.id);
                              }
                              _syncSession();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _selected.contains(tag.id)
                                  ? _chipOn
                                  : _chipBg,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              tag.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _selected.contains(tag.id)
                                    ? _blue
                                    : _text,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading || _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_saving ? '保存中…' : '完成'),
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

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.foreground,
    required this.borderColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color foreground;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
