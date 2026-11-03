import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/agent/agent_models.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class AgentRepository {
  AgentRepository({ApiClient? client, AuthRepository? auth})
      : _client = client ?? ApiClient(),
        _auth = auth ?? AuthRepository();

  final ApiClient _client;
  final AuthRepository _auth;

  Future<String> _token() async {
    final session = await _auth.readSession();
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw ApiException('未登录', statusCode: 401);
    }
    return token;
  }

  Future<AgentConversation> createConversation({String? title}) async {
    final json = await _client.post(
      '/api/agent/conversations',
      accessToken: await _token(),
      body: {
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
    );
    return AgentConversation.fromJson(json);
  }

  Future<List<AgentConversation>> listConversations() async {
    final json = await _client.get(
      '/api/agent/conversations',
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

  Future<AgentTurnResult> sendMessage({
    required int conversationId,
    required String content,
    String? clientMessageId,
  }) async {
    final json = await _client.post(
      '/api/agent/conversations/$conversationId/messages',
      accessToken: await _token(),
      body: {
        'content': content,
        if (clientMessageId != null && clientMessageId.isNotEmpty)
          'clientMessageId': clientMessageId,
      },
    );
    return AgentTurnResult.fromJson(json);
  }

  /// 归档会话（列表不再展示；等同删除当前聊天记录）
  Future<void> archiveConversation(int id) async {
    await _client.delete(
      '/api/agent/conversations/$id',
      accessToken: await _token(),
    );
  }
}
