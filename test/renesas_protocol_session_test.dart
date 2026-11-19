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

Uint8List _dataFrame(List<int> data) {
  final length = data.length == 256 ? 0 : data.length;
  final sum = (-(length + data.fold<int>(0, (a, b) => a + b))) & 0xff;
  return Uint8List.fromList([0x02, length, ...data, sum, 0x03]);
}

String _s3Record(int address, List<int> data) {
  final bytes = <int>[
    5 + data.length,
    (address >> 24) & 0xff,
    (address >> 16) & 0xff,
    (address >> 8) & 0xff,
    address & 0xff,
    ...data,
  ];
  final sum = bytes.fold<int>(0, (a, b) => a + b);
  final encoded = [...bytes, (~sum) & 0xff]
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return 'S3' + encoded;
}

Uint8List _full16kS3Image() {
  final lines = <String>[];
  for (var address = 0; address < 0x4000; address += 64) {
    lines.add(_s3Record(address, List<int>.generate(64, (i) => (address + i) & 0xff)));
  }
  lines.add('S70500000000FA');
  return Uint8List.fromList(utf8.encode(lines.join('\n') + '\n'));
}

void main() {
  group('RenesasProtocolSession', () {
    test('reads signature only after ACK and validates response checksum', () async {
      final signature = <int>[
        0x10, 0x7f, 0x04, 0xdc, 0xfd, 0xfd, 0xff, 0x3f, 0x00,
        ...'D78F1201  '.codeUnits,
        0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff,
      ];
      final channel = _FakeChannel([
        _statusFrame([0x06]),
        _dataFrame(signature),
      ]);
      final session = RenesasProtocolSession(
        channel: channel,
        timing: const RenesasSessionTiming(
          interFrame: Duration.zero,
          commandTimeout: Duration(seconds: 1),
          dataTimeout: Duration(seconds: 1),
        ),
      );

      expect(await session.readSiliconSignature(), signature);
      expect(channel.writes, hasLength(1));
      expect(channel.writes.single, [0x01, 0x01, 0xc0, 0x3f, 0x03]);
      expect(channel.txCount, 1);
      expect(channel.rxCount, 1);
    });

    test('sends erase, program and verify frames and checks every status', () async {
      final plan = RenesasProgramPlan.fromSRecord(_full16kS3Image());
      final responses = <Uint8List>[
        _statusFrame([0x06]),
        _statusFrame([0x06]),
        ...List<Uint8List>.generate(64, (_) => _statusFrame([0x06, 0x06])),
        _statusFrame([0x06]), // final automatic internal-verify result
        _statusFrame([0x06]),
        ...List<Uint8List>.generate(64, (_) => _statusFrame([0x06, 0x06])),
      ];
      final channel = _FakeChannel(responses);
      final session = RenesasProtocolSession(
        channel: channel,
        timing: const RenesasSessionTiming(
          interFrame: Duration.zero,
          commandTimeout: Duration(seconds: 1),
          dataTimeout: Duration(seconds: 1),
        ),
      );

      final progress = <RenesasProgramProgress>[];
      await session.program(
        plan: plan,
        confirmDestructiveErase: true,
        onProgress: progress.add,
      );

      expect(channel.writes, hasLength(131));
      expect(channel.writes.first, plan.eraseFrame);
      expect(channel.writes[1], plan.programCommandFrame);
      expect(channel.writes[66], plan.verifyCommandFrame);
      expect(channel.writes.last, plan.verifyDataFrames.last);
      expect(channel.txCount, 131);
      expect(channel.rxCount, 131);
      expect(responses, isEmpty);
      expect(progress.last.stage, RenesasProgramStage.complete);
      expect(progress.last.completedFrames, progress.last.totalFrames);
      expect(progress.last.fraction, 1);
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
