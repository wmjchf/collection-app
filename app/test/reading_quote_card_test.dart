import 'package:flutter_test/flutter_test.dart';
import 'package:super_collection/features/items/reading_quote_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quote share png encodes', () async {
    final bytes = await renderReadingQuotePng(
      quote: '把以后再看变成随时能看。',
    );
    expect(bytes.length, greaterThan(100));
    expect(bytes[0], 0x89);
    expect(bytes[1], 0x50);
  });
}
