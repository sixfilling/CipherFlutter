import 'package:cipher_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Cipher shell', (WidgetTester tester) async {
    await tester.pumpWidget(const CipherApp());
    await tester.pump();

    expect(find.text('Cipher'), findsOneWidget);
    expect(find.text('Encrypt'), findsOneWidget);
    expect(find.text('Decrypt'), findsOneWidget);
  });
}
