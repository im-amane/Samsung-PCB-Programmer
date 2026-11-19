import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/firmware_validator.dart';

void main() {
  group('FirmwareValidator', () {
    test('accepts a valid S1/S9 image', () {
      final result = FirmwareValidator.validateSRecords(
        Uint8List.fromList(utf8.encode('S10500000102F7\nS9030000FC\n')),
      );
      expect(result.valid, isTrue);
      expect(result.dataRecords, 1);
      expect(result.dataBytes, 2);
      expect(result.startAddress, 0);
      expect(result.endAddress, 1);
    });

    test('accepts the S3/S7 record type used by the single-door image', () {
      final result = FirmwareValidator.validateSRecords(
        Uint8List.fromList(utf8.encode('S3060000000001F8\\nS70500000000FA\\n')),
      );
      expect(result.valid, isTrue);
      expect(result.dataRecords, 1);
      expect(result.dataBytes, 1);
    });

    test('rejects a bad checksum', () {
      final result = FirmwareValidator.validateSRecords(
        Uint8List.fromList(utf8.encode('S10500000102F6\nS9030000FC\n')),
      );
      expect(result.valid, isFalse);
      expect(result.message, contains('Checksum mismatch'));
    });

    test('rejects a missing termination record', () {
      final result = FirmwareValidator.validateSRecords(
        Uint8List.fromList(utf8.encode('S10500000102F7\n')),
      );
      expect(result.valid, isFalse);
      expect(result.message, contains('Missing'));
    });

    test('rejects bytes after termination', () {
      final result = FirmwareValidator.validateSRecords(
        Uint8List.fromList(utf8.encode('S9030000FC\nS10500000102F7\n')),
      );
      expect(result.valid, isFalse);
      expect(result.message, contains('after termination'));
    });
  });
}
