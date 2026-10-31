import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/widgets/app_tooltip.dart';
import '../../../l10n/l10n.dart';

class VideoPreviewTile extends StatefulWidget {
  const VideoPreviewTile({super.key, required this.path});
  final String path;
  @override
  State<VideoPreviewTile> createState() => _VideoPreviewTileState();
}

class _VideoPreviewTileState extends State<VideoPreviewTile> {
  VideoPlayerController? _controller;
  Future<void>? _initFuture;
  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(VideoPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller?.dispose();
      _open();
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
    _initFuture = controller.initialize().then((_) {
      controller.setLooping(true);
      if (mounted) {
        setState(() {});
      }
    });
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
          // Light text: the tile sits on black, and on Windows, which has
          // no video_player, this is what people see.
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                context.l10n.videoPreviewUnavailable,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xb8ffffff)),
              ),
            ),
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: controller.value.aspectRatio <= 0
                  ? 16 / 9
                  : controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
            Positioned(
              bottom: 12,
              child: AppTooltip(
                message: controller.value.isPlaying
                    ? context.l10n.pause
                    : context.l10n.play,
                child: Semantics(
                  button: true,
                  label: controller.value.isPlaying
                      ? context.l10n.pause
                      : context.l10n.play,
                  excludeSemantics: true,
                  child: CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 7,
                    ),
                    onPressed: () => setState(
                      () => controller.value.isPlaying
                          ? controller.pause()
                          : controller.play(),
                    ),
                    child: Icon(
                      controller.value.isPlaying
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
