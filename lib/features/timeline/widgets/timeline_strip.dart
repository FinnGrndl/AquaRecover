import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/timeline/timeline_project.dart';
import '../timeline_controller.dart';
import '../timeline_theme.dart';
import 'tools/transition_panel.dart';

/// Pixels per second of the timeline, shared by the strip and the zoom
/// buttons in the transport row.
class TimelineZoom extends ValueNotifier<double> {
  TimelineZoom([super.value = 56]);

  static const min = 12.0;
  static const max = 320.0;

  void zoomIn() => value = (value * 1.5).clamp(min, max);
  void zoomOut() => value = (value / 1.5).clamp(min, max);
  bool get canZoomIn => value < max - .01;
  bool get canZoomOut => value > min + .01;
}

/// The multi-lane timeline. The playhead stays fixed in the centre and
/// everything scrolls under it, which keeps scrubbing one-handed on a phone.
///
/// From the top: the ruler, overlay lanes (the highest layer on top, as in
/// iMovie), the magnetic main track with transition buttons between clips
/// and an Add button at its end, then audio lanes. A tap selects an item;
/// the selected overlay or sound moves with a drag (snapping to the playhead
/// and other edges, vertically to another lane), and every selected item
/// has trim handles. Touch and hold a main clip to reorder it. Pinch, or
/// the zoom buttons, change the scale. Lanes shrink to thin bars when
/// [compact].
class TimelineStrip extends StatefulWidget {
  const TimelineStrip({
    super.key,
    required this.controller,
    this.zoom,
    this.compact = false,
    this.onScrubStart,
    this.onAdd,
    this.onAddText,
    this.onAddOverlay,
    this.onAddAudio,
    this.onJunction,
    this.activeJunction,
  });

  final TimelineController controller;
  final TimelineZoom? zoom;
  final bool compact;
  final VoidCallback? onScrubStart;

  /// The "+" at the end of the main track.
  final VoidCallback? onAdd;

  /// The buttons in the empty lane above the overlays and below the sounds,
  /// which keep the extra tracks visible before anything is on them.
  final VoidCallback? onAddText;
  final VoidCallback? onAddOverlay;
  final VoidCallback? onAddAudio;

  /// A tap on the transition button before clip `index`.
  final ValueChanged<int>? onJunction;

  /// The junction whose Transition panel is open.
  final int? activeJunction;

  static const rulerHeight = 22.0;
  static const mainHeight = 56.0;
  static const overlayHeight = 36.0;
  static const audioHeight = 30.0;
  static const compactHeight = 8.0;
  static const leadingWidth = 32.0;

  static double _gap(bool compact) => compact ? 3 : 4;

  /// Height of a strip with these lanes.
  static double heightFor({
    required int overlayLanes,
    required int audioLanes,
    bool compact = false,
  }) {
    // A full strip keeps one empty lane on each side for adding to.
    if (!compact) {
      overlayLanes++;
      audioLanes++;
    }
    final gap = _gap(compact);
    final o = compact ? compactHeight : overlayHeight;
    final a = compact ? compactHeight : audioHeight;
    return rulerHeight +
        overlayLanes * (o + gap) +
        mainHeight +
        6 +
        audioLanes * (a + gap) +
        6;
  }

  /// Height for [project]'s lanes.
  static double heightOf(TimelineProject project, {bool compact = false}) =>
      heightFor(
        overlayLanes: project.overlays.map((o) => o.lane).toSet().length,
        audioLanes: project.audioClips.map((a) => a.lane).toSet().length,
        compact: compact,
      );

  @override
  State<TimelineStrip> createState() => _TimelineStripState();
}

/// A pan that starts at the touch slop rather than the larger pan slop, so
/// dragging a selected item wins over scrolling the timeline.
class _ItemDragRecognizer extends PanGestureRecognizer {
  _ItemDragRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      computeHitSlop(pointerDeviceKind, gestureSettings);
}

enum _ItemKind { clip, overlay, audio }

class _Item {
  const _Item({
    required this.id,
    required this.kind,
    required this.start,
    required this.duration,
    required this.lane,
  });

  final String id;
  final _ItemKind kind;
  final double start;
  final double duration;
  final int lane;

  double get end => start + duration;
}

class _TimelineStripState extends State<TimelineStrip> {
  final _scroll = ScrollController();
  final _contentKey = GlobalKey();
  late TimelineZoom _zoom = widget.zoom ?? TimelineZoom();
  double _scaleStart = 56;
  bool _userScrolling = false;

  // Moving an overlay or sound.
  String? _moveId;
  double _moveStart = 0;
  Offset _moveOrigin = Offset.zero;
  double? _snappedTo;
  bool _dropNewLane = false;

  // Trimming.
  String? _trimId;
  double _trimEdgeTime = 0;
  Offset _trimOrigin = Offset.zero;

  // Reordering the main track.
  int? _reorderFrom;
  double _reorderX = 0;
  int? _reorderTo;

  TimelineController get _controller => widget.controller;
  double get _pps => _zoom.value;
  bool get _compact => widget.compact;
  double get _overlayH =>
      _compact ? TimelineStrip.compactHeight : TimelineStrip.overlayHeight;
  double get _audioH =>
      _compact ? TimelineStrip.compactHeight : TimelineStrip.audioHeight;
  double get _gap => TimelineStrip._gap(_compact);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncToPlayhead);
    _zoom.addListener(_onZoom);
  }

  @override
  void didUpdateWidget(TimelineStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncToPlayhead);
      widget.controller.addListener(_syncToPlayhead);
    }
    if (widget.zoom != null && widget.zoom != _zoom) {
      _zoom.removeListener(_onZoom);
      if (oldWidget.zoom == null) _zoom.dispose();
      _zoom = widget.zoom!..addListener(_onZoom);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncToPlayhead);
    _zoom.removeListener(_onZoom);
    if (widget.zoom == null) _zoom.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onZoom() {
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToPlayhead());
  }

  void _syncToPlayhead() {
    if (_userScrolling || !_scroll.hasClients) return;
    final target = _controller.playhead * _pps;
    if ((_scroll.offset - target).abs() > 0.5) {
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
      widget.onScrubStart?.call();
    }
    if (_userScrolling && notification is ScrollUpdateNotification) {
      _controller.seek(_scroll.offset / _pps);
    }
    if (notification is ScrollEndNotification) {
      _userScrolling = false;
    }
    return false;
  }

  // -------------------------------------------------------------------
  // Geometry
  // -------------------------------------------------------------------

  int get _overlayLanes =>
      _controller.project.overlays.map((o) => o.lane).toSet().length;
  int get _audioLanes =>
      _controller.project.audioClips.map((a) => a.lane).toSet().length;

  /// Overlay rows, counting the empty lane a full strip keeps on top.
  int get _overlaySlots => _overlayLanes + (_compact ? 0 : 1);

  double _overlayTop(int lane) =>
      TimelineStrip.rulerHeight +
      (_overlaySlots - 1 - lane) * (_overlayH + _gap);

  double get _mainTop =>
      TimelineStrip.rulerHeight + _overlaySlots * (_overlayH + _gap);

  double _audioTop(int lane) =>
      _mainTop + TimelineStrip.mainHeight + 6 + lane * (_audioH + _gap);

  Offset _local(Offset global) {
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  // -------------------------------------------------------------------
  // Moving overlays and sounds
  // -------------------------------------------------------------------

  void _moveStartGesture(_Item item, DragStartDetails details) {
    widget.onScrubStart?.call();
    _moveId = item.id;
    _moveStart = item.start;
    _moveOrigin = details.globalPosition;
    _snappedTo = null;
    _controller.beginGesture();
  }

  void _moveUpdate(_Item item, DragUpdateDetails details) {
    if (_moveId != item.id) return;
    final dx = (details.globalPosition.dx - _moveOrigin.dx) / _pps;
    final snap = _controller.snapStart(
      _moveStart + dx,
      item.duration,
      exclude: item.id,
      tolerance: 10 / _pps,
    );
    if (snap.snappedTo != null && snap.snappedTo != _snappedTo) {
      HapticFeedback.selectionClick();
    }
    _snappedTo = snap.snappedTo;
    final y = _local(details.globalPosition).dy;
    int lane;
    var newLane = false;
    if (item.kind == _ItemKind.overlay) {
      final n = _overlayLanes;
      final row = ((y - TimelineStrip.rulerHeight) / (_overlayH + _gap))
          .floor();
      final slot = _overlaySlots - 1 - row;
      if (row < 0 || slot >= n) {
        lane = n;
        newLane = true;
      } else {
        lane = slot.clamp(0, n - 1);
      }
    } else {
      final m = _audioLanes;
      final row = ((y - _audioTop(0)) / (_audioH + _gap)).floor();
      if (row >= m) {
        lane = m;
        newLane = true;
      } else {
        lane = row.clamp(0, m - 1);
      }
    }
    setState(() {
      _dropNewLane = newLane;
    });
    _controller.moveItem(
      item.id,
      start: snap.start,
      // A lane past the last one makes a new lane once the drag ends.
      lane: newLane ? 1 << 20 : lane,
      resolveConflicts: false,
    );
  }

  void _moveEnd() {
    final id = _moveId;
    if (id == null) return;
    _controller.moveItem(id);
    _controller.endGesture();
    setState(() {
      _moveId = null;
      _snappedTo = null;
      _dropNewLane = false;
    });
  }

  // -------------------------------------------------------------------
  // Trimming
  // -------------------------------------------------------------------

  void _trimStart(_Item item, TrimEdge edge, DragStartDetails details) {
    widget.onScrubStart?.call();
    _trimId = item.id;
    _trimEdgeTime = edge == TrimEdge.start ? item.start : item.end;
    _trimOrigin = details.globalPosition;
    _snappedTo = null;
    _controller.beginGesture();
  }

  void _trimUpdate(_Item item, TrimEdge edge, DragUpdateDetails details) {
    if (_trimId != item.id) return;
    var delta = (details.globalPosition.dx - _trimOrigin.dx) / _pps;
    if (item.kind != _ItemKind.clip) {
      final snap = _controller.snapTime(
        _trimEdgeTime + delta,
        exclude: item.id,
        tolerance: 10 / _pps,
      );
      if (snap.snappedTo != null && snap.snappedTo != _snappedTo) {
        HapticFeedback.selectionClick();
      }
      _snappedTo = snap.snappedTo;
      delta = snap.time - _trimEdgeTime;
    }
    _controller.trimItem(item.id, edge, delta);
  }

  void _trimEnd() {
    if (_trimId == null) return;
    _trimId = null;
    _snappedTo = null;
    _controller.endGesture();
  }

  // -------------------------------------------------------------------
  // Reordering
  // -------------------------------------------------------------------

  int _insertionIndex(double localX, double half) {
    final t = (localX - half) / _pps;
    final entries = _controller.layout.entries;
    var index = 0;
    for (final entry in entries) {
      if (entry.index == _reorderFrom) continue;
      if ((entry.start + entry.end) / 2 < t) index++;
    }
    return index;
  }

  // -------------------------------------------------------------------
  // Building
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => LayoutBuilder(builder: _build),
    );
  }

  Widget _build(BuildContext context, BoxConstraints constraints) {
    final project = _controller.project;
    final layout = _controller.layout;
    final half = constraints.maxWidth / 2;
    final contentWidth = layout.duration * _pps;
    final height = TimelineStrip.heightOf(project, compact: _compact);
    final selection = _controller.selection;
    final children = <Widget>[];
    final handles = <Widget>[];

    children.add(
      Positioned(
        left: half,
        width: contentWidth,
        top: 0,
        height: 18,
        child: CustomPaint(
          painter: _RulerPainter(
            pixelsPerSecond: _pps,
            duration: layout.duration,
            labelStyle: const TextStyle(
              color: TimelineColors.secondaryText,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );

    // Main track.
    for (final entry in layout.entries) {
      final item = _Item(
        id: entry.clip.id,
        kind: _ItemKind.clip,
        start: entry.start,
        duration: entry.duration,
        lane: 0,
      );
      final selected = selection == TimelineSelection.clip(entry.clip.id);
      final lifted = _reorderFrom == entry.index;
      final left = half + entry.start * _pps;
      final width = math.max(8.0, entry.duration * _pps);
      children.add(
        Positioned(
          left: lifted ? left + (_reorderX - (left + width / 2)) : left,
          width: width,
          top: _mainTop,
          height: TimelineStrip.mainHeight,
          child: Opacity(
            opacity: lifted ? .75 : 1,
            child: GestureDetector(
              onTap: () => _controller.select(entry.clip.id),
              onLongPressStart: (d) {
                HapticFeedback.mediumImpact();
                widget.onScrubStart?.call();
                setState(() {
                  _reorderFrom = entry.index;
                  _reorderX = _local(d.globalPosition).dx;
                  _reorderTo = entry.index;
                });
              },
              onLongPressMoveUpdate: (d) => setState(() {
                _reorderX = _local(d.globalPosition).dx;
                _reorderTo = _insertionIndex(_reorderX, half);
              }),
              onLongPressEnd: (_) {
                final from = _reorderFrom, to = _reorderTo;
                setState(() => _reorderFrom = _reorderTo = null);
                if (from != null && to != null && from != to) {
                  _controller.reorder(from, to);
                }
              },
              child: _ClipTile(
                key: Key('timeline_clip_${entry.clip.id}'),
                entry: entry,
                selected: selected,
                overlapWidth: entry.overlapIn * _pps,
              ),
            ),
          ),
        ),
      );
      if (selected && _reorderFrom == null) {
        handles.addAll(
          _handles(item, left, width, _mainTop, TimelineStrip.mainHeight),
        );
      }
    }

    // Reorder insertion marker.
    if (_reorderFrom != null && _reorderTo != null) {
      final others = [
        for (final e in layout.entries)
          if (e.index != _reorderFrom) e,
      ];
      final t = _reorderTo! >= others.length
          ? (others.isEmpty ? 0.0 : others.last.end)
          : others[_reorderTo!].start;
      children.add(
        Positioned(
          left: half + t * _pps - 1.5,
          width: 3,
          top: _mainTop - 4,
          height: TimelineStrip.mainHeight + 8,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      );
    }

    // Overlays.
    for (final overlay in project.overlays) {
      final start = math.max(0.0, overlay.start);
      final item = _Item(
        id: overlay.id,
        kind: _ItemKind.overlay,
        start: start,
        duration: overlay.duration,
        lane: overlay.lane,
      );
      final selected = selection == TimelineSelection.overlay(overlay.id);
      final left = half + start * _pps;
      final width = math.max(10.0, overlay.duration * _pps);
      final top = _overlayTop(overlay.lane);
      children.add(
        Positioned(
          left: left,
          width: width,
          top: top,
          height: _overlayH,
          child: _movable(
            item,
            selected,
            _LaneItem(
              key: Key('timeline_overlay_${overlay.id}'),
              color: overlay.kind == OverlayKind.text
                  ? TimelineColors.titleItem
                  : TimelineColors.overlayItem,
              icon: switch (overlay.kind) {
                OverlayKind.text => CupertinoIcons.textformat,
                OverlayKind.video => CupertinoIcons.film,
                OverlayKind.image => CupertinoIcons.photo,
              },
              label: _overlayLabel(overlay),
              semanticLabel: _describe(
                _overlayKindName(overlay),
                _overlayLabel(overlay),
                start,
                overlay.duration,
              ),
              selected: selected,
              compact: _compact,
              muted: overlay.isVideo && overlay.gain <= 0,
            ),
          ),
        ),
      );
      if (selected && !_compact) {
        handles.addAll(_handles(item, left, width, top, _overlayH));
      }
    }

    // Audio.
    for (final audio in project.audioClips) {
      final start = math.max(0.0, audio.start);
      final item = _Item(
        id: audio.id,
        kind: _ItemKind.audio,
        start: start,
        duration: audio.duration,
        lane: audio.lane,
      );
      final selected = selection == TimelineSelection.audio(audio.id);
      final left = half + start * _pps;
      final width = math.max(10.0, audio.duration * _pps);
      final top = _audioTop(audio.lane);
      final name = audio.name.isEmpty
          ? p.basenameWithoutExtension(audio.path)
          : audio.name;
      children.add(
        Positioned(
          left: left,
          width: width,
          top: top,
          height: _audioH,
          child: _movable(
            item,
            selected,
            _LaneItem(
              key: Key('timeline_audio_${audio.id}'),
              color: TimelineColors.audioItem,
              icon: audio.role == AudioRole.extracted
                  ? CupertinoIcons.waveform
                  : CupertinoIcons.music_note,
              label: name,
              semanticLabel: _describe(
                audio.role.label,
                name,
                start,
                audio.duration,
              ),
              selected: selected,
              compact: _compact,
              muted: audio.volume <= 0,
            ),
          ),
        ),
      );
      if (selected && !_compact) {
        handles.addAll(_handles(item, left, width, top, _audioH));
      }
    }

    // Transition buttons between clips.
    {
      for (final entry in layout.entries.skip(1)) {
        final x = half + (entry.start + entry.overlapIn / 2) * _pps;
        children.add(
          Positioned(
            left: x - 22,
            top: _mainTop + TimelineStrip.mainHeight / 2 - 22,
            width: 44,
            height: 44,
            child: _JunctionButton(
              key: Key('timeline_junction_${entry.index}'),
              transition: entry.clip.transition,
              index: entry.index,
              active: widget.activeJunction == entry.index,
              onPressed: widget.onJunction == null
                  ? null
                  : () => widget.onJunction!(entry.index),
            ),
          ),
        );
      }
    }

    if (!_compact) {
      Widget addRow(double top, double height, List<Widget> buttons) =>
          Positioned(
            left: half,
            top: top + height / 2 - 22,
            height: 44,
            child: Row(children: buttons),
          );
      children
        ..add(
          addRow(_overlayTop(_overlayLanes), _overlayH, [
            _AddLaneButton(
              key: const Key('timeline_add_text'),
              icon: CupertinoIcons.textformat,
              label: 'Text',
              semanticLabel: 'Add text',
              onPressed: widget.onAddText,
            ),
            const SizedBox(width: 8),
            _AddLaneButton(
              key: const Key('timeline_add_overlay'),
              icon: CupertinoIcons.square_on_square,
              label: 'Overlay',
              semanticLabel: 'Add a photo or video overlay',
              onPressed: widget.onAddOverlay,
            ),
          ]),
        )
        ..add(
          addRow(_audioTop(_audioLanes), _audioH, [
            _AddLaneButton(
              key: const Key('timeline_add_audio'),
              icon: CupertinoIcons.music_note,
              label: 'Audio',
              semanticLabel: 'Add music or sound',
              onPressed: widget.onAddAudio,
            ),
          ]),
        );
    }

    if (widget.onAdd != null && project.clips.isNotEmpty) {
      children.add(
        Positioned(
          left: half + contentWidth + 6,
          top: _mainTop + TimelineStrip.mainHeight / 2 - 22,
          width: 44,
          height: 44,
          child: Semantics(
            button: true,
            label: 'Add photos and clips',
            excludeSemantics: true,
            child: CupertinoButton(
              key: const Key('timeline_add'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: widget.onAdd,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  CupertinoIcons.add,
                  size: 20,
                  color: CupertinoColors.black,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Where a dragged item goes when it leaves the existing lanes.
    if (_moveId != null && _dropNewLane) {
      final isOverlay = _controller.overlayById(_moveId!) != null;
      children.add(
        Positioned(
          left: half - 2000,
          right: 0,
          top: isOverlay ? 2 : height - 5,
          height: isOverlay ? 16 : 3,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x1fffffff),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0x99ffffff), width: .5),
              ),
            ),
          ),
        ),
      );
    }

    final content = SizedBox(
      key: _contentKey,
      width: contentWidth + half * 2,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [...children, ...handles],
      ),
    );

    return GestureDetector(
      onScaleStart: (_) => _scaleStart = _pps,
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) return;
        _zoom.value = (_scaleStart * details.horizontalScale).clamp(
          TimelineZoom.min,
          TimelineZoom.max,
        );
      },
      child: Semantics(
        container: true,
        label: 'Timeline',
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Zoom in'): _zoom.zoomIn,
          const CustomSemanticsAction(label: 'Zoom out'): _zoom.zoomOut,
        },
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: const [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0xff000000),
                    ],
                    stops: [
                      0,
                      (TimelineStrip.leadingWidth - 6) / bounds.width,
                      (TimelineStrip.leadingWidth + 22) / bounds.width,
                    ],
                  ).createShader(bounds),
                  child: SingleChildScrollView(
                    key: const Key('timeline_strip_scroll'),
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: content,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: TimelineStrip.leadingWidth,
                child: _leadingColumn(),
              ),
              Positioned(
                left: half - 6,
                top: 16,
                bottom: 0,
                width: 12,
                child: const IgnorePointer(child: _Playhead()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _movable(_Item item, bool selected, Widget child) {
    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.select(item.id),
      child: child,
    );
    if (selected && !_compact) {
      result = RawGestureDetector(
        gestures: {
          _ItemDragRecognizer:
              GestureRecognizerFactoryWithHandlers<_ItemDragRecognizer>(
                () => _ItemDragRecognizer(debugOwner: this),
                (r) => r
                  // The item follows the finger from where it touched down.
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = ((d) => _moveStartGesture(item, d))
                  ..onUpdate = ((d) => _moveUpdate(item, d))
                  ..onEnd = ((_) => _moveEnd())
                  ..onCancel = _moveEnd,
              ),
        },
        child: result,
      );
    }
    return result;
  }

  List<Widget> _handles(
    _Item item,
    double left,
    double width,
    double top,
    double height,
  ) {
    final hitHeight = math.max(44.0, height);
    Widget handle(TrimEdge edge) {
      final atStart = edge == TrimEdge.start;
      final x = atStart ? left : left + width;
      return Positioned(
        key: Key('timeline_trim_${edge.name}'),
        left: x - 22,
        width: 44,
        top: top + height / 2 - hitHeight / 2,
        height: hitHeight,
        child: Semantics(
          label: atStart ? 'Trim start' : 'Trim end',
          hint: 'Drag sideways',
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _ItemDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<_ItemDragRecognizer>(
                    () => _ItemDragRecognizer(debugOwner: this),
                    (r) => r
                      ..dragStartBehavior = DragStartBehavior.down
                      ..onStart = ((d) => _trimStart(item, edge, d))
                      ..onUpdate = ((d) => _trimUpdate(item, edge, d))
                      ..onEnd = ((_) => _trimEnd())
                      ..onCancel = _trimEnd,
                  ),
            },
            child: Align(
              alignment: atStart
                  ? const Alignment(0.45, 0)
                  : const Alignment(-0.45, 0),
              child: _TrimHandle(height: height, start: atStart),
            ),
          ),
        ),
      );
    }

    return [handle(TrimEdge.start), handle(TrimEdge.end)];
  }

  Widget _leadingColumn() {
    final project = _controller.project;
    final hasVideo = project.clips.any((c) => c.isVideo);
    final muted = _controller.clipAudioMuted;
    Widget lane(double top, double height, IconData icon, String label) =>
        Positioned(
          left: 0,
          right: 0,
          top: top,
          height: height,
          child: Semantics(
            label: label,
            child: Icon(
              icon,
              size: _compact ? 10 : 15,
              color: TimelineColors.secondaryText,
            ),
          ),
        );
    final overlays = _overlayLanes;
    final audios = _audioLanes;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (!_compact) ...[
          for (var lane0 = 0; lane0 < overlays; lane0++)
            lane(
              _overlayTop(lane0),
              _overlayH,
              CupertinoIcons.square_on_square,
              'Overlay layer ${lane0 + 1}',
            ),
          for (var lane0 = 0; lane0 < audios; lane0++)
            lane(
              _audioTop(lane0),
              _audioH,
              CupertinoIcons.music_note,
              'Audio lane ${lane0 + 1}',
            ),
        ],
        Positioned(
          left: -6,
          width: 44,
          top: _mainTop + TimelineStrip.mainHeight / 2 - 22,
          height: 44,
          child: hasVideo
              ? Semantics(
                  button: true,
                  toggled: muted,
                  label: 'Mute clip audio',
                  excludeSemantics: true,
                  child: CupertinoButton(
                    key: const Key('timeline_mute_clips'),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: _controller.toggleClipAudio,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: muted
                            ? CupertinoColors.white
                            : TimelineColors.fill,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        muted
                            ? CupertinoIcons.speaker_slash_fill
                            : CupertinoIcons.speaker_2_fill,
                        size: 14,
                        color: muted
                            ? CupertinoColors.black
                            : TimelineColors.text,
                      ),
                    ),
                  ),
                )
              : Semantics(
                  label: 'Main track',
                  child: const Icon(
                    CupertinoIcons.film,
                    size: 15,
                    color: TimelineColors.secondaryText,
                  ),
                ),
        ),
      ],
    );
  }

  static String _overlayKindName(TimelineOverlay overlay) =>
      switch (overlay.kind) {
        OverlayKind.text => 'Title',
        OverlayKind.video => 'Video overlay',
        OverlayKind.image => 'Photo overlay',
      };

  static String _overlayLabel(TimelineOverlay overlay) {
    final title = overlay.title;
    if (title != null) {
      final text = title.text.split('\n').first.trim();
      return text.isEmpty ? 'Title' : text;
    }
    return p.basenameWithoutExtension(overlay.path ?? 'Overlay');
  }

  static String _describe(
    String kind,
    String name,
    double start,
    double duration,
  ) =>
      '$kind $name, starts at ${formatTimecode(start)}, '
      '${duration.toStringAsFixed(1)} seconds';
}

class _TrimHandle extends StatelessWidget {
  const _TrimHandle({required this.height, required this.start});

  final double height;
  final bool start;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(6);
    return Container(
      width: 10,
      height: height,
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: start
            ? const BorderRadius.horizontal(left: radius)
            : const BorderRadius.horizontal(right: radius),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 2,
        height: math.min(14, height * .4),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

class _JunctionButton extends StatelessWidget {
  const _JunctionButton({
    super.key,
    required this.transition,
    required this.index,
    required this.active,
    required this.onPressed,
  });

  final ClipTransition transition;
  final int index;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final set = transition != ClipTransition.cut;
    final filled = set || active;
    return Semantics(
      button: true,
      selected: active,
      label: 'Transition before clip ${index + 1}',
      value: TransitionPanel.labelOf(transition),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: filled ? CupertinoColors.white : const Color(0xe61c1c1e),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: filled
                    ? const Color(0x99000000)
                    : const Color(0x99ffffff),
                width: active ? 2 : .7,
              ),
            ),
            child: Icon(
              set ? TransitionPanel.iconOf(transition) : CupertinoIcons.minus,
              size: 12,
              color: filled ? CupertinoColors.black : CupertinoColors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// White playhead line, as in Photos and iMovie, over a slightly wider dark
/// stroke like the crop overlay's lines, so it stays crisp on bright
/// thumbnails without a blurred shadow.
class _Playhead extends StatelessWidget {
  const _Playhead();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _PlayheadPainter());
  }
}

class _PlayheadPainter extends CustomPainter {
  const _PlayheadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final top = Offset(size.width / 2, 1);
    final bottom = Offset(size.width / 2, size.height - 1);
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..color = CupertinoColors.black.withValues(alpha: .5)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..color = TimelineColors.playhead
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PlayheadPainter oldDelegate) => false;
}

/// An overlay, title, or sound on its lane: a rounded capsule tinted by
/// kind, with a symbol and a name. Selection adds a white outline (the trim
/// handles are drawn separately), so it never depends on colour alone.
class _LaneItem extends StatelessWidget {
  const _LaneItem({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.compact,
    this.muted = false,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String semanticLabel;
  final bool selected;
  final bool compact;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: .5),
        padding: compact
            ? null
            : EdgeInsets.symmetric(horizontal: selected ? 14 : 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(compact ? 3 : 8),
          border: selected
              ? Border.all(color: CupertinoColors.white, width: 2)
              : null,
        ),
        clipBehavior: Clip.hardEdge,
        child: compact
            ? null
            : Row(
                children: [
                  Icon(icon, size: 13, color: TimelineColors.text),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TimelineColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (muted)
                    const Icon(
                      CupertinoIcons.speaker_slash,
                      size: 12,
                      color: TimelineColors.text,
                    ),
                ],
              ),
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.overlapWidth,
  });

  final TimelineEntry entry;
  final bool selected;
  final double overlapWidth;

  @override
  Widget build(BuildContext context) {
    final clip = entry.clip;
    final base = clip.isVideo
        ? TimelineColors.videoClip
        : TimelineColors.photoClip;
    final speed = clip.playbackSpeed;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${clip.isVideo ? 'Clip' : 'Photo'} ${entry.index + 1}, '
          '${formatTimecode(clip.duration)}'
          '${speed != 1 ? ', ${speed}x speed' : ''}'
          '${clip.effects.isEmpty ? '' : ', ${clip.effects.length} effects'}',
      hint: 'Touch and hold to move',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? CupertinoColors.white : TimelineColors.stroke,
            width: selected ? 2 : .7,
          ),
        ),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(9),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!clip.isVideo)
              Image.file(
                File(clip.path),
                fit: BoxFit.cover,
                cacheHeight: 120,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            // Keeps the labels readable on bright photos.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x00000000),
                    Color(0x99000000),
                  ],
                  stops: [0, .4, 1],
                ),
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
              // Selected clips keep their label clear of the trim handles.
              padding: EdgeInsets.fromLTRB(
                selected ? 14 : 6,
                4,
                selected ? 14 : 6,
                4,
              ),
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
                      if (speed != 1) ...[
                        const SizedBox(width: 3),
                        Text(
                          '${speed.toStringAsFixed(speed == speed.roundToDouble() ? 0 : 2).replaceFirst(RegExp(r'0$'), '')}×',
                          style: const TextStyle(
                            color: TimelineColors.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (clip.motion != ClipMotion.none) ...[
                        const SizedBox(width: 3),
                        const Icon(
                          CupertinoIcons.zoom_in,
                          size: 12,
                          color: TimelineColors.text,
                        ),
                      ],
                      if (clip.effects.isNotEmpty) ...[
                        const SizedBox(width: 3),
                        const Icon(
                          CupertinoIcons.sparkles,
                          size: 12,
                          color: TimelineColors.text,
                        ),
                      ],
                      if (clip.isVideo && clip.gain <= 0) ...[
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
                    formatTimecode(entry.duration),
                    key: Key('timeline_clip_duration_${clip.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      color: TimelineColors.secondaryText,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter({
    required this.pixelsPerSecond,
    required this.duration,
    required this.labelStyle,
  });

  final double pixelsPerSecond;
  final double duration;
  final TextStyle labelStyle;

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
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.pixelsPerSecond != pixelsPerSecond ||
      old.duration != duration ||
      old.labelStyle != labelStyle;
}

/// A "+ Text" style button in one of the empty lanes.
class _AddLaneButton extends StatelessWidget {
  const _AddLaneButton({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticLabel,
    excludeSemantics: true,
    child: CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: TimelineColors.fill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TimelineColors.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.add,
              size: 14,
              color: TimelineColors.secondaryText,
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 15, color: TimelineColors.secondaryText),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: TimelineColors.secondaryText,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
