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

  Future<Tag> createTag(String name) async {
    final token = await _token();
    final json = await _api.post(
      '/api/tags',
      body: {'name': name},
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
