import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';

/// 弹出「新建归类」弹框；成功返回 [TagModule]。
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
  return showModalBottomSheet<TagModule>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    useSafeArea: false,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom,
        ),
        child: _ModuleNameSheet(module: module),
      );
    },
  );
}

class _ModuleNameSheet extends StatefulWidget {
  const _ModuleNameSheet({this.module});

  final TagModule? module;

  @override
  State<_ModuleNameSheet> createState() => _ModuleNameSheetState();
}

class _ModuleNameSheetState extends State<_ModuleNameSheet> {
  late final TextEditingController _controller;
  final _repo = TagModulesRepository();
  String? _error;
  bool _submitting = false;

  bool get _isRename => widget.module != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.module?.name ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (_submitting) return;
    Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final colors = AppColors.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + (bottom > 0 ? bottom : 0)),
      child: Material(
        color: colors.card,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.iconMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 27,
                child: Row(
                  children: [
                    Text(
                      _isRename ? '修改名称' : '新建归类',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _close,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        '关闭',
                        style: TextStyle(
                          fontSize: 14,
                          color: _submitting
                              ? colors.muted.withValues(alpha: 0.4)
                              : colors.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                enabled: !_submitting,
                autofocus: true,
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 15, color: colors.ink),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _onSubmit(),
                decoration: InputDecoration(
                  hintText: '例如：工作 / 学习',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: colors.placeholder,
                  ),
                  filled: true,
                  fillColor: colors.inputBg,
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
                    borderSide: BorderSide(color: colors.brand, width: 1.5),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.danger,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.brand,
                    disabledBackgroundColor:
                        colors.brand.withValues(alpha: 0.45),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isRename ? '保存' : '创建',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
