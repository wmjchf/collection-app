import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/folder_models.dart';
import 'package:super_collection/features/items/item_models.dart';

class FoldersRepository {
  FoldersRepository({
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

  Future<List<Folder>> listFolders() async {
    final token = await _token();
    final json = await _api.get('/api/folders', accessToken: token);
    final list = json['folders'] as List<dynamic>? ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(Folder.fromJson)
        .toList();
  }

  Future<Folder> createFolder(String name) async {
    final token = await _token();
    final json = await _api.post(
      '/api/folders',
      body: {'name': name},
      accessToken: token,
    );
    final folderJson = json['folder'] as Map<String, dynamic>? ?? {};
    return Folder.fromJson(folderJson);
  }

  Future<void> deleteFolder(int id) async {
    final token = await _token();
    await _api.delete('/api/folders/$id', accessToken: token);
  }

  Future<({List<CollectionItem> items, int total})> listFolderItems(
    int folderId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await _token();
    final json = await _api.get(
      '/api/folders/$folderId/items?limit=$limit&offset=$offset',
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
