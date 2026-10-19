import 'dart:math' as math;

import '../models/lut_profile.dart';
import '../models/restoration_settings.dart';
import 'timeline_effects.dart';
import 'timeline_json.dart';
import 'timeline_timing.dart';

/// What an overlay item shows.
enum OverlayKind { video, image, text }

/// How an overlay enters or leaves, over [OverlayAnimation.seconds].
enum OverlayAnimation {
  none('None'),

  /// Opacity 0 → 1 (in) or 1 → 0 (out).
  fade('Fade'),

  /// Moves up by 8 % of the canvas height while fading.
  slideUp('Slide up'),

  /// Scales 0.6 → 1.08 → 1 about its centre while fading.
  pop('Pop');

  const OverlayAnimation(this.label);

  final String label;

  /// Length of every in or out animation.
  static const seconds = 0.4;
}

/// Look of a title.
enum TitleStyle {
  classic('Classic'),
  boldBox('Box'),
  outline('Outline'),
  caption('Caption'),
  diveStamp('Dive stamp');

  const TitleStyle(this.label);

  final String label;
}

enum TitleAlign { left, center, right }

/// Text and styling of a title overlay. Titles are rasterised in Dart (see
/// `timeline_textures.dart`), so every renderer shows identical pixels.
class TitleSpec {
  const TitleSpec({
    required this.text,
    this.style = TitleStyle.classic,
    this.color = 0xFFFFFFFF,
    this.backgroundColor = 0xB3000000,
    this.fontScale = defaultFontScale,
    this.align = TitleAlign.center,
    this.bold = true,
  });

  static const defaultFontScale = 0.075;

  /// The text; `\n` starts a new line. A [TitleStyle.diveStamp] shows the
  /// first line large and the rest as a smaller second line.
  final String text;
  final TitleStyle style;

  /// Text colour as ARGB.
  final int color;

  /// Box colour as ARGB, used by [TitleStyle.boldBox] and
  /// [TitleStyle.caption].
  final int backgroundColor;

  /// Font size as a fraction of the canvas height.
  final double fontScale;
  final TitleAlign align;
  final bool bold;

  TitleSpec copyWith({
    String? text,
    TitleStyle? style,
    int? color,
    int? backgroundColor,
    double? fontScale,
    TitleAlign? align,
    bool? bold,
  }) => TitleSpec(
    text: text ?? this.text,
    style: style ?? this.style,
    color: color ?? this.color,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    fontScale: fontScale ?? this.fontScale,
    align: align ?? this.align,
    bold: bold ?? this.bold,
  );

  Map<String, Object?> toJson() => {
    'text': text,
    'style': style.name,
    'color': color,
    'backgroundColor': backgroundColor,
    'fontScale': fontScale,
    'align': align.name,
    'bold': bold,
  };

  factory TitleSpec.fromJson(Map<String, Object?> json) => TitleSpec(
    text: json['text'] as String? ?? '',
    style: enumByName(TitleStyle.values, json['style'], TitleStyle.classic),
    color: jsonInt(json, 'color', 0xFFFFFFFF) & 0xFFFFFFFF,
    backgroundColor: jsonInt(json, 'backgroundColor', 0xB3000000) & 0xFFFFFFFF,
    fontScale: jsonDouble(
      json,
      'fontScale',
      defaultFontScale,
    ).clamp(0.01, 0.5).toDouble(),
    align: enumByName(TitleAlign.values, json['align'], TitleAlign.center),
    bold: json['bold'] != false,
  );

  @override
  bool operator ==(Object other) =>
      other is TitleSpec &&
      other.text == text &&
      other.style == style &&
      other.color == color &&
      other.backgroundColor == backgroundColor &&
      other.fontScale == fontScale &&
      other.align == align &&
      other.bold == bold;

  @override
  int get hashCode =>
      Object.hash(text, style, color, backgroundColor, fontScale, align, bold);
}

/// A video, photo, or title on an overlay lane above the main track, placed at
/// an absolute timeline time with its own transform.
class TimelineOverlay {
  const TimelineOverlay({
    required this.id,
    required this.kind,
    this.lane = 0,
    this.start = 0,
    this.path,
    this.sourceStart = 0,
    this.sourceEnd,
    this.sourceDuration,
    this.stillSeconds = defaultStillSeconds,
    this.speed = 1,
    this.volume = 1,
    this.muted = false,
    this.grade,
    this.look = LutProfile.none,
    this.effects = const [],
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.widthFraction = 0.5,
    this.rotation = 0,
    this.opacity = 1,
    this.fadeIn = 0,
    this.fadeOut = 0,
    this.mediaAspect = 16 / 9,
    this.animationIn = OverlayAnimation.none,
    this.animationOut = OverlayAnimation.none,
    this.title,
  });

  static const defaultStillSeconds = 3.0;
  static const minSeconds = 0.1;
  static const minWidthFraction = 0.05;
  static const maxWidthFraction = 2.0;
  static const maxFadeSeconds = 3.0;

  final String id;
  final OverlayKind kind;

  /// Overlay lane, 0 being the lowest; higher lanes draw on top.
  final int lane;

  /// Timeline seconds where the item appears.
  final double start;

  /// Media file for [OverlayKind.video] and [OverlayKind.image].
  final String? path;

  /// Video in point in source seconds.
  final double sourceStart;

  /// Video out point in source seconds; `null` plays to [sourceDuration].
  final double? sourceEnd;

  /// Full length of the source video when known.
  final double? sourceDuration;

  /// How long a photo or title stays on screen.
  final double stillSeconds;

  /// Video playback speed, clamped to 0.25…4 by [playbackSpeed].
  final double speed;

  /// Audio level of a video overlay, 0…1.
  final double volume;
  final bool muted;

  /// Restoration grade; `null` leaves the overlay's colours as they are.
  final RestorationSettings? grade;
  final LutProfile look;

  /// Effects; only those with [EffectType.overlayAllowed] are rendered.
  final List<ClipEffect> effects;

  /// Centre of the item as a fraction of the canvas width and height.
  final double centerX, centerY;

  /// Width as a fraction of the canvas width, 0.05…2.
  final double widthFraction;

  /// Degrees, clockwise on screen.
  final double rotation;

  /// 0…1.
  final double opacity;

  /// Alpha fade lengths in seconds.
  final double fadeIn, fadeOut;

  /// Width / height of the source. For titles this is the rasterised title's
  /// aspect (see `measureTitle`).
  final double mediaAspect;
  final OverlayAnimation animationIn, animationOut;

  /// The title of an [OverlayKind.text] item.
  final TitleSpec? title;

  bool get isVideo => kind == OverlayKind.video;

  /// [speed] clamped to the supported range; 1 for photos and titles.
  double get playbackSpeed => isVideo ? TimelineSpeed.clamp(speed) : 1;

  /// Source seconds the item plays: the trimmed range of a video, or the
  /// still duration of a photo or title.
  double get sourceSpan {
    if (!isVideo) return stillSeconds;
    final end = sourceEnd ?? sourceDuration;
    if (end == null) return defaultStillSeconds;
    return math.max(0, end - sourceStart);
  }

  /// Seconds the item stays on the timeline.
  double get duration => math.max(minSeconds, sourceSpan / playbackSpeed);

  double get end => math.max(0, start) + duration;

  /// [fadeIn] and [fadeOut] clamped to 0…3 s and to [duration].
  ({double fadeIn, double fadeOut}) get fades =>
      resolveFades(fadeIn, fadeOut, duration, maxSeconds: maxFadeSeconds);

  /// Effective audio gain.
  double get gain => muted ? 0 : volume.clamp(0.0, 1.0).toDouble();

  /// The effects renderers apply to overlays.
  Iterable<ClipEffect> get renderedEffects =>
      effects.where((effect) => effect.type.overlayAllowed);

  /// Source time of a video for [localSeconds] into the item.
  double sourceTimeAt(double localSeconds) =>
      sourceStart + localSeconds * playbackSpeed;

  TimelineOverlay copyWith({
    String? id,
    int? lane,
    double? start,
    String? path,
    double? sourceStart,
    double? sourceEnd,
    bool clearSourceEnd = false,
    double? sourceDuration,
    double? stillSeconds,
    double? speed,
    double? volume,
    bool? muted,
    RestorationSettings? grade,
    bool clearGrade = false,
    LutProfile? look,
    List<ClipEffect>? effects,
    double? centerX,
    double? centerY,
    double? widthFraction,
    double? rotation,
    double? opacity,
    double? fadeIn,
    double? fadeOut,
    double? mediaAspect,
    OverlayAnimation? animationIn,
    OverlayAnimation? animationOut,
    TitleSpec? title,
  }) => TimelineOverlay(
    id: id ?? this.id,
    kind: kind,
    lane: lane ?? this.lane,
    start: start ?? this.start,
    path: path ?? this.path,
    sourceStart: sourceStart ?? this.sourceStart,
    sourceEnd: clearSourceEnd ? null : sourceEnd ?? this.sourceEnd,
    sourceDuration: sourceDuration ?? this.sourceDuration,
    stillSeconds: stillSeconds ?? this.stillSeconds,
    speed: speed ?? this.speed,
    volume: volume ?? this.volume,
    muted: muted ?? this.muted,
    grade: clearGrade ? null : grade ?? this.grade,
    look: look ?? this.look,
    effects: effects ?? this.effects,
    centerX: centerX ?? this.centerX,
    centerY: centerY ?? this.centerY,
    widthFraction: widthFraction ?? this.widthFraction,
    rotation: rotation ?? this.rotation,
    opacity: opacity ?? this.opacity,
    fadeIn: fadeIn ?? this.fadeIn,
    fadeOut: fadeOut ?? this.fadeOut,
    mediaAspect: mediaAspect ?? this.mediaAspect,
    animationIn: animationIn ?? this.animationIn,
    animationOut: animationOut ?? this.animationOut,
    title: title ?? this.title,
  );

  /// Splits the item at [localSeconds] from its start, or returns `null` when
  /// either half would be shorter than [minSeconds]. The first half keeps the
  /// in fade and animation, the second half the out ones.
  (TimelineOverlay, TimelineOverlay)? splitAt(
    double localSeconds, {
    required String newId,
  }) {
    if (localSeconds < minSeconds || duration - localSeconds < minSeconds) {
      return null;
    }
    final first = copyWith(fadeOut: 0, animationOut: OverlayAnimation.none);
    final second = copyWith(
      id: newId,
      start: math.max(0, start) + localSeconds,
      fadeIn: 0,
      animationIn: OverlayAnimation.none,
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
    'kind': kind.name,
    'lane': lane,
    'start': start,
    'path': path,
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
    'sourceDuration': sourceDuration,
    'stillSeconds': stillSeconds,
    'speed': speed,
    'volume': volume,
    'muted': muted,
    'grade': grade?.toJson(),
    'look': look.toJson(),
    'effects': [for (final effect in effects) effect.toJson()],
    'centerX': centerX,
    'centerY': centerY,
    'widthFraction': widthFraction,
    'rotation': rotation,
    'opacity': opacity,
    'fadeIn': fadeIn,
    'fadeOut': fadeOut,
    'mediaAspect': mediaAspect,
    'animationIn': animationIn.name,
    'animationOut': animationOut.name,
    'title': title?.toJson(),
  };

  factory TimelineOverlay.fromJson(Map<String, Object?> json) {
    final grade = jsonMap(json, 'grade');
    final look = jsonMap(json, 'look');
    final title = jsonMap(json, 'title');
    return TimelineOverlay(
      id: json['id'] as String,
      kind: enumByName(OverlayKind.values, json['kind'], OverlayKind.image),
      lane: math.max(0, jsonInt(json, 'lane', 0)),
      start: math.max(0, jsonDouble(json, 'start', 0)),
      path: json['path'] as String?,
      sourceStart: math.max(0, jsonDouble(json, 'sourceStart', 0)),
      sourceEnd: jsonOptionalDouble(json, 'sourceEnd'),
      sourceDuration: jsonOptionalDouble(json, 'sourceDuration'),
      stillSeconds: math.max(
        minSeconds,
        jsonDouble(json, 'stillSeconds', defaultStillSeconds),
      ),
      speed: TimelineSpeed.clamp(jsonDouble(json, 'speed', 1)),
      volume: jsonDouble(json, 'volume', 1).clamp(0.0, 1.0).toDouble(),
      muted: json['muted'] == true,
      grade: grade == null ? null : RestorationSettings.fromJson(grade),
      look: look == null ? LutProfile.none : LutProfile.fromJson(look),
      effects: ClipEffect.listFromJson(json, 'effects'),
      centerX: jsonDouble(json, 'centerX', 0.5),
      centerY: jsonDouble(json, 'centerY', 0.5),
      widthFraction: jsonDouble(
        json,
        'widthFraction',
        0.5,
      ).clamp(minWidthFraction, maxWidthFraction).toDouble(),
      rotation: jsonDouble(json, 'rotation', 0),
      opacity: jsonDouble(json, 'opacity', 1).clamp(0.0, 1.0).toDouble(),
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
      mediaAspect: math.max(0.01, jsonDouble(json, 'mediaAspect', 16 / 9)),
      animationIn: enumByName(
        OverlayAnimation.values,
        json['animationIn'],
        OverlayAnimation.none,
      ),
      animationOut: enumByName(
        OverlayAnimation.values,
        json['animationOut'],
        OverlayAnimation.none,
      ),
      title: title == null ? null : TitleSpec.fromJson(title),
    );
  }
}
