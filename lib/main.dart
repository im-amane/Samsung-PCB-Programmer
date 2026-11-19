import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

import 'firmware_validator.dart';
import 'srecord_image.dart';

void main() => runApp(const SamsungPcbProgrammerApp());

class SamsungPcbProgrammerApp extends StatelessWidget {
  const SamsungPcbProgrammerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Samsung PCB Programmer',
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
  BoardProfile('0459C · Double Door', 'DA41-00814A', 'DA41-00814A.mot', '0459C', '6d51f294e21cdbb2efa207f63fff41c69468eba86199d419578af9a98cac5f02'),
  BoardProfile('0459G · Double Door', 'DA41-00814D', 'DA41-00814D_0459G.mot', '0459G', 'fc91858a2423324184ef708341e4a6929dfa8b39f53f7c479cbf152bec589873'),
  BoardProfile('0459M · Single Door', 'DA41-00814D', 'DA41-00814D_0459M.bin', '0459M', '4e96a1f2e3c6f39c9af2e61e2f07b69c12123546e4d93365457800e5f76adfc9'),
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
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int selectedIndex = 0;
  List<UsbDevice> devices = [];
  UsbPort? port;
  UsbDevice? connectedDevice;
  FirmwareInfo? firmware;
  final Map<String, Uint8List> apkFirmware = {};
  bool scanning = false;
  bool importingApk = false;
  String connectionMessage = 'Connect a USB-C OTG adapter to detect the interface.';
  String apkMessage = 'Original APK not imported.';

  @override
  void initState() {
    super.initState();
    _scanUsb();
  }

  @override
  void dispose() {
    port?.close();
    super.dispose();
  }

  Future<void> _scanUsb() async {
    setState(() => scanning = true);
    try {
      final found = await UsbSerial.listDevices();
      if (!mounted) return;
      setState(() {
        devices = found;
        scanning = false;
        connectionMessage = found.isEmpty
            ? 'No USB serial interface detected.'
            : '${found.length} USB device(s) detected. Select the correct interface.';
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

  Future<void> _disconnect() async {
    final current = port;
    setState(() {
      port = null;
      connectedDevice = null;
      connectionMessage = 'USB serial port disconnected.';
    });
    await current?.close();
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
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = entry.name;
        if (!name.contains('assets/flutter_assets/assets/firmwares/')) continue;
        final baseName = name.split('/').last;
        if (!boardProfiles.any((p) => p.firmware == baseName)) continue;
        final content = entry.content;
        if (content is List<int>) {
          extracted[baseName] = Uint8List.fromList(content);
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
        importingApk = false;
        apkMessage = '${extracted.length} firmware file(s) extracted from the APK in memory. Nothing was uploaded.';
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

  void _loadApkFirmware() {
    final profile = boardProfiles[selectedIndex];
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
    final expected = boardProfiles[selectedIndex];
    final profileMatches = name == expected.firmware && digest == expected.sha256;
    final profileMessage = profileMatches
        ? 'Exact filename and SHA-256 match for selected APK profile.'
        : 'PROFILE MISMATCH: expected ${expected.firmware} with SHA-256 ${expected.sha256}.';
    SRecordImage? parsedImage;
    var preparedBlocks = 0;
    var parserMessage = '';
    if (validation.valid) {
      try {
        parsedImage = SRecordImage.parse(bytes);
        preparedBlocks = parsedImage.dataBlocks(blockSize: 256).length;
        parserMessage = ' Memory map parsed; ${preparedBlocks} generic 256-byte data blocks prepared (not target commands).';
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
        title: const Text('Samsung PCB Programmer'),
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
                Text(port == null ? 'Not connected' : 'USB connected',
                    style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(connectionMessage, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: scanning ? null : _scanUsb,
                  icon: const Icon(Icons.usb_rounded),
                  label: Text(scanning ? 'Scanning…' : 'Scan USB devices'),
                ),
                if (port != null)
                  TextButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Disconnect'),
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
              ]),
            ),
            const SizedBox(height: 18),
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
                  onChanged: (v) => setState(() {
                    selectedIndex = v ?? 0;
                    firmware = null;
                  }),
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
                Text('Selected profile: ${selected.firmware}'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: importingApk ? null : _importApk,
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(importingApk ? 'Reading APK…' : 'Import original Samsung Swap APK'),
                ),
                Text(apkMessage, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (apkFirmware.containsKey(selected.firmware))
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
                  Text('Address range: ${_formatAddress(firmware!.startAddress)} - ${_formatAddress(firmware!.endAddress)}'),
                  Text('S-record validation: ${firmware!.validSRecord ? "PASS" : "FAIL"}'),
                  Text('Exact profile match: ${firmware!.profileMatches ? "YES" : "NO"}'),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.biotech_rounded,
              title: 'ENGINE ANALYSIS · ORIGINAL APK',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recovered engine clues: DA41Engine, SerialTransport, AndroidSerialTransport, eraseFlash, writeChunkFast, writeFlash and verify.'),
                  SizedBox(height: 8),
                  Text('MCU label: Renesas 78K0R / uPD78F1201 (16 KB flash).'),
                  Text('Boot-control clues: TOOL0, DTR, RTS and break pulses.'),
                  Text('Protocol clues: silicon signature 0xC0 and mass-erase status 0x20.'),
                  SizedBox(height: 8),
                  Text('These are static-analysis clues only. Exact packet framing, baud rate, timing, voltage levels and board compatibility are not confirmed. USB open does not configure a guessed baud rate or send data.'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.lock_outline_rounded,
              title: 'PROGRAMMING CONTROLS',
              child: const Text(
                'Erase, write, verify and reboot remain disabled. No programming command is sent. The APK identifies 0459C and 0459G as Double Door profiles and 0459M as Single Door, but does not establish that a 0459C/0459G PCB can safely accept 0459M firmware. Confirm exact PCB revision, pinout, logic voltage and firmware compatibility before any flash operation.',
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
