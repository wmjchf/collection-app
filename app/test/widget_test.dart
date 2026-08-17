import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app boots to login page', (tester) async {
    await tester.pumpWidget(const SuperCollectionApp());
    await tester.pumpAndSettle();
    expect(find.text('Conflux'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
  });
}
