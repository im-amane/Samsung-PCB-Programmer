import 'dart:async';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import 'renesas_78k0r_protocol.dart';
import 'renesas_protocol_session.dart';

/// Small interface around the Android USB serial plugin so the transport can
/// be tested without a physical USB adapter.
abstract interface class RenesasUsbPortDriver {
  Stream<Uint8List>? get inputStream;

  Future<void> configure({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required int parity,
  });

  Future<void> setDtr(bool asserted);
  Future<void> setRts(bool asserted);
  Future<void> write(Uint8List bytes);
}

/// Production adapter for the Android usb_serial plugin.
class AndroidUsbSerialPortDriver implements RenesasUsbPortDriver {
  AndroidUsbSerialPortDriver(this.port);

  final UsbPort port;

  @override
  Stream<Uint8List>? get inputStream => port.inputStream;

  @override
  Future<void> configure({
    required int baudRate,
    required int dataBits,
    required int stopBits,
    required int parity,
  }) =>
      port.setPortParameters(baudRate, dataBits, stopBits, parity);

  @override
  Future<void> setDtr(bool asserted) => port.setDTR(asserted);

  @override
  Future<void> setRts(bool asserted) => port.setRTS(asserted);

  @override
  Future<void> write(Uint8List bytes) => port.write(bytes);
}

/// Explicit USB control-line states for a particular adapter wiring.
///
/// These values are deliberately required. DTR/RTS polarity and their
/// connection to a single-wire TOOL0 transceiver are adapter-specific.
class UsbTool0LineProfile {
  const UsbTool0LineProfile({
    required this.transmitDtr,
    required this.transmitRts,
    required this.receiveDtr,
    required this.receiveRts,
  });

  final bool transmitDtr;
  final bool transmitRts;
  final bool receiveDtr;
  final bool receiveRts;
}

/// Android USB serial transport for the Renesas 78K0R UART protocol.
///
/// The usb_serial plugin exposes DTR and RTS but does not expose a UART BREAK
/// control. This transport therefore does not pretend to support BREAK-based
/// boot entry. Target reset/FLMD0 sequencing must be provided by a separately
/// verified adapter/controller before any programming operation is enabled.
class RenesasUsbSerialTransport {
  RenesasUsbSerialTransport({
    required this.driver,
    required this.lineProfile,
    this.baudRate = Renesas78k0rProtocol.initialBaudRate,
    this.timeout = const Duration(milliseconds: 1500),
  }) {
    if (baudRate <= 0) throw ArgumentError.value(baudRate, 'baudRate');
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
    final stream = driver.inputStream;
    if (stream == null) {
      throw StateError('USB serial input stream is unavailable.');
    }
    _subscription = stream.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
    );
  }

  final RenesasUsbPortDriver driver;
  UsbTool0LineProfile lineProfile;

  void updateLineProfile(UsbTool0LineProfile profile) {
    lineProfile = profile;
  }
  final int baudRate;
  final Duration timeout;

  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _received = <int>[];
  Completer<void>? _dataChanged;
  Object? _streamError;
  bool _closed = false;

  bool get supportsHardwareBreak => false;

  Future<void> transmitMode() async {
    _ensureOpen();
    await driver.configure(
      baudRate: baudRate,
      dataBits: Renesas78k0rProtocol.dataBits,
      stopBits: Renesas78k0rProtocol.programmerToTargetStopBits,
      parity: UsbPort.PARITY_NONE,
    );
    await driver.setDtr(lineProfile.transmitDtr);
    await driver.setRts(lineProfile.transmitRts);
  }

  Future<void> receiveMode() async {
    _ensureOpen();
    await driver.configure(
      baudRate: baudRate,
      dataBits: Renesas78k0rProtocol.dataBits,
      stopBits: Renesas78k0rProtocol.targetToProgrammerStopBits,
      parity: UsbPort.PARITY_NONE,
    );
    await driver.setDtr(lineProfile.receiveDtr);
    await driver.setRts(lineProfile.receiveRts);
  }

  Future<void> writeAll(Uint8List bytes) async {
    _ensureOpen();
    if (bytes.isEmpty) return;
    await driver.write(bytes);
  }

  Future<Uint8List> readExact(int count, {Duration? readTimeout}) async {
    _ensureOpen();
    if (count < 0) throw RangeError.value(count, 'count');
    if (count == 0) return Uint8List(0);

    final deadline = DateTime.now().add(readTimeout ?? timeout);
    while (_received.length < count) {
      _ensureOpen();
      final error = _streamError;
      if (error != null) {
        throw StateError('USB serial input stream failed: $error');
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'USB serial read timed out after ${_received.length}/$count bytes.',
        );
      }
      final waiter = _dataChanged ??= Completer<void>();
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        throw TimeoutException(
          'USB serial read timed out after ${_received.length}/$count bytes.',
        );
      }
    }

    final result = Uint8List.fromList(_received.take(count).toList());
    _received.removeRange(0, count);
    return result;
  }

  Future<Uint8List> readResponseBytes({Duration? readTimeout}) async {
    final header = await readExact(2, readTimeout: readTimeout);
    if (header[0] != Renesas78k0rProtocol.stx) {
      throw FormatException(
        'Expected response STX 0x02, received 0x${header[0].toRadixString(16).padLeft(2, '0')}.',
      );
    }
    final payloadLength = header[1] == 0 ? 256 : header[1];
    final tail = await readExact(payloadLength + 2, readTimeout: readTimeout);
    final frame = Uint8List.fromList(<int>[...header, ...tail]);
    Renesas78k0rProtocol.decodeResponseFrame(frame);
    return frame;
  }

  void _onData(Uint8List data) {
    if (_closed || data.isEmpty) return;
    _received.addAll(data);
    final waiter = _dataChanged;
    _dataChanged = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    _streamError = error;
    final waiter = _dataChanged;
    _dataChanged = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _onDone() {
    _streamError ??= StateError('USB serial input stream closed.');
    final waiter = _dataChanged;
    _dataChanged = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    final waiter = _dataChanged;
    _dataChanged = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('USB serial transport is closed.');
  }
}

/// Connects the Android USB serial transport to the Renesas protocol session.
class RenesasUsbWireChannel implements RenesasWireChannel {
  RenesasUsbWireChannel(this.transport);

  final RenesasUsbSerialTransport transport;

  @override
  Future<void> transmitMode() => transport.transmitMode();

  @override
  Future<void> receiveMode() => transport.receiveMode();

  @override
  Future<void> write(Uint8List bytes) => transport.writeAll(bytes);

  @override
  Future<Uint8List> readFrame(Duration timeout) =>
      transport.readResponseBytes(readTimeout: timeout);
}
