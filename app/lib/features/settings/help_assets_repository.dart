import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

/// 设置 → 使用帮助页配图（OSS help/ 前缀，经 API 签 24h URL）
class HelpAssetsRepository {
  HelpAssetsRepository({
    ApiClient? client,
    AuthRepository? authRepository,
  })  : _client = client ?? ApiClient(),
        _auth = authRepository ?? AuthRepository();

  final ApiClient _client;
  final AuthRepository _auth;
  static final _cache = <String, _CachedHelpAssets>{};

  static const aiAutoTags = 'ai_auto_tags';
  static const shortcuts = 'shortcuts';
  static const howToAddLink = 'how_to_add_link';

  Future<List<String>> loadUrls(String set) async {
    final cached = _cache[set];
    if (cached != null && !cached.isExpired) {
      return cached.urls;
    }

    final session = await _auth.readSession();
    final json = await _client.get(
      '/api/help/assets/$set',
      accessToken: session?.accessToken,
      handleExpiry: false,
    );
    final images = json['images'];
    if (images is! List || images.isEmpty) {
      throw ApiException('帮助配图为空');
    }

    final urls = <String>[];
    for (final item in images) {
      if (item is! Map) continue;
      final url = item['url']?.toString().trim() ?? '';
      if (url.isNotEmpty) urls.add(url);
    }
    if (urls.isEmpty) {
      throw ApiException('帮助配图无效');
    }

    _cache[set] = _CachedHelpAssets(urls);
    return urls;
  }
}

class _CachedHelpAssets {
  _CachedHelpAssets(this.urls) : fetchedAt = DateTime.now();

  final List<String> urls;
  final DateTime fetchedAt;

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > const Duration(hours: 20);
}
