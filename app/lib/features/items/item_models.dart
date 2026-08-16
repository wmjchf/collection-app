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
    this.platform,
    this.errorMessage,
    this.note,
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
  final String? platform;
  final String status; // pending | success | failed
  final String? errorMessage;
  final String? note;
  final int? folderId;
  final bool isUnread;
  final bool isStarred;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastReadAt;
  final DateTime? deletedAt;
  final int? annotationCount;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  bool get isInTrash => deletedAt != null;
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

  /// 阅读页是否应按「图集」展示（文章站 / 仅封面不算）
  bool get isImageGallery {
    if (imageUrls.isEmpty) return false;
    final p = (platform ?? '').toLowerCase();
    if (p == 'kr36' ||
        p == 'web' ||
        p == 'zhihu' ||
        p == 'zaker' ||
        p == 'bilibili') {
      return false;
    }
    if (p == 'weixin' || p == 'wechat') return true;
    if (_isDouyinNoteOrSlidesPath) return true;
    if (p == 'douyin') return !hasVideo;
    if (p == 'xiaohongshu' || p == 'jike' || p == 'weibo') {
      return (videoUrl ?? '').trim().isEmpty;
    }
    return imageUrls.length >= 2;
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
      platform: json['platform'] as String?,
      status: json['status'] as String? ?? 'pending',
      errorMessage: json['errorMessage'] as String?,
      note: json['note'] as String?,
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
