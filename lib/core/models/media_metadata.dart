import 'media_kind.dart';

class MediaMetadata {
  const MediaMetadata({
    required this.path,
    required this.fileName,
    required this.kind,
    required this.fileSizeBytes,
    this.width,
    this.height,
    this.duration,
  });

  final String path;
  final String fileName;
  final MediaKind kind;
  final int fileSizeBytes;
  final int? width;
  final int? height;
  final Duration? duration;

  bool get hasDimensions => width != null && height != null;
  String get sizeLabel => formatBytes(fileSizeBytes);
  String? get dimensionsLabel => hasDimensions ? '${width}x$height' : null;
  String? get durationLabel =>
      duration == null ? null : formatDuration(duration!);

  List<String> get detailLabels => [
    kind.label,
    sizeLabel,
    ?dimensionsLabel,
    ?durationLabel,
  ];

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024.0;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024.0;
      unitIndex++;
    }
    return '${value >= 10 ? value.toStringAsFixed(1) : value.toStringAsFixed(2)} ${units[unitIndex]}';
  }

  static String formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
    return '$minutes:${two(seconds)}';
  }
}
