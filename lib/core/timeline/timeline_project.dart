import 'dart:math' as math;

import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import 'timeline_audio.dart';
import 'timeline_effects.dart';
import 'timeline_json.dart';
import 'timeline_overlay.dart';
import 'timeline_timing.dart';

export 'timeline_audio.dart';
export 'timeline_effects.dart';
export 'timeline_overlay.dart';
export 'timeline_timing.dart';

/// Output frame shape of a timeline.
enum TimelineAspect {
  landscape(16, 9, 'Landscape 16:9'),
  portrait(9, 16, 'Portrait 9:16'),
  square(1, 1, 'Square 1:1'),
  vertical45(4, 5, 'Portrait 4:5');

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

/// How a clip enters from the previous one. The names are stable JSON.
enum ClipTransition {
  cut,

  /// Dissolves over the previous clip; the clips overlap on the timeline.
  crossfade,

  /// Dips through black around the cut; the clips do not overlap.
  dipBlack,

  /// Dips through white around the cut; the clips do not overlap.
  dipWhite;

  bool get isDip => this == dipBlack || this == dipWhite;
}

/// Colour a clip fades in from and out to.
enum FadeColor {
  black(0xFF000000, 'Black'),
  white(0xFFFFFFFF, 'White'),
  deepBlue(0xFF06263F, 'Deep blue');

  const FadeColor(this.argb, this.label);

  final int argb;
  final String label;
}

/// Slow zoom for stills, the classic "Ken Burns" move.
enum ClipMotion { none, zoomIn, zoomOut }

/// One item on the main track: a photo shown for [stillSeconds] or the
/// `[sourceStart, sourceEnd)` range of a video played at [speed], with its own
/// grade, fades, and effects.
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
    this.speed = 1,
    this.volume = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.fadeColor = FadeColor.black,
    this.effects = const [],
  });

  static const defaultStillSeconds = 3.0;
  static const minSeconds = 0.5;
  static const maxStillSeconds = 30.0;
  static const maxFadeSeconds = 3.0;

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

  /// Drops this clip's audio. Photos never have audio. Kept next to
  /// [volume] for v1 projects; the effective level is [gain].
  final bool muted;

  /// Video playback speed; see [playbackSpeed]. Photos ignore it.
  final double speed;

  /// Audio level, 0…1.
  final double volume;

  /// Seconds the clip fades in from and out to [fadeColor]; see [fades].
  final double fadeIn, fadeOut;
  final FadeColor fadeColor;

  /// Effects in the order they apply.
  final List<ClipEffect> effects;

  bool get isVideo => kind == TimelineClipKind.video;

  /// [speed] clamped to 0.25…4 for videos; always 1 for photos.
  double get playbackSpeed => isVideo ? TimelineSpeed.clamp(speed) : 1;

  /// Source seconds this clip plays: the trimmed range of a video, or the
  /// still duration of a photo.
  double get sourceSpan {
    if (!isVideo) return stillSeconds;
    final end = sourceEnd ?? sourceDuration;
    if (end == null) return TimelineClip.defaultStillSeconds;
    return math.max(0, end - sourceStart);
  }

  /// Seconds this clip occupies before transitions overlap it: the source
  /// span divided by the speed for videos.
  double get duration {
    if (!isVideo) return stillSeconds;
    return math.max(minSeconds, sourceSpan / playbackSpeed);
  }

  /// Effective audio level: 0 when [muted], else [volume].
  double get gain => muted ? 0 : volume.clamp(0.0, 1.0).toDouble();

  /// [fadeIn] and [fadeOut] clamped to 0…3 s and so they fit in [duration].
  ({double fadeIn, double fadeOut}) get fades =>
      resolveFades(fadeIn, fadeOut, duration, maxSeconds: maxFadeSeconds);

  /// Source time of a video for [localSeconds] into the clip.
  double sourceTimeAt(double localSeconds) =>
      sourceStart + localSeconds * playbackSpeed;

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
    String? id,
    double? speed,
    double? volume,
    double? fadeIn,
    double? fadeOut,
    FadeColor? fadeColor,
    List<ClipEffect>? effects,
  }) => TimelineClip(
    id: id ?? this.id,
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
    speed: speed ?? this.speed,
    volume: volume ?? this.volume,
    fadeIn: fadeIn ?? this.fadeIn,
    fadeOut: fadeOut ?? this.fadeOut,
    fadeColor: fadeColor ?? this.fadeColor,
    effects: effects ?? this.effects,
  );

  /// Splits the clip at [localSeconds] from its start, or returns `null` when
  /// either half would be shorter than [minSeconds]. A video is cut at source
  /// time `sourceStart + localSeconds × speed`. Both halves keep speed,
  /// volume, effects, grade, and look; the first keeps the transition and the
  /// fade in, the second the fade out and enters with a cut.
  (TimelineClip, TimelineClip)? splitAt(
    double localSeconds, {
    required String newId,
  }) {
    if (localSeconds < minSeconds || duration - localSeconds < minSeconds) {
      return null;
    }
    final first = copyWith(fadeOut: 0);
    final second = copyWith(
      id: newId,
      transition: ClipTransition.cut,
      fadeIn: 0,
    );
    if (isVideo) {
      final cut = sourceTimeAt(localSeconds);
      return (
        first.copyWith(sourceEnd: cut),
        second.copyWith(sourceStart: cut),
      );
    }
    return (
      first.copyWith(stillSeconds: localSeconds),
      second.copyWith(stillSeconds: stillSeconds - localSeconds),
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
    'speed': speed,
    'volume': volume,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
    'fadeColor': fadeColor.name,
    'effects': [for (final effect in effects) effect.toJson()],
  };

  factory TimelineClip.fromJson(Map<String, Object?> json) => TimelineClip(
    id: json['id'] as String,
    path: json['path'] as String,
    kind: enumByName(
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
    transition: enumByName(
      ClipTransition.values,
      json['transition'],
      ClipTransition.cut,
    ),
    motion: enumByName(ClipMotion.values, json['motion'], ClipMotion.none),
    muted: json['muted'] == true,
    speed: TimelineSpeed.clamp(jsonDouble(json, 'speed', 1)),
    volume: jsonDouble(json, 'volume', 1).clamp(0.0, 1.0).toDouble(),
    fadeIn: jsonDouble(json, 'fadeIn', 0).clamp(0.0, maxFadeSeconds).toDouble(),
    fadeOut: jsonDouble(
      json,
      'fadeOut',
      0,
    ).clamp(0.0, maxFadeSeconds).toDouble(),
    fadeColor: enumByName(FadeColor.values, json['fadeColor'], FadeColor.black),
    effects: ClipEffect.listFromJson(json, 'effects'),
  );
}

/// A short video assembled from photos and clips on a magnetic main track,
/// each with its own grade, plus overlay lanes (video, photos, titles) and
/// audio lanes placed at absolute times.
class TimelineProject {
  const TimelineProject({
    required this.id,
    this.name = 'Untitled dive',
    this.aspect = TimelineAspect.landscape,
    this.quality = TimelineQuality.fullHd,
    this.frameRate = 30,
    this.transitionSeconds = 0.6,
    this.clips = const [],
    this.overlays = const [],
    this.audioClips = const [],
  });

  /// Version 2 added speed, volume, fades, effects, dip transitions, overlays,
  /// and audio items; version 1 files load with their defaults.
  static const formatVersion = 2;

  final String id;
  final String name;
  final TimelineAspect aspect;
  final TimelineQuality quality;
  final int frameRate;
  final double transitionSeconds;
  final List<TimelineClip> clips;

  /// Overlay items; the compiler trims them to [duration].
  final List<TimelineOverlay> overlays;

  /// Audio items; the compiler trims them to [duration].
  final List<TimelineAudioClip> audioClips;

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

  /// Length of the movie: the main track's length.
  double get duration => layout.duration;

  TimelineProject copyWith({
    String? name,
    TimelineAspect? aspect,
    TimelineQuality? quality,
    int? frameRate,
    double? transitionSeconds,
    List<TimelineClip>? clips,
    List<TimelineOverlay>? overlays,
    List<TimelineAudioClip>? audioClips,
  }) => TimelineProject(
    id: id,
    name: name ?? this.name,
    aspect: aspect ?? this.aspect,
    quality: quality ?? this.quality,
    frameRate: frameRate ?? this.frameRate,
    transitionSeconds: transitionSeconds ?? this.transitionSeconds,
    clips: clips ?? this.clips,
    overlays: overlays ?? this.overlays,
    audioClips: audioClips ?? this.audioClips,
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
    'overlays': [for (final overlay in overlays) overlay.toJson()],
    'audio': [for (final audio in audioClips) audio.toJson()],
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
      aspect: enumByName(
        TimelineAspect.values,
        json['aspect'],
        TimelineAspect.landscape,
      ),
      quality: enumByName(
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
      overlays: [
        for (final overlay in jsonMaps(json, 'overlays'))
          TimelineOverlay.fromJson(overlay),
      ],
      audioClips: [
        for (final audio in jsonMaps(json, 'audio'))
          TimelineAudioClip.fromJson(audio),
      ],
    );
  }
}

/// Where each main-track clip sits on the output timeline, using each clip's
/// speed-aware [TimelineClip.duration].
///
/// A crossfade overlaps a clip with the previous one by the project's
/// transition length, clamped so neither clip is more than half consumed. Dip
/// transitions do not overlap; they are drawn as colour layers by the
/// compiler.
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

  /// Source seconds of a video shown at timeline time [seconds].
  double sourceTime(double seconds) => clip.sourceTimeAt(localTime(seconds));
}
