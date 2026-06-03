class VideoEditSettings {
  const VideoEditSettings({this.enabled = false, this.startSeconds = 0, this.endSeconds});

  static const maxTrimSeconds = 24 * 60 * 60.0;

  final bool enabled;
  final double startSeconds;
  final double? endSeconds;

  bool get hasTrim => enabled && (startSeconds > 0 || endSeconds != null);

  void validate() {
    if (!enabled) return;
    if (!startSeconds.isFinite || startSeconds < 0) throw const FormatException('Trim start must be zero or greater.');
    if (startSeconds > maxTrimSeconds) throw const FormatException('Trim start must be less than 24 hours.');
    final end = endSeconds;
    if (end != null && (!end.isFinite || end <= startSeconds)) throw const FormatException('Trim end must be after trim start.');
    if (end != null && end > maxTrimSeconds) throw const FormatException('Trim end must be less than 24 hours.');
  }

  List<String> toFfmpegInputPrefixArgs() {
    validate();
    if (!hasTrim || startSeconds <= 0) return const [];
    return ['-ss', _fmt(startSeconds)];
  }

  List<String> toFfmpegOutputArgs() {
    validate();
    final end = endSeconds;
    if (!hasTrim || end == null) return const [];
    return ['-t', _fmt(end - startSeconds)];
  }

  static String _fmt(double value) => value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'startSeconds': startSeconds,
        'endSeconds': endSeconds,
      };
}

