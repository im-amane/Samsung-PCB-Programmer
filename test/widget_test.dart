import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/main.dart';

void main() {
  testWidgets('application dashboard renders', (tester) async {
    await tester.pumpWidget(const SamsungPcbProgrammerApp());
    await tester.pump();
    expect(find.text('Samsung PCB Programmer'), findsOneWidget);
    expect(find.text('TARGET FIRMWARE PROFILE'), findsOneWidget);
    expect(find.text('FIRMWARE CATALOGUE'), findsOneWidget);
  });
}
