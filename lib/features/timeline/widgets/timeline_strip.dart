import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;

import '../../../core/timeline/timeline_project.dart';
import '../timeline_controller.dart';
import '../timeline_theme.dart';

/// The horizontal timeline. The playhead stays fixed in the centre and the
/// clips scroll under it, which keeps scrubbing one-handed on a phone. Pinch
/// to zoom changes the seconds-per-pixel scale.
class TimelineStrip extends StatefulWidget {
  const TimelineStrip({
    super.key,
    required this.controller,
    this.height = 92,
    this.onScrubStart,
  });

  final TimelineController controller;
  final double height;
  final VoidCallback? onScrubStart;

  @override
  State<TimelineStrip> createState() => _TimelineStripState();
}

class _TimelineStripState extends State<TimelineStrip> {
  final _scroll = ScrollController();
  double _pixelsPerSecond = 56;
  double _scaleStart = 56;
  bool _userScrolling = false;

  TimelineController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncToPlayhead);
  }

  @override
  void didUpdateWidget(TimelineStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncToPlayhead);
      widget.controller.addListener(_syncToPlayhead);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncToPlayhead);
    _scroll.dispose();
    super.dispose();
  }

  void _syncToPlayhead() {
    if (_userScrolling || !_scroll.hasClients) return;
    final target = _controller.playhead * _pixelsPerSecond;
    if ((_scroll.offset - target).abs() > 0.5) {
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
      widget.onScrubStart?.call();
    }
    if (_userScrolling && notification is ScrollUpdateNotification) {
      _controller.seek(_scroll.offset / _pixelsPerSecond);
    }
    if (notification is ScrollEndNotification) {
      _userScrolling = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final project = _controller.project;
        final layout = project.layout;
        return LayoutBuilder(
          builder: (context, constraints) {
            final half = constraints.maxWidth / 2;
            final contentWidth = layout.duration * _pixelsPerSecond;
            return GestureDetector(
              onScaleStart: (_) => _scaleStart = _pixelsPerSecond,
              onScaleUpdate: (details) {
                if (details.pointerCount < 2) return;
                setState(() {
                  _pixelsPerSecond = (_scaleStart * details.horizontalScale)
                      .clamp(12.0, 320.0);
                });
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _syncToPlayhead(),
                );
              },
              child: SizedBox(
                height: widget.height,
                child: Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: SingleChildScrollView(
                        key: const Key('timeline_strip_scroll'),
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: SizedBox(
                          width: contentWidth + half * 2,
                          height: widget.height,
                          child: Stack(
                            children: [
                              Positioned(
                                left: half,
                                width: contentWidth,
                                top: 0,
                                height: 18,
                                child: CustomPaint(
                                  painter: _RulerPainter(
                                    pixelsPerSecond: _pixelsPerSecond,
                                    duration: layout.duration,
                                  ),
                                ),
                              ),
                              for (final entry in layout.entries)
                                Positioned(
                                  left: half + entry.start * _pixelsPerSecond,
                                  width: (entry.duration * _pixelsPerSecond)
                                      .clamp(8.0, double.infinity),
                                  top: 22,
                                  bottom: 6,
                                  child: _ClipTile(
                                    entry: entry,
                                    selected:
                                        entry.clip.id ==
                                        _controller.selectedClip?.id,
                                    overlapWidth:
                                        entry.overlapIn * _pixelsPerSecond,
                                    onTap: () =>
                                        _controller.select(entry.clip.id),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (layout.entries.isEmpty)
                      const Center(
                        child: Text(
                          'Add photos or clips to start a movie',
                          style: TextStyle(
                            color: TimelineColors.secondaryText,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Positioned(
                      left: half - 1,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: const IgnorePointer(
                        child: ColoredBox(color: TimelineColors.playhead),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    required this.entry,
    required this.selected,
    required this.overlapWidth,
    required this.onTap,
  });

  final TimelineEntry entry;
  final bool selected;
  final double overlapWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final clip = entry.clip;
    final base = clip.isVideo
        ? TimelineColors.videoClip
        : TimelineColors.photoClip;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${clip.isVideo ? 'Clip' : 'Photo'} ${entry.index + 1}, '
          '${formatTimecode(clip.duration)}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? TimelineColors.accent : TimelineColors.stroke,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!clip.isVideo)
                Opacity(
                  opacity: .55,
                  child: Image.file(
                    File(clip.path),
                    fit: BoxFit.cover,
                    cacheHeight: 120,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              if (overlapWidth > 1)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: overlapWidth,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xcc000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          clip.isVideo
                              ? CupertinoIcons.film
                              : CupertinoIcons.photo,
                          size: 12,
                          color: TimelineColors.text,
                        ),
                        if (clip.motion != ClipMotion.none) ...[
                          const SizedBox(width: 3),
                          const Icon(
                            CupertinoIcons.zoom_in,
                            size: 12,
                            color: TimelineColors.text,
                          ),
                        ],
                        if (clip.muted) ...[
                          const SizedBox(width: 3),
                          const Icon(
                            CupertinoIcons.speaker_slash,
                            size: 12,
                            color: TimelineColors.text,
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    Text(
                      p.basenameWithoutExtension(clip.path),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        color: TimelineColors.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      formatTimecode(clip.duration),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        color: TimelineColors.secondaryText,
                        fontSize: 10,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({required this.pixelsPerSecond, required this.duration});

  final double pixelsPerSecond;
  final double duration;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = TimelineColors.secondaryText
      ..strokeWidth = 1;
    final step = pixelsPerSecond >= 40
        ? 1
        : pixelsPerSecond >= 15
        ? 5
        : 10;
    for (var s = 0; s <= duration + 0.001; s++) {
      final x = s * pixelsPerSecond;
      final major = s % step == 0;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - (major ? 7 : 3)),
        tick,
      );
      if (major) {
        final text = TextPainter(
          text: TextSpan(
            text: formatTimecode(s.toDouble(), tenths: false),
            style: const TextStyle(
              color: TimelineColors.secondaryText,
              fontSize: 9,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.pixelsPerSecond != pixelsPerSecond || old.duration != duration;
}
