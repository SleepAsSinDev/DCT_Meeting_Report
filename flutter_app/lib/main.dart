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

    final supervisor = ServerSupervisor(
      host: '127.0.0.1',
      port: 8000,
      serverDir: 'server',
      startTimeout: const Duration(seconds: 120),
      useReload: false,
      environmentOverrides: config.toServerEnvironment(),
    );
    supervisor.status.value =
        'เตรียมเซิร์ฟเวอร์สำหรับโมเดล ${config.modelSize}...';
    final api = BackendApi(
      'http://127.0.0.1:8000',
      defaultModelSize: config.modelSize,
      defaultLanguage: config.language,
      defaultQuality: config.quality,
    );

    setState(() {
      _config = config;
      _ready = false;
      _modelReady = false;
      _restartToken += 1;
      _modelToken += 1;
      _supervisor = supervisor;
      _api = api;
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

    final Widget homeWidget;
    if (!_ready) {
      homeWidget = ServerBootPage(
        key: ValueKey('boot$_restartToken'),
        supervisor: supervisor,
        onReady: _onServerReady,
      );
    } else if (!_modelReady) {
      homeWidget = ModelLoadingPage(
        key: ValueKey('model$_modelToken'),
        api: api,
        config: _config,
        onReady: _onModelReady,
      );
    } else {
      homeWidget = HomePage(
        key: ValueKey('home$_restartToken'),
        api: api,
        config: _config,
        onConfigChanged: _handleConfigChanged,
      );
    }

    return MaterialApp(
      title: 'Meeting Minutes App',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: homeWidget,
    );
  }
}
