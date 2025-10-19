class AppConfig {
  AppConfig({required this.serverUri});

  final Uri serverUri;

  factory AppConfig.fromEnvironment() {
    const rawBaseUrl = String.fromEnvironment(
      'SERVER_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    );
    final trimmed = rawBaseUrl.trim();
    Uri uri = Uri.parse('http://127.0.0.1:8000');
    if (trimmed.isNotEmpty) {
      final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
      final parsed = Uri.tryParse(withScheme);
      if (parsed != null) {
        uri = parsed;
      }
    }
    return AppConfig(serverUri: uri);
  }

  String get baseUrl {
    final normalized = serverUri.replace(path: '', query: '', fragment: '');
    final scheme = normalized.scheme.isEmpty ? 'http' : normalized.scheme;
    final effectivePort =
        normalized.hasPort ? normalized.port : (scheme == 'https' ? 443 : 80);
    final needsPort = !((scheme == 'http' && effectivePort == 80) ||
        (scheme == 'https' && effectivePort == 443));
    final portPart = needsPort ? ':$effectivePort' : '';
    return '$scheme://${normalized.host}$portPart';
  }
}
