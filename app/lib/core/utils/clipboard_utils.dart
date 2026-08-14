import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/utils/link_utils.dart';

const _clipboardChannel = MethodChannel('super_collection/clipboard');

/// 用户拒绝粘贴 / 读失败后，同一代剪贴板不再自动读，避免反复弹「允许粘贴」
int? _skipChangeCount;

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

Future<int?> _pasteboardChangeCount() async {
  if (kIsWeb || !Platform.isIOS) return null;
  try {
    final v = await _clipboardChannel.invokeMethod<int>('pasteboardChangeCount');
    return v;
  } catch (_) {
    return null;
  }
}

void _markSkipCurrentPasteboard(int? changeCount) {
  if (changeCount != null) {
    _skipChangeCount = changeCount;
  }
}

/// [probeFirst] 为 true 时：先做无授权检测，不像链接则直接返回 null（不读剪贴板）。
/// 若用户拒绝粘贴或读不到链接，会记住当前剪贴板代数，直到内容变化才再问。
Future<String?> readClipboardHttpUrl({bool probeFirst = false}) async {
  try {
    if (probeFirst) {
      final likely = await clipboardLikelyHasHttpUrl();
      if (!likely) return null;
    }

    final changeCount = await _pasteboardChangeCount();
    if (changeCount != null && changeCount == _skipChangeCount) {
      return null;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      // 拒绝粘贴或空内容：本代剪贴板不再自动请求
      _markSkipCurrentPasteboard(changeCount);
      return null;
    }
    final url = extractHttpUrl(text);
    if (url == null) {
      _markSkipCurrentPasteboard(changeCount);
    }
    return url;
  } catch (_) {
    final changeCount = await _pasteboardChangeCount();
    _markSkipCurrentPasteboard(changeCount);
    return null;
  }
}

Future<void> clearClipboard() async {
  try {
    await Clipboard.setData(const ClipboardData(text: ''));
    // 清空后换代，允许下次再自动检测
    final changeCount = await _pasteboardChangeCount();
    if (changeCount != null) {
      _skipChangeCount = changeCount;
    }
  } catch (_) {}
}
