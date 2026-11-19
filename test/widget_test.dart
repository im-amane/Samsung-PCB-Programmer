import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/main.dart';

void main() {
  testWidgets('application dashboard renders', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pump();

    expect(find.text('Samsung Swap'), findsOneWidget);
    expect(find.text('00755A · RT36 Inverter'), findsOneWidget);
    expect(find.text('TARGET FIRMWARE PROFILE'), findsOneWidget);

    final frenchDoor = find.text('00838A · French Door');
    await tester.scrollUntilVisible(
      frenchDoor,
      300,
      scrollable: find.descendant(
        of: find.byType(Scrollable).first,
        matching: find.byType(Scrollable),
      ),
    );
    expect(frenchDoor, findsOneWidget);
  });
}
