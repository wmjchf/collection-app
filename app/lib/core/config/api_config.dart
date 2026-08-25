/// 后端 API 基址（编译期常量，改后需 `flutter clean` 再装包，热重载无效）。
///
/// 环境切换：
/// - 测试：`http://47.97.67.47:3002`（真机已配 ATS / 明文网络例外）
/// - 生产：`https://conflux.wobufang.com`
/// - 本机：`http://127.0.0.1:3001` 或局域网 `http://192.168.x.x:3001`
/// - 临时覆盖：`flutter run --dart-define=API_BASE_URL=http://...`
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://47.97.67.47:3002',
    // defaultValue: 'https://conflux.wobufang.com',
    // defaultValue: 'http://127.0.0.1:3001',
  );
}
