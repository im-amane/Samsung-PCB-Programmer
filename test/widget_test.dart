import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/main.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('application dashboard renders all board profiles', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    expect(find.text('Samsung Swap'), findsOneWidget);
    expect(find.text('TARGET FIRMWARE PROFILE'), findsOneWidget);

    final firstProfile = find.text('00755A · RT36 Inverter');
    await reveal(tester, firstProfile);
    expect(firstProfile, findsOneWidget);

    final frenchDoor = find.text('00838A · French Door');
    await reveal(tester, frenchDoor);
    expect(frenchDoor, findsOneWidget);
  });

  testWidgets('default board loads its bundled verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    final firmwareName = find.text('DA41-00814A.mot');
    await reveal(tester, firmwareName);
    expect(firmwareName, findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);
    expect(find.text('Renesas 16 KB frame plan: READY (no bytes sent to PCB)'), findsOneWidget);
  });

  testWidgets('each bundled DA41 profile selects its own verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    final profile0459G = find.text('0459G · Double Door');
    await reveal(tester, profile0459G);
    await tester.tap(profile0459G);
    await tester.pumpAndSettle();

    final firmware0459G = find.text('DA41-00814D_0459G.mot');
    await reveal(tester, firmware0459G);
    expect(firmware0459G, findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);

    final profile0459M = find.text('0459M · Single Door');
    await reveal(tester, profile0459M);
    await tester.tap(profile0459M);
    await tester.pumpAndSettle();

    final firmware0459M = find.text('DA41-00814D_0459M.bin');
    await reveal(tester, firmware0459M);
    expect(firmware0459M, findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);
  });
}
