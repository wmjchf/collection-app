import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/features/agent/agent_models.dart';

/// 助手会话本地缓存：进页先出缓存，再后台拉网同步，避免每次全屏 loading。
class AgentChatCache {
  AgentChatCache._();

  static const _maxMessages = 80;

  static String _key({required int userId, int? focusItemId}) {
    if (focusItemId != null) {
      return 'agent_chat_v1_${userId}_item_$focusItemId';
    }
    return 'agent_chat_v1_${userId}_global';
  }

  static Future<AgentChatSnapshot?> read({
    required int userId,
    int? focusItemId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId: userId, focusItemId: focusItemId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return AgentChatSnapshot.fromJson(Map<String, dynamic>.from(json));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write({
    required int userId,
    int? focusItemId,
    required int conversationId,
    required List<AgentMessage> messages,
    List<String>? presets,
    String? presetKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = messages.length > _maxMessages
        ? messages.sublist(messages.length - _maxMessages)
        : List<AgentMessage>.from(messages);
    final snap = AgentChatSnapshot(
      conversationId: conversationId,
      messages: trimmed,
      presets: presets ?? const [],
      presetKey: presetKey,
    );
    await prefs.setString(
      _key(userId: userId, focusItemId: focusItemId),
      jsonEncode(snap.toJson()),
    );
  }

  static Future<void> clear({
    required int userId,
    int? focusItemId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId: userId, focusItemId: focusItemId));
  }
}

class AgentChatSnapshot {
  const AgentChatSnapshot({
    required this.conversationId,
    required this.messages,
    this.presets = const [],
    this.presetKey,
  });

  final int conversationId;
  final List<AgentMessage> messages;
  final List<String> presets;
  final String? presetKey;

  Map<String, dynamic> toJson() => {
        'conversationId': conversationId,
        'messages': [for (final m in messages) m.toJson()],
        'presets': presets,
        if (presetKey != null) 'presetKey': presetKey,
      };

  factory AgentChatSnapshot.fromJson(Map<String, dynamic> json) {
    final messages = <AgentMessage>[];
    final raw = json['messages'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          messages.add(AgentMessage.fromJson(e));
        } else if (e is Map) {
          messages.add(AgentMessage.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final presets = <String>[];
    final rawPresets = json['presets'];
    if (rawPresets is List) {
      for (final e in rawPresets) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) presets.add(s);
      }
    }
    return AgentChatSnapshot(
      conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      messages: messages,
      presets: presets,
      presetKey: json['presetKey'] as String?,
    );
  }
}
