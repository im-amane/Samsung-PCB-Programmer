import 'package:flutter/material.dart';

void main() {
  runApp(const SamsungPcbProgrammerApp());
}

class SamsungPcbProgrammerApp extends StatelessWidget {
  const SamsungPcbProgrammerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
}

class BoardProfile {
  const BoardProfile({
    required this.name,
    required this.board,
    required this.firmware,
    required this.status,
  });

  final String name;
  final String board;
  final String firmware;
  final String status;
}

const boardProfiles = <BoardProfile>[
  BoardProfile(
    name: '0459C · Double Door',
    board: 'DA41-00814A',
    firmware: 'DA41-00814A.mot',
    status: 'Reference only',
  ),
  BoardProfile(
    name: '0459G · Double Door',
    board: 'DA41-00814D',
    firmware: 'DA41-00814D_0459G.mot',
    status: 'Reference only',
  ),
  BoardProfile(
    name: '0459M · Single Door',
    board: 'DA41-00814D',
    firmware: 'DA41-00814D_0459M.bin',
    status: 'Reference only',
  ),
];

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final selected = boardProfiles[selectedIndex];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Samsung PCB Programmer'),
        actions: [
          IconButton(
            tooltip: 'Connection information',
            onPressed: _showConnectionInfo,
            icon: const Icon(Icons.usb_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.memory_rounded, size: 28),
                        SizedBox(width: 10),
                        Text(
                          'PROGRAMMER STATUS',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Not connected',
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Connect the USB-C OTG adapter to begin device detection.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _showConnectionInfo,
                      icon: const Icon(Icons.usb),
                      label: const Text('USB connection setup'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text('PCB MODEL', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...List.generate(boardProfiles.length, (index) {
              final profile = boardProfiles[index];
              return Card(
                child: RadioListTile<int>(
                  value: index,
                  groupValue: selectedIndex,
                  onChanged: (value) => setState(() => selectedIndex = value ?? 0),
                  title: Text(profile.name),
                  subtitle: Text('${profile.board}  ·  ${profile.status}'),
                ),
              );
            }),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FIRMWARE CATALOGUE',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(selected.firmware, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      'Firmware asset not bundled in this starter build.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(label: Text('MCU: uPD78F1201 · unverified per revision')),
                        Chip(label: Text('Write: locked pending protocol validation')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SAFETY INTERLOCK',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      'Flash erase/write is not enabled. Confirm exact PCB revision, target voltage, connector pinout, and firmware compatibility before enabling any programming operation.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectionInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('USB-C OTG'),
        content: const Text(
          'USB host detection is not implemented in this starter build. The cable or adapter chipset and its protocol must be identified before selecting a serial driver.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
