import 'dart:convert';
import 'dart:typed_data';

/// Parsed Motorola S-record image. This is a format parser only; it does not
/// imply that a particular target MCU accepts the image or a given write size.
class SRecordImage {
  SRecordImage._({
    required this.recordType,
    required this.totalRecords,
    required this.dataRecords,
    required this.dataBytes,
    required this.startAddress,
    required this.endAddress,
    required Map<int, int> memory,
  }) : memory = Map.unmodifiable(memory);

  final String recordType;
  final int totalRecords;
  final int dataRecords;
  final int dataBytes;
  final int startAddress;
  final int endAddress;
  final Map<int, int> memory;

  static const _addressBytes = <String, int>{
    '0': 2, '1': 2, '2': 3, '3': 4,
    '5': 2, '6': 3, '7': 4, '8': 3, '9': 2,
  };

  static SRecordImage parse(Uint8List bytes) {
    final source = utf8.decode(bytes, allowMalformed: false);
    final lines = const LineSplitter().convert(source);
    final memory = <int, int>{};
    var total = 0;
    var dataRecords = 0;
    var dataBytes = 0;
    var countRecord = -1;
    var sawHeader = false;
    var sawData = false;
    var sawTermination = false;
    String? dataType;
    String? terminationType;
    var minAddress = 0x7fffffff;
    var maxAddress = -1;

    FormatException fail(String message) => FormatException(message);

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex].trim();
      if (line.isEmpty) continue;
      if (sawTermination) throw fail('Record after termination at line ${lineIndex + 1}.');
      if (!RegExp(r'^S[0-9][0-9A-Fa-f]+$').hasMatch(line) || line.length.isOdd) {
        throw fail('Malformed S-record at line ${lineIndex + 1}.');
      }
      final type = line.substring(1, 2);
      final addressLength = _addressBytes[type];
      if (addressLength == null) throw fail('Unsupported S-record type S$type.');
      final hex = line.substring(2);
      if (hex.isEmpty || hex.length.isOdd) throw fail('Invalid hex length at line ${lineIndex + 1}.');
      final record = <int>[
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
      final byteCount = record.first;
      if (byteCount != record.length - 1) throw fail('Byte-count mismatch at line ${lineIndex + 1}.');
      if ((record.fold<int>(0, (sum, value) => sum + value) & 0xff) != 0xff) {
        throw fail('Checksum mismatch at line ${lineIndex + 1}.');
      }
      if (byteCount < addressLength + 1) throw fail('Record too short at line ${lineIndex + 1}.');
      final address = record.skip(1).take(addressLength).fold<int>(
        0, (value, byte) => (value << 8) | byte,
      );
      final payloadLength = byteCount - addressLength - 1;
      final payload = record.sublist(1 + addressLength, record.length - 1);

      if (type == '0') {
        if (sawHeader || total != 0 || sawData) throw fail('S0 header must be first and unique.');
        if (payloadLength == 0 && byteCount != addressLength + 1) {
          throw fail('Invalid S0 header.');
        }
        sawHeader = true;
      } else if (type == '1' || type == '2' || type == '3') {
        if (payloadLength == 0) throw fail('Empty data record at line ${lineIndex + 1}.');
        if (dataType != null && dataType != type) throw fail('Mixed data record types are not supported.');
        dataType = type;
        sawData = true;
        dataRecords++;
        dataBytes += payloadLength;
        for (var i = 0; i < payload.length; i++) {
          final targetAddress = address + i;
          if (memory.containsKey(targetAddress)) {
            throw fail('Overlapping data at address 0x${targetAddress.toRadixString(16).toUpperCase()}.');
          }
          memory[targetAddress] = payload[i];
        }
        if (address < minAddress) minAddress = address;
        final end = address + payloadLength - 1;
        if (end > 0xffffffff) throw fail('Address overflow at line ${lineIndex + 1}.');
        if (end > maxAddress) maxAddress = end;
      } else if (type == '5' || type == '6') {
        if (!sawData || payloadLength != 0 || countRecord >= 0) {
          throw fail('Invalid or duplicate S$type count record.');
        }
        countRecord = address;
      } else if (type == '7' || type == '8' || type == '9') {
        final expectedDataType = type == '9' ? '1' : type == '8' ? '2' : '3';
        if (!sawData || payloadLength != 0 || dataType != expectedDataType) {
          throw fail('S$type termination does not match the data record type.');
        }
        terminationType = type;
        sawTermination = true;
      }
      total++;
    }

    if (!sawData || dataRecords == 0) throw fail('No firmware data records found.');
    if (!sawTermination) throw fail('Missing S7/S8/S9 termination record.');
    if (countRecord >= 0 && countRecord != dataRecords) {
      throw fail('Count record says $countRecord data records, found $dataRecords.');
    }

    return SRecordImage._(
      recordType: dataType!,
      totalRecords: total,
      dataRecords: dataRecords,
      dataBytes: dataBytes,
      startAddress: minAddress,
      endAddress: maxAddress,
      memory: memory,
    );
  }

  /// Returns bytes for a continuous address range. Missing addresses are
  /// rejected by default instead of silently fabricating erased bytes.
  Uint8List bytesAt(int start, int length, {int? fillByte}) {
    if (start < 0 || length < 0 || start + length > 0x100000000) {
      throw RangeError('Invalid address range.');
    }
    final output = Uint8List(length);
    for (var i = 0; i < length; i++) {
      final value = memory[start + i];
      if (value == null && fillByte == null) {
        throw FormatException('Firmware gap at address 0x${(start + i).toRadixString(16).toUpperCase()}.');
      }
      output[i] = value ?? fillByte!;
    }
    return output;
  }

  /// Splits already-parsed bytes into generic data blocks. The block size is
  /// not a target protocol setting and must not be used as a flash command size
  /// until the MCU programmer protocol is confirmed.
  List<Uint8List> dataBlocks({int blockSize = 256}) {
    if (blockSize <= 0) throw ArgumentError.value(blockSize, 'blockSize');
    final full = bytesAt(startAddress, endAddress - startAddress + 1);
    return List.unmodifiable([
      for (var offset = 0; offset < full.length; offset += blockSize)
        Uint8List.fromList(full.sublist(
          offset,
          offset + blockSize > full.length ? full.length : offset + blockSize,
        )),
    ]);
  }
}
