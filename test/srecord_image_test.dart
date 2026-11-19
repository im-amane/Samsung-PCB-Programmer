import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/srecord_image.dart';

void main() {
  group('SRecordImage', () {
    test('parses S1 data into addressable memory', () {
      final image = SRecordImage.parse(
        Uint8List.fromList(utf8.encode('S10500000102F7\nS9030000FC\n')),
      );
      expect(image.recordType, '1');
      expect(image.dataBytes, 2);
      expect(image.bytesAt(0, 2), [1, 2]);
      expect(image.dataBlocks(blockSize: 1), hasLength(2));
    });

    test('parses the S3/S7 format used by the 0459M asset', () {
      final image = SRecordImage.parse(
        Uint8List.fromList(utf8.encode('S3060000000001F8\nS70500000000FA\n')),
      );
      expect(image.recordType, '3');
      expect(image.startAddress, 0);
      expect(image.endAddress, 0);
      expect(image.bytesAt(0, 1), [1]);
    });

    test('rejects overlapping addresses', () {
      expect(
        () => SRecordImage.parse(Uint8List.fromList(utf8.encode(
          'S10500000102F7\nS10500000102F7\nS9030000FC\n',
        ))),
        throwsFormatException,
      );
    });

    test('rejects gaps when a continuous range is requested', () {
      final image = SRecordImage.parse(
        Uint8List.fromList(utf8.encode('S104000001FA\nS104000202F7\nS9030000FC\n')),
      );
      expect(() => image.bytesAt(0, 3), throwsFormatException);
      expect(image.bytesAt(0, 3, fillByte: 0xff), [1, 0xff, 2]);
    });

    test('rejects a mismatched S5 data-record count', () {
      expect(
        () => SRecordImage.parse(Uint8List.fromList(utf8.encode(
          'S10500000102F7\nS5030002FA\nS9030000FC\n',
        ))),
        throwsFormatException,
      );
    });
  });
}
