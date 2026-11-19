import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:usb_serial_next/usb_serial_next.dart' as usb_next;
import 'package:flutter_libserialport/flutter_libserialport.dart' as libserial;

import 'firmware_validator.dart';
import 'srecord_image.dart';
import 'renesas_program_plan.dart';
import 'renesas_protocol_session.dart';
import 'renesas_serial_transport.dart';
import 'renesas_usb_serial_transport.dart';

void main() => runApp(const SamsungPcbProgrammerApp());

class SamsungPcbProgrammerApp extends StatelessWidget {
  const SamsungPcbProgrammerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Samsung Swap',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF176B5B),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF101816),
        ),
        home: const DashboardPage(),
      );
}

class BoardProfile {
  const BoardProfile(this.name, this.board, this.firmware, this.revision, this.sha256);
  final String name;
  final String board;
  final String firmware;
  final String revision;
  final String sha256;
}

const boardProfiles = <BoardProfile>[
  BoardProfile('00755A · RT36 Inverter', 'DA41-00755A', '', 'RT36', ''),
  BoardProfile('0459C · Double Door', 'DA41-00814A', 'DA41-00814A.mot', '0459C', '674a4e4c632ee167849269e05341d133243a310ab8661c712cbaa179f813e5dc'),
  BoardProfile('0459G · Double Door', 'DA41-00814D', 'DA41-00814D_0459G.mot', '0459G', 'd6e23a11b200a61ba5943a760bc9b2fdd0898842b13fad9290a554d5ed128860'),
  BoardProfile('0459M · Single Door', 'DA41-00814D', 'DA41-00814D_0459M.bin', '0459M', 'ee709d6f843c429f726953ad7a1550819d8e43bf6d9e6604fd75cbd72d317499'),
  BoardProfile('00838A · French Door', 'DA41-00838A', '', 'French Door', ''),
];

class FirmwareInfo {
  const FirmwareInfo({
    required this.name,
    required this.size,
    required this.sha256,
    required this.validSRecord,
    required this.records,
    required this.dataBytes,
    required this.startAddress,
    required this.endAddress,
    required this.profileMatches,
    required this.message,
    required this.preparedBlocks,
    required this.protocolPlanReady,
  });
  final String name;
  final int size;
  final String sha256;
  final bool validSRecord;
  final int records;
  final int dataBytes;
  final int? startAddress;
  final int? endAddress;
  final bool profileMatches;
  final String message;
  final int preparedBlocks;
  final bool protocolPlanReady;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int selectedIndex = 1;
  List<usb_next.UsbDevice> devices = [];
  StreamSubscription<usb_next.UsbDeviceEvent>? usbEventSubscription;
  usb_next.UsbSerialPort? port;
  RenesasSerialTransport? nativeTransport;
  RenesasUsbSerialTransport? usbTransport;
  bool transmitDtr = false;
  bool transmitRts = false;
  bool receiveDtr = false;
  bool receiveRts = false;
  int usbBaudRate = 9600;
  bool readingSignature = false;
  String signatureMessage = 'Target signature not read.';
  String? signatureDeviceName;
  int? signatureFlashLastAddress;
  Uint8List? firmwareBytes;
  bool programming = false;
  RenesasProgramProgress? programProgress;
  String programMessage = 'Programming locked until firmware and target are verified.';
  String? connectedNativePath;
  List<String> nativePorts = [];
  usb_next.UsbDevice? connectedDevice;
  FirmwareInfo? firmware;
  final Map<String, Uint8List> apkFirmware = {};
  final Map<String, Uint8List> apkImages = {};
  final Map<String, Uint8List> apkAssets = {};
  bool scanning = false;
  bool importingApk = false;
  String connectionMessage = 'Connect a USB-C OTG adapter to detect the interface.';
  String apkMessage = 'Original APK not imported.';

  @override
  void initState() {
    super.initState();
    usbEventSubscription = usb_next.UsbSerial.instance.deviceEvents.listen(
      _handleUsbEvent,
      onError: (Object error) {
        if (mounted) setState(() => connectionMessage = 'USB event listener failed: $error');
      },
    );
    _scanUsb();
    _loadSelectedFirmware();
  }

  @override
  void dispose() {
    usbEventSubscription?.cancel();
    usbTransport?.close();
    port?.close();
    nativeTransport?.close();
    super.dispose();
  }

  void _handleUsbEvent(usb_next.UsbDeviceEvent event) {
    if (event is usb_next.UsbDeviceAttached) {
      _scanUsb();
      return;
    }
    if (event is usb_next.UsbDeviceDetached &&
        event.device.deviceId == connectedDevice?.deviceId) {
      _disconnect();
      if (mounted) {
        setState(() => connectionMessage = 'USB adapter unplugged. Connection closed.');
      }
    }
  }

  Future<void> _scanUsb() async {
    setState(() => scanning = true);
    try {
      final found = await usb_next.UsbSerial.instance.listDevices();
      var nativeFound = <String>[];
      try {
        nativeFound = libserial.SerialPort.availablePorts;
      } catch (_) {
        // Native enumeration may be unavailable on an emulator or desktop test.
      }
      if (!mounted) return;
      setState(() {
        devices = found;
        nativePorts = nativeFound;
        scanning = false;
        connectionMessage = found.isEmpty && nativeFound.isEmpty
            ? 'No USB serial interface detected.'
            : '${found.length} Android USB device(s), ${nativeFound.length} native serial port(s) detected.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        scanning = false;
        connectionMessage = 'USB scan failed: $e';
      });
    }
  }

  Future<void> _connect(usb_next.UsbDevice device) async {
    if (programming) return;
    usb_next.UsbSerialPort? candidate;
    try {
      await usbTransport?.close();
      usbTransport = null;
      await port?.close();
      port = null;
      connectedDevice = null;
      final oldNative = nativeTransport;
      nativeTransport = null;
      connectedNativePath = null;
      oldNative?.close();

      candidate = await usb_next.UsbSerial.instance.open(
        device,
        config: const usb_next.SerialConfig(
          baudRate: 9600,
          dataBits: 8,
          stopBits: usb_next.StopBits.one,
          parity: usb_next.Parity.none,
        ),
      );
      final openedPort = candidate;
      // Opening uses 9600 8N1 with DTR/RTS left unchanged. The Renesas
      // session switches to 8N2 before the first transmit frame.
      if (!mounted) {
        await openedPort.close();
        candidate = null;
        return;
      }
      final usbLink = RenesasUsbSerialTransport(
        driver: AndroidUsbSerialPortDriver(openedPort),
        lineProfile: _usbLineProfile,
        baudRate: usbBaudRate,
      );
      setState(() {
        port = openedPort;
        usbTransport = usbLink;
        connectedDevice = device;
        signatureDeviceName = null;
        signatureFlashLastAddress = null;
        signatureMessage = 'New USB connection. Read target signature again.';
        connectionMessage =
            'USB serial port opened at 9600 8N1. DTR/RTS left unchanged; no MCU command sent.';
      });
      candidate = null; // ownership transferred to DashboardPage
    } catch (e) {
      try {
        await candidate?.close();
      } catch (_) {
        // Preserve the original connection error.
      }
      if (mounted) {
        setState(() {
          port = null;
          usbTransport = null;
          connectedDevice = null;
          connectionMessage = 'USB connection failed: $e';
        });
      }
    }
  }

  Future<void> _connectNative(String path) async {
    if (programming) return;
    libserial.SerialPort? candidate;
    try {
      await usbTransport?.close();
      usbTransport = null;
      await port?.close();
      nativeTransport?.close();
      nativeTransport = null;
      candidate = libserial.SerialPort(path);
      if (!candidate.openReadWrite()) {
        candidate.dispose();
        if (mounted) setState(() => connectionMessage = 'Native serial port could not be opened: $path');
        return;
      }
      if (!mounted) {
        candidate.close();
        candidate.dispose();
        return;
      }
      setState(() {
        port = null;
        connectedDevice = null;
        nativeTransport = RenesasSerialTransport(candidate!);
        connectedNativePath = path;
        signatureDeviceName = null;
        signatureFlashLastAddress = null;
        signatureMessage = 'Native serial connection is not enabled for flash programming.';
        connectionMessage = 'Native libserialport opened $path. No baud rate, DTR/RTS, break pulse, or MCU data has been changed/sent.';
      });
    } catch (e) {
      candidate?.dispose();
      if (mounted) setState(() => connectionMessage = 'Native serial open failed: $e');
    }
  }

  Future<void> _disconnect() async {
    if (programming) {
      _message('Disconnect is locked while flash programming is running.');
      return;
    }
    final current = port;
    final usb = usbTransport;
    final native = nativeTransport;
    setState(() {
      port = null;
      usbTransport = null;
      connectedDevice = null;
      nativeTransport = null;
      connectedNativePath = null;
      signatureDeviceName = null;
      signatureFlashLastAddress = null;
      signatureMessage = 'Target signature cleared after disconnect.';
      connectionMessage = 'Serial interface disconnected.';
    });
    await usb?.close();
    await current?.close();
    native?.close();
  }

  Future<void> _readSiliconSignature() async {
    final transport = usbTransport;
    if (transport == null) {
      setState(() => signatureMessage = 'Connect an Android USB serial adapter first.');
      return;
    }
    setState(() {
      readingSignature = true;
      signatureDeviceName = null;
      signatureFlashLastAddress = null;
      signatureMessage = 'Waiting for READY pulse. Trigger the target boot-entry/reset sequence now...';
      programMessage = 'Read a fresh target signature before programming.';
    });
    try {
      final session = RenesasProtocolSession(
        channel: RenesasUsbWireChannel(transport),
        timing: const RenesasSessionTiming(
          interFrame: Duration.zero,
          commandTimeout: Duration(seconds: 2),
          dataTimeout: Duration(seconds: 2),
        ),
      );
      await session.synchronize();
      final signature = await session.readSiliconSignature();
      final deviceName = String.fromCharCodes(signature.sublist(9, 19)).trim();
      final flashLastAddress =
          signature[6] | (signature[7] << 8) | (signature[8] << 16);
      final hex = signature
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(' ')
          .toUpperCase();
      if (!mounted) return;
      setState(() {
        readingSignature = false;
        signatureDeviceName = deviceName;
        signatureFlashLastAddress = flashLastAddress;
        signatureMessage =
            'Read-only signature: $deviceName · flash end 0x${flashLastAddress.toRadixString(16).toUpperCase()} · ${signature.length} bytes\\n$hex';
        programMessage = _programReadinessMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        readingSignature = false;
        signatureDeviceName = null;
        signatureFlashLastAddress = null;
        signatureMessage = 'Signature/synchronization failed: $e';
        programMessage = 'Programming locked because target identity was not verified.';
      });
    }
  }


  Future<void> _importApk() async {
    if (programming) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      _message('Could not read the selected APK.');
      return;
    }
    setState(() => importingApk = true);
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final extracted = <String, Uint8List>{};
      final extractedImages = <String, Uint8List>{};
      final allAssets = <String, Uint8List>{};
      const flutterAssetsPrefix = 'assets/flutter_assets/';
      const supportedImages = <String>{
        'app_logo.jpg',
        'samsung_da41_00814d.jpg',
        'samsung_da41_00814d_h.jpg',
        'samsung_da41_00863a.jpg',
      };
      for (final entry in archive) {
        if (!entry.isFile || !entry.name.startsWith(flutterAssetsPrefix)) continue;
        final name = entry.name;
        final content = entry.content;
        if (content is! List<int>) continue;
        final relativeName = name.substring(flutterAssetsPrefix.length);
        final bytes = Uint8List.fromList(content);
        allAssets[relativeName] = bytes;
        final baseName = name.split('/').last;
        if (name.contains('assets/flutter_assets/assets/firmwares/') &&
            boardProfiles.any((p) => p.firmware == baseName)) {
          extracted[baseName] = bytes;
        } else if (name.contains('assets/flutter_assets/assets/images/') &&
            supportedImages.contains(baseName)) {
          extractedImages[baseName] = bytes;
        }
      }
      if (extracted.isEmpty) {
        throw const FormatException('No supported DA41 firmware assets found in this APK.');
      }
      if (!mounted) return;
      setState(() {
        apkFirmware
          ..clear()
          ..addAll(extracted);
        apkImages
          ..clear()
          ..addAll(extractedImages);
        apkAssets
          ..clear()
          ..addAll(allAssets);
        importingApk = false;
        final totalBytes = allAssets.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
        apkMessage = '${allAssets.length} original Flutter assets (${(totalBytes / 1024).toStringAsFixed(1)} KB), ${extracted.length} firmware file(s), and ${extractedImages.length} board/application image(s) extracted in memory. Nothing was uploaded.';
      });
      _loadApkFirmware();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        importingApk = false;
        apkMessage = 'APK extraction failed: $e';
      });
    }
  }

  Future<void> _exportApkAssets() async {
    if (apkAssets.isEmpty) {
      _message('Import the original Samsung Swap APK first.');
      return;
    }
    try {
      final bundle = Archive();
      for (final asset in apkAssets.entries) {
        bundle.addFile(ArchiveFile(asset.key, asset.value.length, asset.value));
      }
      final encoded = ZipEncoder().encode(bundle);
      if (encoded == null || encoded.isEmpty) {
        throw StateError('Could not create the Flutter asset archive.');
      }
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Export original Samsung Swap Flutter assets',
        fileName: 'samsung_swap_flutter_assets.zip',
        bytes: Uint8List.fromList(encoded),
      );
      if (!mounted) return;
      _message(saved == null
          ? 'Asset export cancelled.'
          : 'Original Flutter assets exported: $saved');
    } catch (e) {
      if (mounted) _message('Asset export failed: $e');
    }
  }

  Future<void> _loadSelectedFirmware() async {
    final profile = boardProfiles[selectedIndex];
    if (profile.firmware.isEmpty) {
      if (mounted) setState(() {
        firmware = null;
        firmwareBytes = null;
        signatureDeviceName = null;
        signatureFlashLastAddress = null;
      });
      return;
    }

    // Prefer the locally imported APK copy when present, otherwise use the
    // verified firmware asset bundled into this independent application.
    final imported = apkFirmware[profile.firmware];
    if (imported != null) {
      _inspectFirmware(profile.firmware, imported);
      return;
    }

    try {
      final data = await rootBundle.load('assets/firmwares/${profile.firmware}');
      final bytes = Uint8List.view(
        data.buffer,
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (!mounted) return;
      _inspectFirmware(profile.firmware, bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        firmware = null;
        firmwareBytes = null;
        signatureDeviceName = null;
        signatureFlashLastAddress = null;
      });
      _message('Bundled firmware could not be loaded: $e');
    }
  }

  void _loadApkFirmware() {
    final profile = boardProfiles[selectedIndex];
    if (profile.firmware.isEmpty) {
      _message('The supplied APK contains no bundled firmware for this board profile.');
      return;
    }
    final bytes = apkFirmware[profile.firmware];
    if (bytes == null) {
      _message('Selected firmware is not present in the imported APK.');
      return;
    }
    _inspectFirmware(profile.firmware, bytes);
  }

  Future<void> _importFirmware() async {
    if (programming) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mot', 'srec', 's19', 's28', 's37', 'bin'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _message('Could not read the selected file.');
      return;
    }
    _inspectFirmware(file.name, bytes);
  }

  bool get _canProgram {
    final info = firmware;
    return !programming &&
        !readingSignature &&
        usbTransport != null &&
        firmwareBytes != null &&
        info != null &&
        info.validSRecord &&
        info.profileMatches &&
        info.protocolPlanReady &&
        (signatureDeviceName ?? '').toUpperCase().contains('78F1201') &&
        signatureFlashLastAddress == 0x3fff;
  }

  String get _programReadinessMessage {
    if (programming) return 'Programming is in progress. Keep USB connected and do not reset or power off.';
    if (usbTransport == null) return 'Connect an Android USB serial adapter first.';
    if (readingSignature) return 'Waiting for target signature.';
    if (signatureDeviceName == null) return 'Read and verify the target silicon signature first.';
    if (!signatureDeviceName!.toUpperCase().contains('78F1201')) {
      return 'Unsupported target MCU: expected uPD78F1201, received $signatureDeviceName.';
    }
    if (signatureFlashLastAddress != 0x3fff) {
      return 'Unsupported flash range: expected 0x0000-0x3FFF (16 KB).';
    }
    final info = firmware;
    if (info == null || firmwareBytes == null) return 'Load a firmware image first.';
    if (!info.validSRecord) return 'Selected firmware is not a valid supported S-record image.';
    if (!info.profileMatches) return 'Firmware filename/hash does not exactly match the selected board profile.';
    if (!info.protocolPlanReady) return 'A complete 16 KB Renesas programming plan is not available for this firmware.';
    return 'Preflight passed. Confirm the physical PCB revision and verified adapter wiring before chip erase.';
  }

  String _programStageLabel(RenesasProgramStage stage) {
    switch (stage) {
      case RenesasProgramStage.erase:
        return 'Erasing target flash...';
      case RenesasProgramStage.programCommand:
        return 'Starting programming command...';
      case RenesasProgramStage.programData:
        return 'Writing firmware data...';
      case RenesasProgramStage.internalVerify:
        return 'Checking MCU internal verify...';
      case RenesasProgramStage.verifyCommand:
        return 'Starting explicit verify...';
      case RenesasProgramStage.verifyData:
        return 'Verifying firmware data...';
      case RenesasProgramStage.complete:
        return 'Programming and verify complete.';
    }
  }

  Future<bool> _confirmProgramming(FirmwareInfo info) async {
    var acknowledged = false;
    final selected = boardProfiles[selectedIndex];
    return await showDialog<bool>(
          context: context,
          barrierDismissible: !programming,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Confirm chip erase and flash'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This operation starts with a full-chip erase. A power loss, disconnect or reset during programming can leave the controller without working firmware.',
                      ),
                      const SizedBox(height: 12),
                      Text('Selected PCB profile: ${selected.name}'),
                      Text('Firmware: ${info.name}'),
                      Text('SHA-256: ${info.sha256}'),
                      Text('Target MCU: ${signatureDeviceName ?? 'unknown'}'),
                      Text('Target flash end: 0x${(signatureFlashLastAddress ?? 0).toRadixString(16).toUpperCase()}'),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: acknowledged,
                        onChanged: (value) =>
                            setDialogState(() => acknowledged = value ?? false),
                        title: const Text(
                          'I checked the physical PCB sticker/revision, firmware compatibility, adapter voltage, and RESET/FLMD0/TOOL0 wiring.',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const Text(
                        'The app does not control target VDD, RESET or FLMD0. The target must already be in flash-programming mode and the cable wiring must be independently verified.',
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: acknowledged
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: const Text('ERASE AND PROGRAM'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Future<void> _programFirmware() async {
    if (!_canProgram) {
      setState(() => programMessage = _programReadinessMessage);
      return;
    }
    final transport = usbTransport!;
    final info = firmware!;
    final bytes = firmwareBytes!;
    final plan = RenesasProgramPlan.fromSRecord(bytes);
    final confirmed = await _confirmProgramming(info);
    if (!confirmed || !mounted) return;

    setState(() {
      programming = true;
      programProgress = null;
      programMessage = 'Starting destructive programming sequence...';
    });

    try {
      final session = RenesasProtocolSession(
        channel: RenesasUsbWireChannel(transport),
        timing: const RenesasSessionTiming(
          interFrame: Duration.zero,
          commandTimeout: Duration(seconds: 10),
          dataTimeout: Duration(seconds: 5),
        ),
      );
      await session.program(
        plan: plan,
        confirmDestructiveErase: true,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            programProgress = progress;
            programMessage = _programStageLabel(progress.stage);
          });
        },
      );
      if (mounted) {
        setState(() {
          programMessage =
              'Programming and verify completed. Target remains in flash mode; no reset or power-off command was sent.';
          signatureDeviceName = null;
          signatureFlashLastAddress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          programMessage =
              'Programming stopped with an error: $e. Flash contents may be incomplete; do not assume the board is operational.';
        });
        signatureDeviceName = null;
        signatureFlashLastAddress = null;
      }
    } finally {
      if (mounted) setState(() => programming = false);
    }
  }

  void _inspectFirmware(String name, Uint8List bytes) {
    final validation = FirmwareValidator.validateSRecords(bytes);
    final digest = FirmwareValidator.sha256Hex(bytes);
    final canonicalDigest = FirmwareValidator.canonicalSRecordSha256Hex(bytes);
    final expected = boardProfiles[selectedIndex];
    final profileMatches = expected.firmware.isNotEmpty &&
        name == expected.firmware && canonicalDigest == expected.sha256;
    final profileMessage = profileMatches
        ? 'Exact filename and canonical S-record SHA-256 match for selected APK profile (line endings normalized).'
        : expected.firmware.isEmpty
            ? 'No bundled firmware or verified hash exists for this board profile.'
            : 'PROFILE MISMATCH: expected ${expected.firmware} with canonical SHA-256 ${expected.sha256}.';
    SRecordImage? parsedImage;
    var preparedBlocks = 0;
    var protocolPlanReady = false;
    var parserMessage = '';
    if (validation.valid) {
      try {
        parsedImage = SRecordImage.parse(bytes);
        preparedBlocks = parsedImage.dataBlocks(blockSize: 256).length;
        if (profileMatches) {
          RenesasProgramPlan.fromSRecord(bytes);
          protocolPlanReady = true;
        }
        parserMessage = ' Memory map parsed; ${preparedBlocks} generic 256-byte data blocks prepared. ${protocolPlanReady ? 'Renesas 16 KB command/data frame plan prepared.' : 'Exact-profile 16 KB protocol plan unavailable.'}';
      } on FormatException catch (e) {
        parserMessage = ' Memory-map preparation failed: ${e.message}';
      }
    }
    setState(() {
      firmwareBytes = Uint8List.fromList(bytes);
      signatureDeviceName = null;
      signatureFlashLastAddress = null;
      programProgress = null;
      programMessage = 'Firmware changed. Read target signature again before programming.';
      firmware = FirmwareInfo(
        name: name,
        size: bytes.length,
        sha256: digest,
        validSRecord: validation.valid && parsedImage != null,
        records: validation.totalRecords,
        dataBytes: validation.dataBytes,
        startAddress: validation.startAddress,
        endAddress: validation.endAddress,
        profileMatches: profileMatches,
        message: '${validation.message} ${parserMessage} ${profileMessage}',
        preparedBlocks: preparedBlocks,
        protocolPlanReady: protocolPlanReady,
      );
    });
  }


  String _formatAddress(int? value) => value == null ? 'unknown' : '0x${value.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final selected = boardProfiles[selectedIndex];
    return Scaffold(
      appBar: AppBar(
        leading: apkImages.containsKey('app_logo.jpg')
            ? Padding(
                padding: const EdgeInsets.all(7),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.memory(apkImages['app_logo.jpg']!, fit: BoxFit.cover),
                ),
              )
            : null,
        title: const Text('Samsung Swap'),
        actions: [
          IconButton(
            tooltip: 'Scan USB',
            onPressed: scanning ? null : _scanUsb,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionCard(
              icon: Icons.memory_rounded,
              title: 'PROGRAMMER STATUS',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(port == null && nativeTransport == null ? 'Not connected' : 'USB / serial connected',
                    style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(connectionMessage, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: scanning ? null : _scanUsb,
                  icon: const Icon(Icons.usb_rounded),
                  label: Text(scanning ? 'Scanning…' : 'Scan USB devices'),
                ),
                if (devices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...devices.map((d) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.usb),
                        title: Text(d.productName ?? d.deviceName ?? 'USB serial device'),
                        subtitle: Text('VID: ${d.vendorId}  ·  PID: ${d.productId}'),
                        trailing: connectedDevice?.deviceId == d.deviceId
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : TextButton(onPressed: () => _connect(d), child: const Text('Connect')),
                      )),
                ],
                if (nativePorts.isNotEmpty) ...[
                  const Divider(height: 20),
                  const Text('Native libserialport interfaces'),
                  ...nativePorts.map((path) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.settings_input_component),
                        title: Text(path),
                        subtitle: Text(connectedNativePath == path ? 'Connected via libserialport' : 'Native serial endpoint'),
                        trailing: connectedNativePath == path
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : TextButton(onPressed: () => _connectNative(path), child: const Text('Open')),
                      )),
                ],
                if (port != null || nativeTransport != null)
                  TextButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Disconnect'),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.tune_rounded,
              title: 'USB TOOL0 ADAPTER PROFILE',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('These settings define the DTR/RTS states the app will request when the protocol transport is explicitly used. They do not identify your cable wiring.'),
                  const SizedBox(height: 8),
                  _lineSwitch('Transmit DTR asserted', transmitDtr, (v) => _setUsbLineProfile(transmitDtr: v)),
                  _lineSwitch('Transmit RTS asserted', transmitRts, (v) => _setUsbLineProfile(transmitRts: v)),
                  _lineSwitch('Receive DTR asserted', receiveDtr, (v) => _setUsbLineProfile(receiveDtr: v)),
                  _lineSwitch('Receive RTS asserted', receiveRts, (v) => _setUsbLineProfile(receiveRts: v)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('UART baud rate'),
                      const SizedBox(width: 16),
                      DropdownButton<int>(
                        value: usbBaudRate,
                        items: const [9600, 19200, 38400, 57600, 115200]
                            .map((rate) => DropdownMenuItem<int>(
                                  value: rate,
                                  child: Text('$rate baud'),
                                ))
                            .toList(),
                        onChanged: readingSignature ? null : (rate) {
                          if (rate != null) _setUsbBaudRate(rate);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('USB serial BREAK control is available when supported by the adapter. RESET/FLMD0 sequencing and board-specific boot entry are still not implemented, so programming remains locked.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (selected.board == 'DA41-00814D' && apkImages.containsKey('samsung_da41_00814d.jpg')) ...[
              _sectionCard(
                icon: Icons.developer_board_rounded,
                title: 'ORIGINAL BOARD IMAGE',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(apkImages['samsung_da41_00814d.jpg']!, fit: BoxFit.contain, width: double.infinity),
                  ),
                  if (apkImages.containsKey('samsung_da41_00814d_h.jpg')) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(apkImages['samsung_da41_00814d_h.jpg']!, fit: BoxFit.contain, width: double.infinity),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 18),
            ],
            const Text('TARGET FIRMWARE PROFILE', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('This selects the firmware profile only. The physical PCB model is not detected automatically; check its sticker and revision before choosing.'),
            const SizedBox(height: 8),
            ...List.generate(boardProfiles.length, (i) {
              final p = boardProfiles[i];
              return Card(
                child: RadioListTile<int>(
                  value: i,
                  groupValue: selectedIndex,
                  onChanged: programming ? null : (v) {
                    setState(() {
                      selectedIndex = v ?? 0;
                      firmware = null;
                      firmwareBytes = null;
                      signatureDeviceName = null;
                      signatureFlashLastAddress = null;
                      programProgress = null;
                      programMessage = 'Board profile changed. Read target signature again.';
                    });
                    _loadSelectedFirmware();
                  },
                  title: Text(p.name),
                  subtitle: Text('${p.board}  ·  Revision ${p.revision}'),
                ),
              );
            }),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.folder_open_rounded,
              title: 'FIRMWARE CATALOGUE',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Selected profile: ${selected.firmware.isEmpty ? 'No firmware bundled in supplied APK' : selected.firmware}'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (importingApk || programming) ? null : _importApk,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(importingApk ? 'Reading APK…' : 'Import original Samsung Swap APK'),
                ),
                Text(apkMessage, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (apkAssets.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Original Flutter asset files (${apkAssets.length})'),
                    children: apkAssets.entries.map((asset) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(asset.key, style: const TextStyle(fontSize: 12)),
                      trailing: Text('${(asset.value.length / 1024).toStringAsFixed(1)} KB'),
                    )).toList(),
                  ),
                if (apkAssets.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: programming ? null : _exportApkAssets,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Export all original Flutter assets as ZIP'),
                  ),
                if (selected.firmware.isNotEmpty && apkFirmware.containsKey(selected.firmware))
                  TextButton.icon(
                    onPressed: programming ? null : _loadApkFirmware,
                    icon: const Icon(Icons.download_done),
                    label: const Text('Load selected firmware from APK'),
                  ),
                const Divider(height: 22),
                OutlinedButton.icon(
                  onPressed: programming ? null : _importFirmware,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Import S-record firmware file separately'),
                ),
                if (firmware != null) ...[
                  const Divider(height: 24),
                  Text(firmware!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${firmware!.size} bytes'),
                  SelectableText('SHA-256: ${firmware!.sha256}'),
                  const SizedBox(height: 6),
                  Text(firmware!.message),
                  Text('${firmware!.records} total records · ${firmware!.dataBytes} firmware bytes'),
                  Text('${firmware!.preparedBlocks} generic data blocks prepared for protocol integration'),
                  Text('Renesas 16 KB frame plan: ${firmware!.protocolPlanReady ? "READY" : "NOT READY"} (preflight required before programming)'),
                  Text('Address range: ${_formatAddress(firmware!.startAddress)} - ${_formatAddress(firmware!.endAddress)}'),
                  Text('S-record validation: ${firmware!.validSRecord ? "PASS" : "FAIL"}'),
                  Text('Exact profile match: ${firmware!.profileMatches ? "YES" : "NO"}'),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.biotech_rounded,
              title: 'PROGRAMMING ENGINE · RENESAS 78K0R',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recovered engine clues: DA41Engine, SerialTransport, AndroidSerialTransport, eraseFlash, writeChunkFast, writeFlash and verify.'),
                  SizedBox(height: 8),
                  Text('MCU target: Renesas 78K0R / uPD78F1201 with a 16 KB flash range.'),
                  Text('Android USB serial transport supports DTR/RTS direction control and hardware BREAK where the adapter driver supports it.'),
                  SizedBox(height: 8),
                  Text('The app now receives the READY pulse, sends the two 0x00 synchronization bytes, performs the Reset handshake, reads the silicon signature, and can run the tested erase/program/verify session after strict preflight and explicit confirmation.'),
                  SizedBox(height: 8),
                  Text('VDD, RESET and FLMD0 are not driven by the app. Board-specific wiring, logic voltage and boot-entry control must be verified before any destructive operation.'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.fingerprint_rounded,
              title: 'READ-ONLY SILICON SIGNATURE',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tap Read target signature, then trigger the cable's boot-entry/reset sequence within five seconds. After RESET release, the Renesas target emits READY within its documented 4.4-100 ms window. The app synchronizes and reads the signature. It does not control VDD, RESET or FLMD0.'),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: usbTransport == null || readingSignature || programming
                        ? null
                        : _readSiliconSignature,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(readingSignature ? 'Reading signature…' : 'Read target signature'),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(signatureMessage),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.lock_outline_rounded,
              title: 'PROGRAMMING CONTROLS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_programReadinessMessage),
                  const SizedBox(height: 8),
                  if (programProgress != null) ...[
                    LinearProgressIndicator(
                      value: programProgress!.fraction,
                    ),
                    const SizedBox(height: 6),
                    Text('${programProgress!.completedFrames}/${programProgress!.totalFrames} protocol responses checked'),
                  ],
                  SelectableText(programMessage),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _canProgram ? _programFirmware : null,
                    icon: const Icon(Icons.flash_on_rounded),
                    label: Text(programming ? 'Programming…' : 'Erase + Write + Verify'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Only exact-profile 16 KB S-record images and a verified uPD78F1201/16 KB target pass preflight. The operation starts with a full-chip erase. The app does not reboot or power off the target.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  UsbTool0LineProfile get _usbLineProfile => UsbTool0LineProfile(
        transmitDtr: transmitDtr,
        transmitRts: transmitRts,
        receiveDtr: receiveDtr,
        receiveRts: receiveRts,
      );

  void _setUsbLineProfile({
    bool? transmitDtr,
    bool? transmitRts,
    bool? receiveDtr,
    bool? receiveRts,
  }) {
    setState(() {
      this.transmitDtr = transmitDtr ?? this.transmitDtr;
      this.transmitRts = transmitRts ?? this.transmitRts;
      this.receiveDtr = receiveDtr ?? this.receiveDtr;
      this.receiveRts = receiveRts ?? this.receiveRts;
      usbTransport?.updateLineProfile(_usbLineProfile);
    });
  }

  void _setUsbBaudRate(int value) {
    setState(() {
      usbBaudRate = value;
      usbTransport?.updateBaudRate(value);
    });
  }

  Widget _lineSwitch(String title, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        value: value,
        onChanged: (readingSignature || programming) ? null : onChanged,
      );

  Widget _sectionCard({required IconData icon, required String title, required Widget child}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon), const SizedBox(width: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );
}
