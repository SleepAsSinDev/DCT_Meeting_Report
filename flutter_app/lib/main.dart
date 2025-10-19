import 'package:flutter/material.dart';
import 'package:meeting_minutes_app/pages/home_page.dart';
import 'package:meeting_minutes_app/services/app_config.dart';
import 'package:meeting_minutes_app/services/transcription_config.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppConfig _appConfig;
  BackendApi? _api;
  int _restartToken = 0;
  final TranscriptionConfig _config = const TranscriptionConfig();
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _appConfig = AppConfig.fromEnvironment();
    _recreateServices();
  }

  Future<void> _recreateServices([TranscriptionConfig? newConfig]) async {
    final config = newConfig ?? _config;
    final api = BackendApi(
      _appConfig.baseUrl,
      defaultModelSize: config.modelSize,
      defaultLanguage: config.language,
      defaultQuality: config.quality,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _config = config;
      _api = api;
      _connectionError = null;
      _restartToken += 1;
    });
    _verifyRemoteHealth(api);
  }

  Future<void> _handleConfigChanged(TranscriptionConfig config) async {
    if (config == _config) return;
    await _recreateServices(config);
  }

  void _verifyRemoteHealth(BackendApi api) {
    Future.microtask(() async {
      try {
        await api.fetchHealth();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้: $e')),
        );
        setState(() {
          _connectionError = e.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;

    if (api == null) {
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
      home: HomePage(
        key: ValueKey('home$_restartToken'),
        api: api,
        config: _config,
        onConfigChanged: _handleConfigChanged,
        connectionError: _connectionError,
      ),
    );
  }
}
