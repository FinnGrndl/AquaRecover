import 'media_kind.dart';
import 'media_metadata.dart';

class MediaJob {
  const MediaJob({
    required this.id,
    required this.inputPath,
    required this.kind,
    this.displayName,
    this.source = MediaSource.files,
    this.metadata,
    this.status = JobStatus.pending,
    this.outputPath,
    this.error,
    this.progress = 0,
  });

  final String id;
  final String inputPath;
  final MediaKind kind;
  final String? displayName;
  final MediaSource source;
  final MediaMetadata? metadata;
  final JobStatus status;
  final String? outputPath;
  final String? error;
  final double progress;

  MediaJob copyWith({
    String? id,
    String? inputPath,
    MediaKind? kind,
    String? displayName,
    MediaSource? source,
    MediaMetadata? metadata,
    JobStatus? status,
    String? outputPath,
    String? error,
    double? progress,
    bool clearOutput = false,
    bool clearError = false,
  }) {
    return MediaJob(
      id: id ?? this.id,
      inputPath: inputPath ?? this.inputPath,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      source: source ?? this.source,
      metadata: metadata ?? this.metadata,
      status: status ?? this.status,
      outputPath: clearOutput ? null : outputPath ?? this.outputPath,
      error: clearError ? null : error ?? this.error,
      progress: progress ?? this.progress,
    );
  }
}

enum MediaSource { files, photos }

extension MediaSourceX on MediaSource {
  String get label => this == MediaSource.files ? 'Files' : 'Photos';
}

enum JobStatus { pending, processing, complete, failed }

extension JobStatusX on JobStatus {
  String get label => switch (this) {
    JobStatus.pending => 'Pending',
    JobStatus.processing => 'Processing',
    JobStatus.complete => 'Complete',
    JobStatus.failed => 'Failed',
  };
}
