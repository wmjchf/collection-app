import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/features/agent/agent_markdown.dart';
import 'package:super_collection/features/items/item_thoughts.dart';

class ThoughtEditResult {
  const ThoughtEditResult({
    required this.title,
    required this.text,
    this.format = ItemNoteFormat.markdown,
  });

  final String title;
  /// 正文源：当前为 Markdown（可当纯文本写）；日后富文本编辑器仍序列化为此字段。
  final String text;
  final ItemNoteFormat format;
}

enum ThoughtPageMode { reading, editing }

/// 全屏想法页：阅读态（MD 渲染）/ 编辑态（标题+正文源）。
/// 正文按 Markdown 源编辑/保存，便于日后换富文本壳而不改存储。
Future<ThoughtEditResult?> showReadingThoughtEditPage(
  BuildContext context, {
  String? initialTitle,
  String? initialText,
  ItemNoteFormat initialFormat = ItemNoteFormat.markdown,
  /// 已有想法默认阅读；新建 / 助手划选默认编辑。
  ThoughtPageMode initialMode = ThoughtPageMode.editing,
}) {
  return Navigator.of(context).push<ThoughtEditResult>(
    MaterialPageRoute(
      builder: (_) => ReadingThoughtEditPage(
        initialTitle: initialTitle ?? '',
        initialText: initialText ?? '',
        initialFormat: initialFormat,
        initialMode: initialMode,
      ),
    ),
  );
}

class ReadingThoughtEditPage extends StatefulWidget {
  const ReadingThoughtEditPage({
    super.key,
    required this.initialTitle,
    required this.initialText,
    this.initialFormat = ItemNoteFormat.markdown,
    this.initialMode = ThoughtPageMode.editing,
  });

  final String initialTitle;
  final String initialText;
  final ItemNoteFormat initialFormat;
  final ThoughtPageMode initialMode;

  @override
  State<ReadingThoughtEditPage> createState() => _ReadingThoughtEditPageState();
}

class _ReadingThoughtEditPageState extends State<ReadingThoughtEditPage> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  late final TextEditingController _title;
  late final TextEditingController _body;
  late final FocusNode _titleFocus;
  late final FocusNode _bodyFocus;
  late ThoughtPageMode _mode;
  late String _baselineTitle;
  late String _baselineText;
  /// 本会话内点开书提交过的版本；关闭时带回给外层写库。
  ThoughtEditResult? _sessionSaved;
  bool _dirty = false;

  bool get _isReading => _mode == ThoughtPageMode.reading;

  bool get _canCommit {
    final title = _title.text.trim();
    final text = _body.text.trim();
    return title.isNotEmpty && text.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _baselineTitle = widget.initialTitle;
    _baselineText = widget.initialText;
    _title = TextEditingController(text: widget.initialTitle);
    _body = TextEditingController(text: widget.initialText);
    _titleFocus = FocusNode();
    _bodyFocus = FocusNode();
    void markDirty() {
      final dirty =
          _title.text != _baselineTitle || _body.text != _baselineText;
      if (dirty != _dirty) setState(() => _dirty = dirty);
    }

    _title.addListener(markDirty);
    _body.addListener(markDirty);
    if (!_isReading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.initialText.trim().isEmpty &&
            widget.initialTitle.trim().isEmpty) {
          _titleFocus.requestFocus();
        } else {
          _bodyFocus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showAppConfirmDialog(
      context,
      title: '放弃修改？',
      message: '当前编辑尚未保存。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃',
    );
    return ok == true;
  }

  Future<void> _close() async {
    if (!await _confirmDiscard() || !mounted) return;
    // 仅当本会话点过开书提交时才回写；纯阅读关闭不触达写库。
    Navigator.pop(context, _sessionSaved);
  }

  void _enterReading() {
    _titleFocus.unfocus();
    _bodyFocus.unfocus();
    setState(() => _mode = ThoughtPageMode.reading);
  }

  void _enterEditing() {
    setState(() => _mode = ThoughtPageMode.editing);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  /// 开书图标：可提交则记为已保存并进阅读；否则仅预览阅读态。
  void _onBookTap() {
    if (_canCommit) {
      _sessionSaved = ThoughtEditResult(
        title: _title.text.trim(),
        text: _body.text.trim(),
        format: ItemNoteFormat.markdown,
      );
      _baselineTitle = _title.text;
      _baselineText = _body.text;
      _dirty = false;
    }
    _enterReading();
  }

  Widget _readingBody() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
      children: [
        Text(
          title.isEmpty ? '未命名' : title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: title.isEmpty ? const Color(0xFFC5CAD3) : _text,
            height: 1.25,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 14),
        if (body.isEmpty)
          const Text(
            '暂无正文',
            style: TextStyle(
              fontSize: 17,
              color: Color(0xFFC5CAD3),
              height: 1.55,
            ),
          )
        else
          AgentMarkdown(
            body,
            style: const TextStyle(
              fontSize: 17,
              color: _text,
              height: 1.55,
            ),
          ),
      ],
    );
  }

  Widget _editingBody() {
    return GestureDetector(
      onTap: () => _bodyFocus.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
        children: [
          TextField(
            controller: _title,
            focusNode: _titleFocus,
            maxLines: null,
            maxLength: 80,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _bodyFocus.requestFocus(),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _text,
              height: 1.25,
              letterSpacing: -0.3,
            ),
            cursorColor: _blue,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterText: '',
              hintText: '标题',
              hintStyle: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFFC5CAD3),
                height: 1.25,
                letterSpacing: -0.3,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _body,
            focusNode: _bodyFocus,
            maxLines: null,
            minLines: 12,
            maxLength: 2000,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              color: _text,
              height: 1.55,
            ),
            cursorColor: _blue,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _close();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _text,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => unawaited(_close()),
          ),
          actions: [
            if (_isReading)
              IconButton(
                tooltip: '编辑',
                onPressed: _enterEditing,
                icon: const Icon(Icons.edit_outlined, size: 22),
              )
            else
              IconButton(
                tooltip: _canCommit ? '保存并阅读' : '阅读',
                onPressed: _onBookTap,
                icon: Icon(
                  Icons.menu_book_outlined,
                  size: 22,
                  color: _canCommit ? _text : _muted,
                ),
              ),
          ],
        ),
        body: _isReading ? _readingBody() : _editingBody(),
      ),
    );
  }
}
