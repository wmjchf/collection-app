/// 后端 API 基址。
/// - 本地调试可用 `http://127.0.0.1:3001`
/// - 也可用 `--dart-define=API_BASE_URL=...` 覆盖
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    // defaultValue: 'https://inkmind.xyz/collection'
    // defaultValue: 'http://127.0.0.1:3001',
    defaultValue:'http://192.168.10.4:3001'
    // defaultValue:'http://47.97.67.47:3001'
  );
}
