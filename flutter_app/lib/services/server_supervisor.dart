import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class ServerSupervisor {
  final String host;
  final int port;
  final String serverDir; // may be relative or absolute
  final Duration startTimeout;
  final bool useReload; // if true -> --reload (dev hot-reload)
  final Dio dio;
  // Live status for UI
  final ValueNotifier<String> status =
      ValueNotifier<String>('กำลังตรวจสอบเซิร์ฟเวอร์...');

  Process? _proc;
  bool startedByUs = false;

  ServerSupervisor({
    this.host = '127.0.0.1',
    this.port = 8000,
    this.serverDir = 'server',
    this.startTimeout = const Duration(seconds: 120),
    this.useReload = false,
    Dio? dio,
  }) : dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'http://127.0.0.1:8000',
              connectTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 5),
            ));

  Future<bool> _isHealthy() async {
    try {
      final r = await dio.get('/healthz');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureStarted() async {
    status.value = 'กำลังตรวจสอบเซิร์ฟเวอร์ที่พอร์ต $port...';
    if (await _isHealthy()) {
      startedByUs = false;
      status.value = 'พบเซิร์ฟเวอร์ที่ทำงานอยู่แล้ว';
      // ignore: avoid_print
      print('[server] already running at http://$host:$port');
      return;
    }

    // Resolve server dir first
    final resolvedDir = _resolveServerDir();
    status.value = 'ตำแหน่ง server: $resolvedDir';
    if (!Directory(resolvedDir).existsSync() ||
        !File(p.join(resolvedDir, 'main.py')).existsSync()) {
      final msg =
          'ไม่พบ server/main.py ที่: $resolvedDir\nโปรดตั้งค่า serverDir ให้เป็น path แบบ absolute ไปยังโฟลเดอร์ server';
      status.value = msg;
      throw Exception(msg);
    }

    final python = _findPython(resolvedDir);
    final args = <String>[
      '-m',
      'uvicorn',
      'main:app',
      '--host',
      host,
      '--port',
      port.toString(),
    ];
    if (useReload) {
      args.add('--reload'); // dev only
    }

    status.value = 'กำลังเริ่มเซิร์ฟเวอร์... (uvicorn)';
    _proc = await Process.start(
      python,
      args,
      workingDirectory: resolvedDir,
      runInShell: false,
      mode: ProcessStartMode.detachedWithStdio,
    );
    startedByUs = true;

    // Pipe logs
    _proc!.stdout.transform(utf8.decoder).listen((s) {
      for (final line in const LineSplitter().convert(s)) {
        if (line.trim().isEmpty) continue;
        // ignore: avoid_print
        print('[server] $line');
      }
    });
    _proc!.stderr.transform(utf8.decoder).listen((s) {
      for (final line in const LineSplitter().convert(s)) {
        if (line.trim().isEmpty) continue;
        // ignore: avoid_print
        print('[server] $line');
      }
    });

    final sw = Stopwatch()..start();
    var delay = const Duration(milliseconds: 250);
    var attempt = 0;
    while (sw.elapsed < startTimeout) {
      attempt += 1;
      status.value = 'กำลังเชื่อมต่อเซิร์ฟเวอร์... (ลองครั้งที่ $attempt)';
      if (await _isHealthy()) {
        status.value = 'เซิร์ฟเวอร์พร้อมใช้งาน';
        return;
      }
      await Future.delayed(delay);
      final nextMs = (delay.inMilliseconds * 1.5).clamp(250, 2000);
      delay = Duration(milliseconds: nextMs.toInt());
    }

    await stop();
    status.value = 'เริ่มต้นไม่สำเร็จ (หมดเวลา ${startTimeout.inSeconds}s)';
    throw Exception('Server failed to start within ${startTimeout.inSeconds}s');
  }

  /// Try to find the absolute server directory.
  /// 1) MEETING_APP_SERVER_DIR env
  /// 2) given [serverDir] if absolute
  /// 3) relative to current working dir
  /// 4) relative to executable dir (walk up 2..7 levels and append 'server')
  String _resolveServerDir() {
    final env = Platform.environment['MEETING_APP_SERVER_DIR'];
    if (env != null && env.isNotEmpty && Directory(env).existsSync()) {
      return p.normalize(env);
    }

    if (p.isAbsolute(serverDir)) {
      return p.normalize(serverDir);
    }

    // relative to CWD
    final cwdPath = p.normalize(p.join(Directory.current.path, serverDir));
    if (Directory(cwdPath).existsSync()) return cwdPath;

    // relative to executable dir, walking up
    final exeDir = File(Platform.resolvedExecutable).parent;
    var node = exeDir;
    for (int up = 0; up < 8; up++) {
      final candidate = p.normalize(p.join(node.path, serverDir));
      if (Directory(candidate).existsSync()) return candidate;
      final sibling = p.normalize(p.join(node.path, 'server'));
      if (Directory(sibling).existsSync()) return sibling;
      node = node.parent;
    }

    // fallback to CWD/server
    return p.normalize(p.join(Directory.current.path, 'server'));
  }

  String _findPython(String resolvedServerDir) {
    // Prefer project venv in resolvedServerDir, then system python3/python
    final candidates = <String>[];
    if (Platform.isWindows) {
      candidates.addAll([
        p.join(resolvedServerDir, '.venv', 'Scripts', 'python.exe'),
        'python.exe',
        'py',
      ]);
    } else {
      candidates.addAll([
        p.join(resolvedServerDir, '.venv', 'bin', 'python'),
        'python3',
        'python',
      ]);
    }

    for (final c in candidates) {
      if (_isExecutable(c)) return c;
    }
    return Platform.isWindows ? 'python.exe' : 'python3';
  }

  bool _isExecutable(String cmd) {
    try {
      if (cmd.contains(Platform.pathSeparator)) {
        return File(cmd).existsSync();
      } else {
        final proc =
            Process.runSync(Platform.isWindows ? 'where' : 'which', [cmd]);
        return proc.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    final p = _proc;
    if (p == null) return;
    if (!startedByUs) return;

    try {
      if (Platform.isWindows) {
        p.kill();
      } else {
        p.kill(ProcessSignal.sigterm);
        final _ = await Future.any(
            [p.exitCode, Future.delayed(const Duration(seconds: 3))]);
        try {
          p.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
