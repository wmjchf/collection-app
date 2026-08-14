import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/utils/link_utils.dart';

const _clipboardChannel = MethodChannel('super_collection/clipboard');

/// 是否可能含链接。iOS 上不读剪贴板内容，避免无链接时弹出「允许粘贴」。
Future<bool> clipboardLikelyHasHttpUrl() async {
  if (kIsWeb) return false;
  if (!Platform.isIOS) return true;
  try {
    final v = await _clipboardChannel.invokeMethod<bool>('hasProbableUrl');
    return v == true;
  } catch (_) {
    // 通道失败时保守跳过自动读取，避免误弹授权
    return false;
  }
}

/// [probeFirst] 为 true 时：先做无授权检测，不像链接则直接返回 null（不读剪贴板）。
Future<String?> readClipboardHttpUrl({bool probeFirst = false}) async {
  try {
    if (probeFirst) {
      final likely = await clipboardLikelyHasHttpUrl();
      if (!likely) return null;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return null;
    return extractHttpUrl(text);
  } catch (_) {
    return null;
  }
}

Future<void> clearClipboard() async {
  try {
    await Clipboard.setData(const ClipboardData(text: ''));
  } catch (_) {}
}
