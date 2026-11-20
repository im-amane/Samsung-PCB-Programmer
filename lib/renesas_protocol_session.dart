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
  Future<Uint8List> readRawBytes(int count, Duration timeout);
}

/// Timing values are explicit because the Samsung adapter's timing profile
/// has not yet been recovered. No undocumented defaults are assumed.
class RenesasSessionTiming {
  const RenesasSessionTiming({
    required this.interFrame,
    required this.commandTimeout,
    required this.dataTimeout,
  });

  /// Minimum wait between ordinary command/data transactions. For the
  /// 78K0R/Ix3 profile, 100 us covers the documented 83.8 us verify-data
  /// setup minimum; target-specific maximum windows still need commissioning.
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

enum RenesasProgramStage {
  erase,
  programCommand,
  programData,
  internalVerify,
  verifyCommand,
  verifyData,
  complete,
}

class RenesasProgramProgress {
  const RenesasProgramProgress({
    required this.stage,
    required this.completedFrames,
    required this.totalFrames,
  });

  final RenesasProgramStage stage;
  final int completedFrames;
  final int totalFrames;

  double get fraction =>
      totalFrames == 0 ? 1.0 : (completedFrames / totalFrames).clamp(0, 1).toDouble();
}

/// Executes documented 78K0R command/data transactions after the target has
/// already been placed in UART flash-programming mode by a verified adapter.
class RenesasProtocolSession {
  RenesasProtocolSession({
    required this.channel,
    required this.timing,
    this.allowDestructiveOperations = false,
  }) {
    timing.validate();
  }

  static const readyPulseTimeout = Duration(seconds: 5);

  final RenesasWireChannel channel;
  final RenesasSessionTiming timing;

  /// A second, library-level interlock. UI state alone must never authorize
  /// a destructive flash operation. Defaults to false for every caller.
  final bool allowDestructiveOperations;

  Future<RenesasResponseFrame> _exchangeCommand(
    Uint8List command, {
    String operation = 'command',
  }) async {
    await Future<void>.delayed(timing.interFrame);
    try {
      await channel.transmitMode();
      await channel.write(command);
      await channel.receiveMode();
      final response = Renesas78k0rProtocol.decodeResponseFrame(
        await channel.readFrame(timing.commandTimeout),
      );
      Renesas78k0rProtocol.requireAck(response, operation: operation);
      return response;
    } catch (_) {
      // Never leave a shared half-duplex line in transmit mode after failure.
      try { await channel.receiveMode(); } catch (_) {}
      rethrow;
    }
  }

  Future<void> _exchangeData(
    Uint8List frame, {
    required String operation,
  }) async {
    await Future<void>.delayed(timing.interFrame);
    try {
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
    } catch (_) {
      try { await channel.receiveMode(); } catch (_) {}
      rethrow;
    }
  }

  /// Synchronizes the TOOL0 UART after the target's READY pulse is present.
  ///
  /// Renesas U19486EJ1V0AN specifies a READY 00H pulse from target to
  /// programmer, two 00H synchronization bytes from programmer to target,
  /// then the Reset command/status exchange at 9600 bps. The app allows five
  /// seconds for the operator to trigger manual boot entry; the MCU's own
  /// READY pulse timing after RESET release remains device-controlled.
  Future<void> synchronize() async {
    await channel.receiveMode();
    final ready = await channel.readRawBytes(1, readyPulseTimeout);
    if (ready.length != 1 || ready.single != 0x00) {
      final value = ready.isEmpty
          ? 'no byte'
          : '0x${ready.first.toRadixString(16).padLeft(2, '0')}';
      throw StateError('Expected Renesas READY pulse 0x00, received $value.');
    }
    // U19486EJ1V0AN §4.4 specifies two separate 00H low-level outputs:
    // tCOM before the first, t12 between them, then receive direction and
    // t2C before the Reset command. Combining the bytes into one write skips
    // required timing and direction transitions.
    await Future<void>.delayed(const Duration(microseconds: 14)); // tCOM >= 13.2 us
    await channel.transmitMode();
    await channel.write(Uint8List.fromList([0x00]));
    await Future<void>.delayed(const Duration(microseconds: 111)); // t12 >= 110.6 us
    await channel.write(Uint8List.fromList([0x00]));
    await channel.receiveMode();
    await Future<void>.delayed(const Duration(microseconds: 609)); // t2C >= 608.1 us
    // Renesas §4.4 allows up to 16 Reset-command attempts when the
    // target returns a non-ACK status. A receive timeout is not retried:
    // the manual requires a fresh hardware reset and programming-mode entry.
    StateError? lastStatusError;
    for (var attempt = 0; attempt < 16; attempt++) {
      try {
        await _exchangeCommand(
          Renesas78k0rProtocol.resetFrame(),
          operation: 'reset synchronization',
        );
        return;
      } on StateError catch (error) {
        lastStatusError = error;
        if (attempt == 15) rethrow;
        await Future<void>.delayed(const Duration(microseconds: 609)); // t2C
      }
    }
    throw lastStatusError ?? StateError('Reset synchronization failed.');
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
    void Function(RenesasProgramProgress progress)? onProgress,
  }) async {
    if (!allowDestructiveOperations) {
      throw StateError(
        'Destructive programming is disabled until hardware commissioning is explicitly enabled.',
      );
    }
    if (!confirmDestructiveErase) {
      throw StateError('Chip erase was not explicitly confirmed.');
    }

    final totalFrames = 4 + plan.programDataFrames.length +
        plan.verifyDataFrames.length;
    var completedFrames = 0;
    void report(RenesasProgramStage stage) {
      onProgress?.call(RenesasProgramProgress(
        stage: stage,
        completedFrames: completedFrames,
        totalFrames: totalFrames,
      ));
    }

    report(RenesasProgramStage.erase);
    await _exchangeCommand(plan.eraseFrame, operation: 'chip erase');
    completedFrames++;
    report(RenesasProgramStage.erase);
    report(RenesasProgramStage.programCommand);
    await _exchangeCommand(
      plan.programCommandFrame,
      operation: 'programming command',
    );
    completedFrames++;
    report(RenesasProgramStage.programCommand);
    for (var i = 0; i < plan.programDataFrames.length; i++) {
      await _exchangeData(
        plan.programDataFrames[i],
        operation: 'program data frame ${i + 1}',
      );
      completedFrames++;
      report(RenesasProgramStage.programData);
    }

    // Renesas specifies one additional status frame after the final write
    // data frame. This reports the MCU's automatic internal-verify result.
    report(RenesasProgramStage.internalVerify);
    final internalVerify = Renesas78k0rProtocol.decodeResponseFrame(
      await channel.readFrame(timing.commandTimeout),
    );
    Renesas78k0rProtocol.requireAck(
      internalVerify,
      operation: 'program internal verify',
    );
    completedFrames++;
    report(RenesasProgramStage.internalVerify);

    report(RenesasProgramStage.verifyCommand);
    await _exchangeCommand(
      plan.verifyCommandFrame,
      operation: 'verify command',
    );
    completedFrames++;
    report(RenesasProgramStage.verifyCommand);
    for (var i = 0; i < plan.verifyDataFrames.length; i++) {
      await _exchangeData(
        plan.verifyDataFrames[i],
        operation: 'verify data frame ${i + 1}',
      );
      completedFrames++;
      report(RenesasProgramStage.verifyData);
    }
    report(RenesasProgramStage.complete);
  }
}
