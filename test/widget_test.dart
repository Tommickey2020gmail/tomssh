import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tomssh/main.dart';

void main() {
  testWidgets('App launches with lock screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TomSSHApp()));
    await tester.pump();

    // Verify the app shows the lock screen
    expect(find.text('TomSSH'), findsOneWidget);
  });
}
