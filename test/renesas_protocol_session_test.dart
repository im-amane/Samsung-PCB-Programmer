import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/renesas_protocol_session.dart';
import 'package:samsung_pcb_programmer/renesas_program_plan.dart';

class _FakeChannel implements RenesasWireChannel {
  final List<Uint8List> responses;
  final List<Uint8List> writes = [];
  int txCount = 0;
  int rxCount = 0;

  _FakeChannel(this.responses);

  @override
  Future<void> transmitMode() async { txCount++; }

  @override
  Future<void> receiveMode() async { rxCount++; }

  @override
  Future<void> write(Uint8List bytes) async => writes.add(Uint8List.fromList(bytes));

  @override
  Future<Uint8List> readFrame(Duration timeout) async {
    if (responses.isEmpty) throw StateError('No fake response queued.');
    return responses.removeAt(0);
  }
}

Uint8List _statusFrame(List<int> statuses) {
  final length = statuses.length;
  final sum = (-(length + statuses.fold<int>(0, (a, b) => a + b))) & 0xff;
  return Uint8List.fromList([0x02, length, ...statuses, sum, 0x03]);
}

String _s3Record(int address, List<int> data) {
  final bytes = <int>[
    4 + data.length + 1,
    (address >> 24) & 0xff,
    (address >> 16) & 0xff,
    (address >> 8) & 0xff,
    address & 0xff,
    ...data,
  ];
  final sum = bytes.fold<int>(0, (a, b) => a + b);
  return 'S3${[...bytes, (~sum) & 0xff].map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
}

Uint8List _full16kS3Image() {
  final lines = <String>[];
  for (var address = 0; address < 0x4000; address += 64) {
    lines.add(_s3Record(address, List<int>.generate(64, (i) => (address + i) & 0xff)));
  }
  lines.add('S70500000000FA');
  return Uint8List.fromList(utf8.encode('${lines.join('\\n')}\\n'));
}

void main() {
  group('RenesasProtocolSession', () {
    test('reads signature only after ACK and validates response checksum', () async {
      final channel = _FakeChannel([
        _statusFrame([0x06]),
        _statusFrame([0x12, 0x34]),
      ]);
      final session = RenesasProtocolSession(
        channel: channel,
        timing: const RenesasSessionTiming(
          interFrame: Duration.zero,
          commandTimeout: Duration(seconds: 1),
          dataTimeout: Duration(seconds: 1),
        ),
      );

      expect(await session.readSiliconSignature(), [0x12, 0x34]);
      expect(channel.writes, hasLength(1));
      expect(channel.writes.single, [0x01, 0x01, 0xc0, 0x3f, 0x03]);
      expect(channel.txCount, 1);
      expect(channel.rxCount, 1);
    });

    test('refuses destructive programming without explicit erase confirmation', () async {
      final channel = _FakeChannel([]);
      final session = RenesasProtocolSession(
        channel: channel,
        timing: const RenesasSessionTiming(
          interFrame: Duration.zero,
          commandTimeout: Duration(seconds: 1),
          dataTimeout: Duration(seconds: 1),
        ),
      );
      final plan = RenesasProgramPlan.fromSRecord(_full16kS3Image());
      await expectLater(
        session.program(plan: plan, confirmDestructiveErase: false),
        throwsStateError,
      );
      expect(channel.writes, isEmpty);
    });
  });
}
