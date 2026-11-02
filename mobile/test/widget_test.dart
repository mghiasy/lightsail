import 'package:flutter_test/flutter_test.dart';
import 'package:lightsail_mobile/main.dart';

void main() {
  testWidgets('shows Lightsail home', (tester) async {
    await tester.pumpWidget(const LightsailApp());
    await tester.pump();
    expect(find.textContaining('Lightsail'), findsWidgets);
  });
}
