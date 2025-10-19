import 'package:flutter/material.dart';
import 'package:meeting_minutes_app/pages/home_page.dart';
import 'package:meeting_minutes_app/pages/model_loading_page.dart';
import 'package:meeting_minutes_app/pages/server_boot_page.dart';
import 'package:meeting_minutes_app/services/api.dart';
import 'package:meeting_minutes_app/services/app_config.dart';
import 'package:meeting_minutes_app/services/server_supervisor.dart';
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
  ServerSupervisor? _supervisor;
  BackendApi? _api;
  bool _serverReady = false;
  bool _modelReady = false;
  int _restartToken = 0;
  int _modelToken = 0;
  TranscriptionConfig _config = const TranscriptionConfig();

  @override
  void initState() {
    super.initState();
    _appConfig = AppConfig.fromEnvironment();
    _recreateServices();
  }

  Future<void> _recreateServices([TranscriptionConfig? newConfig]) async {
    final config = newConfig ?? _config;
    if (_appConfig.manageServerProcess) {
      final previousSupervisor = _supervisor;
      if (previousSupervisor != null) {
        await previousSupervisor.stop();
      }

      final supervisor = ServerSupervisor(
        host: _appConfig.host,
        port: _appConfig.port,
        serverDir: 'server',
        startTimeout: _appConfig.serverStartTimeout,
        useReload: false,
        environmentOverrides: config.toServerEnvironment(),
      );
      supervisor.status.value =
          'เตรียมเซิร์ฟเวอร์สำหรับโมเดล ${config.modelSize}...';

      final api = BackendApi(
        _appConfig.baseUrl,
        defaultModelSize: config.modelSize,
        defaultLanguage: config.language,
        defaultQuality: config.quality,
      );

      if (!mounted) {
        await supervisor.stop();
        return;
      }

      setState(() {
        _config = config;
        _serverReady = false;
        _modelReady = false;
        _restartToken += 1;
        _modelToken += 1;
        _supervisor = supervisor;
        _api = api;
      });
    } else {
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
        _supervisor = null;
        _serverReady =
            true; // Remote server assumed reachable; UI still polls health.
        _modelReady = false;
        _restartToken += 1;
        _modelToken += 1;
      });
    }
  }

  void _onServerReady() {
    if (!mounted) return;
    setState(() {
      _serverReady = true;
      _modelToken += 1;
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
    _supervisor?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;

    if (api == null || (!_appConfig.manageServerProcess && !_serverReady)) {
      return MaterialApp(
        title: 'Meeting Minutes App',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final Widget homeWidget;
    if (_appConfig.manageServerProcess && !_serverReady) {
      final supervisor = _supervisor;
      if (supervisor == null) {
        homeWidget = const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      } else {
        homeWidget = ServerBootPage(
          key: ValueKey('boot$_restartToken'),
          supervisor: supervisor,
          onReady: _onServerReady,
        );
      }
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
