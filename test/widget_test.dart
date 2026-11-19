import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/main.dart';

void main() {
  testWidgets('application dashboard renders all board profiles', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    expect(find.text('Samsung Swap'), findsOneWidget);
    expect(find.text('00755A · RT36 Inverter'), findsOneWidget);
    expect(find.text('TARGET FIRMWARE PROFILE'), findsOneWidget);

    final frenchDoor = find.text('00838A · French Door');
    await tester.scrollUntilVisible(
      frenchDoor,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(frenchDoor, findsOneWidget);
  });

  testWidgets('default board loads its bundled verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    expect(find.text('DA41-00814A.mot'), findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);
    expect(find.text('Renesas 16 KB frame plan: READY (no bytes sent to PCB)'), findsOneWidget);
  });
}
