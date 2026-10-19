import 'package:flutter/cupertino.dart';

/// Colours of the movie editor. They follow the photo editor's dark glass
/// language: white text, system blue for selection and the primary action,
/// and translucent white fills for controls.
abstract final class TimelineColors {
  static const background = CupertinoColors.black;
  static const fill = Color(0x1affffff);
  static const stroke = Color(0x29ffffff);
  static const text = CupertinoColors.white;
  static const secondaryText = Color(0xb8ffffff);

  /// System blue in dark mode, as the photo editor resolves it.
  static const accent = Color(0xff0a84ff);
  static const playhead = CupertinoColors.white;
  static const photoClip = Color(0xff1f3f50);
  static const videoClip = Color(0xff2c3350);

  /// Lane items, dark enough for white labels (≥ 5:1): indigo for photo
  /// and video overlays, amber for titles, green for sound.
  static const overlayItem = Color(0xff3b3f8f);
  static const titleItem = Color(0xff8a6212);
  static const audioItem = Color(0xff1f6b43);

  /// System red in dark mode.
  static const danger = Color(0xffff453a);
}

/// The dark, system-blue theme the movie screens run in.
CupertinoThemeData timelineTheme(BuildContext context) =>
    CupertinoTheme.of(context).copyWith(
      brightness: Brightness.dark,
      primaryColor: CupertinoColors.activeBlue,
      scaffoldBackgroundColor: TimelineColors.background,
    );

String formatTimecode(double seconds, {bool tenths = true}) {
  final safe = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  final minutes = safe ~/ 60;
  final rest = safe - minutes * 60;
  final secondsText = tenths
      ? rest.toStringAsFixed(1).padLeft(4, '0')
      : rest.floor().toString().padLeft(2, '0');
  return '${minutes.toString().padLeft(2, '0')}:$secondsText';
}
