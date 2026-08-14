import 'package:flutter/services.dart';
import 'package:super_collection/core/utils/link_utils.dart';

Future<String?> readClipboardHttpUrl() async {
  try {
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
