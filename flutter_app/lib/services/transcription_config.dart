class TranscriptionConfig {
  final String modelSize;
  final String language;
  final String quality;
  final bool preprocess;
  final bool fastPreprocess;
  final String initialPrompt;
  final bool diarize;

  const TranscriptionConfig({
    this.modelSize = 'large-v3',
    this.language = 'th',
    this.quality = 'accurate',
    this.preprocess = true,
    this.fastPreprocess = false,
    this.initialPrompt = '',
    this.diarize = false,
  });

  TranscriptionConfig copyWith({
    String? modelSize,
    String? language,
    String? quality,
    bool? preprocess,
    bool? fastPreprocess,
    String? initialPrompt,
    bool? diarize,
  }) {
    return TranscriptionConfig(
      modelSize: modelSize ?? this.modelSize,
      language: language ?? this.language,
      quality: quality ?? this.quality,
      preprocess: preprocess ?? this.preprocess,
      fastPreprocess: fastPreprocess ?? this.fastPreprocess,
      initialPrompt: initialPrompt ?? this.initialPrompt,
      diarize: diarize ?? this.diarize,
    );
  }

  @override
  int get hashCode => Object.hash(modelSize, language, quality, preprocess,
      fastPreprocess, initialPrompt, diarize);

  @override
  bool operator ==(Object other) {
    return other is TranscriptionConfig &&
        other.modelSize == modelSize &&
        other.language == language &&
        other.quality == quality &&
        other.preprocess == preprocess &&
        other.fastPreprocess == fastPreprocess &&
        other.initialPrompt == initialPrompt &&
        other.diarize == diarize;
  }
}
