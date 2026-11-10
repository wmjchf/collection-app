import 'package:flutter/foundation.dart';

/// 助手等处转写成功后通知阅读页刷新文稿展示。
class ItemTranscriptRefresh {
  ItemTranscriptRefresh._();

  static final ValueNotifier<int> version = ValueNotifier(0);
  static int? lastItemId;

  static void notify(int itemId) {
    if (itemId <= 0) return;
    lastItemId = itemId;
    version.value++;
  }
}
