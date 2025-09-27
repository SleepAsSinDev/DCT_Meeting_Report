import 'dart:async';

import 'package:flutter/material.dart';

import 'package:meeting_minutes_app/services/api.dart';
import 'package:meeting_minutes_app/services/transcription_config.dart';

class ModelLoadingPage extends StatefulWidget {
  const ModelLoadingPage({
    super.key,
    required this.api,
    required this.config,
    required this.onReady,
  });

  final BackendApi api;
  final TranscriptionConfig config;
  final VoidCallback onReady;

  @override
  State<ModelLoadingPage> createState() => _ModelLoadingPageState();
}

class _ModelLoadingPageState extends State<ModelLoadingPage> {
  bool _loading = false;
  bool _polling = false;
  String _status = 'กำลังตรวจสอบสถานะโมเดล...';
  String? _error;
  List<String> _loadedModels = const [];

  static const Duration _timeout = Duration(minutes: 5);
  static const Duration _interval = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  Future<void> _startPolling() async {
    if (_polling) return;
    _polling = true;
    setState(() {
      _loading = true;
      _error = null;
      _status =
          'กำลังโหลดโมเดล "${widget.config.modelSize}" โปรดรอสักครู่...';
      _loadedModels = const [];
    });

    final stopwatch = Stopwatch()..start();
    while (mounted && stopwatch.elapsed < _timeout) {
      try {
        final health = await widget.api.fetchHealth();
        final defaultModel =
            (health['default_model'] as String?)?.trim() ?? '';
        final loaded = (health['loaded_models'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[];
        if (!mounted) {
          _polling = false;
          return;
        }
        setState(() {
          _status = defaultModel.isEmpty
              ? 'กำลังเตรียมโมเดลจากเซิร์ฟเวอร์...'
              : 'โมเดลที่เซิร์ฟเวอร์กำลังกระตุ้น: $defaultModel';
          _loadedModels = loaded;
          _error = null;
        });
        if (loaded.isNotEmpty) {
          _polling = false;
          widget.onReady();
          return;
        }
      } catch (e) {
        if (!mounted) {
          _polling = false;
          return;
        }
        setState(() {
          _error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้: $e';
        });
      }
      await Future.delayed(_interval);
    }

    if (!mounted) {
      _polling = false;
      return;
    }
    setState(() {
      _loading = false;
      _error ??=
          'โหลดโมเดลไม่สำเร็จภายใน ${_timeout.inMinutes} นาที โปรดลองอีกครั้งหรือเปลี่ยนการตั้งค่า';
    });
    _polling = false;
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
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'กำลังโหลดโมเดลเสียง',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text('โมเดลที่เลือก: ${widget.config.modelSize}'),
                  const SizedBox(height: 8),
                  Text(_status),
                  if (_loadedModels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('โมเดลที่โหลดแล้ว (${_loadedModels.length}):'),
                    const SizedBox(height: 4),
                    for (final entry in _loadedModels)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $entry'),
                      ),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    if (!_loading) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _startPolling,
                          icon: const Icon(Icons.refresh),
                          label: const Text('ลองใหม่'),
                        ),
                      ),
                    ],
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
