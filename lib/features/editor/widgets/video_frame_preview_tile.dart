import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';

import '../../../core/models/restoration_settings.dart';
import 'gpu_preview_filter.dart';

class VideoFramePreviewTile extends StatefulWidget {
  const VideoFramePreviewTile({
    super.key,
    required this.path,
    this.settings,
    this.caption = 'Representative frame',
    this.position,
    this.onDurationKnown,
    this.showCaption = true,
  });

  final String path;
  final RestorationSettings? settings;
  final String caption;
  final Duration? position;
  final ValueChanged<Duration>? onDurationKnown;
  final bool showCaption;

  static Duration representativePositionFor(Duration duration) {
    if (duration <= const Duration(seconds: 2)) return Duration.zero;
    final quarter = Duration(milliseconds: duration.inMilliseconds ~/ 4);
    return quarter > const Duration(seconds: 3)
        ? const Duration(seconds: 3)
        : quarter;
  }

  static Duration clampPosition(Duration position, Duration duration) {
    if (position <= Duration.zero || duration <= Duration.zero) {
      return Duration.zero;
    }
    final lastFrame = duration > const Duration(milliseconds: 50)
        ? duration - const Duration(milliseconds: 50)
        : Duration.zero;
    return position > lastFrame ? lastFrame : position;
  }

  @override
  State<VideoFramePreviewTile> createState() => _VideoFramePreviewTileState();
}

class _VideoFramePreviewTileState extends State<VideoFramePreviewTile> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  Duration _framePosition = Duration.zero;
  Duration? _pendingPosition;
  bool _seeking = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(VideoFramePreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller?.dispose();
      _open();
    } else if (oldWidget.position != widget.position &&
        widget.position != null) {
      _queueSeek(widget.position!);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _open() {
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    _initFuture = controller.initialize().then((_) async {
      if (!mounted || !identical(controller, _controller)) return;
      final duration = controller.value.duration;
      widget.onDurationKnown?.call(duration);
      _framePosition = VideoFramePreviewTile.clampPosition(
        widget.position ??
            VideoFramePreviewTile.representativePositionFor(duration),
        duration,
      );
      if (_framePosition > Duration.zero) {
        await controller.seekTo(_framePosition);
      }
      await controller.pause();
      if (mounted) setState(() {});
    });
  }

  void _queueSeek(Duration position) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _pendingPosition = VideoFramePreviewTile.clampPosition(
      position,
      controller.value.duration,
    );
    if (!_seeking) unawaited(_drainSeeks(controller));
  }

  Future<void> _drainSeeks(VideoPlayerController controller) async {
    _seeking = true;
    try {
      while (_pendingPosition != null && identical(controller, _controller)) {
        final target = _pendingPosition!;
        _pendingPosition = null;
        await controller.seekTo(target);
        await controller.pause();
        _framePosition = target;
      }
      if (mounted && identical(controller, _controller)) setState(() {});
    } on Object {
      // A stale seek can fail when the user switches queue items quickly.
    } finally {
      _seeking = false;
      if (_pendingPosition != null && identical(controller, _controller)) {
        _queueSeek(_pendingPosition!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CupertinoActivityIndicator());
    }
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CupertinoActivityIndicator());
        }
        if (snapshot.hasError || !controller.value.isInitialized) {
          return const Center(child: Text('Video frame preview unavailable.'));
        }
        final aspectRatio = controller.value.aspectRatio <= 0
            ? 16 / 9
            : controller.value.aspectRatio;
        Widget video = AspectRatio(
          aspectRatio: aspectRatio,
          child: VideoPlayer(controller),
        );
        final settings = widget.settings;
        if (settings != null) {
          video = ColorFiltered(
            colorFilter: ColorFilter.matrix(
              GpuPreviewFilter.matrixFor(settings),
            ),
            child: video,
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Center(child: video),
            if (widget.showCaption)
              Positioned(
                left: 10,
                bottom: 10,
                child: _label(context, _caption(controller.value.duration)),
              ),
          ],
        );
      },
    );
  }

  String _caption(Duration duration) {
    final frame = _format(_framePosition);
    final total = duration == Duration.zero ? null : _format(duration);
    return total == null ? widget.caption : '${widget.caption} $frame / $total';
  }

  String _format(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final secondsText = seconds.toString().padLeft(2, '0');
    return '$minutes:$secondsText';
  }

  Widget _label(BuildContext context, String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CupertinoColors.black.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text,
          style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
            color: CupertinoColors.white,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
