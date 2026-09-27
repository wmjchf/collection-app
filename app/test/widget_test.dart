import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 非首次启动：跳过 LaunchScreen 3 秒，走秒进路径
    SharedPreferences.setMockInitialValues({
      'splash_first_launch_done': true,
    });
  });

  testWidgets('app boots to login page', (tester) async {
    tester.binding.deferFirstFrame();
    await tester.pumpWidget(const SuperCollectionApp());
    await tester.pumpAndSettle();
    expect(find.text('奏折'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
  });
}
