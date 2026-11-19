import 'dart:typed_data';

import 'renesas_78k0r_protocol.dart';
import 'renesas_program_plan.dart';

/// Half-duplex byte channel for a 78K0R TOOL0 UART interface.
///
/// Implementations must provide electrically correct direction switching and
/// must only be enabled after the board-specific wiring and voltage levels
/// have been verified. A plain USB-UART adapter is not automatically a
/// single-wire TOOL0 interface.
abstract interface class RenesasWireChannel {
  Future<void> transmitMode();
  Future<void> receiveMode();
  Future<void> write(Uint8List bytes);
  Future<Uint8List> readFrame(Duration timeout);
}

/// Timing values are explicit because the Samsung adapter's timing profile
/// has not yet been recovered. No undocumented defaults are assumed.
class RenesasSessionTiming {
  const RenesasSessionTiming({
    required this.interFrame,
    required this.commandTimeout,
    required this.dataTimeout,
  });

  final Duration interFrame;
  final Duration commandTimeout;
  final Duration dataTimeout;

  void validate() {
    if (interFrame.isNegative ||
        commandTimeout <= Duration.zero ||
        dataTimeout <= Duration.zero) {
      throw ArgumentError('Protocol timing values must be non-negative and timeouts positive.');
    }
  }
}

/// Executes documented 78K0R command/data transactions after the target has
/// already been placed in UART flash-programming mode by a verified adapter.
class RenesasProtocolSession {
  RenesasProtocolSession({
    required this.channel,
    required this.timing,
  }) {
    timing.validate();
  }

  final RenesasWireChannel channel;
  final RenesasSessionTiming timing;

  Future<RenesasResponseFrame> _exchangeCommand(
    Uint8List command, {
    String operation = 'command',
  }) async {
    await Future<void>.delayed(timing.interFrame);
    await channel.transmitMode();
    await channel.write(command);
    await channel.receiveMode();
    final response = Renesas78k0rProtocol.decodeResponseFrame(
      await channel.readFrame(timing.commandTimeout),
    );
    Renesas78k0rProtocol.requireAck(response, operation: operation);
    return response;
  }

  Future<void> _exchangeData(
    Uint8List frame, {
    required String operation,
  }) async {
    await Future<void>.delayed(timing.interFrame);
    await channel.transmitMode();
    await channel.write(frame);
    await channel.receiveMode();
    final response = Renesas78k0rProtocol.decodeResponseFrame(
      await channel.readFrame(timing.dataTimeout),
    );
    Renesas78k0rProtocol.requireStatuses(
      response,
      expectedCount: 2,
      operation: operation,
    );
  }

  /// Reads the silicon signature only. Target must already be in programming
  /// mode and the channel must already be configured for the documented UART.
  Future<Uint8List> readSiliconSignature() async {
    await _exchangeCommand(
      Renesas78k0rProtocol.siliconSignatureFrame(),
      operation: 'silicon signature',
    );
    final frame = await channel.readFrame(timing.dataTimeout);
    return Renesas78k0rProtocol.decodeSiliconSignatureFrame(frame).raw;
  }

  /// Performs chip erase, write and verify. This is intentionally not exposed
  /// in the UI until Samsung's six-wire adapter pinout, power sequencing,
  /// TOOL0 direction switching and reset/FLMD0 timings are verified.
  Future<void> program({
    required RenesasProgramPlan plan,
    required bool confirmDestructiveErase,
  }) async {
    if (!confirmDestructiveErase) {
      throw StateError('Chip erase was not explicitly confirmed.');
    }

    await _exchangeCommand(plan.eraseFrame, operation: 'chip erase');
    await _exchangeCommand(
      plan.programCommandFrame,
      operation: 'programming command',
    );
    for (var i = 0; i < plan.programDataFrames.length; i++) {
      await _exchangeData(
        plan.programDataFrames[i],
        operation: 'program data frame ${i + 1}',
      );
    }

    // Renesas specifies one additional status frame after the final write
    // data frame. This reports the MCU's automatic internal-verify result.
    final internalVerify = Renesas78k0rProtocol.decodeResponseFrame(
      await channel.readFrame(timing.commandTimeout),
    );
    Renesas78k0rProtocol.requireAck(
      internalVerify,
      operation: 'program internal verify',
    );

    await _exchangeCommand(
      plan.verifyCommandFrame,
      operation: 'verify command',
    );
    for (var i = 0; i < plan.verifyDataFrames.length; i++) {
      await _exchangeData(
        plan.verifyDataFrames[i],
        operation: 'verify data frame ${i + 1}',
      );
    }
  }
}
