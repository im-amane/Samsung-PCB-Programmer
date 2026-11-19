import 'dart:typed_data';

import 'renesas_78k0r_protocol.dart';
import 'renesas_protocol_session.dart';
import 'renesas_serial_transport.dart';

/// Adapter-specific direction control for the physical single-wire TOOL0 bus.
/// These callbacks must be implemented from the verified Samsung adapter
/// schematic/pinout. No GPIO or DTR/RTS polarity is assumed here.
class RenesasSerialWireChannel implements RenesasWireChannel {
  RenesasSerialWireChannel({
    required this.transport,
    required this.setTransmitDirection,
    required this.setReceiveDirection,
    this.baudRate = Renesas78k0rProtocol.initialBaudRate,
    this.timeoutMs = 1500,
  });

  final RenesasSerialTransport transport;
  final Future<void> Function() setTransmitDirection;
  final Future<void> Function() setReceiveDirection;
  final int baudRate;
  final int timeoutMs;

  @override
  Future<void> transmitMode() async {
    await setTransmitDirection();
    transport.configureProgrammerTransmit(baudRate: baudRate);
  }

  @override
  Future<void> receiveMode() async {
    await setReceiveDirection();
    transport.configureTargetReceive(baudRate: baudRate);
  }

  @override
  Future<void> write(Uint8List bytes) async {
    transport.writeAll(bytes, timeoutMs: timeoutMs);
  }

  @override
  Future<Uint8List> readFrame(Duration timeout) async {
    final timeoutValue = timeout.inMilliseconds;
    if (timeoutValue <= 0) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    return transport
        .readResponseFrame(timeoutMs: timeoutValue)
        .data
        .letBytes();
  }
}

extension on Uint8List {
  Uint8List letBytes() => this;
}
