/// 后端 API 基址。
/// - 模拟器调试可用 `http://127.0.0.1:3000`
/// - 真机 / 打给同网段测试的包：用电脑局域网 IP
/// - 也可用 `--dart-define=API_BASE_URL=...` 覆盖
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.10.4:3000',
  );
}
