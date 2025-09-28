import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final List<String> binaryNames;
  final Map<String, String> environmentOverrides;
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
    List<String>? binaryNames,
    Map<String, String>? environmentOverrides,
  })  : dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'http://$host:$port',
              connectTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 5),
            )),
        binaryNames = List.unmodifiable(
          binaryNames ?? _defaultBinaryNames(),
        ),
        environmentOverrides =
            Map.unmodifiable(environmentOverrides ?? const <String, String>{});

  static List<String> _defaultBinaryNames() {
    if (Platform.isWindows) {
      return [
        'meeting_server.exe',
        'meeting_server',
        'meeting_server_debug.exe',
        'server.exe',
        'server',
      ];
    }
    return ['meeting_server', 'server'];
  }

  Future<bool> _isHealthy() async {
    try {
      final r = await dio.get('/healthz');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureStarted() async {
    status.value = 'กำลังตรวจสอบเซิร์ฟเวอร์ที่ http://$host:$port...';
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

    final binaryPath = _findBundledBinary(resolvedDir);
    final environment = Map<String, String>.from(Platform.environment)
      ..addAll(environmentOverrides)
      ..['HOST'] = host
      ..['PORT'] = port.toString()
      ..['MEETING_SERVER_HOST'] = host
      ..['MEETING_SERVER_PORT'] = port.toString();
    final modelLabel = environmentOverrides['WHISPER_MODEL'] ?? 'ค่าเริ่มต้น';

    if (binaryPath != null) {
      final binaryDir = File(binaryPath).parent.path;
      status.value = 'กำลังเริ่มเซิร์ฟเวอร์... (${p.basename(binaryPath)})';
      _proc = await Process.start(
        binaryPath,
        const <String>[],
        workingDirectory: binaryDir,
        runInShell: Platform.isWindows,
        mode: Platform.isWindows
            ? ProcessStartMode.normal
            : ProcessStartMode.detachedWithStdio,
        environment: environment,
      );
      startedByUs = true;
      _attachProcessStreams(_proc!);
    } else {
      if (!Directory(resolvedDir).existsSync() ||
          !File(p.join(resolvedDir, 'main.py')).existsSync()) {
        final msg =
            'ไม่พบ server/main.py ที่: $resolvedDir\nโปรดตั้งค่า serverDir ให้เป็น path แบบ absolute ไปยังโฟลเดอร์ server';
        status.value = msg;
        throw Exception(msg);
      }

      final python = await _preparePython(resolvedDir);
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
        runInShell: Platform.isWindows,
        mode: Platform.isWindows
            ? ProcessStartMode.normal
            : ProcessStartMode.detachedWithStdio,
        environment: environment,
      );
      startedByUs = true;
      _attachProcessStreams(_proc!);
    }

    status.value =
        'กำลังโหลดโมเดล $modelLabel... (อาจใช้เวลาหลายนาทีเมื่อเป็นโมเดลใหญ่)';
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

  Future<String> _preparePython(String resolvedServerDir) async {
    final requirementsPath = p.join(resolvedServerDir, 'requirements.txt');
    final requirementsFile = File(requirementsPath);
    final venvDir = p.join(resolvedServerDir, '.venv');
    final venvPython = Platform.isWindows
        ? p.join(venvDir, 'Scripts', 'python.exe')
        : p.join(venvDir, 'bin', 'python');

    final systemPython = _findPython(resolvedServerDir);
    var pythonExecutable = systemPython;

    if (!requirementsFile.existsSync()) {
      return pythonExecutable;
    }

    try {
      if (!File(venvPython).existsSync()) {
        status.value = 'กำลังตั้งค่า virtualenv สำหรับเซิร์ฟเวอร์...';
        await _runProcess(
          systemPython,
          ['-m', 'venv', venvDir],
          workingDirectory: resolvedServerDir,
        );
      }

      if (File(venvPython).existsSync()) {
        pythonExecutable = venvPython;
        final stampFile = File(p.join(venvDir, '.requirements.stamp'));
        final requirementsContent = await requirementsFile.readAsString();
        final previousStamp =
            stampFile.existsSync() ? await stampFile.readAsString() : '';
        if (previousStamp != requirementsContent) {
          status.value = 'กำลังติดตั้งไลบรารีเซิร์ฟเวอร์...';
          await _runProcess(
            pythonExecutable,
            ['-m', 'pip', 'install', '--upgrade', 'pip'],
            workingDirectory: resolvedServerDir,
          );
          await _runProcess(
            pythonExecutable,
            ['-m', 'pip', 'install', '-r', 'requirements.txt'],
            workingDirectory: resolvedServerDir,
          );
          await stampFile.writeAsString(requirementsContent);
        }
        return pythonExecutable;
      }
    } catch (error, stackTrace) {
      status.value =
          'เตือน: เตรียม virtualenv ไม่สำเร็จ กำลังลองใช้ Python ระบบที่มีอยู่';
      _logBootstrapError(error, stackTrace);
      try {
        status.value =
            'กำลังติดตั้งไลบรารีเซิร์ฟเวอร์ด้วย Python ระบบ (โหมด --user)...';
        await _runProcess(
          systemPython,
          ['-m', 'pip', 'install', '--user', '-r', requirementsPath],
          workingDirectory: resolvedServerDir,
        );
      } catch (nestedError, nestedStack) {
        status.value =
            'เตือน: ติดตั้งไลบรารีอัตโนมัติไม่สำเร็จ โปรดติดตั้งด้วยตนเอง';
        _logBootstrapError(nestedError, nestedStack);
      }
    }

    return pythonExecutable;
  }

  Future<void> _runProcess(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.stdout is String) {
      _logBootstrapOutput(result.stdout as String);
    }
    if (result.stderr is String) {
      _logBootstrapOutput(result.stderr as String);
    }

    if (result.exitCode != 0) {
      throw ProcessException(executable, arguments, result.stderr, result.exitCode);
    }
  }

  void _logBootstrapOutput(String output) {
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // ignore: avoid_print
      print('[server][bootstrap] $trimmed');
    }
  }

  void _logBootstrapError(Object error, StackTrace stackTrace) {
    // ignore: avoid_print
    print('[server][bootstrap][error] $error');
    // ignore: avoid_print
    print('[server][bootstrap][error] $stackTrace');
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

  void _attachProcessStreams(Process proc) {
    proc.stdout.transform(utf8.decoder).listen((s) {
      for (final line in const LineSplitter().convert(s)) {
        if (line.trim().isEmpty) continue;
        // ignore: avoid_print
        print('[server] $line');
      }
    });
    proc.stderr.transform(utf8.decoder).listen((s) {
      for (final line in const LineSplitter().convert(s)) {
        if (line.trim().isEmpty) continue;
        // ignore: avoid_print
        print('[server] $line');
      }
    });
  }

  String? _findBundledBinary(String resolvedServerDir) {
    String? normalize(String candidate, {String? base}) {
      if (candidate.isEmpty) return null;
      if (p.isAbsolute(candidate)) {
        return p.normalize(candidate);
      }
      final prefix = base ?? Directory.current.path;
      return p.normalize(p.join(prefix, candidate));
    }

    String? firstExecutable(Iterable<String> candidates) {
      final seen = <String>{};
      for (final path in candidates) {
        if (path.isEmpty) continue;
        final norm = p.normalize(path);
        if (!seen.add(norm)) continue;
        if (_isExecutable(norm)) {
          return norm;
        }
      }
      return null;
    }

    final envOverride = Platform.environment['MEETING_APP_SERVER_BINARY'];
    if (envOverride != null && envOverride.isNotEmpty) {
      final direct = normalize(envOverride);
      if (direct != null && _isExecutable(direct)) {
        return direct;
      }
    }

    final candidates = <String>[];

    for (final name in binaryNames) {
      if (p.isAbsolute(name)) {
        candidates.add(name);
      }
    }

    final searchDirs = <String>{
      Directory.current.path,
      if (resolvedServerDir.isNotEmpty) resolvedServerDir,
      if (resolvedServerDir.isNotEmpty) p.join(resolvedServerDir, 'dist'),
      if (resolvedServerDir.isNotEmpty) p.join(resolvedServerDir, 'bin'),
      File(Platform.resolvedExecutable).parent.path,
    };

    final exeParent = File(Platform.resolvedExecutable).parent.parent;
    if (exeParent.path.isNotEmpty) {
      searchDirs.add(exeParent.path);
    }

    for (final dir in searchDirs) {
      for (final name in binaryNames) {
        if (p.isAbsolute(name)) continue;
        final norm = normalize(name, base: dir);
        if (norm != null) {
          candidates.add(norm);
        }
      }
    }

    return firstExecutable(candidates);
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
