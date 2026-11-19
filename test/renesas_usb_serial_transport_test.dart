import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_pcb_programmer/renesas_78k0r_protocol.dart';
import 'package:samsung_pcb_programmer/renesas_usb_serial_transport.dart';

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

    test('reports that USB plugin does not support hardware BREAK', () {
      expect(transport.supportsHardwareBreak, isFalse);
    });
  });
}
