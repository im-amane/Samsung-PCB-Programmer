import 'dart:typed_data';

import 'firmware_validator.dart';
import 'renesas_78k0r_protocol.dart';
import 'srecord_image.dart';

/// A fully prepared 16 KB programming sequence. It contains protocol frames
/// only; a hardware driver must still manage direction changes, timing and
/// response handling using the exact target/adapter electrical specification.
class RenesasProgramPlan {
  RenesasProgramPlan._({
    required this.eraseFrame,
    required this.programCommandFrame,
    required this.programDataFrames,
    required this.verifyCommandFrame,
    required this.verifyDataFrames,
    required this.imageSha256,
    required this.totalBytes,
  });

  static const int flashStart = 0x0000;
  static const int flashEnd = 0x3fff;
  static const int flashBytes = 16 * 1024;
  static const int blockBytes = 1024;
  static const int dataFrameBytes = 256;

  final Uint8List eraseFrame;
  final Uint8List programCommandFrame;
  final List<Uint8List> programDataFrames;
  final Uint8List verifyCommandFrame;
  final List<Uint8List> verifyDataFrames;
  final String imageSha256;
  final int totalBytes;

  static RenesasProgramPlan fromSRecord(Uint8List firmwareBytes) {
    final validation = FirmwareValidator.validateSRecords(firmwareBytes);
    if (!validation.valid) {
      throw FormatException('Firmware validation failed: ${validation.message}');
    }
    final image = SRecordImage.parse(firmwareBytes);
    if (image.startAddress != flashStart ||
        image.endAddress != flashEnd ||
        image.dataBytes != flashBytes ||
        image.memory.length != flashBytes) {
      throw FormatException(
        'Expected a complete 16 KB image at 0x0000-0x3FFF; got '
        '${image.dataBytes} bytes at '
        '0x${image.startAddress.toRadixString(16)}-0x${image.endAddress.toRadixString(16)}.',
      );
    }

    // bytesAt rejects any missing address rather than filling gaps silently.
    final payload = image.bytesAt(flashStart, flashBytes);
    final programFrames = <Uint8List>[];
    final verifyFrames = <Uint8List>[];
    for (var offset = 0; offset < payload.length; offset += dataFrameBytes) {
      final end = offset + dataFrameBytes;
      final chunk = payload.sublist(offset, end);
      final last = end == payload.length;
      programFrames.add(Renesas78k0rProtocol.dataFrame(chunk, last: last));
      verifyFrames.add(Renesas78k0rProtocol.dataFrame(chunk, last: last));
    }

    return RenesasProgramPlan._(
      eraseFrame: Renesas78k0rProtocol.chipEraseFrame(),
      programCommandFrame: Renesas78k0rProtocol.programmingFrame(flashStart, flashEnd),
      programDataFrames: List.unmodifiable(programFrames),
      verifyCommandFrame: Renesas78k0rProtocol.verifyFrame(flashStart, flashEnd),
      verifyDataFrames: List.unmodifiable(verifyFrames),
      imageSha256: FirmwareValidator.sha256Hex(firmwareBytes),
      totalBytes: payload.length,
    );
  }
}
