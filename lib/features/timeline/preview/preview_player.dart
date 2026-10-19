import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'preview_math.dart';

/// The part of a media player the preview drives. [VideoPreviewPlayer] wraps
/// `video_player`; tests pass fakes through a [PreviewPlayerFactory].
abstract class PreviewPlayer {
  String get path;
  bool get isInitialized;

  /// Decoded frame size; [Size.zero] until initialised.
  Size get size;
  Duration get duration;

  /// Last position the platform reported.
  Duration get position;

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setPlaybackSpeed(double speed);

  /// The decoded frames, sized by its parent.
  Widget buildView();
  Future<void> dispose();
}

/// Creates a player for the media file at [path].
typedef PreviewPlayerFactory = PreviewPlayer Function(String path);

/// A [PreviewPlayer] backed by `video_player` (AVPlayer, ExoPlayer). It also
/// plays audio-only files on iOS, Android, and macOS.
class VideoPreviewPlayer implements PreviewPlayer {
  VideoPreviewPlayer(this.path)
    : _controller = VideoPlayerController.file(File(path));

  @override
  final String path;
  final VideoPlayerController _controller;

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  Size get size => _controller.value.size;

  @override
  Duration get duration => _controller.value.duration;

  @override
  Duration get position => _controller.value.position;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _controller.setVolume(volume);

  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _controller.setPlaybackSpeed(speed);

  @override
  Widget buildView() => VideoPlayer(_controller);

  @override
  Future<void> dispose() => _controller.dispose();
}

/// Seconds since an arbitrary start; injectable so tests control time.
typedef PreviewClock = double Function();

/// A monotonic [PreviewClock].
PreviewClock stopwatchClock() {
  final watch = Stopwatch()..start();
  return () => watch.elapsedMicroseconds / 1e6;
}

/// One pooled player and what the preview last asked of it, so each frame
/// only sends the platform calls that change something: coalesced seeks
/// while scrubbing, a seek during playback only when the predicted position
/// drifts more than [driftTolerance], and throttled volume changes.
class PreviewPlayerSlot {
  PreviewPlayerSlot(this.id, this.player, {required this.lastUsed});

  /// Seek during playback when the player is this far off, in seconds.
  static const driftTolerance = 0.1;

  /// Time a player gets after a seek or start before drift is judged.
  static const settleSeconds = 0.4;

  /// The item the player currently serves (a clip, layer, or audio id).
  String id;
  final PreviewPlayer player;
  double lastUsed;
  bool ready = false;
  bool failed = false;
  bool disposed = false;

  bool _playing = false;
  double? _speed;
  double? _volume;
  double _volumeAt = double.negativeInfinity;
  double? _target;
  double? _pendingSeek;
  bool _seeking = false;
  double _settleUntil = double.negativeInfinity;
  Duration? _reported;
  double _anchor = 0;
  double _anchorAt = 0;
  double? _parkedAt;

  bool get isPlaying => _playing;
  double? get volume => _volume;

  String get path => player.path;

  /// Source seconds the player is most likely showing at [now]: its last
  /// reported position advanced by the time since the report.
  double predictedPosition(double now) {
    final reported = player.position;
    if (reported != _reported) {
      _reported = reported;
      _anchor = reported.inMicroseconds / 1e6;
      _anchorAt = now;
    }
    if (!_playing) return _anchor;
    return _anchor + (now - _anchorAt) * (_speed ?? 1);
  }

  /// Paused on the frame at source second [target] (scrubbing). Seeks are
  /// coalesced so only the newest position is decoded.
  void showPaused(double target) {
    if (!ready) return;
    final wasPlaying = _playing;
    if (wasPlaying) {
      _playing = false;
      _call(player.pause());
    }
    _parkedAt = null;
    if (!wasPlaying && _target != null && (target - _target!).abs() < 1e-4) {
      return;
    }
    _seek(target);
  }

  /// Waiting paused at source second [target] for its turn (prepared ahead
  /// of the playhead); seeks once.
  void park(double target) {
    if (!ready) return;
    if (_playing) {
      _playing = false;
      _call(player.pause());
    }
    if (_parkedAt != null && (_parkedAt! - target).abs() < 1e-3) return;
    _parkedAt = target;
    _seek(target);
  }

  /// Stops playback without moving.
  void pause() {
    if (!ready || !_playing) return;
    _playing = false;
    _call(player.pause());
  }

  /// Playing at [speed] so that it shows source second [target] at [now],
  /// at [volume].
  void showPlaying(
    double target, {
    required double now,
    required double speed,
    required double volume,
  }) {
    if (!ready) return;
    _parkedAt = null;
    if (_speed != speed) {
      _speed = speed;
      _call(player.setPlaybackSpeed(speed));
    }
    setVolume(volume, now: now);
    if (!_playing) {
      final predicted = predictedPosition(now);
      if (_target == null || (predicted - target).abs() > 1 / 30) {
        _seek(target, now: now);
      }
      _playing = true;
      _settleUntil = now + settleSeconds;
      _call(player.play());
      return;
    }
    if (now < _settleUntil || _seeking) return;
    if ((predictedPosition(now) - target).abs() > driftTolerance) {
      _seek(target, now: now);
      _settleUntil = now + settleSeconds;
    }
  }

  /// Sets the volume when [PreviewAudioMath.shouldSetVolume] says so.
  void setVolume(double volume, {required double now}) {
    if (!ready) return;
    if (!PreviewAudioMath.shouldSetVolume(
      current: _volume,
      next: volume,
      lastSetAt: _volumeAt,
      now: now,
    )) {
      return;
    }
    _volume = volume;
    _volumeAt = now;
    _call(player.setVolume(volume));
  }

  void _seek(double seconds, {double? now}) {
    _target = seconds;
    // Predict from the target until the player reports a new position.
    _reported = player.position;
    _anchor = seconds;
    if (now != null) _anchorAt = now;
    _pendingSeek = seconds;
    if (_seeking) return;
    _seeking = true;
    unawaited(_drainSeeks());
  }

  Future<void> _drainSeeks() async {
    try {
      while (_pendingSeek != null && !disposed) {
        final next = _pendingSeek!;
        _pendingSeek = null;
        await player.seekTo(Duration(microseconds: (next * 1e6).round()));
      }
    } on Object {
      // A seek can fail while the player is being replaced.
    } finally {
      _seeking = false;
    }
  }

  /// Releases the player; safe to call twice.
  void dispose() {
    if (disposed) return;
    disposed = true;
    _pendingSeek = null;
    _call(player.dispose());
  }

  static void _call(Future<void> future) {
    unawaited(future.catchError((Object _) {}));
  }
}
