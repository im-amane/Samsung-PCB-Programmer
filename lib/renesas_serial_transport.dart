import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'renesas_78k0r_protocol.dart';

/// Low-level serial adapter for the Renesas 78K0R single-wire TOOL0 link.
///
/// This class exposes the documented UART framing and native BREAK,
/// DTR and RTS controls found in the original Samsung Swap APK. It does not
/// decide pin wiring, pulse durations, power sequencing, or when to flash.
class RenesasSerialTransport {
  RenesasSerialTransport(this.port);

  final SerialPort port;

  bool get isOpen => port.isOpen;

  void configureProgrammerTransmit({int? baudRate}) {
    _configure(
      baudRate: baudRate ?? Renesas78k0rProtocol.initialBaudRate,
      stopBits: Renesas78k0rProtocol.programmerToTargetStopBits,
    );
  }

  void configureTargetReceive({int? baudRate}) {
    _configure(
      baudRate: baudRate ?? Renesas78k0rProtocol.initialBaudRate,
      stopBits: Renesas78k0rProtocol.targetToProgrammerStopBits,
    );
  }

  void _configure({required int baudRate, required int stopBits}) {
    _requireOpen();
    final config = SerialPortConfig();
    try {
      config
        ..baudRate = baudRate
        ..bits = Renesas78k0rProtocol.dataBits
        ..parity = SerialPortParity.none
        ..stopBits = stopBits;
      port.config = config;
    } finally {
      config.dispose();
    }
  }

  void setDtr(bool asserted) {
    _requireOpen();
    final config = SerialPortConfig();
    try {
      config.dtr = asserted ? SerialPortDtr.on : SerialPortDtr.off;
      port.config = config;
    } finally {
      config.dispose();
    }
  }

  void setRts(bool asserted) {
    _requireOpen();
    final config = SerialPortConfig();
    try {
      config.rts = asserted ? SerialPortRts.on : SerialPortRts.off;
      port.config = config;
    } finally {
      config.dispose();
    }
  }

  bool startBreak() {
    _requireOpen();
    return port.startBreak();
  }

  bool endBreak() {
    _requireOpen();
    return port.endBreak();
  }

  Future<void> pulseBreak(Duration duration) async {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive.');
    }
    if (!startBreak()) throw StateError('Could not assert serial BREAK.');
    try {
      await Future<void>.delayed(duration);
    } finally {
      if (!endBreak()) throw StateError('Could not release serial BREAK.');
    }
  }

  void writeAll(Uint8List bytes, {int timeoutMs = 1000}) {
    _requireOpen();
    var offset = 0;
    while (offset < bytes.length) {
      final written = port.write(
        Uint8List.sublistView(bytes, offset),
        timeout: timeoutMs,
      );
      if (written <= 0) {
        throw StateError('Serial write stopped after ${offset}/${bytes.length} bytes.');
      }
      offset += written;
    }
    port.drain();
  }

  Uint8List readExact(int count, {int timeoutMs = 1000}) {
    _requireOpen();
    if (count < 0) throw RangeError.value(count, 'count');
    if (count == 0) return Uint8List(0);
    final stopwatch = Stopwatch()..start();
    final builder = BytesBuilder(copy: false);
    var received = 0;
    while (received < count) {
      final remainingMs = timeoutMs - stopwatch.elapsedMilliseconds;
      if (remainingMs <= 0) {
        throw TimeoutException('Serial read timed out after ${received}/${count} bytes.');
      }
      final chunk = port.read(count - received, timeout: remainingMs);
      if (chunk.isNotEmpty) {
        builder.add(chunk);
        received += chunk.length;
      }
    }
    return builder.takeBytes();
  }

  void close() {
    if (port.isOpen) port.close();
    port.dispose();
  }

  void _requireOpen() {
    if (!port.isOpen) throw StateError('Serial port is not open.');
  }
}
