import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';

/// 弹出「创建归类」弹框；成功返回 [TagModule]。
Future<TagModule?> showCreateModuleSheet(BuildContext context) {
  return _showModuleNameSheet(context);
}

/// 弹出「修改归类名」弹框；成功返回更新后的 [TagModule]。
Future<TagModule?> showRenameModuleSheet(
  BuildContext context, {
  required TagModule module,
}) {
  return _showModuleNameSheet(context, module: module);
}

Future<TagModule?> _showModuleNameSheet(
  BuildContext context, {
  TagModule? module,
}) {
  return showAppBottomSheet<TagModule>(
    context: context,
    builder: (context) => _ModuleNameSheet(module: module),
  );
}

class _ModuleNameSheet extends StatefulWidget {
  const _ModuleNameSheet({this.module});

  final TagModule? module;

  @override
  State<_ModuleNameSheet> createState() => _ModuleNameSheetState();
}

class _ModuleNameSheetState extends State<_ModuleNameSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _fieldBg = Color(0xFFF5F7FA);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFE5E8ED);

  late final TextEditingController _controller;
  late final FocusNode _focus;
  final _repo = TagModulesRepository();
  String? _error;
  bool _submitting = false;

  bool get _isRename => widget.module != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.module?.name ?? '');
    _focus = FocusNode();
    // 与「感想」一致：首帧后再抢焦点，避免弹层未落稳时键盘顶出灰遮罩
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

  Future<void> _onSubmit() async {
    if (_submitting) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入归类名称');
      return;
    }
    if (name.length > 64) {
      setState(() => _error = '名称最多 64 个字');
      return;
    }

    final existing = widget.module;
    if (existing != null && name == existing.name) {
      Navigator.of(context).pop(existing);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final module = existing == null
          ? await _repo.createModule(name)
          : await _repo.renameModule(existing.id, name);
      if (!mounted) return;
      Navigator.of(context).pop(module);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '创建失败，请检查网络或后端是否启动';
      });
    }
  }

  InputDecoration _fieldDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 15, color: _muted),
      filled: true,
      fillColor: _fieldBg,
      contentPadding: const EdgeInsets.all(14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _blue, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 与「感想」同壳：白底圆角卡 + 拖条，外边距交给 AppBottomSheetShell
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _isRename ? '修改名称' : '创建归类',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: !_submitting,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15, color: _text),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _onSubmit(),
              decoration: _fieldDecoration(hint: '例如：工作 / 学习'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFD14343),
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _submitting ? null : _onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  disabledBackgroundColor: _blue.withValues(alpha: 0.45),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isRename ? '保存' : '创建',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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
