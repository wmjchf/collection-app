import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/item_thoughts.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_wiki_relate_sheet.dart';

class ThoughtEditResult {
  const ThoughtEditResult({
    required this.title,
    required this.text,
    this.format = ItemNoteFormat.plain,
    this.deleted = false,
  });

  const ThoughtEditResult.deleted()
      : title = '',
        text = '',
        format = ItemNoteFormat.plain,
        deleted = true;

  final String title;
  /// 纯文本正文。
  final String text;
  final ItemNoteFormat format;
  /// 用户在想法页点删除并确认。
  final bool deleted;
}

enum ThoughtPageMode { reading, editing }

/// 想法页：阅读态 / 编辑态；正文均为纯文本。
/// 手机全屏 push；平板居中浮卡（对齐设置子页）。
Future<ThoughtEditResult?> showReadingThoughtEditPage(
  BuildContext context, {
  String? initialTitle,
  String? initialText,
  ItemNoteFormat initialFormat = ItemNoteFormat.plain,
  /// 已有想法默认阅读；新建 / 助手划选默认编辑。
  ThoughtPageMode initialMode = ThoughtPageMode.editing,
  /// 阅读态划选「关联」时排除当前收藏；来自笔记页时传入。
  int? relateItemId,
  ItemsRepository? repository,
  /// 右上角显示删除（已有想法）；新建不展示。
  bool canDelete = false,
}) {
  final page = ReadingThoughtEditPage(
    initialTitle: initialTitle ?? '',
    initialText: initialText ?? '',
    initialFormat: initialFormat,
    initialMode: initialMode,
    relateItemId: relateItemId,
    repository: repository,
    canDelete: canDelete,
  );

  if (!AppOrientation.isTablet(context)) {
    return Navigator.of(context).push<ThoughtEditResult>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  final size = MediaQuery.sizeOf(context);
  final width = (size.width * 0.48).clamp(420.0, 560.0);
  final height = (size.height * 0.78).clamp(420.0, 760.0);

  return showGeneralDialog<ThoughtEditResult>(
    context: context,
    // 须走页内关闭以确认放弃修改 / 带回已保存结果
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.36),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return SizedBox.expand(
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: width,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MediaQuery(
                    data: MediaQuery.of(ctx).copyWith(
                      size: Size(width, height),
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                    ),
                    child: page,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class ReadingThoughtEditPage extends StatefulWidget {
  const ReadingThoughtEditPage({
    super.key,
    required this.initialTitle,
    required this.initialText,
    this.initialFormat = ItemNoteFormat.plain,
    this.initialMode = ThoughtPageMode.editing,
    /// 嵌入笔记浮卡等场景：关闭时回调而不 [Navigator.pop]。
    this.onClose,
    this.relateItemId,
    this.repository,
    this.canDelete = false,
  });

  final String initialTitle;
  final String initialText;
  final ItemNoteFormat initialFormat;
  final ThoughtPageMode initialMode;
  final ValueChanged<ThoughtEditResult?>? onClose;
  final int? relateItemId;
  final ItemsRepository? repository;
  final bool canDelete;

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
    final result = _sessionSaved;
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
    } else {
      Navigator.pop(context, result);
    }
  }

  Future<void> _onDelete() async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除想法？',
      message: '删除后不可恢复。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;
    const result = ThoughtEditResult.deleted();
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose(result);
    } else {
      Navigator.pop(context, result);
    }
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
        format: ItemNoteFormat.plain,
      );
      _baselineTitle = _title.text;
      _baselineText = _body.text;
      _dirty = false;
    }
    _enterReading();
  }

  Future<void> _onWikiRelate(String text, VoidCallback clearSelection) async {
    final selected = text.trim();
    clearSelection();
    if (selected.isEmpty || !mounted) return;
    await showReadingWikiRelateSheet(
      context,
      selectedText: selected,
      excludeItemId: widget.relateItemId,
      repository: widget.repository ?? ItemsRepository(),
    );
  }

  Widget _readingSelectionToolbar({
    required TextSelectionToolbarAnchors anchors,
    required String selected,
    required VoidCallback clearSelection,
  }) {
    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (context, child) {
        return Material(
          color: const Color(0xFF1F242E),
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          child: child,
        );
      },
      children: [
        _ThoughtToolbarAction(
          label: '关联',
          onTap: () => unawaited(_onWikiRelate(selected, clearSelection)),
        ),
        _ThoughtToolbarAction(
          label: '复制',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: selected));
            clearSelection();
            if (mounted) AppToast.show(context, '已复制');
          },
        ),
      ],
    );
  }

  EditableTextContextMenuBuilder get _readingContextMenu {
    return (context, state) {
      final value = state.textEditingValue;
      final sel = value.selection;
      if (!sel.isValid || sel.isCollapsed) {
        return const SizedBox.shrink();
      }
      final selected = sel.textInside(value.text);
      if (selected.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      return _readingSelectionToolbar(
        anchors: state.contextMenuAnchors,
        selected: selected,
        clearSelection: () {
          ContextMenuController.removeAny();
          state.hideToolbar();
          state.userUpdateTextEditingValue(
            value.copyWith(
              selection: TextSelection.collapsed(offset: sel.end),
            ),
            SelectionChangedCause.toolbar,
          );
        },
      );
    };
  }

  Widget _readingBody() {
    final title = _title.text.trim();
    final body = _body.text.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
      children: [
        SelectableText(
          title.isEmpty ? '未命名' : title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: title.isEmpty ? const Color(0xFFC5CAD3) : _text,
            height: 1.25,
            letterSpacing: -0.3,
          ),
          contextMenuBuilder: title.isEmpty ? null : _readingContextMenu,
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
          SelectableText(
            body,
            style: const TextStyle(
              fontSize: 17,
              color: _text,
              height: 1.55,
            ),
            contextMenuBuilder: _readingContextMenu,
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
          title: const Text(
            '想法',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          actions: [
            if (widget.canDelete)
              IconButton(
                tooltip: '删除',
                onPressed: () => unawaited(_onDelete()),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 22,
                  color: Color(0xFFE34D59),
                ),
              ),
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

class _ThoughtToolbarAction extends StatelessWidget {
  const _ThoughtToolbarAction({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
