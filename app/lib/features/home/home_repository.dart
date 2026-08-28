import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/items/item_models.dart';

class HomeSectionData {
  const HomeSectionData({
    required this.total,
    required this.items,
  });

  final int total;
  final List<CollectionItem> items;

  factory HomeSectionData.fromJson(Map<String, dynamic> json) {
    final list = json['items'] as List<dynamic>? ?? const [];
    return HomeSectionData(
      total: (json['total'] as num?)?.toInt() ?? 0,
      items: list
          .whereType<Map<String, dynamic>>()
          .map(CollectionItem.fromJson)
          .toList(),
    );
  }
}

class HomeData {
  const HomeData({
    required this.unread,
    required this.starred,
  });

  final HomeSectionData unread;
  final HomeSectionData starred;

  factory HomeData.fromJson(Map<String, dynamic> json) {
    return HomeData(
      unread: HomeSectionData.fromJson(
        json['unread'] as Map<String, dynamic>? ?? const {},
      ),
      starred: HomeSectionData.fromJson(
        json['starred'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class HomeRepository {
  HomeRepository({
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

  Future<HomeData> fetchHome() async {
    final token = await _token();
    final tz = DateTime.now().timeZoneOffset.inMinutes;
    final json = await _api.get(
      '/api/home?tzOffsetMinutes=$tz',
      accessToken: token,
    );
    return HomeData.fromJson(json);
  }
}
