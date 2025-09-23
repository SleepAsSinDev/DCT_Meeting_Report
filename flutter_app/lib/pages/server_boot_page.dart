import 'package:flutter/material.dart';
import 'package:meeting_minutes_app/services/server_supervisor.dart';

class ServerBootPage extends StatefulWidget {
  const ServerBootPage({super.key, required this.supervisor, required this.onReady});

  final ServerSupervisor supervisor;
  final VoidCallback onReady;

  @override
  State<ServerBootPage> createState() => _ServerBootPageState();
}

class _ServerBootPageState extends State<ServerBootPage> {
  String? errorText;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      errorText = null;
      _starting = true;
    });
    try {
      await widget.supervisor.ensureStarted();
      widget.onReady();
    } catch (e) {
      setState(() {
        errorText = e.toString();
      });
    } finally {
      setState(() {
        _starting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('กำลังเริ่มเซิร์ฟเวอร์', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: widget.supervisor.status,
                    builder: (_, value, __) => Text(value),
                  ),
                  const SizedBox(height: 16),
                  if (_starting) const LinearProgressIndicator(),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text('เกิดข้อผิดพลาด', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    SelectableText(errorText!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _start,
                          icon: const Icon(Icons.refresh),
                          label: const Text('ลองใหม่'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close),
                          label: const Text('ปิดหน้าต่าง'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
