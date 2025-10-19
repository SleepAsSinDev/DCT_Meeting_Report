class AppConfig {
  AppConfig({
    required this.serverUri,
    required this.manageServerProcess,
    required this.serverStartTimeout,
  });

  final Uri serverUri;
  final bool manageServerProcess;
  final Duration serverStartTimeout;

  factory AppConfig.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment('SERVER_BASE_URL',
        defaultValue: 'http://127.0.0.1:8000');
    const rawManage =
        String.fromEnvironment('MANAGE_SERVER', defaultValue: 'true');
    const rawTimeout =
        String.fromEnvironment('SERVER_START_TIMEOUT', defaultValue: '120');

    final trimmed = rawBaseUrl.trim();
    Uri uri = Uri.parse('http://127.0.0.1:8000');
    if (trimmed.isNotEmpty) {
      final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
      final parsed = Uri.tryParse(withScheme);
      if (parsed != null) {
        uri = parsed;
      }
    }

    final manage = rawManage.toLowerCase() == 'true';
    final timeoutSeconds = int.tryParse(rawTimeout) ?? 120;

    return AppConfig(
      serverUri: uri,
      manageServerProcess: manage,
      serverStartTimeout: Duration(seconds: timeoutSeconds),
    );
  }

  String get host => serverUri.host.isEmpty ? '127.0.0.1' : serverUri.host;

  int get port {
    if (serverUri.hasPort) return serverUri.port;
    return scheme == 'https' ? 443 : 80;
  }

  String get scheme => serverUri.scheme.isEmpty ? 'http' : serverUri.scheme;

  /// Base URL that Dio can consume (no path/query component).
  String get baseUrl {
    final normalized = serverUri.replace(path: '', query: '', fragment: '');
    final effectivePort = normalized.hasPort ? normalized.port : port;
    final needsPort = !((scheme == 'http' && effectivePort == 80) ||
        (scheme == 'https' && effectivePort == 443));
    final portPart = needsPort ? ':$effectivePort' : '';
    return '$scheme://${normalized.host}$portPart';
  }
}
