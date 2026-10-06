import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 全屏编辑正文 Markdown 原文
Future<CollectionItem?> showReadingContentEditPage(
  BuildContext context, {
  required int itemId,
  required String initialContent,
}) {
  return Navigator.of(context).push<CollectionItem>(
    MaterialPageRoute(
      builder: (_) => ReadingContentEditPage(
        itemId: itemId,
        initialContent: initialContent,
      ),
    ),
  );
}

class ReadingContentEditPage extends StatefulWidget {
  const ReadingContentEditPage({
    super.key,
    required this.itemId,
    required this.initialContent,
  });

  final int itemId;
  final String initialContent;

  @override
  State<ReadingContentEditPage> createState() => _ReadingContentEditPageState();
}

class _ReadingContentEditPageState extends State<ReadingContentEditPage> {
  late final TextEditingController _controller;
  final _repo = ItemsRepository();
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(() {
      if (!_dirty && _controller.text != widget.initialContent) {
        setState(() => _dirty = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('当前编辑尚未保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final item = await _repo.updateContent(widget.itemId, _controller.text);
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
    final colors = AppColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: colors.card,
        appBar: AppBar(
          backgroundColor: colors.card,
          foregroundColor: colors.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (await _confirmDiscard() && mounted) {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            '编辑正文',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colors.ink,
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(
                _saving ? '保存中…' : '保存',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _saving ? colors.muted : colors.brand,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Text(
                '编辑 Markdown 原文。含图片 ![]()、内嵌视频 !v[]() 等语法，请勿随意删改标记行。',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.muted.withValues(alpha: 0.95),
                  height: 1.45,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.ink,
                    height: 1.55,
                    fontFamily: 'Menlo',
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colors.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
