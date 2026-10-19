import 'dart:math' as math;

import 'timeline_json.dart';
import 'timeline_timing.dart';

/// Where an audio item came from, for icons and lane colours.
enum AudioRole {
  music('Music'),
  voiceover('Voiceover'),
  sound('Sound'),
  extracted('Extracted audio');

  const AudioRole(this.label);

  final String label;
}

/// A sound on an audio lane: music, a voiceover, an effect, or audio extracted
/// from a clip, placed at an absolute timeline time.
class TimelineAudioClip {
  const TimelineAudioClip({
    required this.id,
    required this.path,
    this.name = '',
    this.role = AudioRole.music,
    this.lane = 0,
    this.start = 0,
    this.sourceStart = 0,
    this.sourceEnd,
    this.sourceDuration,
    this.volume = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
  });

  static const defaultSeconds = 3.0;
  static const minSeconds = 0.1;
  static const maxFadeSeconds = 10.0;

  final String id;

  /// Display name, such as the file name or "Voiceover 2".
  final String name;
  final String path;
  final AudioRole role;

  /// Audio lane in the editor, 0 being the first.
  final int lane;

  /// Timeline seconds where the sound starts.
  final double start;

  /// In point in source seconds.
  final double sourceStart;

  /// Out point in source seconds; `null` plays to [sourceDuration].
  final double? sourceEnd;

  /// Full length of the source when known.
  final double? sourceDuration;

  /// 0…1.
  final double volume;

  /// Fade lengths in seconds.
  final double fadeIn, fadeOut;

  /// Seconds of the source that play.
  double get sourceSpan {
    final end = sourceEnd ?? sourceDuration;
    if (end == null) return defaultSeconds;
    return math.max(0, end - sourceStart);
  }

  /// Seconds the sound occupies on the timeline.
  double get duration => math.max(minSeconds, sourceSpan);

  double get end => math.max(0, start) + duration;

  /// [fadeIn] and [fadeOut] clamped to 0…10 s and to [duration].
  ({double fadeIn, double fadeOut}) get fades =>
      resolveFades(fadeIn, fadeOut, duration, maxSeconds: maxFadeSeconds);

  TimelineAudioClip copyWith({
    String? id,
    String? name,
    String? path,
    AudioRole? role,
    int? lane,
    double? start,
    double? sourceStart,
    double? sourceEnd,
    bool clearSourceEnd = false,
    double? sourceDuration,
    double? volume,
    double? fadeIn,
    double? fadeOut,
  }) => TimelineAudioClip(
    id: id ?? this.id,
    name: name ?? this.name,
    path: path ?? this.path,
    role: role ?? this.role,
    lane: lane ?? this.lane,
    start: start ?? this.start,
    sourceStart: sourceStart ?? this.sourceStart,
    sourceEnd: clearSourceEnd ? null : sourceEnd ?? this.sourceEnd,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    volume: volume ?? this.volume,
    fadeIn: fadeIn ?? this.fadeIn,
    fadeOut: fadeOut ?? this.fadeOut,
  );

  /// Splits the sound at [localSeconds] from its start, or returns `null`
  /// when either half would be shorter than [minSeconds]. The first half
  /// keeps the fade in, the second the fade out.
  (TimelineAudioClip, TimelineAudioClip)? splitAt(
    double localSeconds, {
    required String newId,
  }) {
    if (localSeconds < minSeconds || duration - localSeconds < minSeconds) {
      return null;
    }
    final cut = sourceStart + localSeconds;
    return (
      copyWith(sourceEnd: cut, fadeOut: 0),
      copyWith(
        id: newId,
        start: math.max(0, start) + localSeconds,
        sourceStart: cut,
        fadeIn: 0,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'role': role.name,
    'lane': lane,
    'start': start,
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
    'sourceDuration': sourceDuration,
    'volume': volume,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
  };

  factory TimelineAudioClip.fromJson(Map<String, Object?> json) =>
      TimelineAudioClip(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        path: json['path'] as String,
        role: enumByName(AudioRole.values, json['role'], AudioRole.music),
        lane: math.max(0, jsonInt(json, 'lane', 0)),
        start: math.max(0, jsonDouble(json, 'start', 0)),
        sourceStart: math.max(0, jsonDouble(json, 'sourceStart', 0)),
        sourceEnd: jsonOptionalDouble(json, 'sourceEnd'),
        sourceDuration: jsonOptionalDouble(json, 'sourceDuration'),
        volume: jsonDouble(json, 'volume', 1).clamp(0.0, 1.0).toDouble(),
        fadeIn: jsonDouble(
          json,
          'fadeIn',
          0,
        ).clamp(0.0, maxFadeSeconds).toDouble(),
        fadeOut: jsonDouble(
          json,
          'fadeOut',
          0,
        ).clamp(0.0, maxFadeSeconds).toDouble(),
      );
}
