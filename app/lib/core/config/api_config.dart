/// 后端 API 基址。模拟器/真机调试时按环境改。
/// - iOS 模拟器 / 桌面：可用 localhost
/// - Android 模拟器：用 10.0.2.2 访问宿主机
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );
}
