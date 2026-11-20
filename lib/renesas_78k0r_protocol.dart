import 'dart:typed_data';

/// Frame codec for the Renesas 78K0R serial flash programming protocol.
///
/// Based on Renesas application note U19486EJ1V0AN. The codec only creates
/// and validates protocol frames. It does not control VDD, RESET, FLMD0,
/// TOOL0, baud switching, direction control, or any physical target.
class Renesas78k0rProtocol {
  static const int soh = 0x01;
  static const int stx = 0x02;
  static const int etx = 0x03;
  static const int etb = 0x17;

  // U19486 UART entry settings before any Baud Rate Set command.
  static const int initialBaudRate = 9600;
  static const int dataBits = 8;
  static const int programmerToTargetStopBits = 2;
  static const int targetToProgrammerStopBits = 1;

  static const int reset = 0x00;
  static const int baudRateSet = 0x9a;
  static const int chipErase = 0x20;
  static const int blockErase = 0x22;
  static const int programming = 0x40;
  static const int verify = 0x13;
  static const int blockBlankCheck = 0x32;
  static const int siliconSignature = 0xc0;
  static const int versionGet = 0xc5;
  static const int checksum = 0xb0;

  static const int ack = 0x06;
  static const int checksumError = 0x07;
  static const int verifyError = 0x0f;
  static const int protectError = 0x10;
  static const int nack = 0x15;

  /// The protocol checksum is the two's-complement negative sum of LEN,
  /// COM and command information, modulo 256.
  static int _checksum(Iterable<int> bytes) {
    var sum = 0;
    for (final byte in bytes) {
      if (byte < 0 || byte > 0xff) throw RangeError.range(byte, 0, 0xff, 'byte');
      sum = (sum + byte) & 0xff;
    }
    return (-sum) & 0xff;
  }

  static Uint8List commandFrame(int command, [List<int> information = const []]) {
    if (command < 0 || command > 0xff) {
      throw RangeError.range(command, 0, 0xff, 'command');
    }
    if (information.length > 254) {
      throw ArgumentError('Command information cannot exceed 254 bytes.');
    }
    for (final value in information) {
      if (value < 0 || value > 0xff) {
        throw RangeError.range(value, 0, 0xff, 'information byte');
      }
    }
    final length = 1 + information.length;
    final checksum = _checksum([length, command, ...information]);
    return Uint8List.fromList([soh, length, command, ...information, checksum, etx]);
  }

  static Uint8List resetFrame() => commandFrame(reset);
  static Uint8List chipEraseFrame() => commandFrame(chipErase);
  static Uint8List siliconSignatureFrame() => commandFrame(siliconSignature);
  static Uint8List versionGetFrame() => commandFrame(versionGet);

  /// D01..D04 are deliberately required from the caller. The D04 voltage
  /// mode and D02 baud divisor must come from the verified target setup.
  static Uint8List baudRateSetFrame({
    required int synchronizationMode,
    required int baudHigh,
    required int baudLow,
    required int noiseFilter,
    required int voltageMode,
  }) =>
      commandFrame(baudRateSet, [
        synchronizationMode,
        baudHigh,
        baudLow,
        noiseFilter,
        voltageMode,
      ]);

  static List<int> _address24(int address) {
    if (address < 0 || address > 0xffffff) {
      throw RangeError.range(address, 0, 0xffffff, 'address');
    }
    return [
      (address >> 16) & 0xff,
      (address >> 8) & 0xff,
      address & 0xff,
    ];
  }

  static void _checkBlockRange(int startAddress, int endAddress) {
    if (endAddress < startAddress) {
      throw ArgumentError('End address must be at or after start address.');
    }
    if ((startAddress & 0x3ff) != 0 || (endAddress & 0x3ff) != 0x3ff) {
      throw ArgumentError('Start/end addresses must align to 1 KB block boundaries.');
    }
  }

  static Uint8List blockEraseFrame(int startAddress, int endAddress) {
    _checkBlockRange(startAddress, endAddress);
    return commandFrame(blockErase, [
      ..._address24(startAddress),
      ..._address24(endAddress),
    ]);
  }

  static Uint8List programmingFrame(int startAddress, int endAddress) {
    _checkBlockRange(startAddress, endAddress);
    return commandFrame(programming, [
      ..._address24(startAddress),
      ..._address24(endAddress),
    ]);
  }

  static Uint8List verifyFrame(int startAddress, int endAddress) {
    _checkBlockRange(startAddress, endAddress);
    return commandFrame(verify, [
      ..._address24(startAddress),
      ..._address24(endAddress),
    ]);
  }

  static Uint8List dataFrame(List<int> data, {required bool last}) {
    if (data.isEmpty || data.length > 256) {
      throw ArgumentError('A data frame must contain between 1 and 256 bytes.');
    }
    for (final value in data) {
      if (value < 0 || value > 0xff) {
        throw RangeError.range(value, 0, 0xff, 'data byte');
      }
    }
    final length = data.length == 256 ? 0 : data.length;
    final sum = _checksum([length, ...data]);
    return Uint8List.fromList([stx, length, ...data, sum, last ? etx : etb]);
  }

  /// Decodes and validates a complete STX response frame.
  static RenesasResponseFrame decodeResponseFrame(List<int> frame) {
    if (frame.length < 5 || frame.first != stx) {
      throw const FormatException('Response frame must start with STX and contain a payload.');
    }
    final declaredLength = frame[1];
    final dataLength = declaredLength == 0 ? 256 : declaredLength;
    if (frame.length != dataLength + 4) {
      throw FormatException(
        'Response length mismatch: declared $dataLength data bytes, received ${frame.length - 4}.',
      );
    }
    final footer = frame.last;
    if (footer != etx && footer != etb) {
      throw const FormatException('Invalid response frame footer.');
    }
    final data = frame.sublist(2, 2 + dataLength);
    final receivedChecksum = frame[2 + dataLength];
    final expectedChecksum = _checksum([declaredLength, ...data]);
    if (receivedChecksum != expectedChecksum) {
      throw const FormatException('Response frame checksum mismatch.');
    }
    return RenesasResponseFrame(
      data: Uint8List.fromList(data),
      isFinal: footer == etx,
    );
  }

  /// Decodes the complete 78K0R/Ix3 silicon-signature payload described by
  /// Renesas application note U19486EJ1V0AN. The frame includes STX, LEN,
  /// the 27-byte signature, checksum and ETX.
  static RenesasSiliconSignature decodeSiliconSignatureFrame(List<int> frame) {
    final response = decodeResponseFrame(frame);
    if (!response.isFinal || response.data.length != 27) {
      throw FormatException('Invalid 78K0R silicon signature length: expected 27 bytes, received ${response.data.length}.');
    }
    final data = response.data;
    return RenesasSiliconSignature(
      vendor: data[0],
      macroExtension: data[1],
      macroFunction: data[2],
      deviceExtension: Uint8List.fromList(data.sublist(3, 6)),
      flashLastAddress: (data[8] << 16) | (data[7] << 8) | data[6],
      deviceName: String.fromCharCodes(data.sublist(9, 19)).trim(),
      securityFlags: data[19],
      bootBlock: data[20],
      flashShieldWindow: Uint8List.fromList(data.sublist(21, 25)),
      reserved: Uint8List.fromList(data.sublist(25, 27)),
      raw: Uint8List.fromList(data),
    );
  }

  static void requireAck(RenesasResponseFrame response, {String operation = 'command'}) {
    requireStatuses(response, expectedCount: 1, operation: operation);
  }

  /// Programming data-frame responses contain two status bytes: reception
  /// check (ST1) and flash write result (ST2). Both must be ACK.
  static void requireStatuses(
    RenesasResponseFrame response, {
    required int expectedCount,
    String operation = 'command',
  }) {
    if (!response.isFinal) {
      throw FormatException('The $operation response did not terminate with ETX.');
    }
    if (response.data.length != expectedCount) {
      throw FormatException('Unexpected status length for $operation: expected $expectedCount, received ${response.data.length}.');
    }
    for (var index = 0; index < response.data.length; index++) {
      final status = response.data[index];
      if (status != ack) {
        throw RenesasProtocolStatusError(
          '78K0R $operation status ${index + 1} failed with 0x${status.toRadixString(16).padLeft(2, '0').toUpperCase()}.',
        );
      }
    }
  }
}

/// Parsed Renesas 78K0R silicon signature (U19486EJ1V0AN, section 3.8).
class RenesasSiliconSignature {
  const RenesasSiliconSignature({
    required this.vendor,
    required this.macroExtension,
    required this.macroFunction,
    required this.deviceExtension,
    required this.flashLastAddress,
    required this.deviceName,
    required this.securityFlags,
    required this.bootBlock,
    required this.flashShieldWindow,
    required this.reserved,
    required this.raw,
  });

  final int vendor;
  final int macroExtension;
  final int macroFunction;
  final Uint8List deviceExtension;
  final int flashLastAddress;
  final String deviceName;
  final int securityFlags;
  final int bootBlock;
  final Uint8List flashShieldWindow;
  final Uint8List reserved;
  final Uint8List raw;
}

class RenesasResponseFrame {
  const RenesasResponseFrame({required this.data, required this.isFinal});

  final Uint8List data;
  final bool isFinal;

  int? get status => data.length == 1 ? data.single : null;
}

/// A syntactically valid response frame whose protocol status is not ACK.
/// Kept distinct from transport/time-out failures so only NACK-like responses
/// are eligible for the Reset retry rule.
class RenesasProtocolStatusError extends StateError {
  RenesasProtocolStatusError(super.message);
}
