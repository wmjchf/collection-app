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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'focusItemId': focusItemId,
        'status': status,
        'preview': preview,
      };
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

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'title': title,
        'snippet': snippet,
        'tagNames': tagNames,
        'coverImageUrl': coverImageUrl,
      };
}

class AgentPendingAction {
  const AgentPendingAction({
    required this.type,
    required this.status,
    this.itemId = 0,
    this.title = '',
    this.before = const [],
    this.after = const [],
    this.add = const [],
    this.remove = const [],
    this.willCreate = const [],
    this.willCreateModules = const [],
  });

  final String type;
  final String status;
  final int itemId;
  final String title;
  final List<String> before;
  final List<String> after;
  final List<String> add;
  final List<String> remove;
  final List<String> willCreate;
  final List<String> willCreateModules;

  bool get isPending =>
      status == 'pending' &&
      (type == 'item_tag_edit' || type == 'organize_tags');

  bool get isOrganize => type == 'organize_tags';

  String get confirmLabel => isOrganize ? '确认整理' : '确认调整';

  factory AgentPendingAction.fromJson(Map<String, dynamic> json) {
    List<String> names(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if ((e?.toString().trim() ?? '').isNotEmpty) e.toString().trim(),
      ];
    }

    return AgentPendingAction(
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      before: names(json['before']),
      after: names(json['after']),
      add: names(json['add']),
      remove: names(json['remove']),
      willCreate: names(json['willCreate']),
      willCreateModules: names(json['willCreateModules']),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'status': status,
        'itemId': itemId,
        'title': title,
        'before': before,
        'after': after,
        'add': add,
        'remove': remove,
        'willCreate': willCreate,
        'willCreateModules': willCreateModules,
      };

  AgentPendingAction copyWith({String? status}) {
    return AgentPendingAction(
      type: type,
      status: status ?? this.status,
      itemId: itemId,
      title: title,
      before: before,
      after: after,
      add: add,
      remove: remove,
      willCreate: willCreate,
      willCreateModules: willCreateModules,
    );
  }
}

class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    this.citations = const [],
    this.pendingAction,
    this.toolTrace = const [],
  });

  final int id;
  final String role;
  final String content;
  final List<AgentCitation> citations;
  final AgentPendingAction? pendingAction;
  final List<Map<String, dynamic>> toolTrace;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  /// 转写写文章草稿（可一键复制全文）
  bool get isComposeArticleDraft {
    for (final step in toolTrace) {
      final tool = step['tool']?.toString() ?? '';
      if (tool == 'draft_article' || tool == 'draft_from_transcript') {
        return true;
      }
    }
    return false;
  }

  AgentMessage copyWith({
    int? id,
    String? role,
    String? content,
    List<AgentCitation>? citations,
    AgentPendingAction? pendingAction,
    List<Map<String, dynamic>>? toolTrace,
    bool clearPendingAction = false,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      citations: citations ?? this.citations,
      pendingAction:
          clearPendingAction ? null : (pendingAction ?? this.pendingAction),
      toolTrace: toolTrace ?? this.toolTrace,
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
    AgentPendingAction? pending;
    final pa = json['pendingAction'];
    if (pa is Map<String, dynamic>) {
      pending = AgentPendingAction.fromJson(pa);
    } else if (pa is Map) {
      pending = AgentPendingAction.fromJson(Map<String, dynamic>.from(pa));
    }
    final toolTrace = <Map<String, dynamic>>[];
    void addSteps(dynamic rawTrace) {
      if (rawTrace is List) {
        for (final e in rawTrace) {
          if (e is Map<String, dynamic>) {
            toolTrace.add(e);
          } else if (e is Map) {
            toolTrace.add(Map<String, dynamic>.from(e));
          }
        }
      } else if (rawTrace is Map) {
        final steps = rawTrace['steps'];
        if (steps is List) {
          addSteps(steps);
        }
      }
    }

    addSteps(json['toolTrace'] ?? json['tool_trace']);
    return AgentMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      citations: citations,
      pendingAction: pending,
      toolTrace: toolTrace,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'citations': [for (final c in citations) c.toJson()],
        if (pendingAction != null) 'pendingAction': pendingAction!.toJson(),
        if (toolTrace.isNotEmpty) 'toolTrace': toolTrace,
      };
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
