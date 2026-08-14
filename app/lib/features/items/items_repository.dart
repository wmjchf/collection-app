import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/items/item_models.dart';

class ItemsRepository {
  ItemsRepository({
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

  Future<({CollectionItem item, bool existed})> createItem(String url) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items',
      body: {'url': url},
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return (
      item: CollectionItem.fromJson(itemJson),
      existed: json['existed'] as bool? ?? false,
    );
  }

  Future<CollectionItem> getItem(int id) async {
    final token = await _token();
    final json = await _api.get('/api/items/$id', accessToken: token);
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<({List<SearchHit> items, int total, String query})> search(
    String q, {
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await _token();
    final encoded = Uri.encodeQueryComponent(q.trim());
    final json = await _api.get(
      '/api/items/search?q=$encoded&limit=$limit&offset=$offset',
      accessToken: token,
    );
    final list = json['items'] as List<dynamic>? ?? const [];
    return (
      items: list
          .whereType<Map<String, dynamic>>()
          .map(SearchHit.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      query: json['query'] as String? ?? q,
    );
  }

  Future<CollectionItem> reparse(int id) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/reparse',
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<({String status, String? title, String? errorMessage})> getParseStatus(
    int id,
  ) async {
    final token = await _token();
    final json = await _api.get(
      '/api/items/$id/parse-status',
      accessToken: token,
    );
    return (
      status: json['status'] as String? ?? 'pending',
      title: json['title'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  Future<
      ({
        String status,
        String? title,
        String? errorMessage,
        bool needsClientFetch,
        String? url,
        String? platform,
      })> getParseStatusDetailed(int id) async {
    final token = await _token();
    final json = await _api.get(
      '/api/items/$id/parse-status',
      accessToken: token,
    );
    return (
      status: json['status'] as String? ?? 'pending',
      title: json['title'] as String?,
      errorMessage: json['errorMessage'] as String?,
      needsClientFetch: json['needsClientFetch'] as bool? ?? false,
      url: json['url'] as String?,
      platform: json['platform'] as String?,
    );
  }

  /// 客户端抓到的 HTML 交给服务端抽取
  Future<CollectionItem> parseWithHtml(int id, String html) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/parse-with-html',
      body: {'html': html},
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<CollectionItem> markAsRead(int id) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/read',
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<CollectionItem> setStarred(int id, {required bool starred}) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/star',
      body: {'starred': starred},
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<CollectionItem> updateNote(int id, String? note) async {
    final token = await _token();
    final json = await _api.patch(
      '/api/items/$id',
      body: {'note': note},
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<CollectionItem> moveToFolder(int id, int folderId) async {
    final token = await _token();
    final json = await _api.patch(
      '/api/items/$id',
      body: {'folderId': folderId},
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<void> softDelete(int id) async {
    final token = await _token();
    await _api.delete('/api/items/$id', accessToken: token);
  }

  Future<CollectionItem> restoreFromTrash(int id) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/restore',
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<void> purgeFromTrash(int id) async {
    final token = await _token();
    await _api.delete('/api/items/$id/permanent', accessToken: token);
  }

  Future<int> emptyTrash() async {
    final token = await _token();
    final json = await _api.delete('/api/items/trash', accessToken: token);
    return (json['deletedCount'] as num?)?.toInt() ?? 0;
  }

  Future<List<Tag>> listItemTags(int id) async {
    final token = await _token();
    final json = await _api.get('/api/items/$id/tags', accessToken: token);
    final list = json['tags'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList();
  }

  Future<List<Tag>> setItemTags(int id, List<int> tagIds) async {
    final token = await _token();
    final json = await _api.put(
      '/api/items/$id/tags',
      body: {'tagIds': tagIds},
      accessToken: token,
    );
    final list = json['tags'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList();
  }

  Future<List<ItemAnnotation>> listAnnotations(int id) async {
    final token = await _token();
    final json =
        await _api.get('/api/items/$id/annotations', accessToken: token);
    final list = json['annotations'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ItemAnnotation.fromJson)
        .toList();
  }

  Future<ItemAnnotation> createAnnotation(
    int id, {
    required String selectedText,
    int? startOffset,
    int? endOffset,
    String? note,
  }) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/annotations',
      body: {
        'selectedText': selectedText,
        if (startOffset != null) 'startOffset': startOffset,
        if (endOffset != null) 'endOffset': endOffset,
        if (note != null) 'note': note,
      },
      accessToken: token,
    );
    final ann = json['annotation'] as Map<String, dynamic>? ?? {};
    return ItemAnnotation.fromJson(ann);
  }

  Future<ItemAnnotation> updateAnnotationNote(
    int itemId,
    int annotationId,
    String? note,
  ) async {
    final token = await _token();
    final json = await _api.patch(
      '/api/items/$itemId/annotations/$annotationId',
      body: {'note': note},
      accessToken: token,
    );
    final ann = json['annotation'] as Map<String, dynamic>? ?? {};
    return ItemAnnotation.fromJson(ann);
  }

  Future<void> deleteAnnotation(int itemId, int annotationId) async {
    final token = await _token();
    await _api.delete(
      '/api/items/$itemId/annotations/$annotationId',
      accessToken: token,
    );
  }
}
