import 'package:flutter_test/flutter_test.dart';
import 'package:new_project/main.dart';

void main() {
  testWidgets('Shows auth screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ReflectionDiaryApp());
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Войти через Google'), findsOneWidget);
  });
}
