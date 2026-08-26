import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/transcript_models.dart';

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

  /// 刷新易过期的 CDN 播放直链（如 B站）
  Future<CollectionItem> refreshVideo(int id) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/refresh-video',
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  /// 可转写媒体列表
  Future<List<TranscriptTarget>> getTranscriptTargets(int id) async {
    final token = await _token();
    final json = await _api.get(
      '/api/items/$id/transcript-targets',
      accessToken: token,
    );
    final raw = json['targets'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => TranscriptTarget.fromJson(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ))
        .toList(growable: false);
  }

  /// 按 segmentKey 提交转写
  Future<CollectionItem> requestTranscript(
    int id, {
    required String segmentKey,
    bool force = false,
    String? mediaUrl,
  }) async {
    final token = await _token();
    final body = <String, dynamic>{
      'segmentKey': segmentKey,
      'force': force,
    };
    if (mediaUrl != null && mediaUrl.trim().isNotEmpty) {
      body['mediaUrl'] = mediaUrl.trim();
    }
    final json = await _api.post(
      '/api/items/$id/transcript',
      body: body,
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<({
    Map<String, TranscriptSegment> segments,
    bool hasPending,
    String? pendingSegmentKey,
  })> getTranscriptStatus(int id) async {
    final token = await _token();
    final json = await _api.get(
      '/api/items/$id/transcript-status',
      accessToken: token,
    );
    final raw = json['segments'];
    final segments = <String, TranscriptSegment>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          segments[key.toString()] = TranscriptSegment.fromJson(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      });
    }
    return (
      segments: segments,
      hasPending: json['hasPending'] as bool? ?? false,
      pendingSegmentKey: json['pendingSegmentKey'] as String?,
    );
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

  /// 待本机抓页补齐的 pending 条目（快捷指令后台入库等）
  Future<
      List<
          ({
            int id,
            String? title,
            String url,
            String? platform,
          })>> listNeedsClientFetch({int limit = 20}) async {
    final token = await _token();
    final json = await _api.get(
      '/api/items/needs-client-fetch?limit=$limit',
      accessToken: token,
    );
    final list = json['items'] as List<dynamic>? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return (
        id: (m['id'] as num).toInt(),
        title: m['title'] as String?,
        url: m['url'] as String? ?? '',
        platform: m['platform'] as String?,
      );
    }).where((e) => e.url.isNotEmpty).toList();
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

  Future<({
    AiTagsMeta tags,
    String? model,
  })> getAiSuggestStatus(int id) async {
    final token = await _token();
    final json = await _api.get(
      '/api/items/$id/ai-suggest-status',
      accessToken: token,
    );
    final rawTags = json['tags'];
    AiTagsMeta tags = const AiTagsMeta();
    if (rawTags is Map<String, dynamic>) {
      tags = AiTagsMeta.fromJson(rawTags);
    } else if (rawTags is Map) {
      tags = AiTagsMeta.fromJson(
        rawTags.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return (tags: tags, model: json['model'] as String?);
  }

  Future<CollectionItem> requestAiSuggest(int id, {bool force = false}) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/ai-suggest',
      body: {'force': force},
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<CollectionItem> applyAiSuggest(
    int id,
    List<String> names,
  ) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/ai-suggest/apply',
      body: {'names': names},
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
  }

  Future<CollectionItem> dismissAiSuggest(int id) async {
    final token = await _token();
    final json = await _api.post(
      '/api/items/$id/ai-suggest/dismiss',
      accessToken: token,
    );
    final itemJson = json['item'] as Map<String, dynamic>? ?? {};
    return CollectionItem.fromJson(itemJson);
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
