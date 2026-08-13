import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/utils/link_utils.dart';
import 'package:super_collection/features/items/item_detail_page.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 弹出「添加链接」底部弹框（对齐 Figma）。
/// 可预填 [initialUrl]；若为空则尝试读取剪贴板中的 URL。
/// 暂无本地 mock 保存；后端接入后替换 [_save]。
Future<void> showAddLinkSheet(
  BuildContext context, {
  String? initialUrl,
}) async {
  var url = initialUrl?.trim() ?? '';
  if (url.isEmpty) {
    url = await _readClipboardUrl() ?? '';
  }

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x73000000),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: AddLinkSheet(initialUrl: url),
      );
    },
  );
}

Future<String?> _readClipboardUrl() async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return null;
    return extractHttpUrl(text);
  } catch (_) {
    return null;
  }
}

bool _isValidUrl(String value) => isValidHttpUrl(value);

class AddLinkSheet extends StatefulWidget {
  const AddLinkSheet({super.key, this.initialUrl = ''});

  final String initialUrl;

  @override
  State<AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<AddLinkSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _fieldBg = Color(0xFFF5F7FA);
  static const _blue = Color(0xFF2F6FED);
  static const _blueLoading = Color(0xFF8CADF2);
  static const _handle = Color(0xFFD9DBE0);

  late final TextEditingController _controller;
  final _items = ItemsRepository();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    if (_saving) return;
    Navigator.of(context).pop();
  }

  Future<void> _onSave() async {
    if (_saving) return;
    final url = _controller.text.trim();
    if (!_isValidUrl(url)) {
      setState(() => _error = '请输入有效的 http(s) 链接');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final result = await _items.createItem(url);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.existed ? '该链接已收藏' : '已保存：${result.item.title ?? ''}',
          ),
        ),
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ItemDetailPage(
            itemId: result.item.id,
            initialItem: result.item,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请检查网络或后端是否启动';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: !_saving,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + bottom),
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
            const SizedBox(height: 14),
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  const Text(
                    '添加链接',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _close,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 15,
                        color: _saving ? _muted.withValues(alpha: 0.4) : _muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '链接',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              enabled: !_saving,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 13, color: _text),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _onSave(),
              decoration: InputDecoration(
                hintText: '粘贴或输入链接',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: _muted.withValues(alpha: 0.7),
                ),
                filled: true,
                fillColor: _fieldBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
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
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE34D59)),
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  disabledBackgroundColor: _blueLoading,
                  disabledForegroundColor: Colors.white,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            '保存中…',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        '保存',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              const Text(
                '正在获取标题并保存',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
