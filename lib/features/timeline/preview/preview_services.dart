import 'dart:io';

import 'preview_player.dart';
import 'preview_textures.dart';

/// What the preview uses to decode and rasterise; the defaults are the
/// platform's. Widget tests pass fakes.
class PreviewServices {
  const PreviewServices({
    this.videoPlayer,
    this.audioPlayer,
    this.rasterize,
    this.audioEnabled,
    this.clock,
  });

  /// Creates video players; default `video_player`.
  final PreviewPlayerFactory? videoPlayer;

  /// Creates players for audio items; default `video_player`, which plays
  /// audio files on iOS, Android, and macOS.
  final PreviewPlayerFactory? audioPlayer;

  /// Rasterises titles and effect textures; default the export's rasteriser.
  final PreviewRasterizer? rasterize;

  /// Whether audio items play during preview; default only where
  /// `video_player` is implemented (not Windows or Linux).
  final bool? audioEnabled;

  /// Seconds clock for player sync; default a stopwatch.
  final PreviewClock? clock;

  PreviewPlayerFactory get videoPlayerFactory =>
      videoPlayer ?? VideoPreviewPlayer.new;

  PreviewPlayerFactory get audioPlayerFactory =>
      audioPlayer ?? VideoPreviewPlayer.new;

  bool get playsAudio => audioEnabled ?? platformHasPlayers;

  /// Whether `video_player` has an implementation on this platform.
  static bool get platformHasPlayers =>
      Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
}
