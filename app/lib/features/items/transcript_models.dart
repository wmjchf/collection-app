import 'package:super_collection/features/items/article_content_blocks.dart';

/// 单段转写状态（对应 transcript_segments[segmentKey]）
class TranscriptSegment {
  const TranscriptSegment({
    this.status = 'none',
    this.text,
    this.error,
    this.transcribedAt,
  });

  final String status;
  final String? text;
  final String? error;
  final DateTime? transcribedAt;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  bool get hasText => (text ?? '').trim().isNotEmpty;

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      status: json['status'] as String? ?? 'none',
      text: json['text'] as String?,
      error: json['error'] as String?,
      transcribedAt: _parseTime(json['transcribedAt']),
    );
  }

  static DateTime? _parseTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

/// 可转写媒体（GET transcript-targets 或本地枚举）
class TranscriptTarget {
  const TranscriptTarget({
    required this.segmentKey,
    required this.label,
    this.needsClientResolve = false,
    this.status = 'none',
  });

  final String segmentKey;
  final String label;
  final bool needsClientResolve;
  final String status;

  factory TranscriptTarget.fromJson(Map<String, dynamic> json) {
    return TranscriptTarget(
      segmentKey: json['segmentKey'] as String? ?? '',
      label: json['label'] as String? ?? '',
      needsClientResolve: json['needsClientResolve'] as bool? ?? false,
      status: json['status'] as String? ?? 'none',
    );
  }
}

/// 与后端 transcriptSegments.js 一致的枚举规则
class TranscriptTargets {
  TranscriptTargets._();

  static const segmentVideoUrl = 'video_url';

  static bool _isHttpsMedia(String url) {
    final u = url.trim();
    return (u.startsWith('http://') || u.startsWith('https://')) &&
        !u.toLowerCase().startsWith('qqvid:');
  }

  static List<TranscriptTarget> listFor({
    String? content,
    String? videoUrl,
    bool hasTopVideo = false,
  }) {
    final body = content ?? '';
    if (ArticleContentBlocks.hasInlineVideos(body)) {
      final urls = ArticleContentBlocks.inlineVideoUrls(body);
      return urls.asMap().entries.map((e) {
        final url = e.value;
        return TranscriptTarget(
          segmentKey: 'inline:${e.key}',
          label: '文中视频 ${e.key + 1}',
          needsClientResolve: !_isHttpsMedia(url),
        );
      }).toList(growable: false);
    }
    final v = videoUrl?.trim() ?? '';
    if (!hasTopVideo || v.isEmpty) return const [];
    return [
      TranscriptTarget(
        segmentKey: segmentVideoUrl,
        label: '音频',
        needsClientResolve: !_isHttpsMedia(v),
      ),
    ];
  }
}
