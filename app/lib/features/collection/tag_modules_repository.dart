import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/ai_organize_models.dart';
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

  Future<void> deleteModule(int id) async {
    final token = await _token();
    await _api.delete('/api/tag-modules/$id', accessToken: token);
  }

  /// AI 归类建议（同步）；不落库。
  Future<({AiOrganizeProposal proposal, String message})> suggestAiOrganize({
    String? hint,
  }) async {
    final token = await _token();
    final body = <String, dynamic>{};
    final h = hint?.trim();
    if (h != null && h.isNotEmpty) body['hint'] = h;
    final json = await _api.post(
      '/api/tag-modules/ai-organize',
      body: body,
      accessToken: token,
    );
    final proposalJson = json['proposal'] as Map<String, dynamic>? ?? {};
    return (
      proposal: AiOrganizeProposal.fromJson(proposalJson),
      message: json['message'] as String? ?? '已生成归类建议',
    );
  }

  /// 应用 AI 归类方案。
  Future<({List<TagModule> modules, List<Tag> ungrouped, String message})>
      applyAiOrganize(AiOrganizeProposal proposal) async {
    final token = await _token();
    final json = await _api.post(
      '/api/tag-modules/ai-organize/apply',
      body: proposal.toApplyBody(),
      accessToken: token,
    );
    final modules = (json['modules'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TagModule.fromJson)
        .toList();
    final ungrouped = (json['ungrouped'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList();
    return (
      modules: modules,
      ungrouped: ungrouped,
      message: json['message'] as String? ?? '已应用归类',
    );
  }
}
