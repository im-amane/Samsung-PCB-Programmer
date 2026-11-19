import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/main.dart';

Finder dashboardScrollable() => find.descendant(
      of: find.byType(ListView).first,
      matching: find.byType(Scrollable),
    ).first;

Future<void> reveal(
  WidgetTester tester,
  Finder finder,
  Finder scrollable,
) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: scrollable,
    maxScrolls: 40,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('application dashboard renders all board profiles', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    expect(find.text('Samsung Swap'), findsOneWidget);
    final flashButton = find.widgetWithText(FilledButton, 'Erase + Write + Verify');
    await reveal(tester, flashButton, dashboardScrollable());
    expect(tester.widget<FilledButton>(flashButton).onPressed, isNull);
    final scrollable = dashboardScrollable();

    final profileHeading = find.text('TARGET FIRMWARE PROFILE');
    await reveal(tester, profileHeading, scrollable);
    expect(profileHeading, findsOneWidget);

    final firstProfile = find.text('00755A · RT36 Inverter');
    await reveal(tester, firstProfile, scrollable);
    expect(firstProfile, findsOneWidget);

    final frenchDoor = find.text('00838A · French Door');
    await reveal(tester, frenchDoor, scrollable);
    expect(frenchDoor, findsOneWidget);
  });

  testWidgets('default board loads its bundled verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    final scrollable = dashboardScrollable();
    final firmwareName = find.text('DA41-00814A.mot');
    await reveal(tester, firmwareName, scrollable);
    expect(firmwareName, findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);
    expect(find.text('Renesas 16 KB frame plan: READY (no bytes sent to PCB)'), findsOneWidget);
  });

  testWidgets('0459G profile selects its own verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    final scrollable = dashboardScrollable();
    final profile = find.text('0459G · Double Door');
    await reveal(tester, profile, scrollable);
    await tester.tap(profile);
    await tester.pumpAndSettle();

    final firmwareName = find.text('DA41-00814D_0459G.mot');
    await reveal(tester, firmwareName, scrollable);
    expect(firmwareName, findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);
  });

  testWidgets('0459M profile selects its own verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();

    final scrollable = dashboardScrollable();
    final profile = find.text('0459M · Single Door');
    await reveal(tester, profile, scrollable);
    await tester.tap(profile);
    await tester.pumpAndSettle();

    final firmwareName = find.text('DA41-00814D_0459M.bin');
    await reveal(tester, firmwareName, scrollable);
    expect(firmwareName, findsOneWidget);
    expect(find.text('Exact profile match: YES'), findsOneWidget);
  });
}
