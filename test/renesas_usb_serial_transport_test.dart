import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/renesas_78k0r_protocol.dart';
import 'package:samsung_pcb_programmer/renesas_usb_serial_transport.dart';
import 'package:samsung_pcb_programmer/renesas_protocol_session.dart';

class FakeUsbDriver implements RenesasUsbPortDriver {
  final StreamController<Uint8List> controller =
      StreamController<Uint8List>();
  final List<String> calls = <String>[];
  int configuredStopBits = 0;
  Uint8List? written;

  @override
  Stream<Uint8List> get inputStream => controller.stream;

  @override
  Future<void> configure({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required int parity,
  }) async {
    calls.add('configure:$baudRate:$dataBits:$stopBits:$parity');
    configuredStopBits = stopBits;
  }

  @override
  Future<void> setDtr(bool asserted) async {
    calls.add('dtr:$asserted');
  }

  @override
  Future<void> setRts(bool asserted) async {
    calls.add('rts:$asserted');
  }

  @override
  Future<void> write(Uint8List bytes) async {
    written = Uint8List.fromList(bytes);
    if (bytes.length == 5 && bytes[2] == 0xc0) {
      final signature = <int>[
        0x10, 0x7f, 0x04, 0xdc, 0xfd, 0xfd, 0xff, 0x3f, 0x00,
        ...'D78F1201  '.codeUnits,
        0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0xff, 0xff,
      ];
      final checksum =
          (-(signature.length + signature.fold<int>(0, (a, b) => a + b))) & 0xff;
      final signatureFrame = Uint8List.fromList([
        0x02, signature.length, ...signature, checksum, 0x03,
      ]);
      scheduleMicrotask(() {
        controller.add(Uint8List.fromList([0x02, 0x01, 0x06, 0xf9, 0x03]));
        controller.add(signatureFrame);
      });
    }
  }

  Future<void> dispose() => controller.close();
}

void main() {
  group('RenesasUsbSerialTransport', () {
    late FakeUsbDriver driver;
    late RenesasUsbSerialTransport transport;

    setUp(() {
      driver = FakeUsbDriver();
      transport = RenesasUsbSerialTransport(
        driver: driver,
        lineProfile: const UsbTool0LineProfile(
          transmitDtr: true,
          transmitRts: false,
          receiveDtr: false,
          receiveRts: true,
        ),
      );
    });

    tearDown(() async {
      await transport.close();
      await driver.dispose();
    });

    test('applies the documented transmit and receive UART framing', () async {
      await transport.transmitMode();
      expect(driver.configuredStopBits,
          Renesas78k0rProtocol.programmerToTargetStopBits);
      expect(driver.calls, contains('dtr:true'));
      expect(driver.calls, contains('rts:false'));

      await transport.receiveMode();
      expect(driver.configuredStopBits,
          Renesas78k0rProtocol.targetToProgrammerStopBits);
      expect(driver.calls, contains('dtr:false'));
      expect(driver.calls, contains('rts:true'));
    });

    test('applies a changed UART baud rate on the next direction switch', () async {
      transport.updateBaudRate(19200);
      await transport.transmitMode();
      expect(driver.calls, contains('configure:19200:8:2:0'));
    });

    test('reassembles a response split across USB stream events', () async {
      final pending = transport.readResponseBytes();
      driver.controller.add(Uint8List.fromList([0x02, 0x01]));
      driver.controller.add(Uint8List.fromList([0x06, 0xf9, 0x03]));

      final frame = await pending;
      expect(frame, [0x02, 0x01, 0x06, 0xf9, 0x03]);
      expect(Renesas78k0rProtocol.decodeResponseFrame(frame).status, 0x06);
    });

    test('rejects a corrupted response frame', () async {
      final pending = transport.readResponseBytes();
      driver.controller.add(Uint8List.fromList([0x02, 0x01, 0x06, 0xf8, 0x03]));
      await expectLater(pending, throwsFormatException);
    });


    test('runs the read-only silicon-signature transaction over USB serial', () async {
      final session = RenesasProtocolSession(
        channel: RenesasUsbWireChannel(transport),
        timing: const RenesasSessionTiming(
          interFrame: Duration.zero,
          commandTimeout: Duration(seconds: 1),
          dataTimeout: Duration(seconds: 1),
        ),
      );

      final signature = await session.readSiliconSignature();

      expect(signature.length, 27);
      expect(String.fromCharCodes(signature.sublist(9, 19)).trim(), 'D78F1201');
      expect(driver.written, Renesas78k0rProtocol.siliconSignatureFrame());
    });

    test('rejects an unbounded USB input burst instead of growing memory', () async {
      final limited = RenesasUsbSerialTransport(
        driver: driver,
        lineProfile: const UsbTool0LineProfile(
          transmitDtr: false,
          transmitRts: false,
          receiveDtr: false,
          receiveRts: false,
        ),
        maxBufferedBytes: 260,
      );
      driver.controller.add(Uint8List(261));
      await expectLater(limited.readExact(1), throwsStateError);
      await limited.close();
    });

    test('reports that USB plugin does not support hardware BREAK', () {
      expect(transport.supportsHardwareBreak, isFalse);
    });
  });
}
