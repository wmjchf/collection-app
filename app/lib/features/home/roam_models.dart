class RoamSnippet {
  const RoamSnippet({
    required this.id,
    required this.kind,
    required this.text,
    required this.itemId,
    this.quote,
    this.annotationId,
    this.itemTitle,
    this.createdAt,
  });

  /// highlight=标注原文，note=批注，thought=感想
  final String id;
  final String kind;
  final String text;
  final String? quote;
  final int itemId;
  final int? annotationId;
  final String? itemTitle;
  final DateTime? createdAt;

  bool get isNote => kind == 'note';
  bool get isThought => kind == 'thought';

  String get kindLabel {
    if (isThought) return '感想';
    if (isNote) return '批注';
    return '高亮';
  }

  factory RoamSnippet.fromJson(Map<String, dynamic> json) {
    return RoamSnippet(
      id: json['id']?.toString() ?? '',
      kind: json['kind'] as String? ?? 'highlight',
      text: (json['text'] as String? ?? '').trim(),
      quote: (json['quote'] as String?)?.trim(),
      itemId: (json['itemId'] as num).toInt(),
      annotationId: (json['annotationId'] as num?)?.toInt(),
      itemTitle: json['itemTitle'] as String?,
      createdAt: _parseTime(json['createdAt']),
    );
  }

  static DateTime? _parseTime(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }
}

class RoamSectionData {
  const RoamSectionData({
    required this.total,
    required this.items,
  });

  final int total;
  final List<RoamSnippet> items;

  factory RoamSectionData.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List<dynamic>? ?? const [];
    return RoamSectionData(
      total: (json['total'] as num?)?.toInt() ?? 0,
      items: list
          .whereType<Map<String, dynamic>>()
          .map(RoamSnippet.fromJson)
          .toList(),
    );
  }
}
