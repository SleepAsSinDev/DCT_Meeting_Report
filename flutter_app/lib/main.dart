import 'package:flutter/material.dart';
import 'package:meeting_minutes_app/services/api.dart';
import 'package:meeting_minutes_app/services/server_supervisor.dart';
import 'package:meeting_minutes_app/services/transcription_config.dart';
import 'package:meeting_minutes_app/pages/home_page.dart';
import 'package:meeting_minutes_app/pages/model_loading_page.dart';
import 'package:meeting_minutes_app/pages/server_boot_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ServerSupervisor? _supervisor;
  BackendApi? _api;
  bool _ready = false;
  bool _modelReady = false;
  int _restartToken = 0;
  int _modelToken = 0;
  TranscriptionConfig _config = const TranscriptionConfig();

  @override
  void initState() {
    super.initState();
    _recreateServices();
  }

  void _onServerReady() {
    setState(() {
      _ready = true;
      _modelToken += 1;
    });
  }

  Future<void> _recreateServices([TranscriptionConfig? newConfig]) async {
    final config = newConfig ?? _config;
    if (_supervisor != null) {
      await _supervisor!.stop();
    }
    setState(() {
      _config = config;
      _ready = false;
      _modelReady = false;
      _restartToken += 1;
      _modelToken += 1;
      _supervisor = ServerSupervisor(
        host: '127.0.0.1',
        port: 8000,
        serverDir: 'server',
        startTimeout: const Duration(seconds: 120),
        useReload: false,
        environmentOverrides: config.toServerEnvironment(),
      );
      _supervisor!.status.value =
          'เตรียมเซิร์ฟเวอร์สำหรับโมเดล ${config.modelSize}...';
      _api = BackendApi(
        'http://127.0.0.1:8000',
        defaultModelSize: config.modelSize,
        defaultLanguage: config.language,
        defaultQuality: config.quality,
      );
    });
  }

  void _onModelReady() {
    if (!mounted) return;
    setState(() {
      _modelReady = true;
    });
  }

  Future<void> _handleConfigChanged(TranscriptionConfig config) async {
    if (config == _config) return;
    await _recreateServices(config);
  }

  @override
  void dispose() {
    _supervisor?.stop(); // ปิดเฉพาะกรณีเราเป็นคนเปิด
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supervisor = _supervisor;
    final api = _api;
    if (supervisor == null || api == null) {
      return MaterialApp(
        title: 'Meeting Minutes App',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'Meeting Minutes App',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: !_ready
          ? ServerBootPage(
              key: ValueKey('boot$_restartToken'),
              supervisor: supervisor,
              onReady: _onServerReady,
            )
          : !_modelReady
              ? ModelLoadingPage(
                  key: ValueKey('model$_modelToken'),
                  api: api,
                  config: _config,
                  onReady: _onModelReady,
                )
              : HomePage(
                  key: ValueKey('home$_restartToken'),
                  api: api,
                  config: _config,
                  onConfigChanged: _handleConfigChanged,
                ),
    );
  }
}
