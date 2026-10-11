import 'package:flutter/cupertino.dart';

/// Colours of the dark, Resolve-inspired timeline workspace.
abstract final class TimelineColors {
  static const background = Color(0xff0e1013);
  static const panel = Color(0xff181b20);
  static const panelRaised = Color(0xff22262d);
  static const stroke = Color(0x22ffffff);
  static const text = Color(0xffeef2f5);
  static const secondaryText = Color(0x99eef2f5);
  static const accent = Color(0xff35b6e8);
  static const playhead = Color(0xffff5a4f);
  static const photoClip = Color(0xff2b5a73);
  static const videoClip = Color(0xff31406e);
  static const danger = Color(0xffff6b61);
}

String formatTimecode(double seconds, {bool tenths = true}) {
  final safe = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  final minutes = safe ~/ 60;
  final rest = safe - minutes * 60;
  final secondsText = tenths
      ? rest.toStringAsFixed(1).padLeft(4, '0')
      : rest.floor().toString().padLeft(2, '0');
  return '${minutes.toString().padLeft(2, '0')}:$secondsText';
}
