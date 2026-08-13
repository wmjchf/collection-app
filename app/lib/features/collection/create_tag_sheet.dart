import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';

/// 弹出「新建标签」弹框；成功返回 [Tag]，关闭返回 null。
Future<Tag?> showCreateTagSheet(BuildContext context) {
  return showModalBottomSheet<Tag>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const CreateTagSheet(),
      );
    },
  );
}

class CreateTagSheet extends StatefulWidget {
  const CreateTagSheet({super.key});

  @override
  State<CreateTagSheet> createState() => _CreateTagSheetState();
}

class _CreateTagSheetState extends State<CreateTagSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _fieldBg = Color(0xFFF5F7FA);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFE5E8ED);

  late final TextEditingController _controller;
  final _tags = TagsRepository();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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

  Future<void> _onCreate() async {
    if (_submitting) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入标签名称');
      return;
    }
    if (name.length > 64) {
      setState(() => _error = '名称最多 64 个字');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final tag = await _tags.createTag(name);
      if (!mounted) return;
      Navigator.of(context).pop(tag);
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + (bottom > 0 ? bottom : 0)),
      child: Material(
        color: Colors.white,
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
                  color: _handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 27,
                child: Row(
                  children: [
                    const Text(
                      '新建标签',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text,
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
                              ? _muted.withValues(alpha: 0.4)
                              : _muted,
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
                style: const TextStyle(fontSize: 15, color: _text),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _onCreate(),
                decoration: InputDecoration(
                  hintText: '例如：读书',
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
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE34D59),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _onCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    disabledBackgroundColor: _blue.withValues(alpha: 0.6),
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
                      : const Text(
                          '创建',
                          style: TextStyle(
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
