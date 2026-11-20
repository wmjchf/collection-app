import 'package:flutter/material.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/reading_item_notes_sheet.dart';

/// 兼容旧入口：打开「这篇的笔记」并偏到「想法」。
Future<CollectionItem?> showReadingNoteSheet(
  BuildContext context, {
  required int itemId,
  String? initialNote,
  String? title,
  String? link,
  String? coverUrl,
  String? pageUrl,
  List<ItemAnnotation> annotations = const [],
  bool isPro = false,
}) async {
  final result = await showReadingItemNotesSheet(
    context,
    itemId: itemId,
    annotations: annotations,
    initialNote: initialNote,
    shareTitle: title,
    shareLink: link,
    shareCoverUrl: coverUrl,
    sharePageUrl: pageUrl,
    isPro: isPro,
    initialFilter: ReadingNotesFilter.thought,
  );
  return result?.item;
}
