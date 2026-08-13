import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/system_filter_models.dart';
import 'package:super_collection/features/items/item_models.dart';

class SystemFiltersRepository {
  SystemFiltersRepository({
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

  int get _tzOffsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  Future<({List<SystemFilter> filters, List<SystemFilter> others})>
      listFilters() async {
    final token = await _token();
    final json = await _api.get(
      '/api/system-filters?tzOffsetMinutes=$_tzOffsetMinutes',
      accessToken: token,
    );
    final list = json['filters'] as List<dynamic>? ?? const [];
    final others = json['others'] as List<dynamic>? ?? const [];
    return (
      filters: list
          .whereType<Map<String, dynamic>>()
          .map(SystemFilter.fromJson)
          .toList(),
      others: others
          .whereType<Map<String, dynamic>>()
          .map(SystemFilter.fromJson)
          .toList(),
    );
  }

  Future<({List<CollectionItem> items, int total})> listItems({
    required String filter,
    int limit = 50,
    int offset = 0,
  }) async {
    final token = await _token();
    final json = await _api.get(
      '/api/items?filter=$filter'
      '&tzOffsetMinutes=$_tzOffsetMinutes'
      '&limit=$limit&offset=$offset',
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
