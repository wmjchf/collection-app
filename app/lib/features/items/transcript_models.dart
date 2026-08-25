import 'package:super_collection/features/items/article_content_blocks.dart';

/// 文稿时间块（对应 segment.cues[]）
class TranscriptCue {
  const TranscriptCue({
    this.startMs,
    this.endMs,
    this.speaker,
    required this.text,
  });

  final int? startMs;
  final int? endMs;
  final int? speaker;
  final String text;

  factory TranscriptCue.fromJson(Map<String, dynamic> json) {
    return TranscriptCue(
      startMs: _asInt(json['startMs']),
      endMs: _asInt(json['endMs']),
      speaker: _asInt(json['speaker']),
      text: (json['text'] as String?)?.trim() ?? '',
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String && value.isNotEmpty) return int.tryParse(value);
    return null;
  }

  /// 展示用：`0:12` / `1:05:03`
  static String formatTime(int? ms) {
    if (ms == null || ms < 0) return '';
    final totalSec = ms ~/ 1000;
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// 单段转写状态（对应 transcript_segments[segmentKey]）
class TranscriptSegment {
  const TranscriptSegment({
    this.status = 'none',
    this.text,
    this.cues = const [],
    this.error,
    this.transcribedAt,
  });

  final String status;
  final String? text;
  final List<TranscriptCue> cues;
  final String? error;
  final DateTime? transcribedAt;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  bool get hasText => (text ?? '').trim().isNotEmpty;
  bool get hasCues => cues.isNotEmpty;

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      status: json['status'] as String? ?? 'none',
      text: json['text'] as String?,
      cues: _parseCues(json['cues']),
      error: json['error'] as String?,
      transcribedAt: _parseTime(json['transcribedAt']),
    );
  }

  static List<TranscriptCue> _parseCues(Object? raw) {
    if (raw is! List) return const [];
    final out = <TranscriptCue>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final cue = TranscriptCue.fromJson(item);
        if (cue.text.isNotEmpty) out.add(cue);
      } else if (item is Map) {
        final cue = TranscriptCue.fromJson(Map<String, dynamic>.from(item));
        if (cue.text.isNotEmpty) out.add(cue);
      }
    }
    return out;
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
