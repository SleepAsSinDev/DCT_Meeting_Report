class TranscriptionConfig {
  final String modelSize;
  final String language;
  final String quality;
  final bool preprocess;
  final bool fastPreprocess;
  final String initialPrompt;

  const TranscriptionConfig({
    this.modelSize = 'large-v3',
    this.language = 'th',
    this.quality = 'accurate',
    this.preprocess = true,
    this.fastPreprocess = false,
    this.initialPrompt = '',
  });

  TranscriptionConfig copyWith({
    String? modelSize,
    String? language,
    String? quality,
    bool? preprocess,
    bool? fastPreprocess,
    String? initialPrompt,
  }) {
    return TranscriptionConfig(
      modelSize: modelSize ?? this.modelSize,
      language: language ?? this.language,
      quality: quality ?? this.quality,
      preprocess: preprocess ?? this.preprocess,
      fastPreprocess: fastPreprocess ?? this.fastPreprocess,
      initialPrompt: initialPrompt ?? this.initialPrompt,
    );
  }

  Map<String, String> toServerEnvironment() {
    return {
      'WHISPER_MODEL': modelSize,
      'WHISPER_LANG': language,
      'WHISPER_QUALITY': quality,
    };
  }

  @override
  int get hashCode => Object.hash(modelSize, language, quality, preprocess,
      fastPreprocess, initialPrompt);

  @override
  bool operator ==(Object other) {
    return other is TranscriptionConfig &&
        other.modelSize == modelSize &&
        other.language == language &&
        other.quality == quality &&
        other.preprocess == preprocess &&
        other.fastPreprocess == fastPreprocess &&
        other.initialPrompt == initialPrompt;
  }
}
