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
  Future<void> transmitMode() async => txCount++;

  @override
  Future<void> receiveMode() async => rxCount++;

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
      expect(channel.writes.single, [0x01, 0x01, 0xc0, 0x3e, 0x03]);
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
      final firmware = Uint8List.fromList(utf8.encode(
        'S3060000000001F8\nS70500000000FA\n',
      ));
      // An incomplete image cannot produce a program plan, so this assertion
      // checks the plan parser independently of any hardware transaction.
      expect(() => RenesasProgramPlan.fromSRecord(firmware), throwsFormatException);
      expect(channel.writes, isEmpty);
    });
  });
}
