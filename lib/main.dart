import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

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
  const BoardProfile(this.name, this.board, this.firmware, this.revision);
  final String name;
  final String board;
  final String firmware;
  final String revision;
}

const boardProfiles = <BoardProfile>[
  BoardProfile('0459C · Double Door', 'DA41-00814A', 'DA41-00814A.mot', '0459C'),
  BoardProfile('0459G · Double Door', 'DA41-00814D', 'DA41-00814D_0459G.mot', '0459G'),
  BoardProfile('0459M · Single Door', 'DA41-00814D', 'DA41-00814D_0459M.bin', '0459M'),
];

class FirmwareInfo {
  const FirmwareInfo({
    required this.name,
    required this.size,
    required this.sha256,
    required this.isSRecord,
    required this.validSRecord,
    required this.records,
    required this.message,
  });
  final String name;
  final int size;
  final String sha256;
  final bool isSRecord;
  final bool validSRecord;
  final int records;
  final String message;
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
  bool scanning = false;
  String connectionMessage = 'Connect a USB-C OTG adapter to detect the interface.';

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
    await port?.close();
    final candidate = await device.create();
    if (candidate == null) {
      setState(() => connectionMessage = 'No serial driver is available for this USB device.');
      return;
    }
    final opened = await candidate.open();
    if (!opened) {
      setState(() => connectionMessage = 'USB permission or connection was denied.');
      return;
    }
    // Open the serial interface only. No bootloader or flash commands are sent.
    await candidate.setPortParameters(
      9600,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );
    if (!mounted) {
      await candidate.close();
      return;
    }
    setState(() {
      port = candidate;
      connectedDevice = device;
      connectionMessage = 'USB serial port opened. Programming protocol is not yet validated.';
    });
  }

  Future<void> _importFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mot', 'srec', 's19', 's28', 's37', 'bin', 'hex'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      _message('Could not read the selected file.');
      return;
    }
    final textData = utf8.decode(bytes, allowMalformed: true);
    final looksSRecord = textData.trimLeft().startsWith('S');
    final validation = looksSRecord ? _validateSRecords(textData) : (false, 0, 'Binary/HEX format: imported and hashed; format-specific validation is pending.');
    setState(() {
      firmware = FirmwareInfo(
        name: file.name,
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        isSRecord: looksSRecord,
        validSRecord: validation.$1,
        records: validation.$2,
        message: validation.$3,
      );
    });
  }

  (bool, int, String) _validateSRecords(String content) {
    var records = 0;
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.length < 4 || !RegExp(r'^S[0-9]').hasMatch(line)) {
        return (false, records, 'Invalid S-record line detected.');
      }
      final hex = line.substring(2);
      if (hex.length.isOdd || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(hex)) {
        return (false, records, 'Malformed hexadecimal data in S-record.');
      }
      final data = <int>[];
      for (var i = 0; i < hex.length; i += 2) {
        data.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      if (data.isEmpty || data.first != data.length - 1) {
        return (false, records, 'S-record byte count does not match line length.');
      }
      final sum = data.fold<int>(0, (a, b) => a + b) & 0xff;
      if (sum != 0xff) return (false, records, 'S-record checksum mismatch.');
      records++;
    }
    return records > 0
        ? (true, records, 'S-record count and checksums are valid.')
        : (false, 0, 'No S-record data found.');
  }

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
            const Text('PCB MODEL', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...List.generate(boardProfiles.length, (i) {
              final p = boardProfiles[i];
              return Card(
                child: RadioListTile<int>(
                  value: i,
                  groupValue: selectedIndex,
                  onChanged: (v) => setState(() => selectedIndex = v ?? 0),
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
                Text('Expected profile file: ${selected.firmware}'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _importFirmware,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Import firmware file'),
                ),
                if (firmware != null) ...[
                  const Divider(height: 24),
                  Text(firmware!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${firmware!.size} bytes'),
                  SelectableText('SHA-256: ${firmware!.sha256}'),
                  const SizedBox(height: 6),
                  Text(firmware!.message),
                  if (firmware!.isSRecord)
                    Text('${firmware!.records} records · ${firmware!.validSRecord ? "Checksum OK" : "Invalid"}'),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.biotech_rounded,
              title: 'ENGINE ANALYSIS · FROM ORIGINAL APK',
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Static analysis found programming-engine clues in the supplied APK:'),
                  SizedBox(height: 8),
                  Text('• DA41Engine / SerialTransport'),
                  Text('• MCU clue: Renesas 78K0R / uPD78F1201'),
                  Text('• TOOL0, DTR and RTS boot-mode clues'),
                  Text('• Signature clue: 0xC0'),
                  Text('• Mass Erase command clue: 0x20'),
                  Text('• Chunked write, verify and reboot routine names'),
                  SizedBox(height: 10),
                  Text('These are reverse-engineering clues, not a validated command sequence. Exact packet formats, timing, voltage levels and board compatibility are still unconfirmed.'),
                  SizedBox(height: 8),
                  Text('Firmware assets identified: DA41-00814A.mot, DA41-00814D_0459G.mot and DA41-00814D_0459M.bin. Import the matching file manually; proprietary firmware binaries are not bundled in this public app.'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionCard(
              icon: Icons.lock_outline_rounded,
              title: 'PROGRAMMING CONTROLS',
              child: const Text(
                'Erase, write, verify and reboot controls remain locked until the exact PCB revision, connector pinout, electrical levels, bootloader protocol and firmware compatibility are independently confirmed. USB connection and firmware inspection do not send programming commands.',
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
