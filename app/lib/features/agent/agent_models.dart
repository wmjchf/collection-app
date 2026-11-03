class AgentConversation {
  const AgentConversation({
    required this.id,
    this.title,
    this.focusItemId,
    this.status = 'active',
    this.preview,
  });

  final int id;
  final String? title;
  final int? focusItemId;
  final String status;
  final String? preview;

  factory AgentConversation.fromJson(Map<String, dynamic> json) {
    return AgentConversation(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      focusItemId: (json['focusItemId'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'active',
      preview: json['preview'] as String?,
    );
  }
}

class AgentCitation {
  const AgentCitation({
    required this.itemId,
    required this.title,
    this.snippet = '',
    this.tagNames = const [],
    this.coverImageUrl,
  });

  final int itemId;
  final String title;
  final String snippet;
  final List<String> tagNames;
  final String? coverImageUrl;

  factory AgentCitation.fromJson(Map<String, dynamic> json) {
    final tags = <String>[];
    final raw = json['tagNames'];
    if (raw is List) {
      for (final e in raw) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) tags.add(s);
      }
    }
    return AgentCitation(
      itemId: (json['itemId'] as num).toInt(),
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : '条目 ${json['itemId']}',
      snippet: (json['snippet'] as String?)?.trim() ?? '',
      tagNames: tags,
      coverImageUrl: json['coverImageUrl'] as String?,
    );
  }
}

class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    this.citations = const [],
  });

  final int id;
  final String role;
  final String content;
  final List<AgentCitation> citations;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  AgentMessage copyWith({
    int? id,
    String? role,
    String? content,
    List<AgentCitation>? citations,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      citations: citations ?? this.citations,
    );
  }

  factory AgentMessage.fromJson(Map<String, dynamic> json) {
    final citations = <AgentCitation>[];
    final raw = json['citations'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          citations.add(AgentCitation.fromJson(e));
        } else if (e is Map) {
          citations.add(AgentCitation.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return AgentMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      citations: citations,
    );
  }
}

class AgentTurnResult {
  const AgentTurnResult({
    required this.userMessage,
    required this.assistantMessage,
  });

  final AgentMessage userMessage;
  final AgentMessage assistantMessage;

  factory AgentTurnResult.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return <String, dynamic>{};
    }

    return AgentTurnResult(
      userMessage: AgentMessage.fromJson(asMap(json['userMessage'])),
      assistantMessage: AgentMessage.fromJson(asMap(json['assistantMessage'])),
    );
  }
}
