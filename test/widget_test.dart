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

  testWidgets('each bundled DA41 profile selects its own verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final profile0459G = find.text('0459G · Double Door');
    await tester.scrollUntilVisible(profile0459G, 250, scrollable: scrollable);
    await tester.tap(profile0459G);
    await tester.pumpAndSettle();
    expect(find.text('DA41-00814D_0459G.mot'), findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);

    final profile0459M = find.text('0459M · Single Door');
    await tester.scrollUntilVisible(profile0459M, 250, scrollable: scrollable);
    await tester.tap(profile0459M);
    await tester.pumpAndSettle();
    expect(find.text('DA41-00814D_0459M.bin'), findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);
  });
}
