import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/items/item_models.dart';

class TagsRepository {
  TagsRepository({
    ApiClient? apiClient,
    AuthRepository? authRepository,
  })  : _api = apiClient ?? ApiClient(),
        _auth = authRepository ?? AuthRepository();

  final ApiClient _api;
  final AuthRepository _auth;

  Future<String> _token() async {
    final session = await _auth.readSession();
    if (session == null) {
      throw ApiException('未登录', statusCode: 401);
    }
    return session.accessToken;
  }

  Future<List<Tag>> listTags() async {
    final token = await _token();
    final json = await _api.get('/api/tags', accessToken: token);
    final list = json['tags'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList();
  }

  Future<Tag> createTag(String name, {int? moduleId}) async {
    final token = await _token();
    final body = <String, dynamic>{'name': name};
    if (moduleId != null) body['moduleId'] = moduleId;
    final json = await _api.post(
      '/api/tags',
      body: body,
      accessToken: token,
    );
    final tagJson = json['tag'] as Map<String, dynamic>? ?? {};
    return Tag.fromJson(tagJson);
  }

  /// 搜标签；`tags` 为基集文章上的全部标签（命中靠前）；可用 filterTagIds 二次筛选（AND）
  Future<
      ({
        List<Tag> tags,
        List<int> matchedTagIds,
        int? primaryTagId,
        List<CollectionItem> items,
        int itemsTotal,
        String query,
      })> searchTags(
    String q, {
    int limit = 50,
    int offset = 0,
    List<int> filterTagIds = const [],
  }) async {
    final token = await _token();
    final encoded = Uri.encodeQueryComponent(q.trim());
    final filter = filterTagIds.isEmpty
        ? ''
        : '&filterTagIds=${filterTagIds.join(',')}';
    final json = await _api.get(
      '/api/tags/search?q=$encoded&limit=$limit&offset=$offset$filter',
      accessToken: token,
    );
    final tags = (json['tags'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList();
    final matchedTagIds = <int>[];
    final rawMatched = json['matchedTagIds'];
    if (rawMatched is List) {
      for (final e in rawMatched) {
        if (e is num) matchedTagIds.add(e.toInt());
      }
    }
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CollectionItem.fromJson)
        .toList();
    return (
      tags: tags,
      matchedTagIds: matchedTagIds,
      primaryTagId: (json['primaryTagId'] as num?)?.toInt(),
      items: items,
      itemsTotal: (json['itemsTotal'] as num?)?.toInt() ?? 0,
      query: json['query'] as String? ?? q,
    );
  }

  Future<Tag> renameTag(int id, String name) async {
    final token = await _token();
    final json = await _api.patch(
      '/api/tags/$id',
      body: {'name': name},
      accessToken: token,
    );
    final tagJson = json['tag'] as Map<String, dynamic>? ?? {};
    return Tag.fromJson(tagJson);
  }

  Future<Tag> placeTag(
    int id, {
    int? moduleId,
    int? beforeTagId,
  }) async {
    final token = await _token();
    final body = <String, dynamic>{'moduleId': moduleId};
    if (beforeTagId != null) body['beforeTagId'] = beforeTagId;
    final json = await _api.patch(
      '/api/tags/$id',
      body: body,
      accessToken: token,
    );
    final tagJson = json['tag'] as Map<String, dynamic>? ?? {};
    return Tag.fromJson(tagJson);
  }

  Future<void> deleteTag(int id) async {
    final token = await _token();
    await _api.delete('/api/tags/$id', accessToken: token);
  }

  Future<({List<CollectionItem> items, int total})> listTagItems(
    int tagId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await _token();
    final json = await _api.get(
      '/api/tags/$tagId/items?limit=$limit&offset=$offset',
      accessToken: token,
    );
    final list = json['items'] as List<dynamic>? ?? const [];
    return (
      items: list
          .whereType<Map<String, dynamic>>()
          .map(CollectionItem.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }
}
