class AiTagSuggestion {
  const AiTagSuggestion({
    required this.name,
    this.existingTagId,
  });

  final String name;
  final int? existingTagId;

  factory AiTagSuggestion.fromJson(Map<String, dynamic> json) {
    return AiTagSuggestion(
      name: json['name'] as String? ?? '',
      existingTagId: (json['existingTagId'] as num?)?.toInt(),
    );
  }
}

class AiTagsMeta {
  const AiTagsMeta({
    this.status = 'none',
    this.items = const [],
    this.error,
    this.generatedAt,
  });

  final String status;
  final List<AiTagSuggestion> items;
  final String? error;
  final DateTime? generatedAt;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isEmpty => status == 'empty';
  bool get isFailed => status == 'failed';
  bool get hasSuggestions => items.isNotEmpty;

  factory AiTagsMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AiTagsMeta();
    final raw = json['items'];
    final items = <AiTagSuggestion>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          items.add(AiTagSuggestion.fromJson(e));
        } else if (e is Map) {
          items.add(AiTagSuggestion.fromJson(
            e.map((k, v) => MapEntry(k.toString(), v)),
          ));
        }
      }
    }
    return AiTagsMeta(
      status: json['status'] as String? ?? 'none',
      items: items,
      error: json['error'] as String?,
      generatedAt: _parseTime(json['generatedAt']),
    );
  }

  static DateTime? _parseTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class AiMeta {
  const AiMeta({
    this.tags = const AiTagsMeta(),
    this.model,
  });

  final AiTagsMeta tags;
  final String? model;

  factory AiMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AiMeta();
    return AiMeta(
      tags: AiTagsMeta.fromJson(
        json['tags'] is Map<String, dynamic>
            ? json['tags'] as Map<String, dynamic>
            : json['tags'] is Map
                ? (json['tags'] as Map).map(
                    (k, v) => MapEntry(k.toString(), v),
                  )
                : null,
      ),
      model: json['model'] as String?,
    );
  }
}
