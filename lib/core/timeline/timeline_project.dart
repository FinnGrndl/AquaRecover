import 'dart:math' as math;

import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';

/// Output frame shape of a timeline.
enum TimelineAspect {
  landscape(16, 9, 'Landscape 16:9'),
  portrait(9, 16, 'Portrait 9:16'),
  square(1, 1, 'Square 1:1');

  const TimelineAspect(this.widthRatio, this.heightRatio, this.label);

  final int widthRatio;
  final int heightRatio;
  final String label;
}

/// Output resolution, named by the short side.
enum TimelineQuality {
  hd(720, '720p'),
  fullHd(1080, '1080p'),
  uhd(2160, '4K');

  const TimelineQuality(this.shortSide, this.label);

  final int shortSide;
  final String label;
}

enum TimelineClipKind { image, video }

/// How a clip enters from the previous one.
enum ClipTransition { cut, crossfade }

/// Slow zoom for stills, the classic "Ken Burns" move.
enum ClipMotion { none, zoomIn, zoomOut }

/// One item on the timeline: a photo shown for [stillSeconds] or the
/// `[sourceStart, sourceEnd)` range of a video, with its own grade.
class TimelineClip {
  const TimelineClip({
    required this.id,
    required this.path,
    required this.kind,
    this.sourceStart = 0,
    this.sourceEnd,
    this.sourceDuration,
    this.stillSeconds = defaultStillSeconds,
    this.grade = const RestorationSettings(),
    this.look = LutProfile.none,
    this.transition = ClipTransition.cut,
    this.motion = ClipMotion.none,
    this.muted = false,
  });

  static const defaultStillSeconds = 3.0;
  static const minSeconds = 0.5;
  static const maxStillSeconds = 30.0;

  final String id;
  final String path;
  final TimelineClipKind kind;

  /// Video in point in source seconds.
  final double sourceStart;

  /// Video out point in source seconds; `null` plays to [sourceDuration].
  final double? sourceEnd;

  /// Full length of the source video when known.
  final double? sourceDuration;

  /// How long a photo stays on screen.
  final double stillSeconds;

  final RestorationSettings grade;
  final LutProfile look;
  final ClipTransition transition;
  final ClipMotion motion;

  /// Drops this clip's audio. Photos never have audio.
  final bool muted;

  bool get isVideo => kind == TimelineClipKind.video;

  /// Seconds this clip occupies before transitions overlap it.
  double get duration {
    if (!isVideo) return stillSeconds;
    final end = sourceEnd ?? sourceDuration;
    if (end == null) return TimelineClip.defaultStillSeconds;
    return math.max(minSeconds, end - sourceStart);
  }

  TimelineClip copyWith({
    String? path,
    double? sourceStart,
    double? sourceEnd,
    bool clearSourceEnd = false,
    double? sourceDuration,
    double? stillSeconds,
    RestorationSettings? grade,
    LutProfile? look,
    ClipTransition? transition,
    ClipMotion? motion,
    bool? muted,
  }) => TimelineClip(
    id: id,
    path: path ?? this.path,
    kind: kind,
    sourceStart: sourceStart ?? this.sourceStart,
    sourceEnd: clearSourceEnd ? null : sourceEnd ?? this.sourceEnd,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    stillSeconds: stillSeconds ?? this.stillSeconds,
    grade: grade ?? this.grade,
    look: look ?? this.look,
    transition: transition ?? this.transition,
    motion: motion ?? this.motion,
    muted: muted ?? this.muted,
  );

  /// Splits the clip at [localSeconds] from its start, or returns `null` when
  /// either half would be shorter than [minSeconds].
  (TimelineClip, TimelineClip)? splitAt(
    double localSeconds, {
    required String newId,
  }) {
    if (localSeconds < minSeconds || duration - localSeconds < minSeconds) {
      return null;
    }
    if (isVideo) {
      final cut = sourceStart + localSeconds;
      return (
        copyWith(sourceEnd: cut),
        TimelineClip(
          id: newId,
          path: path,
          kind: kind,
          sourceStart: cut,
          sourceEnd: sourceEnd,
          sourceDuration: sourceDuration,
          grade: grade,
          look: look,
          motion: motion,
          muted: muted,
        ),
      );
    }
    return (
      copyWith(stillSeconds: localSeconds),
      TimelineClip(
        id: newId,
        path: path,
        kind: kind,
        stillSeconds: stillSeconds - localSeconds,
        grade: grade,
        look: look,
        motion: motion,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'kind': kind.name,
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
    'sourceDuration': sourceDuration,
    'stillSeconds': stillSeconds,
    'grade': grade.toJson(),
    'look': look.toJson(),
    'transition': transition.name,
    'motion': motion.name,
    'muted': muted,
  };

  factory TimelineClip.fromJson(Map<String, Object?> json) => TimelineClip(
    id: json['id'] as String,
    path: json['path'] as String,
    kind: _enumByName(
      TimelineClipKind.values,
      json['kind'],
      TimelineClipKind.image,
    ),
    sourceStart: (json['sourceStart'] as num?)?.toDouble() ?? 0,
    sourceEnd: (json['sourceEnd'] as num?)?.toDouble(),
    sourceDuration: (json['sourceDuration'] as num?)?.toDouble(),
    stillSeconds:
        (json['stillSeconds'] as num?)?.toDouble() ?? defaultStillSeconds,
    grade: json['grade'] is Map
        ? RestorationSettings.fromJson(
            (json['grade'] as Map).cast<String, Object?>(),
          )
        : const RestorationSettings(),
    look: json['look'] is Map
        ? LutProfile.fromJson((json['look'] as Map).cast<String, Object?>())
        : LutProfile.none,
    transition: _enumByName(
      ClipTransition.values,
      json['transition'],
      ClipTransition.cut,
    ),
    motion: _enumByName(ClipMotion.values, json['motion'], ClipMotion.none),
    muted: json['muted'] == true,
  );
}

/// A short video assembled from photos and clips, each with its own grade.
class TimelineProject {
  const TimelineProject({
    required this.id,
    this.name = 'Untitled dive',
    this.aspect = TimelineAspect.landscape,
    this.quality = TimelineQuality.fullHd,
    this.frameRate = 30,
    this.transitionSeconds = 0.6,
    this.clips = const [],
  });

  static const formatVersion = 1;

  final String id;
  final String name;
  final TimelineAspect aspect;
  final TimelineQuality quality;
  final int frameRate;
  final double transitionSeconds;
  final List<TimelineClip> clips;

  /// Output size in pixels, even on both sides for H.264.
  ({int width, int height}) get outputSize {
    final short = quality.shortSide;
    final w = aspect.widthRatio, h = aspect.heightRatio;
    int even(double v) => (v / 2).round() * 2;
    return w >= h
        ? (width: even(short * w / h), height: short)
        : (width: short, height: even(short * h / w));
  }

  TimelineLayout get layout => TimelineLayout.of(this);

  double get duration => layout.duration;

  TimelineProject copyWith({
    String? name,
    TimelineAspect? aspect,
    TimelineQuality? quality,
    int? frameRate,
    double? transitionSeconds,
    List<TimelineClip>? clips,
  }) => TimelineProject(
    id: id,
    name: name ?? this.name,
    aspect: aspect ?? this.aspect,
    quality: quality ?? this.quality,
    frameRate: frameRate ?? this.frameRate,
    transitionSeconds: transitionSeconds ?? this.transitionSeconds,
    clips: clips ?? this.clips,
  );

  Map<String, Object?> toJson() => {
    'format': 'aquarecover.timeline',
    'version': formatVersion,
    'id': id,
    'name': name,
    'aspect': aspect.name,
    'quality': quality.name,
    'frameRate': frameRate,
    'transitionSeconds': transitionSeconds,
    'clips': [for (final clip in clips) clip.toJson()],
  };

  factory TimelineProject.fromJson(Map<String, Object?> json) {
    final version = (json['version'] as num?)?.toInt() ?? formatVersion;
    if (version > formatVersion) {
      throw FormatException(
        'This timeline was saved by a newer AquaRecover (format $version).',
      );
    }
    return TimelineProject(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled dive',
      aspect: _enumByName(
        TimelineAspect.values,
        json['aspect'],
        TimelineAspect.landscape,
      ),
      quality: _enumByName(
        TimelineQuality.values,
        json['quality'],
        TimelineQuality.fullHd,
      ),
      frameRate: ((json['frameRate'] as num?)?.toInt() ?? 30).clamp(12, 60),
      transitionSeconds:
          ((json['transitionSeconds'] as num?)?.toDouble() ?? 0.6)
              .clamp(0.1, 2.0)
              .toDouble(),
      clips: [
        for (final clip in (json['clips'] as List? ?? const []))
          TimelineClip.fromJson((clip as Map).cast<String, Object?>()),
      ],
    );
  }
}

/// Where each clip sits on the output timeline.
///
/// A crossfade overlaps a clip with the previous one by the project's
/// transition length, clamped so neither clip is more than half consumed.
class TimelineLayout {
  const TimelineLayout._(this.entries, this.duration);

  factory TimelineLayout.of(TimelineProject project) {
    final entries = <TimelineEntry>[];
    var cursor = 0.0;
    for (var i = 0; i < project.clips.length; i++) {
      final clip = project.clips[i];
      var overlap = 0.0;
      if (i > 0 && clip.transition == ClipTransition.crossfade) {
        final previous = project.clips[i - 1];
        overlap = math.min(
          project.transitionSeconds,
          math.min(previous.duration, clip.duration) / 2,
        );
      }
      final start = cursor - overlap;
      entries.add(
        TimelineEntry(
          index: i,
          clip: clip,
          start: start,
          end: start + clip.duration,
          overlapIn: overlap,
        ),
      );
      cursor = start + clip.duration;
    }
    return TimelineLayout._(List.unmodifiable(entries), cursor);
  }

  final List<TimelineEntry> entries;
  final double duration;

  /// The clip that owns [seconds] (the incoming one during a crossfade).
  TimelineEntry? entryAt(double seconds) {
    if (entries.isEmpty) return null;
    final t = seconds.clamp(0.0, duration);
    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].start <= t) return entries[i];
    }
    return entries.first;
  }
}

class TimelineEntry {
  const TimelineEntry({
    required this.index,
    required this.clip,
    required this.start,
    required this.end,
    required this.overlapIn,
  });

  final int index;
  final TimelineClip clip;
  final double start;
  final double end;

  /// Seconds this clip crossfades over the previous one.
  final double overlapIn;

  double get duration => end - start;

  /// Seconds into the clip for timeline time [seconds].
  double localTime(double seconds) =>
      (seconds - start).clamp(0.0, duration).toDouble();
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
