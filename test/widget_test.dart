import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/main.dart';

Finder dashboardScrollable() => find.descendant(
  of: find.byType(ListView).first,
  matching: find.byType(Scrollable),
).first;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 220, scrollable: dashboardScrollable(), maxScrolls: 30);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> selectBoard(WidgetTester tester, String board) async {
  final dropdown = find.byType(DropdownButtonFormField<int>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(board).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('basic dashboard shows connection, firmware and board controls', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();
    expect(find.text('Samsung PCB Programmer'), findsOneWidget);
    expect(find.text('USB CONNECTION'), findsOneWidget);
    expect(find.text('BOARD SELECTION'), findsOneWidget);
    expect(find.text('FIRMWARE'), findsOneWidget);
    expect(find.text('TARGET SIGNATURE'), findsOneWidget);
    expect(find.text('PROGRAMMING'), findsOneWidget);
    await reveal(tester, find.text('Erase + Write + Verify'));
    expect(find.text('Erase + Write + Verify'), findsOneWidget);
  });

  testWidgets('flash controls stay disabled until hardware commissioning is complete', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();
    final flash = find.widgetWithText(FilledButton, 'Erase + Write + Verify');
    await reveal(tester, flash);
    expect(tester.widget<FilledButton>(flash).onPressed, isNull);
    expect(find.textContaining('HARDWARE COMMISSIONING REQUIRED'), findsOneWidget);
  });

  testWidgets('default board loads its bundled verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();
    expect(find.text('DA41-00814A.mot'), findsOneWidget);
    expect(find.textContaining('Profile match: YES'), findsOneWidget);
  });

  testWidgets('0459G profile selects its own verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();
    await selectBoard(tester, '0459G · Double Door');
    await reveal(tester, find.text('DA41-00814D_0459G.mot'));
    expect(find.text('DA41-00814D_0459G.mot'), findsOneWidget);
    expect(find.textContaining('Profile match: YES'), findsOneWidget);
  });

  testWidgets('0459M profile selects its own verified firmware', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pumpAndSettle();
    await selectBoard(tester, '0459M · Single Door');
    await reveal(tester, find.text('DA41-00814D_0459M.bin'));
    expect(find.text('DA41-00814D_0459M.bin'), findsOneWidget);
    expect(find.textContaining('Profile match: YES'), findsOneWidget);
  });
}
