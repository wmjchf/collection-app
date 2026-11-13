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

class AgentTagChip {
  const AgentTagChip({
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.isSystem = false,
  });

  final int id;
  final String name;
  final int itemCount;
  final bool isSystem;

  factory AgentTagChip.fromJson(Map<String, dynamic> json) {
    return AgentTagChip(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?)?.trim() ?? '',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'itemCount': itemCount,
        'isSystem': isSystem,
      };
}

class AgentCitation {
  const AgentCitation({
    required this.itemId,
    required this.title,
    this.snippet = '',
    this.tagNames = const [],
    this.coverImageUrl,
    this.pageUrl,
  });

  final int itemId;
  final String title;
  final String snippet;
  final List<String> tagNames;
  final String? coverImageUrl;
  /// 源站页，封面 CDN Referer 用（小红书等防盗链）
  final String? pageUrl;

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
      pageUrl: json['pageUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'title': title,
        'snippet': snippet,
        'tagNames': tagNames,
        'coverImageUrl': coverImageUrl,
        if (pageUrl != null) 'pageUrl': pageUrl,
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
    this.resumeCompose = false,
    this.segmentKey,
    this.phase,
    this.phaseLabel,
    this.phaseHint,
    this.phaseAt,
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

  /// start_transcript：转写成功后是否自动续跑成文
  final bool resumeCompose;
  final String? segmentKey;
  final String? phase;
  final String? phaseLabel;
  final String? phaseHint;
  final DateTime? phaseAt;

  /// 改标 / 归类确认条
  bool get isTagConfirmPending =>
      status == 'pending' &&
      (type == 'item_tag_edit' || type == 'organize_tags');

  /// 转写待确认（气泡内确认，不弹系统框）
  bool get isTranscriptConfirmPending =>
      isStartTranscript && status == 'pending';

  /// 气泡确认条（改标 / 归类 / 转写）
  bool get isPending => isTagConfirmPending || isTranscriptConfirmPending;

  bool get isStartTranscript => type == 'start_transcript';

  bool get isTranscriptJobActive =>
      isStartTranscript && (status == 'pending' || status == 'running');

  bool get isOrganize => type == 'organize_tags';

  String get confirmLabel {
    if (isStartTranscript) return '开始转写';
    if (isOrganize) return '确认整理';
    return '确认调整';
  }

  factory AgentPendingAction.fromJson(Map<String, dynamic> json) {
    List<String> names(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if ((e?.toString().trim() ?? '').isNotEmpty) e.toString().trim(),
      ];
    }

    DateTime? phaseAt;
    final rawAt = json['phaseAt'];
    if (rawAt is String && rawAt.isNotEmpty) {
      phaseAt = DateTime.tryParse(rawAt);
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
      resumeCompose: json['resumeCompose'] == true,
      segmentKey: (json['segmentKey'] as String?)?.trim(),
      phase: (json['phase'] as String?)?.trim(),
      phaseLabel: (json['phaseLabel'] as String?)?.trim(),
      phaseHint: (json['phaseHint'] as String?)?.trim(),
      phaseAt: phaseAt,
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
        'resumeCompose': resumeCompose,
        if (segmentKey != null && segmentKey!.isNotEmpty)
          'segmentKey': segmentKey,
        if (phase != null && phase!.isNotEmpty) 'phase': phase,
        if (phaseLabel != null && phaseLabel!.isNotEmpty)
          'phaseLabel': phaseLabel,
        if (phaseHint != null && phaseHint!.isNotEmpty) 'phaseHint': phaseHint,
        if (phaseAt != null) 'phaseAt': phaseAt!.toIso8601String(),
      };

  AgentPendingAction copyWith({
    String? status,
    bool? resumeCompose,
    String? segmentKey,
    String? phase,
    String? phaseLabel,
    String? phaseHint,
    DateTime? phaseAt,
    bool clearPhase = false,
  }) {
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
      resumeCompose: resumeCompose ?? this.resumeCompose,
      segmentKey: segmentKey ?? this.segmentKey,
      phase: clearPhase ? null : (phase ?? this.phase),
      phaseLabel: clearPhase ? null : (phaseLabel ?? this.phaseLabel),
      phaseHint: clearPhase ? null : (phaseHint ?? this.phaseHint),
      phaseAt: clearPhase ? null : (phaseAt ?? this.phaseAt),
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
    this.thinking = '',
  });

  final int id;
  final String role;
  final String content;
  final List<AgentCitation> citations;
  final AgentPendingAction? pendingAction;
  final List<Map<String, dynamic>> toolTrace;
  /// 任务理解与规划独白（可折叠「思考中 / 思考完成」）
  final String thinking;

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  String get displayThinking => thinking.trim();

  /// list_tags 盘点结果：用于 chip 展示（不列文章）
  List<AgentTagChip> get inventoryTags {
    final out = <AgentTagChip>[];
    final seen = <int>{};
    for (final step in toolTrace) {
      if (step['tool']?.toString() != 'list_tags') continue;
      final raw = step['tags'];
      if (raw is! List) continue;
      for (final e in raw) {
        Map<String, dynamic>? map;
        if (e is Map<String, dynamic>) {
          map = e;
        } else if (e is Map) {
          map = Map<String, dynamic>.from(e);
        }
        if (map == null) continue;
        final chip = AgentTagChip.fromJson(map);
        if (chip.id <= 0 || chip.name.isEmpty || seen.contains(chip.id)) {
          continue;
        }
        seen.add(chip.id);
        out.add(chip);
      }
    }
    return out;
  }

  AgentMessage copyWith({
    int? id,
    String? role,
    String? content,
    List<AgentCitation>? citations,
    AgentPendingAction? pendingAction,
    List<Map<String, dynamic>>? toolTrace,
    String? thinking,
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
      thinking: thinking ?? this.thinking,
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
    final rawTrace = json['toolTrace'] ?? json['tool_trace'];
    var thinking = (json['thinking'] as String?)?.trim() ?? '';
    if (thinking.isEmpty && rawTrace is Map) {
      thinking = (rawTrace['thinking'] as String?)?.trim() ?? '';
    }
    return AgentMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      citations: citations,
      pendingAction: pending,
      toolTrace: toolTrace,
      thinking: thinking,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'citations': [for (final c in citations) c.toJson()],
        if (pendingAction != null) 'pendingAction': pendingAction!.toJson(),
        if (toolTrace.isNotEmpty) 'toolTrace': toolTrace,
        if (thinking.trim().isNotEmpty) 'thinking': thinking,
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
