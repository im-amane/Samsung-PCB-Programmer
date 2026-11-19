import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class SRecordValidation {
  const SRecordValidation({required this.valid, required this.totalRecords, required this.dataRecords, required this.dataBytes, required this.startAddress, required this.endAddress, required this.message});
  final bool valid;
  final int totalRecords;
  final int dataRecords;
  final int dataBytes;
  final int? startAddress;
  final int? endAddress;
  final String message;
}

class FirmwareValidator {
  static String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Stable fingerprint for S-record text across CRLF/LF checkout differences.
  /// The original APK uses CRLF and ends with a newline; GitHub text files may
  /// use LF and omit the final newline. This canonical form makes the same
  /// firmware data compare identically without changing the raw-file digest.
  static String canonicalSRecordSha256Hex(Uint8List bytes) {
    final source = utf8.decode(bytes, allowMalformed: false);
    var normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!normalized.endsWith('\n')) normalized = '$normalized\n';
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  static SRecordValidation validateSRecords(Uint8List bytes) {
    late final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return const SRecordValidation(valid: false, totalRecords: 0, dataRecords: 0, dataBytes: 0, startAddress: null, endAddress: null, message: 'Firmware is not valid UTF-8/ASCII S-record text.');
    }
    final lines = const LineSplitter().convert(source);
    var totalRecords = 0, dataRecords = 0, dataBytes = 0, countRecordValue = -1;
    var sawTermination = false, sawHeader = false;
    var minAddress = 0x7fffffff, maxAddress = -1;
    final usedDataTypes = <String>{};
    const addressBytes = <String, int>{'0': 2, '1': 2, '2': 3, '3': 4, '5': 2, '6': 3, '7': 4, '8': 3, '9': 2};
    const dataTypes = {'1', '2', '3'};
    const terminationTypes = {'7', '8', '9'};

    SRecordValidation fail(String message) => SRecordValidation(
      valid: false, totalRecords: totalRecords, dataRecords: dataRecords, dataBytes: dataBytes,
      startAddress: maxAddress < 0 ? null : minAddress, endAddress: maxAddress < 0 ? null : maxAddress, message: message);

    for (var lineNumber = 0; lineNumber < lines.length; lineNumber++) {
      final line = lines[lineNumber].trim();
      if (line.isEmpty) continue;
      if (sawTermination) return fail('Data found after termination record at line ${lineNumber + 1}.');
      if (!RegExp(r'^S[0-9][0-9A-Fa-f]+$').hasMatch(line) || line.length.isOdd) return fail('Malformed S-record at line ${lineNumber + 1}.');
      final type = line.substring(1, 2);
      final addressLength = addressBytes[type];
      if (addressLength == null) return fail('Unsupported S-record type S$type.');
      final hex = line.substring(2);
      if (hex.length < 2 || hex.length.isOdd) return fail('Invalid hex length at line ${lineNumber + 1}.');
      final record = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        record.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      final count = record.first;
      if (count != record.length - 1) return fail('Byte-count mismatch at line ${lineNumber + 1}.');
      if ((record.fold<int>(0, (sum, value) => sum + value) & 0xff) != 0xff) return fail('Checksum mismatch at line ${lineNumber + 1}.');
      if (count < addressLength + 1) return fail('Record too short at line ${lineNumber + 1}.');
      final address = record.skip(1).take(addressLength).fold<int>(0, (value, byte) => (value << 8) | byte);
      final payloadLength = count - addressLength - 1;

      if (type == '0') {
        if (sawHeader || totalRecords != 0) return fail('S0 header must appear only once at the beginning.');
        sawHeader = true;
      } else if (dataTypes.contains(type)) {
        if (payloadLength <= 0) return fail('Empty data record at line ${lineNumber + 1}.');
        final end = address + payloadLength - 1;
        if (end > 0xffffffff) return fail('Address overflow at line ${lineNumber + 1}.');
        if (address < minAddress) minAddress = address;
        if (end > maxAddress) maxAddress = end;
        dataBytes += payloadLength;
        dataRecords++;
        usedDataTypes.add(type);
      } else if (type == '5' || type == '6') {
        if (payloadLength != 0) return fail('S$type count record must not contain data.');
        if (countRecordValue >= 0) return fail('Multiple S-record count records found.');
        countRecordValue = address;
      } else if (terminationTypes.contains(type)) {
        if (payloadLength != 0) return fail('S$type termination record must not contain data.');
        if (dataRecords == 0) return fail('Termination record found without firmware data.');
        final expectedDataType = type == '9' ? '1' : (type == '8' ? '2' : '3');
        if (usedDataTypes.length != 1 || !usedDataTypes.contains(expectedDataType)) return fail('S$type termination type does not match firmware data record type.');
        sawTermination = true;
      }
      totalRecords++;
    }
    if (dataRecords == 0) return fail('No firmware data records found.');
    if (!sawTermination) return fail('Missing S7/S8/S9 termination record.');
    if (countRecordValue >= 0 && countRecordValue != dataRecords) return fail('S5/S6 count record says $countRecordValue data records, found $dataRecords.');
    return SRecordValidation(valid: true, totalRecords: totalRecords, dataRecords: dataRecords, dataBytes: dataBytes,
      startAddress: minAddress, endAddress: maxAddress, message: 'Valid Motorola S-Record: $dataRecords data records, $dataBytes data bytes.');
  }
}
