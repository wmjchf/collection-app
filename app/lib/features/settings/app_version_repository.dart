import 'package:super_collection/core/network/api_client.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.iosStoreUrl,
    required this.androidStoreUrl,
  });

  final String latestVersion;
  final String releaseNotes;
  final String iosStoreUrl;
  final String androidStoreUrl;

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      latestVersion: (json['latestVersion'] as String?)?.trim() ?? '',
      releaseNotes: (json['releaseNotes'] as String?)?.trim() ?? '',
      iosStoreUrl: (json['iosStoreUrl'] as String?)?.trim() ?? '',
      androidStoreUrl: (json['androidStoreUrl'] as String?)?.trim() ?? '',
    );
  }
}

class AppVersionRepository {
  AppVersionRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<AppVersionInfo> fetch() async {
    final json = await _client.get(
      '/api/app/version',
      handleExpiry: false,
    );
    return AppVersionInfo.fromJson(json);
  }
}
