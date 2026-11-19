import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/renesas_program_plan.dart';

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
  final checksum = (~sum) & 0xff;
  return 'S3${[...bytes, checksum].map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
}

Uint8List _full16kS3Image() {
  final lines = <String>[];
  for (var address = 0; address < 0x4000; address += 64) {
    lines.add(_s3Record(address, List<int>.generate(64, (i) => (address + i) & 0xff)));
  }
  lines.add('S70500000000FA');
  return Uint8List.fromList(utf8.encode('${lines.join('\n')}\n'));
}

void main() {
  group('RenesasProgramPlan', () {
    test('prepares 16 KB erase, program and verify frames', () {
      final plan = RenesasProgramPlan.fromSRecord(_full16kS3Image());
      expect(plan.totalBytes, 16384);
      expect(plan.programDataFrames, hasLength(64));
      expect(plan.verifyDataFrames, hasLength(64));
      expect(plan.eraseFrame, [0x01, 0x01, 0x20, 0xdf, 0x03]);
      expect(plan.programDataFrames.first.first, 0x02);
      expect(plan.programDataFrames.first.last, 0x17);
      expect(plan.programDataFrames.last.last, 0x03);
      expect(plan.verifyDataFrames.last.last, 0x03);
      expect(plan.imageSha256, hasLength(64));
    });

    test('rejects an image that is not the complete 16 KB address range', () {
      final small = Uint8List.fromList(utf8.encode('S3060000000001F8\nS70500000000FA\n'));
      expect(() => RenesasProgramPlan.fromSRecord(small), throwsFormatException);
    });
  });
}
