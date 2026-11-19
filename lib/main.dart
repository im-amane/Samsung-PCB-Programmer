import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart' as libserial;

import 'firmware_validator.dart';
import 'srecord_image.dart';
import 'renesas_program_plan.dart';
import 'renesas_serial_transport.dart';

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
  List<UsbDevice> devices = [];
  UsbPort? port;
  RenesasSerialTransport? nativeTransport;
  String? connectedNativePath;
  List<String> nativePorts = [];
  UsbDevice? connectedDevice;
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
    _scanUsb();
    _loadSelectedFirmware();
  }

  @override
  void dispose() {
    port?.close();
    nativeTransport?.close();
    super.dispose();
  }

  Future<void> _scanUsb() async {
    setState(() => scanning = true);
    try {
      final found = await UsbSerial.listDevices();
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

  Future<void> _connect(UsbDevice device) async {
    try {
      await port?.close();
      final oldNative = nativeTransport;
      nativeTransport = null;
      connectedNativePath = null;
      oldNative?.close();
      final candidate = await device.create();
      if (candidate == null) {
        if (mounted) setState(() => connectionMessage = 'No serial driver is available for this USB device.');
        return;
      }
      final opened = await candidate.open();
      if (!opened) {
        await candidate.close();
        if (mounted) setState(() => connectionMessage = 'USB permission or connection was denied.');
        return;
      }
      // Open-only: do not guess a baud rate, toggle boot pins, or send MCU commands.
      if (!mounted) {
        await candidate.close();
        return;
      }
      setState(() {
        port = candidate;
        connectedDevice = device;
        connectionMessage = 'USB serial port opened without sending data or changing serial parameters. Original protocol is not yet validated.';
      });
    } catch (e) {
      if (mounted) setState(() => connectionMessage = 'USB connection failed: $e');
    }
  }

  Future<void> _connectNative(String path) async {
    libserial.SerialPort? candidate;
    try {
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
        connectionMessage = 'Native libserialport opened $path. No baud rate, DTR/RTS, break pulse, or MCU data has been changed/sent.';
      });
    } catch (e) {
      candidate?.dispose();
      if (mounted) setState(() => connectionMessage = 'Native serial open failed: $e');
    }
  }

  Future<void> _disconnect() async {
    final current = port;
    final native = nativeTransport;
    setState(() {
      port = null;
      connectedDevice = null;
      nativeTransport = null;
      connectedNativePath = null;
      connectionMessage = 'Serial interface disconnected.';
    });
    await current?.close();
    native?.close();
  }

  Future<void> _importApk() async {
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
      if (mounted) setState(() => firmware = null);
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
      setState(() => firmware = null);
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
                        subtitle: Text('VID: ${d.vid ?? 0}  ·  PID: ${d.pid ?? 0}'),
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
                  onChanged: (v) {
                    setState(() {
                      selectedIndex = v ?? 0;
                      firmware = null;
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
                  onPressed: importingApk ? null : _importApk,
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
                    onPressed: _exportApkAssets,
                    icon: const Icon(Icons.save_alt_rounded),
                    label: const Text('Export all original Flutter assets as ZIP'),
                  ),
                if (selected.firmware.isNotEmpty && apkFirmware.containsKey(selected.firmware))
                  TextButton.icon(
                    onPressed: _loadApkFirmware,
                    icon: const Icon(Icons.download_done),
                    label: const Text('Load selected firmware from APK'),
                  ),
                const Divider(height: 22),
                OutlinedButton.icon(
                  onPressed: _importFirmware,
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
                  Text('Renesas 16 KB frame plan: ${firmware!.protocolPlanReady ? "READY" : "NOT READY"} (no bytes sent to PCB)'),
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
                  Text('MCU label: Renesas 78K0R / uPD78F1201 (16 KB flash).'),
                  Text('Boot-control clues: TOOL0, DTR, RTS and break pulses.'),
                  Text('Protocol clues: silicon signature 0xC0 and mass-erase status 0x20.'),
                  SizedBox(height: 8),
                  Text('Renesas protocol codec is implemented: command/data frame encoding, checksum validation, ACK/NACK handling, and 1 KB block-range commands. Documented commands include reset, baud setup, chip erase, block erase, program, verify and silicon signature.'),
                  SizedBox(height: 8),
                  Text('No programming bytes are sent yet. The physical single-wire TOOL0 transport, RESET/FLMD0 control, adapter voltage, and 8N2/8N1 direction-specific serial behavior still need hardware confirmation.'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.lock_outline_rounded,
              title: 'PROGRAMMING CONTROLS',
              child: const Text(
                'Protocol frame generation is implemented and unit-tested, but the hardware transport is not connected to the target yet. Erase, write, verify and reboot remain disabled until the single-wire TOOL0 adapter, RESET/FLMD0 control, voltage levels and target-board wiring are verified. The APK labels 0459C/0459G as Double Door and 0459M as Single Door; that does not prove cross-model firmware compatibility.',
              ),
            ),
          ],
        ),
      ),
    );
  }

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
