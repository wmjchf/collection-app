import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/transcript_models.dart';

class CollectionItem {
  const CollectionItem({
    required this.id,
    required this.url,
    required this.status,
    this.canonicalUrl,
    this.title,
    this.content,
    this.summary,
    this.coverImageUrl,
    this.imageUrls = const [],
    this.videoUrl,
    this.transcriptSegments = const {},
    this.aiMeta = const AiMeta(),
    this.platform,
    this.errorMessage,
    this.note,
    this.contentEditedAt,
    this.folderId,
    this.isUnread = true,
    this.isStarred = false,
    this.createdAt,
    this.updatedAt,
    this.lastReadAt,
    this.deletedAt,
    this.annotationCount,
  });

  final int id;
  final String url;
  final String? canonicalUrl;
  final String? title;
  final String? content;
  final String? summary;
  final String? coverImageUrl;
  final List<String> imageUrls;
  /// 视频直链（如小红书）；CDN 签名可能过期
  final String? videoUrl;
  /// 分段转写：segmentKey → 状态与文稿
  final Map<String, TranscriptSegment> transcriptSegments;
  final AiMeta aiMeta;
  final String? platform;
  final String status; // pending | success | failed
  final String? errorMessage;
  final String? note;
  final DateTime? contentEditedAt;
  final int? folderId;
  final bool isUnread;
  final bool isStarred;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastReadAt;
  final DateTime? deletedAt;
  final int? annotationCount;

  bool get hasUserEditedContent => contentEditedAt != null;
  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  bool get isInTrash => deletedAt != null;
  bool get hasAnyTranscriptPending =>
      transcriptSegments.values.any((s) => s.isPending);
  bool get hasAnyTranscript =>
      transcriptSegments.values.any((s) => s.hasText);
  TranscriptSegment? segmentTranscript(String key) =>
      transcriptSegments[key];
  bool get canRequestTranscript =>
      TranscriptTargets.listFor(
        content: content,
        videoUrl: videoUrl,
        hasTopVideo: hasVideo,
      ).isNotEmpty;

  bool get canRequestAiSuggest {
    final t = (title ?? '').trim();
    final body = (content ?? '').trim();
    final sum = (summary ?? '').trim();
    final hasTranscript = transcriptSegments.values.any((s) => s.hasText);
    return t.isNotEmpty || body.isNotEmpty || sum.isNotEmpty || hasTranscript;
  }

  /// 可点击触发 AI 标签建议（转写进行中、AI 生成中不可用）
  bool get canTriggerAiSuggest =>
      (canRequestAiSuggest || shouldAutoTranscribeBeforeMindmap) &&
      !hasAiTagsPending &&
      !(hasAnyTranscriptPending && !aiMeta.tags.awaitTranscript);

  /// AI 功能触发的自动转写进行中（标签或思维导图）
  bool get isAiAwaitingTranscript =>
      (aiMeta.tags.awaitTranscript && aiMeta.tags.isPending) ||
      (aiMeta.mindmap.awaitTranscript && aiMeta.mindmap.isPending);

  /// 转写成功后是否适合弹出「生成标签建议」提示
  bool get shouldPromptAiSuggestAfterTranscript {
    if (!canTriggerAiSuggest) return false;
    final tags = aiMeta.tags;
    if (tags.isPending) return false;
    if (tags.isSuccess && tags.hasSuggestions) return false;
    return true;
  }

  bool get hasAiTagsPending => aiMeta.tags.isPending;

  bool get hasMindmapPending => aiMeta.mindmap.isPending;

  bool get shouldAutoTranscribeBeforeMindmap =>
      TranscriptTargets.shouldAutoTranscribeBeforeMindmap(
        content: content,
        videoUrl: videoUrl,
        hasTopVideo: hasVideo,
        segments: transcriptSegments,
      );

  bool get canTriggerMindmap =>
      (canRequestAiSuggest || shouldAutoTranscribeBeforeMindmap) &&
      !hasMindmapPending &&
      !(hasAnyTranscriptPending && !aiMeta.mindmap.awaitTranscript);

  CollectionItem withAiMeta(AiMeta meta) {
    return CollectionItem(
      id: id,
      url: url,
      canonicalUrl: canonicalUrl,
      title: title,
      content: content,
      summary: summary,
      coverImageUrl: coverImageUrl,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      transcriptSegments: transcriptSegments,
      aiMeta: meta,
      platform: platform,
      status: status,
      errorMessage: errorMessage,
      note: note,
      contentEditedAt: contentEditedAt,
      folderId: folderId,
      isUnread: isUnread,
      isStarred: isStarred,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastReadAt: lastReadAt,
      deletedAt: deletedAt,
      annotationCount: annotationCount,
    );
  }

  CollectionItem withTranscriptSegments(
    Map<String, TranscriptSegment> segments,
  ) {
    return CollectionItem(
      id: id,
      url: url,
      canonicalUrl: canonicalUrl,
      title: title,
      content: content,
      summary: summary,
      coverImageUrl: coverImageUrl,
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      transcriptSegments: segments,
      aiMeta: aiMeta,
      platform: platform,
      status: status,
      errorMessage: errorMessage,
      note: note,
      contentEditedAt: contentEditedAt,
      folderId: folderId,
      isUnread: isUnread,
      isStarred: isStarred,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastReadAt: lastReadAt,
      deletedAt: deletedAt,
      annotationCount: annotationCount,
    );
  }

  /// 防盗链 Referer：优先规范化后的源站。
  String? get sourcePageUrl {
    final canonical = canonicalUrl?.trim();
    if (canonical != null && canonical.isNotEmpty) return canonical;
    final raw = url.trim();
    return raw.isEmpty ? null : raw;
  }

  bool get hasVideo {
    final v = videoUrl?.trim();
    if (v == null || v.isEmpty) return false;
    // 抖音 note/slides：按路径当图文（动图可能误带 play_addr）
    if (_isDouyinNoteOrSlidesPath) return false;
    // 短链常无 /note/：有图集则按图文（本产品视频页会清空 imageUrls）
    if (_isDouyinPlatform && imageUrls.isNotEmpty) return false;
    return true;
  }

  bool get _isDouyinPlatform {
    final p = (platform ?? '').toLowerCase();
    if (p == 'douyin') return true;
    for (final raw in [canonicalUrl, url]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final host = (Uri.tryParse(raw.trim())?.host ?? '').toLowerCase();
      if (host.contains('douyin.com') || host.contains('iesdouyin.com')) {
        return true;
      }
    }
    return false;
  }

  bool get _isDouyinNoteOrSlidesPath {
    for (final raw in [canonicalUrl, url]) {
      if (raw == null || raw.trim().isEmpty) continue;
      final path = (Uri.tryParse(raw.trim())?.path ?? '').toLowerCase();
      if (path.contains('/note/') || path.contains('/slides/')) return true;
    }
    return false;
  }

  /// 阅读页是否按「图集」轮播，看字段不看平台：
  /// 图集把图放进 `imageUrls`、正文不再插图；文章把图写进正文 `![]()`，`imageUrls` 留空。
  bool get isImageGallery {
    if (imageUrls.isEmpty) return false;
    if (hasVideo) return false;
    final body = content ?? '';
    if (RegExp(r'!v?\[[^\]]*\]\([^)\s]+\)').hasMatch(body)) return false;
    return true;
  }

  /// 展示用图集：有 imageUrls 用它，否则退回单封面（按 path 去重，避免同图不同 query *2）
  List<String> get displayImages {
    final raw = <String>[];
    if (imageUrls.isNotEmpty) {
      raw.addAll(imageUrls);
    } else {
      final cover = coverImageUrl?.trim();
      if (cover != null && cover.isNotEmpty) raw.add(cover);
    }
    final out = <String>[];
    final seen = <String>{};
    for (final u in raw) {
      final t = u.trim();
      if (t.isEmpty) continue;
      final key = t.split('?').first;
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(t);
    }
    return out;
  }

  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    final rawImages = json['imageUrls'];
    final images = <String>[];
    if (rawImages is List) {
      for (final e in rawImages) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) images.add(s);
      }
    }
    return CollectionItem(
      id: (json['id'] as num).toInt(),
      url: json['url'] as String? ?? '',
      canonicalUrl: json['canonicalUrl'] as String?,
      title: json['title'] as String?,
      content: json['content'] as String?,
      summary: json['summary'] as String?,
      coverImageUrl: json['coverImageUrl'] as String?,
      imageUrls: images,
      videoUrl: json['videoUrl'] as String?,
      transcriptSegments: _parseTranscriptSegments(json['transcriptSegments']),
      aiMeta: AiMeta.fromJson(
        json['aiMeta'] is Map<String, dynamic>
            ? json['aiMeta'] as Map<String, dynamic>
            : json['aiMeta'] is Map
                ? (json['aiMeta'] as Map).map(
                    (k, v) => MapEntry(k.toString(), v),
                  )
                : null,
      ),
      platform: json['platform'] as String?,
      status: json['status'] as String? ?? 'pending',
      errorMessage: json['errorMessage'] as String?,
      note: json['note'] as String?,
      contentEditedAt: _parseTime(json['contentEditedAt']),
      folderId: (json['folderId'] as num?)?.toInt(),
      isUnread: json['isUnread'] as bool? ?? true,
      isStarred: json['isStarred'] as bool? ?? false,
      createdAt: _parseTime(json['createdAt']),
      updatedAt: _parseTime(json['updatedAt']),
      lastReadAt: _parseTime(json['lastReadAt']),
      deletedAt: _parseTime(json['deletedAt']),
      annotationCount: (json['annotationCount'] as num?)?.toInt(),
    );
  }

  static Map<String, TranscriptSegment> _parseTranscriptSegments(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, TranscriptSegment>{};
    raw.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        out[key.toString()] = TranscriptSegment.fromJson(value);
      } else if (value is Map) {
        out[key.toString()] = TranscriptSegment.fromJson(
          value.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    });
    return out;
  }

  static DateTime? _parseTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class SearchHit {
  const SearchHit({
    required this.item,
    required this.matchedLabels,
  });

  final CollectionItem item;
  final List<String> matchedLabels;

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    final labels = <String>[];
    final raw = json['matchedLabels'];
    if (raw is List) {
      for (final e in raw) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) labels.add(s);
      }
    }
    return SearchHit(
      item: CollectionItem.fromJson(json),
      matchedLabels: labels,
    );
  }
}

class ItemAnnotation {
  const ItemAnnotation({
    required this.id,
    required this.itemId,
    required this.selectedText,
    this.startOffset,
    this.endOffset,
    this.color,
    this.note,
    this.createdAt,
  });

  final int id;
  final int itemId;
  final String selectedText;
  final int? startOffset;
  final int? endOffset;
  final String? color;
  final String? note;
  final DateTime? createdAt;

  factory ItemAnnotation.fromJson(Map<String, dynamic> json) {
    return ItemAnnotation(
      id: (json['id'] as num).toInt(),
      itemId: (json['itemId'] as num).toInt(),
      selectedText: json['selectedText'] as String? ?? '',
      startOffset: (json['startOffset'] as num?)?.toInt(),
      endOffset: (json['endOffset'] as num?)?.toInt(),
      color: json['color'] as String?,
      note: json['note'] as String?,
      createdAt: CollectionItem._parseTime(json['createdAt']),
    );
  }
}
