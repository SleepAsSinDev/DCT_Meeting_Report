import 'package:flutter/material.dart';
import 'package:meeting_minutes_app/services/api.dart';
import 'package:meeting_minutes_app/services/server_supervisor.dart';
import 'package:meeting_minutes_app/pages/server_boot_page.dart';
import 'package:meeting_minutes_app/pages/home_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ServerSupervisor _supervisor;
  late final BackendApi _api;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _supervisor = ServerSupervisor(
      host: '127.0.0.1',
      port: 8000,
      serverDir: 'server',              // ปรับเป็น absolute ได้ หรือใช้ env MEETING_APP_SERVER_DIR
      startTimeout: const Duration(seconds: 120),
      useReload: false,                  // ตั้ง true ถ้าต้องการ dev --reload
    );
    _api = BackendApi(
      'http://127.0.0.1:8000',
      defaultModelSize: 'large-v3',
      defaultLanguage: 'th',
      defaultQuality: 'accurate',
    );
  }

  void _onServerReady() {
    setState(() {
      _ready = true;
    });
  }

  @override
  void dispose() {
    _supervisor.stop(); // ปิดเฉพาะกรณีเราเป็นคนเปิด
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meeting Minutes App',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: _ready
          ? HomePage(api: _api)
          : ServerBootPage(supervisor: _supervisor, onReady: _onServerReady),
    );
  }
}
