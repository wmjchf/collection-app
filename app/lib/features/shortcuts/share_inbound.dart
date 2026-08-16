import 'package:flutter/services.dart';
import 'package:super_collection/core/utils/link_utils.dart';
import 'package:super_collection/features/shortcuts/shortcut_inbound.dart';

/// Android `ACTION_SEND` 文本分享入口（iOS 走 Share Extension → deep link）。
class ShareInbound {
  ShareInbound._();

  static const _channel = MethodChannel('com.bufang.supercollection/share');
  static bool _listening = false;

  static Future<void> start() async {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments?.toString() ?? '';
        await _handleSharedText(text);
      }
    });
    try {
      final text = await _channel.invokeMethod<String>('getSharedText');
      if (text != null && text.isNotEmpty) {
        await _handleSharedText(text);
      }
    } catch (_) {}
  }

  static Future<void> _handleSharedText(String text) async {
    final url = extractHttpUrl(text);
    if (url == null || !isValidHttpUrl(url)) return;
    await ShortcutInbound.saveHttpUrl(url);
  }
}
