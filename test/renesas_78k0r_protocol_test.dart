import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/renesas_78k0r_protocol.dart';

void main() {
  group('Renesas78k0rProtocol frame codec', () {
    test('builds the documented chip erase frame exactly', () {
      expect(
        Renesas78k0rProtocol.chipEraseFrame(),
        [0x01, 0x01, 0x20, 0xdf, 0x03],
      );
    });

    test('builds reset and silicon-signature frames', () {
      expect(Renesas78k0rProtocol.resetFrame(), [0x01, 0x01, 0x00, 0xff, 0x03]);
      expect(Renesas78k0rProtocol.siliconSignatureFrame(), [0x01, 0x01, 0xc0, 0x3f, 0x03]);
    });

    test('builds a block-aligned programming command', () {
      expect(
        Renesas78k0rProtocol.programmingFrame(0x0000, 0x3fff),
        [0x01, 0x07, 0x40, 0x00, 0x00, 0x00, 0x00, 0x3f, 0xff, 0xc1, 0x03],
      );
    });

    test('rejects unaligned programming ranges', () {
      expect(
        () => Renesas78k0rProtocol.programmingFrame(0x0001, 0x3fff),
        throwsArgumentError,
      );
    });

    test('builds a data frame with the documented checksum', () {
      expect(
        Renesas78k0rProtocol.dataFrame([0xff, 0x80, 0x40, 0x22], last: true),
        [0x02, 0x04, 0xff, 0x80, 0x40, 0x22, 0x1b, 0x03],
      );
    });

    test('encodes 256 data bytes with a zero length byte', () {
      final frame = Renesas78k0rProtocol.dataFrame(List<int>.filled(256, 0xff), last: false);
      expect(frame.length, 260);
      expect(frame[0], 0x02);
      expect(frame[1], 0x00);
      expect(frame.last, 0x17);
    });

    test('validates response frame and ACK status', () {
      final response = Renesas78k0rProtocol.decodeResponseFrame([0x02, 0x01, 0x06, 0xf9, 0x03]);
      expect(response.status, 0x06);
      expect(response.isFinal, isTrue);
      expect(() => Renesas78k0rProtocol.requireAck(response), returnsNormally);
    });

    test('rejects response checksum corruption', () {
      expect(
        () => Renesas78k0rProtocol.decodeResponseFrame([0x02, 0x01, 0x06, 0xf8, 0x03]),
        throwsFormatException,
      );
    });

    test('rejects non-ACK status', () {
      final response = Renesas78k0rProtocol.decodeResponseFrame([0x02, 0x01, 0x15, 0xea, 0x03]);
      expect(() => Renesas78k0rProtocol.requireAck(response), throwsStateError);
    });
  });
}
