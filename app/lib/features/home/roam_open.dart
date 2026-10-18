import 'package:flutter/material.dart';
import 'package:super_collection/features/home/roam_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/item_transcript_page.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 漫游点开：文稿标注进文稿页，其余进阅读页。
Future<bool?> openRoamSnippet(
  BuildContext context,
  RoamSnippet snippet, {
  ItemsRepository? itemsRepository,
}) async {
  final repo = itemsRepository ?? ItemsRepository();
  final item = await repo.getItem(snippet.itemId);
  if (!context.mounted) return null;

  final source = (snippet.annotationSource ?? '').trim();
  if (source.startsWith('transcript:')) {
    final key = source.substring('transcript:'.length).trim();
    final seg = key.isEmpty ? null : item.segmentTranscript(key);
    final text = (seg?.text ?? '').trim();
    if (text.isNotEmpty) {
      return Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ItemTranscriptPage(
            text: text,
            cues: seg?.cues ?? const [],
            itemId: item.id,
            segmentKey: key,
            focusAnnotationId: snippet.annotationId,
            shareTitle: (item.title ?? '').trim(),
            shareLink: (item.canonicalUrl ?? item.url).trim(),
            shareCoverUrl: item.shareCoverUrl,
            sharePageUrl: item.sourcePageUrl,
          ),
        ),
      );
    }
  }

  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ItemReadingPage(
        itemId: item.id,
        initialItem: item,
        openEntry: 'roam',
        focusAnnotationId: snippet.annotationId,
        openNoteOnLaunch: snippet.isThought,
      ),
    ),
  );
}
