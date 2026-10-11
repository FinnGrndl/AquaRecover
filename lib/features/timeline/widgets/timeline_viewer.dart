import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';

import '../../../core/timeline/timeline_project.dart';
import '../../editor/widgets/gpu_preview_filter.dart';
import '../../editor/widgets/restored_image_preview.dart';
import '../timeline_theme.dart';

/// Shows the frame under the playhead in the project's aspect ratio.
///
/// Photos use the accurate still renderer (with the slow zoom applied as a
/// transform). Videos use the platform player with a colour-matrix preview of
/// the grade, so scrubbing and playback stay real time; the export applies the
/// full grade.
class TimelineViewer extends StatelessWidget {
  const TimelineViewer({
    super.key,
    required this.project,
    required this.playhead,
    required this.playing,
    this.onVideoDuration,
  });

  final TimelineProject project;
  final double playhead;
  final bool playing;
  final void Function(String clipId, double seconds)? onVideoDuration;

  @override
  Widget build(BuildContext context) {
    final entry = project.layout.entryAt(playhead);
    final aspect = project.aspect.widthRatio / project.aspect.heightRatio;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.black,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: TimelineColors.stroke, width: .7),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: .35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: entry == null
                ? project.clips.isEmpty
                      ? const SizedBox.expand()
                      : const Center(
                          child: Icon(
                            CupertinoIcons.film,
                            color: TimelineColors.secondaryText,
                            size: 40,
                          ),
                        )
                : _frameFor(entry),
          ),
        ),
      ),
    );
  }

  Widget _frameFor(TimelineEntry entry) {
    final clip = entry.clip;
    if (clip.isVideo) {
      return _VideoFrame(
        key: ValueKey('video-${clip.path}'),
        clip: clip,
        localTime: entry.localTime(playhead),
        playing: playing,
        onDuration: (seconds) => onVideoDuration?.call(clip.id, seconds),
      );
    }
    final progress = clip.duration <= 0
        ? 0.0
        : (entry.localTime(playhead) / clip.duration).clamp(0.0, 1.0);
    final zoom = switch (clip.motion) {
      ClipMotion.none => 1.0,
      ClipMotion.zoomIn => 1 + 0.15 * progress,
      ClipMotion.zoomOut => 1.15 - 0.15 * progress,
    };
    return Transform.scale(
      scale: zoom,
      child: RestoredImagePreview(
        key: ValueKey('photo-${clip.id}'),
        path: clip.path,
        settings: clip.grade,
        lutProfile: clip.look,
        fit: clip.motion == ClipMotion.none ? BoxFit.contain : BoxFit.cover,
        maxDimension: 1280,
      ),
    );
  }
}

class _VideoFrame extends StatefulWidget {
  const _VideoFrame({
    super.key,
    required this.clip,
    required this.localTime,
    required this.playing,
    required this.onDuration,
  });

  final TimelineClip clip;
  final double localTime;
  final bool playing;
  final ValueChanged<double> onDuration;

  @override
  State<_VideoFrame> createState() => _VideoFrameState();
}

class _VideoFrameState extends State<_VideoFrame> {
  late final VideoPlayerController _player;
  bool _ready = false;
  bool _seeking = false;
  Duration? _pendingSeek;

  Duration get _target => Duration(
    microseconds: ((widget.clip.sourceStart + widget.localTime) * 1e6).round(),
  );

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(File(widget.clip.path));
    _player
        .initialize()
        .then((_) async {
          if (!mounted) return;
          widget.onDuration(_player.value.duration.inMicroseconds / 1e6);
          await _player.setVolume(widget.clip.muted ? 0 : 1);
          await _player.seekTo(_target);
          if (widget.playing) await _player.play();
          if (mounted) setState(() => _ready = true);
        })
        .catchError((Object _) {});
  }

  @override
  void didUpdateWidget(_VideoFrame old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    if (old.clip.muted != widget.clip.muted) {
      unawaited(_player.setVolume(widget.clip.muted ? 0 : 1));
    }
    if (widget.playing && !old.playing) {
      unawaited(_player.seekTo(_target).then((_) => _player.play()));
    } else if (!widget.playing) {
      if (old.playing) unawaited(_player.pause());
      if (old.localTime != widget.localTime ||
          old.clip.sourceStart != widget.clip.sourceStart) {
        _seek(_target);
      }
    }
  }

  /// Coalesces scrub seeks so only the newest position is decoded.
  void _seek(Duration target) {
    _pendingSeek = target;
    if (_seeking) return;
    _seeking = true;
    () async {
      try {
        while (_pendingSeek != null && mounted) {
          final next = _pendingSeek!;
          _pendingSeek = null;
          await _player.seekTo(next);
        }
      } on Object {
        // A seek can fail while the clip is being replaced.
      } finally {
        _seeking = false;
      }
    }();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CupertinoActivityIndicator());
    }
    final ratio = _player.value.aspectRatio <= 0
        ? 16 / 9
        : _player.value.aspectRatio;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(
        GpuPreviewFilter.matrixFor(widget.clip.grade),
      ),
      child: Center(
        child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(_player)),
      ),
    );
  }
}
