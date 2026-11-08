import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:super_collection/core/config/api_config.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/agent/agent_models.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class AgentRepository {
  AgentRepository({ApiClient? client, AuthRepository? auth, http.Client? httpClient})
      : _client = client ?? ApiClient(),
        _auth = auth ?? AuthRepository(),
        _http = httpClient ?? http.Client();

  final ApiClient _client;
  final AuthRepository _auth;
  final http.Client _http;

  Future<String> _token() async {
    final session = await _auth.readSession();
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw ApiException('未登录', statusCode: 401);
    }
    return token;
  }

  Future<AgentConversation> createConversation({
    String? title,
    int? focusItemId,
  }) async {
    final json = await _client.post(
      '/api/agent/conversations',
      accessToken: await _token(),
      body: {
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        'focusItemId': ?focusItemId,
      },
    );
    return AgentConversation.fromJson(json);
  }

  /// 全局会话（[focusItemId] 空）或某篇专属会话；没有则创建。
  Future<AgentConversation> ensureConversation({
    int? focusItemId,
    String? title,
  }) async {
    final json = await _client.post(
      '/api/agent/conversations/ensure',
      accessToken: await _token(),
      body: {
        'focusItemId': ?focusItemId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
    );
    return AgentConversation.fromJson(json);
  }

  Future<List<AgentConversation>> listConversations({
    int? focusItemId,
    bool globalOnly = false,
  }) async {
    final qs = <String>[];
    if (focusItemId != null) qs.add('focusItemId=$focusItemId');
    if (globalOnly) qs.add('global=1');
    final path = qs.isEmpty
        ? '/api/agent/conversations'
        : '/api/agent/conversations?${qs.join('&')}';
    final json = await _client.get(
      path,
      accessToken: await _token(),
    );
    final items = json['items'];
    if (items is! List) return const [];
    return [
      for (final e in items)
        if (e is Map<String, dynamic>)
          AgentConversation.fromJson(e)
        else if (e is Map)
          AgentConversation.fromJson(Map<String, dynamic>.from(e)),
    ];
  }

  Future<({AgentConversation conversation, List<AgentMessage> messages})>
      getConversation(int id) async {
    final json = await _client.get(
      '/api/agent/conversations/$id',
      accessToken: await _token(),
    );
    final convRaw = json['conversation'];
    final conv = AgentConversation.fromJson(
      convRaw is Map<String, dynamic>
          ? convRaw
          : Map<String, dynamic>.from(convRaw as Map),
    );
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
    return (conversation: conv, messages: messages);
  }

  /// 动态口语预设（服务端不计用户 AI 额度）
  Future<List<String>> fetchPresets({
    required int conversationId,
    int? focusItemId,
    String? lastAssistantContent,
    bool hasPendingAction = false,
  }) async {
    final json = await _client.post(
      '/api/agent/conversations/$conversationId/presets',
      accessToken: await _token(),
      body: {
        'focusItemId': ?focusItemId,
        if (lastAssistantContent != null && lastAssistantContent.isNotEmpty)
          'lastAssistantContent': lastAssistantContent,
        'hasPendingAction': hasPendingAction,
      },
    );
    final raw = json['presets'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if ((e?.toString().trim() ?? '').isNotEmpty) e.toString().trim(),
    ];
  }

  Future<AgentTurnResult> sendMessage({
    required int conversationId,
    required String content,
    String? clientMessageId,
    int? focusItemId,
  }) async {
    final json = await _client.post(
      '/api/agent/conversations/$conversationId/messages',
      accessToken: await _token(),
      body: {
        'content': content,
        if (clientMessageId != null && clientMessageId.isNotEmpty)
          'clientMessageId': clientMessageId,
        'focusItemId': ?focusItemId,
      },
    );
    return AgentTurnResult.fromJson(json);
  }

  /// SSE 发消息：事件 `phase` / `token` / `user` / `done` / `error`
  Future<AgentTurnResult> sendMessageStream({
    required int conversationId,
    required String content,
    String? clientMessageId,
    int? focusItemId,
    void Function(String phase)? onPhase,
    void Function(String text)? onToken,
    void Function(AgentMessage user)? onUser,
  }) async {
    final token = await _token();
    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/api/agent/conversations/$conversationId/messages',
    );
    final req = http.Request('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode({
        'content': content,
        if (clientMessageId != null && clientMessageId.isNotEmpty)
          'clientMessageId': clientMessageId,
        'focusItemId': ?focusItemId,
      });

    final streamed = await _http.send(req).timeout(
      const Duration(seconds: 120),
    );

    if (streamed.statusCode == 401) {
      throw ApiException('登录已过期', statusCode: 401);
    }
    if (streamed.statusCode == 402) {
      throw ApiException('额度不足或需升级', statusCode: 402);
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw ApiException(
        body.isNotEmpty ? body : '请求失败',
        statusCode: streamed.statusCode,
      );
    }

    AgentMessage? userMessage;
    AgentMessage? assistantMessage;
    String? errorMessage;
    int? errorStatus;

    var eventName = 'message';
    final dataBuf = StringBuffer();
    // 跨 TCP chunk 拼行：长 done（整段回复 JSON）常被拆开，按 chunk 直接 split 会丢半行
    var lineCarry = '';

    void flushEvent() {
      final data = dataBuf.toString().trim();
      dataBuf.clear();
      final name = eventName;
      eventName = 'message';
      if (data.isEmpty) return;

      Map<String, dynamic> map;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) {
          map = decoded;
        } else if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        } else {
          return;
        }
      } catch (_) {
        return;
      }

      switch (name) {
        case 'phase':
          final phase = map['phase']?.toString();
          if (phase != null && phase.isNotEmpty) onPhase?.call(phase);
          break;
        case 'token':
          final text = map['text']?.toString() ?? '';
          if (text.isNotEmpty) onToken?.call(text);
          break;
        case 'user':
          final raw = map['message'];
          if (raw is Map) {
            userMessage = AgentMessage.fromJson(Map<String, dynamic>.from(raw));
            onUser?.call(userMessage!);
          }
          break;
        case 'done':
          final u = map['userMessage'];
          final a = map['assistantMessage'];
          if (u is Map) {
            userMessage = AgentMessage.fromJson(Map<String, dynamic>.from(u));
          }
          if (a is Map) {
            assistantMessage =
                AgentMessage.fromJson(Map<String, dynamic>.from(a));
          }
          break;
        case 'error':
          errorMessage = map['message']?.toString() ?? '助手出错了';
          errorStatus = (map['status'] as num?)?.toInt();
          break;
      }
    }

    void handleLine(String line) {
      final trimmed =
          line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
      if (trimmed.startsWith('event:')) {
        eventName = trimmed.substring(6).trim();
      } else if (trimmed.startsWith('data:')) {
        if (dataBuf.isNotEmpty) dataBuf.write('\n');
        dataBuf.write(trimmed.substring(5).trimLeft());
      } else if (trimmed.isEmpty) {
        flushEvent();
      }
    }

    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      lineCarry += chunk;
      while (true) {
        final i = lineCarry.indexOf('\n');
        if (i < 0) break;
        handleLine(lineCarry.substring(0, i));
        lineCarry = lineCarry.substring(i + 1);
      }
    }
    if (lineCarry.isNotEmpty) {
      handleLine(lineCarry);
      lineCarry = '';
    }
    flushEvent();

    if (errorMessage != null) {
      throw ApiException(errorMessage!, statusCode: errorStatus);
    }
    if (userMessage == null || assistantMessage == null) {
      throw ApiException('流式响应不完整', statusCode: streamed.statusCode);
    }
    return AgentTurnResult(
      userMessage: userMessage!,
      assistantMessage: assistantMessage!,
    );
  }

  /// 归档会话（列表不再展示；等同删除当前聊天记录）
  Future<void> archiveConversation(int id) async {
    await _client.delete(
      '/api/agent/conversations/$id',
      accessToken: await _token(),
    );
  }

  /// 确认或取消助手预览中的写操作（如改标签）。
  Future<AgentConfirmActionResult> confirmAction({
    required int conversationId,
    required int messageId,
    required bool approve,
  }) async {
    final json = await _client.post(
      '/api/agent/actions/confirm',
      accessToken: await _token(),
      body: {
        'conversationId': conversationId,
        'messageId': messageId,
        'approve': approve,
      },
    );
    return AgentConfirmActionResult.fromJson(json);
  }
}

class AgentConfirmActionResult {
  const AgentConfirmActionResult({
    this.assistantMessage,
    this.pendingAction,
    this.alreadySettled = false,
  });

  final AgentMessage? assistantMessage;
  final AgentPendingAction? pendingAction;
  final bool alreadySettled;

  factory AgentConfirmActionResult.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    final a = asMap(json['assistantMessage']);
    final p = asMap(json['pendingAction']);
    return AgentConfirmActionResult(
      assistantMessage: a != null ? AgentMessage.fromJson(a) : null,
      pendingAction: p != null ? AgentPendingAction.fromJson(p) : null,
      alreadySettled: json['alreadySettled'] == true,
    );
  }
}
