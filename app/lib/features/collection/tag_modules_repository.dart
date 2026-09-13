import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';

class TagModulesRepository {
  TagModulesRepository({
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

  Future<({List<TagModule> modules, List<Tag> ungrouped})> listModules() async {
    final token = await _token();
    final json = await _api.get('/api/tag-modules', accessToken: token);
    final modules = (json['modules'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TagModule.fromJson)
        .toList();
    final ungrouped = (json['ungrouped'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList();
    return (modules: modules, ungrouped: ungrouped);
  }

  Future<TagModule> createModule(String name) async {
    final token = await _token();
    final json = await _api.post(
      '/api/tag-modules',
      body: {'name': name},
      accessToken: token,
    );
    final moduleJson = json['module'] as Map<String, dynamic>? ?? {};
    return TagModule.fromJson(moduleJson);
  }
}
