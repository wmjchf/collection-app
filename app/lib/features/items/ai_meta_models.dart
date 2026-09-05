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

class AiMindmapNode {
  const AiMindmapNode({
    required this.title,
    this.children = const [],
  });

  final String title;
  final List<AiMindmapNode> children;

  factory AiMindmapNode.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AiMindmapNode(title: '');
    }
    final raw = json['children'];
    final children = <AiMindmapNode>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          children.add(AiMindmapNode.fromJson(e));
        } else if (e is Map) {
          children.add(AiMindmapNode.fromJson(
            e.map((k, v) => MapEntry(k.toString(), v)),
          ));
        }
      }
    }
    return AiMindmapNode(
      title: json['title'] as String? ?? '',
      children: children,
    );
  }
}

class AiMindmapMeta {
  const AiMindmapMeta({
    this.status = 'none',
    this.tree,
    this.contentHash,
    this.error,
    this.generatedAt,
    this.awaitTranscript = false,
  });

  final String status;
  final AiMindmapNode? tree;
  final String? contentHash;
  final String? error;
  final DateTime? generatedAt;
  final bool awaitTranscript;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  bool get hasTree =>
      tree != null && tree!.title.trim().isNotEmpty;

  factory AiMindmapMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AiMindmapMeta();
    AiMindmapNode? tree;
    final rawTree = json['tree'];
    if (rawTree is Map<String, dynamic>) {
      tree = AiMindmapNode.fromJson(rawTree);
    } else if (rawTree is Map) {
      tree = AiMindmapNode.fromJson(
        rawTree.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return AiMindmapMeta(
      status: json['status'] as String? ?? 'none',
      tree: tree,
      contentHash: json['contentHash'] as String?,
      error: json['error'] as String?,
      generatedAt: AiTagsMeta._parseTime(json['generatedAt']),
      awaitTranscript: json['awaitTranscript'] == true,
    );
  }
}

class AiTagsMeta {
  const AiTagsMeta({
    this.status = 'none',
    this.items = const [],
    this.error,
    this.generatedAt,
    this.awaitTranscript = false,
  });

  final String status;
  final List<AiTagSuggestion> items;
  final String? error;
  final DateTime? generatedAt;
  final bool awaitTranscript;

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
      awaitTranscript: json['awaitTranscript'] == true,
    );
  }

  static DateTime? _parseTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class AiSummaryMeta {
  const AiSummaryMeta({
    this.status = 'none',
    this.text,
    this.contentHash,
    this.error,
    this.generatedAt,
    this.awaitTranscript = false,
  });

  final String status;
  final String? text;
  final String? contentHash;
  final String? error;
  final DateTime? generatedAt;
  final bool awaitTranscript;

  bool get isPending => status == 'pending';
  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
  bool get hasText => text != null && text!.trim().isNotEmpty;

  factory AiSummaryMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AiSummaryMeta();
    return AiSummaryMeta(
      status: json['status'] as String? ?? 'none',
      text: json['text'] as String?,
      contentHash: json['contentHash'] as String?,
      error: json['error'] as String?,
      generatedAt: AiTagsMeta._parseTime(json['generatedAt']),
      awaitTranscript: json['awaitTranscript'] == true,
    );
  }
}

class AiMeta {
  const AiMeta({
    this.tags = const AiTagsMeta(),
    this.mindmap = const AiMindmapMeta(),
    this.summary = const AiSummaryMeta(),
    this.model,
  });

  final AiTagsMeta tags;
  final AiMindmapMeta mindmap;
  final AiSummaryMeta summary;
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
      mindmap: AiMindmapMeta.fromJson(
        json['mindmap'] is Map<String, dynamic>
            ? json['mindmap'] as Map<String, dynamic>
            : json['mindmap'] is Map
                ? (json['mindmap'] as Map).map(
                    (k, v) => MapEntry(k.toString(), v),
                  )
                : null,
      ),
      summary: AiSummaryMeta.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : json['summary'] is Map
                ? (json['summary'] as Map).map(
                    (k, v) => MapEntry(k.toString(), v),
                  )
                : null,
      ),
      model: json['model'] as String?,
    );
  }
}
