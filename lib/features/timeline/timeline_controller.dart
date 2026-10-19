import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/media/media_classifier.dart';
import '../../core/models/lut_profile.dart';
import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/timeline/timeline_project.dart';
import '../../core/timeline/timeline_project_store.dart';
import '../../core/timeline/timeline_render_plan.dart';
import '../../core/timeline/timeline_textures.dart';

/// What the movie editor acts on: nothing (the root toolbar), a main-track
/// clip, an overlay (video, photo, or title), or an audio item.
sealed class TimelineSelection {
  const TimelineSelection();

  const factory TimelineSelection.none() = NoSelection;
  const factory TimelineSelection.clip(String id) = ClipSelection;
  const factory TimelineSelection.overlay(String id) = OverlaySelection;
  const factory TimelineSelection.audio(String id) = AudioSelection;

  /// The selected item's id, or `null` when nothing is selected.
  String? get id;

  bool get isNone => this is NoSelection;
}

final class NoSelection extends TimelineSelection {
  const NoSelection();

  @override
  String? get id => null;

  @override
  bool operator ==(Object other) => other is NoSelection;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'TimelineSelection.none()';
}

final class ClipSelection extends TimelineSelection {
  const ClipSelection(this.id);

  @override
  final String id;

  @override
  bool operator ==(Object other) => other is ClipSelection && other.id == id;

  @override
  int get hashCode => Object.hash(1, id);

  @override
  String toString() => 'TimelineSelection.clip($id)';
}

final class OverlaySelection extends TimelineSelection {
  const OverlaySelection(this.id);

  @override
  final String id;

  @override
  bool operator ==(Object other) => other is OverlaySelection && other.id == id;

  @override
  int get hashCode => Object.hash(2, id);

  @override
  String toString() => 'TimelineSelection.overlay($id)';
}

final class AudioSelection extends TimelineSelection {
  const AudioSelection(this.id);

  @override
  final String id;

  @override
  bool operator ==(Object other) => other is AudioSelection && other.id == id;

  @override
  int get hashCode => Object.hash(3, id);

  @override
  String toString() => 'TimelineSelection.audio($id)';
}

/// Which end of an item a trim handle moves.
enum TrimEdge { start, end }

/// Measures a title rasterised for a canvas, in output pixels.
typedef TitleMeasure =
    ({double width, double height}) Function(
      TitleSpec title,
      int canvasWidth,
      int canvasHeight,
    );

({double width, double height}) _measureTitle(
  TitleSpec title,
  int canvasWidth,
  int canvasHeight,
) {
  final size = measureTitle(
    title,
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
  );
  return (width: size.width, height: size.height);
}

/// Editing state of one timeline: the project, the selection, the playhead,
/// and undo history. Every edit replaces the immutable project, so undo is a
/// list of earlier projects. Continuous edits (slider drags, viewer and
/// timeline gestures, typing a title) are bracketed by [beginGesture] and
/// [endGesture] so they undo in one step.
class TimelineController extends ChangeNotifier {
  TimelineController(
    TimelineProject project, {
    TimelineProjectStore? store,
    this.autosaveDelay = const Duration(milliseconds: 600),
    TitleMeasure? titleMeasure,
  }) : _project = project,
       _store = store,
       _titleMeasure = titleMeasure ?? _measureTitle;

  static const maxUndo = 50;

  /// Default snapping distance in seconds; the timeline passes one that
  /// matches its zoom.
  static const snapSeconds = 0.15;

  static const _epsilon = 1e-6;

  final TimelineProjectStore? _store;
  final Duration autosaveDelay;
  final TitleMeasure _titleMeasure;
  TimelineProject _project;
  TimelineSelection _selection = const TimelineSelection.none();
  double _playhead = 0;
  final List<TimelineProject> _undo = [];
  final List<TimelineProject> _redo = [];
  Timer? _saveTimer;
  int _idCounter = 0;
  int _gestureDepth = 0;
  TimelineProject? _gestureBase;
  TimelineProject? _planSource;
  TimelineRenderPlan? _plan;
  TimelineProject? _layoutSource;
  TimelineLayout? _layout;

  TimelineProject get project => _project;
  double get playhead => _playhead;
  bool get canUndo => _undo.isNotEmpty || _gestureChanged;
  bool get canRedo => _redo.isNotEmpty;
  TimelineSelection get selection => _selection;

  /// Whether a continuous edit is in progress.
  bool get inGesture => _gestureDepth > 0;

  bool get _gestureChanged =>
      _gestureBase != null && !identical(_gestureBase, _project);

  /// The project compiled for rendering and the layered preview. It is
  /// compiled lazily once per project change, never per frame.
  TimelineRenderPlan get plan {
    if (_plan == null || !identical(_planSource, _project)) {
      _plan = TimelineCompiler.compile(
        _project,
        titleAspect: (title, w, h) {
          final size = _titleMeasure(title, w, h);
          return size.height <= 0 ? 1 : size.width / size.height;
        },
      );
      _planSource = _project;
    }
    return _plan!;
  }

  /// The main track's layout, cached per project change.
  TimelineLayout get layout {
    if (_layout == null || !identical(_layoutSource, _project)) {
      _layout = _project.layout;
      _layoutSource = _project;
    }
    return _layout!;
  }

  TimelineClip? get selectedClip => switch (_selection) {
    ClipSelection(:final id) => clipById(id),
    _ => null,
  };

  int get selectedIndex => switch (_selection) {
    ClipSelection(:final id) => _project.clips.indexWhere((c) => c.id == id),
    _ => -1,
  };

  TimelineOverlay? get selectedOverlay => switch (_selection) {
    OverlaySelection(:final id) => overlayById(id),
    _ => null,
  };

  TimelineAudioClip? get selectedAudio => switch (_selection) {
    AudioSelection(:final id) => audioById(id),
    _ => null,
  };

  TimelineEntry? get entryAtPlayhead => layout.entryAt(_playhead);

  TimelineClip? clipById(String id) {
    for (final clip in _project.clips) {
      if (clip.id == id) return clip;
    }
    return null;
  }

  TimelineOverlay? overlayById(String id) {
    for (final overlay in _project.overlays) {
      if (overlay.id == id) return overlay;
    }
    return null;
  }

  TimelineAudioClip? audioById(String id) {
    for (final audio in _project.audioClips) {
      if (audio.id == id) return audio;
    }
    return null;
  }

  TimelineEntry? entryFor(String clipId) {
    for (final entry in layout.entries) {
      if (entry.clip.id == clipId) return entry;
    }
    return null;
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_idCounter++).toRadixString(36)}';

  // ---------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------

  void _pushUndo(TimelineProject project) {
    _undo.add(project);
    if (_undo.length > maxUndo) _undo.removeAt(0);
  }

  void _commit(TimelineProject next, {TimelineSelection? select}) {
    next = _normalizeLanes(next);
    if (_gestureDepth == 0) _pushUndo(_project);
    _redo.clear();
    _project = next;
    if (select != null) _selection = select;
    _validateSelection();
    _playhead = _playhead.clamp(0.0, next.duration).toDouble();
    _scheduleSave();
    notifyListeners();
  }

  /// Starts a continuous edit: changes until the matching [endGesture]
  /// become one undo step. Calls nest.
  void beginGesture() {
    if (_gestureDepth++ == 0) _gestureBase = _project;
  }

  /// Ends a continuous edit started with [beginGesture]. A widget that ends
  /// its gesture while it is being disposed passes [notify] false, because
  /// listeners cannot rebuild then.
  void endGesture({bool notify = true}) {
    if (_gestureDepth == 0) return;
    if (--_gestureDepth > 0) return;
    final base = _gestureBase;
    _gestureBase = null;
    if (base != null && !identical(base, _project)) {
      _pushUndo(base);
      _redo.clear();
    }
    if (notify) notifyListeners();
  }

  void _closeGestures() {
    if (_gestureDepth == 0) return;
    _gestureDepth = 1;
    endGesture();
  }

  void undo() {
    _closeGestures();
    if (_undo.isEmpty) return;
    _redo.add(_project);
    _project = _undo.removeLast();
    _afterHistoryChange();
  }

  void redo() {
    _closeGestures();
    if (_redo.isEmpty) return;
    _undo.add(_project);
    _project = _redo.removeLast();
    _afterHistoryChange();
  }

  void _afterHistoryChange() {
    _validateSelection();
    _playhead = _playhead.clamp(0.0, _project.duration).toDouble();
    _scheduleSave();
    notifyListeners();
  }

  void _validateSelection() {
    final valid = switch (_selection) {
      NoSelection() => true,
      ClipSelection(:final id) => clipById(id) != null,
      OverlaySelection(:final id) => overlayById(id) != null,
      AudioSelection(:final id) => audioById(id) != null,
    };
    if (!valid) _selection = const TimelineSelection.none();
  }

  /// Renumbers overlay and audio lanes to 0…n−1 in order, so the editor never
  /// shows an empty lane. Relative order, and so the drawing order, is kept.
  static TimelineProject _normalizeLanes(TimelineProject project) {
    List<int> lanesOf(Iterable<int> lanes) => lanes.toSet().toList()..sort();
    bool contiguous(List<int> lanes) {
      for (var i = 0; i < lanes.length; i++) {
        if (lanes[i] != i) return false;
      }
      return true;
    }

    final overlayLanes = lanesOf(project.overlays.map((o) => o.lane));
    final audioLanes = lanesOf(project.audioClips.map((a) => a.lane));
    final fixOverlays = !contiguous(overlayLanes);
    final fixAudio = !contiguous(audioLanes);
    if (!fixOverlays && !fixAudio) return project;
    return project.copyWith(
      overlays: fixOverlays
          ? [
              for (final o in project.overlays)
                o.copyWith(lane: overlayLanes.indexOf(o.lane)),
            ]
          : null,
      audioClips: fixAudio
          ? [
              for (final a in project.audioClips)
                a.copyWith(lane: audioLanes.indexOf(a.lane)),
            ]
          : null,
    );
  }

  // ---------------------------------------------------------------------
  // Selection and playhead
  // ---------------------------------------------------------------------

  /// Selects the clip, overlay, or audio item called [id].
  void select(String id) {
    if (clipById(id) != null) {
      selectItem(TimelineSelection.clip(id));
    } else if (overlayById(id) != null) {
      selectItem(TimelineSelection.overlay(id));
    } else if (audioById(id) != null) {
      selectItem(TimelineSelection.audio(id));
    }
  }

  void selectItem(TimelineSelection selection) {
    if (_selection == selection) return;
    _selection = selection;
    _validateSelection();
    notifyListeners();
  }

  /// Back to the root toolbar.
  void deselect() => selectItem(const TimelineSelection.none());

  /// Selects the main clip under the playhead, as CapCut's Edit tool and a
  /// tap on empty canvas do.
  bool selectClipAtPlayhead() {
    final entry = entryAtPlayhead;
    if (entry == null) return false;
    selectItem(TimelineSelection.clip(entry.clip.id));
    return true;
  }

  /// Moves the playhead. The selection stays, as in iMovie and CapCut,
  /// unless [selectClip] asks for the clip under the playhead.
  void seek(double seconds, {bool selectClip = false}) {
    _playhead = seconds.clamp(0.0, _project.duration).toDouble();
    if (selectClip) {
      final entry = entryAtPlayhead;
      if (entry != null) _selection = TimelineSelection.clip(entry.clip.id);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Main track
  // ---------------------------------------------------------------------

  /// Appends media after the selected clip (or at the end). Unsupported
  /// files are skipped and returned so the UI can say which.
  List<String> addMedia(
    List<String> paths, {
    Map<String, double> videoDurations = const {},
    RestorationSettings grade = const RestorationSettings(),
  }) {
    final added = <TimelineClip>[];
    final skipped = <String>[];
    for (final path in paths) {
      final MediaKind kind;
      try {
        kind = MediaClassifier.classify(path);
      } on UnsupportedError {
        skipped.add(path);
        continue;
      }
      if (kind == MediaKind.rawVideo) {
        skipped.add(path);
        continue;
      }
      final duration = videoDurations[path];
      added.add(
        TimelineClip(
          id: _newId(),
          path: path,
          kind: kind.isVideo ? TimelineClipKind.video : TimelineClipKind.image,
          sourceDuration: duration,
          sourceEnd: kind.isVideo ? duration : null,
          grade: grade,
          transition: _project.clips.isEmpty && added.isEmpty
              ? ClipTransition.cut
              : ClipTransition.crossfade,
        ),
      );
    }
    if (added.isEmpty) return skipped;
    final clips = [..._project.clips];
    final at = selectedIndex < 0 ? clips.length : selectedIndex + 1;
    clips.insertAll(at, added);
    _commit(
      _project.copyWith(clips: clips),
      select: TimelineSelection.clip(added.first.id),
    );
    return skipped;
  }

  /// Fills in a video's or sound's length once a player has read it, without
  /// an undo step, because the user did not change anything. Works for main
  /// clips, video overlays, and audio items.
  void setSourceDuration(String id, double seconds) {
    if (!seconds.isFinite || seconds <= 0) return;
    double clampEnd(double? end) =>
        end == null || end > seconds ? seconds : end;
    final clip = clipById(id);
    final overlay = overlayById(id);
    final audio = audioById(id);
    TimelineProject? next;
    if (clip != null && clip.sourceDuration != seconds) {
      next = _withClip(
        _project,
        id,
        (c) => c.copyWith(
          sourceDuration: seconds,
          sourceEnd: c.isVideo ? clampEnd(c.sourceEnd) : null,
        ),
      );
    } else if (overlay != null &&
        overlay.isVideo &&
        overlay.sourceDuration != seconds) {
      next = _withOverlay(
        _project,
        id,
        (o) => o.copyWith(
          sourceDuration: seconds,
          sourceEnd: clampEnd(o.sourceEnd),
        ),
      );
    } else if (audio != null && audio.sourceDuration != seconds) {
      next = _withAudio(
        _project,
        id,
        (a) => a.copyWith(
          sourceDuration: seconds,
          sourceEnd: clampEnd(a.sourceEnd),
        ),
      );
    }
    if (next == null) return;
    // Not an edit: rewrite history so undo does not bring the guess back.
    if (identical(_gestureBase, _project)) _gestureBase = next;
    _project = next;
    _scheduleSave();
    notifyListeners();
  }

  TimelineProject _withClip(
    TimelineProject project,
    String id,
    TimelineClip Function(TimelineClip clip) change,
  ) => project.copyWith(
    clips: [
      for (final clip in project.clips) clip.id == id ? change(clip) : clip,
    ],
  );

  TimelineProject _withOverlay(
    TimelineProject project,
    String id,
    TimelineOverlay Function(TimelineOverlay overlay) change,
  ) => project.copyWith(
    overlays: [for (final o in project.overlays) o.id == id ? change(o) : o],
  );

  TimelineProject _withAudio(
    TimelineProject project,
    String id,
    TimelineAudioClip Function(TimelineAudioClip audio) change,
  ) => project.copyWith(
    audioClips: [
      for (final a in project.audioClips) a.id == id ? change(a) : a,
    ],
  );

  void updateClip(String id, TimelineClip Function(TimelineClip) change) {
    if (clipById(id) == null) return;
    _commit(_withClip(_project, id, change));
  }

  void updateOverlay(
    String id,
    TimelineOverlay Function(TimelineOverlay) change,
  ) {
    if (overlayById(id) == null) return;
    _commit(_withOverlay(_project, id, change));
  }

  void updateAudio(
    String id,
    TimelineAudioClip Function(TimelineAudioClip) change,
  ) {
    if (audioById(id) == null) return;
    _commit(_withAudio(_project, id, change));
  }

  void _updateSelected(TimelineClip Function(TimelineClip clip) change) {
    final selected = selectedClip;
    if (selected == null) return;
    updateClip(selected.id, change);
  }

  /// Blade tool: splits the clip under the playhead.
  bool splitAtPlayhead() {
    final entry = entryAtPlayhead;
    if (entry == null) return false;
    return _splitClip(entry);
  }

  bool _splitClip(TimelineEntry entry) {
    final parts = entry.clip.splitAt(
      entry.localTime(_playhead),
      newId: _newId(),
    );
    if (parts == null) return false;
    final (left, right) = parts;
    final clips = [..._project.clips]
      ..removeAt(entry.index)
      ..insertAll(entry.index, [left, right]);
    _commit(
      _project.copyWith(clips: clips),
      select: TimelineSelection.clip(right.id),
    );
    return true;
  }

  /// Splits the selected item at the playhead; with nothing selected, the
  /// clip under the playhead. Returns false when the playhead is not far
  /// enough inside the item.
  bool splitSelected() {
    switch (_selection) {
      case NoSelection():
        return splitAtPlayhead();
      case ClipSelection(:final id):
        final entry = entryFor(id);
        if (entry == null) return false;
        if (_playhead < entry.start || _playhead > entry.end) return false;
        return _splitClip(entry);
      case OverlaySelection(:final id):
        final overlay = overlayById(id)!;
        final parts = overlay.splitAt(
          _playhead - math.max(0, overlay.start),
          newId: _newId(),
        );
        if (parts == null) return false;
        final (left, right) = parts;
        _commit(
          _project.copyWith(
            overlays: [
              for (final o in _project.overlays)
                if (o.id == id) ...[left, right] else o,
            ],
          ),
          select: TimelineSelection.overlay(right.id),
        );
        return true;
      case AudioSelection(:final id):
        final audio = audioById(id)!;
        final parts = audio.splitAt(
          _playhead - math.max(0, audio.start),
          newId: _newId(),
        );
        if (parts == null) return false;
        final (left, right) = parts;
        _commit(
          _project.copyWith(
            audioClips: [
              for (final a in _project.audioClips)
                if (a.id == id) ...[left, right] else a,
            ],
          ),
          select: TimelineSelection.audio(right.id),
        );
        return true;
    }
  }

  /// Deletes the selection. A deleted clip hands the selection to its
  /// neighbour; overlays and sounds return to the root toolbar.
  void deleteSelected() {
    switch (_selection) {
      case NoSelection():
        return;
      case ClipSelection():
        final index = selectedIndex;
        if (index < 0) return;
        final clips = [..._project.clips]..removeAt(index);
        if (clips.isNotEmpty && index == 0) {
          clips[0] = clips[0].copyWith(transition: ClipTransition.cut);
        }
        final next = clips.isEmpty
            ? null
            : clips[math.min(index, clips.length - 1)];
        _commit(
          _project.copyWith(clips: clips),
          select: next == null
              ? const TimelineSelection.none()
              : TimelineSelection.clip(next.id),
        );
      case OverlaySelection(:final id):
        _commit(
          _project.copyWith(
            overlays: [
              for (final o in _project.overlays)
                if (o.id != id) o,
            ],
          ),
          select: const TimelineSelection.none(),
        );
      case AudioSelection(:final id):
        _commit(
          _project.copyWith(
            audioClips: [
              for (final a in _project.audioClips)
                if (a.id != id) a,
            ],
          ),
          select: const TimelineSelection.none(),
        );
    }
  }

  /// Duplicates the selection: a clip right after itself, an overlay or
  /// sound right after itself on the first free lane from its own.
  void duplicateSelected() {
    switch (_selection) {
      case NoSelection():
        return;
      case ClipSelection():
        final index = selectedIndex;
        if (index < 0) return;
        final copy = _project.clips[index].copyWith(id: _newId());
        final clips = [..._project.clips]..insert(index + 1, copy);
        _commit(
          _project.copyWith(clips: clips),
          select: TimelineSelection.clip(copy.id),
        );
      case OverlaySelection(:final id):
        final source = overlayById(id)!;
        final start = source.end;
        final copy = source.copyWith(
          id: _newId(),
          start: start,
          lane: _freeOverlayLane(
            start,
            start + source.duration,
            from: source.lane,
          ),
        );
        _commit(
          _project.copyWith(overlays: [..._project.overlays, copy]),
          select: TimelineSelection.overlay(copy.id),
        );
      case AudioSelection(:final id):
        final source = audioById(id)!;
        final start = source.end;
        final copy = source.copyWith(
          id: _newId(),
          start: start,
          lane: _freeAudioLane(
            start,
            start + source.duration,
            from: source.lane,
          ),
        );
        _commit(
          _project.copyWith(audioClips: [..._project.audioClips, copy]),
          select: TimelineSelection.audio(copy.id),
        );
    }
  }

  /// Moves the selected clip by [delta] places.
  void moveSelected(int delta) {
    final index = selectedIndex;
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _project.clips.length) return;
    reorder(index, target);
  }

  /// Moves clip [from] to place [to] on the main track.
  void reorder(int from, int to) {
    if (from == to) return;
    final clips = [..._project.clips];
    final clip = clips.removeAt(from);
    clips.insert(to.clamp(0, clips.length), clip);
    // The first clip never transitions in.
    clips[0] = clips[0].copyWith(transition: ClipTransition.cut);
    _commit(
      _project.copyWith(clips: clips),
      select: TimelineSelection.clip(clip.id),
    );
  }

  /// Sets how the selected clip enters from the previous one.
  void setTransition(ClipTransition transition) {
    if (selectedIndex <= 0) return;
    setTransitionAt(selectedIndex, transition);
  }

  /// Sets the transition at the junction before clip [index] (1 or more).
  void setTransitionAt(int index, ClipTransition transition) {
    if (index <= 0 || index >= _project.clips.length) return;
    if (_project.clips[index].transition == transition) return;
    final clips = [..._project.clips];
    clips[index] = clips[index].copyWith(transition: transition);
    _commit(_project.copyWith(clips: clips));
  }

  /// Uses [transition] at every junction.
  void applyTransitionToAll(ClipTransition transition) {
    if (_project.clips.length < 2) return;
    _commit(
      _project.copyWith(
        clips: [
          for (final (i, clip) in _project.clips.indexed)
            i == 0 ? clip : clip.copyWith(transition: transition),
        ],
      ),
    );
  }

  /// Length of every crossfade and dip, 0.1…2 s.
  void setTransitionSeconds(double seconds) {
    final value = seconds.clamp(0.1, 2.0).toDouble();
    if (value == _project.transitionSeconds) return;
    _commit(_project.copyWith(transitionSeconds: value));
  }

  /// How long the selected photo, photo overlay, or title stays on screen.
  void setStillSeconds(double seconds) {
    final value = seconds
        .clamp(TimelineClip.minSeconds, TimelineClip.maxStillSeconds)
        .toDouble();
    final overlay = selectedOverlay;
    if (overlay != null) {
      if (!overlay.isVideo) {
        updateOverlay(overlay.id, (o) => o.copyWith(stillSeconds: value));
      }
      return;
    }
    _updateSelected((clip) => clip.copyWith(stillSeconds: value));
  }

  /// Sets the in point of the selected video to the playhead.
  bool trimStartToPlayhead() {
    final clip = selectedClip;
    final entry = clip == null ? null : entryFor(clip.id);
    if (entry == null || clip == null || !clip.isVideo) return false;
    if (_playhead < entry.start || _playhead > entry.end) return false;
    final local = entry.localTime(_playhead);
    if (clip.duration - local < TimelineClip.minSeconds) return false;
    _commit(
      _withClip(
        _project,
        clip.id,
        (c) => c.copyWith(sourceStart: c.sourceTimeAt(local)),
      ),
    );
    _playhead = entry.start;
    notifyListeners();
    return true;
  }

  /// Sets the out point of the selected video (or a photo's length) to the
  /// playhead.
  bool trimEndToPlayhead() {
    final clip = selectedClip;
    final entry = clip == null ? null : entryFor(clip.id);
    if (entry == null || clip == null) return false;
    if (_playhead < entry.start || _playhead > entry.end) return false;
    final local = entry.localTime(_playhead);
    if (local < TimelineClip.minSeconds) return false;
    if (clip.isVideo) {
      _updateSelected((c) => c.copyWith(sourceEnd: c.sourceTimeAt(local)));
    } else {
      setStillSeconds(local);
    }
    return true;
  }

  void setMotion(ClipMotion motion) =>
      _updateSelected((clip) => clip.copyWith(motion: motion));

  void toggleMute() =>
      _updateSelected((clip) => clip.copyWith(muted: !clip.muted));

  /// Whether every main video clip is silent.
  bool get clipAudioMuted {
    final videos = _project.clips.where((c) => c.isVideo);
    return videos.isNotEmpty && videos.every((c) => c.gain <= 0);
  }

  /// CapCut's "mute clip audio": silences every main video clip, or turns
  /// their sound back on.
  void toggleClipAudio() {
    if (!_project.clips.any((c) => c.isVideo)) return;
    final mute = !clipAudioMuted;
    _commit(
      _project.copyWith(
        clips: [
          for (final clip in _project.clips)
            if (!clip.isVideo)
              clip
            else if (mute)
              clip.copyWith(muted: true)
            else
              clip.copyWith(
                muted: false,
                volume: clip.volume <= 0 ? 1 : clip.volume,
              ),
        ],
      ),
    );
  }

  /// Grades the selected clip or overlay. A `null` grade leaves an overlay's
  /// colours as they are; clips always have one.
  void setGrade(RestorationSettings? grade) {
    switch (_selection) {
      case ClipSelection(:final id):
        if (grade != null) updateClip(id, (c) => c.copyWith(grade: grade));
      case OverlaySelection(:final id):
        updateOverlay(
          id,
          (o) => grade == null
              ? o.copyWith(clearGrade: true)
              : o.copyWith(grade: grade),
        );
      case NoSelection() || AudioSelection():
        return;
    }
  }

  void setLook(LutProfile look) {
    switch (_selection) {
      case ClipSelection(:final id):
        updateClip(id, (c) => c.copyWith(look: look));
      case OverlaySelection(:final id):
        updateOverlay(id, (o) => o.copyWith(look: look));
      case NoSelection() || AudioSelection():
        return;
    }
  }

  /// Copies the selected clip's grade and look to every clip, the quick way
  /// to match a whole dive.
  void applyGradeToAll() {
    final source = selectedClip;
    if (source == null) return;
    _commit(
      _project.copyWith(
        clips: [
          for (final clip in _project.clips)
            clip.copyWith(grade: source.grade, look: source.look),
        ],
      ),
    );
  }

  /// Swaps the selected clip's media and keeps its edits. Returns false for
  /// files that cannot go on a timeline.
  bool replaceSelectedClip(String path, {double? videoDuration}) {
    final clip = selectedClip;
    if (clip == null) return false;
    final MediaKind kind;
    try {
      kind = MediaClassifier.classify(path);
    } on UnsupportedError {
      return false;
    }
    if (kind == MediaKind.rawVideo) return false;
    final isVideo = kind.isVideo;
    final replacement = TimelineClip(
      id: clip.id,
      path: path,
      kind: isVideo ? TimelineClipKind.video : TimelineClipKind.image,
      sourceDuration: isVideo ? videoDuration : null,
      sourceEnd: isVideo ? videoDuration : null,
      stillSeconds: isVideo
          ? clip.stillSeconds
          : clip.duration
                .clamp(TimelineClip.minSeconds, TimelineClip.maxStillSeconds)
                .toDouble(),
      grade: clip.grade,
      look: clip.look,
      transition: clip.transition,
      motion: clip.motion,
      muted: clip.muted,
      speed: clip.speed,
      volume: clip.volume,
      fadeIn: clip.fadeIn,
      fadeOut: clip.fadeOut,
      fadeColor: clip.fadeColor,
      effects: clip.effects,
    );
    updateClip(clip.id, (_) => replacement);
    return true;
  }

  void setAspect(TimelineAspect aspect) {
    if (aspect == _project.aspect) return;
    _commit(_project.copyWith(aspect: aspect));
  }

  void updateProject(TimelineProject Function(TimelineProject) change) =>
      _commit(change(_project));

  // ---------------------------------------------------------------------
  // Overlays, titles, and audio
  // ---------------------------------------------------------------------

  static bool _overlaps(
    double aStart,
    double aEnd,
    double bStart,
    double bEnd,
  ) => aStart < bEnd - _epsilon && bStart < aEnd - _epsilon;

  int _freeOverlayLane(
    double start,
    double end, {
    int from = 0,
    String? exclude,
  }) {
    for (var lane = math.max(0, from); ; lane++) {
      final busy = _project.overlays.any(
        (o) =>
            o.id != exclude &&
            o.lane == lane &&
            _overlaps(start, end, math.max(0, o.start), o.end),
      );
      if (!busy) return lane;
    }
  }

  int _freeAudioLane(
    double start,
    double end, {
    int from = 0,
    String? exclude,
  }) {
    for (var lane = math.max(0, from); ; lane++) {
      final busy = _project.audioClips.any(
        (a) =>
            a.id != exclude &&
            a.lane == lane &&
            _overlaps(start, end, math.max(0, a.start), a.end),
      );
      if (!busy) return lane;
    }
  }

  /// Where a new item of [duration] starts: at the playhead, or early enough
  /// to be seen when the playhead sits at the very end.
  double _insertStart(double duration) {
    final total = _project.duration;
    if (_playhead + 0.5 > total) {
      return math.max(0, math.min(_playhead, total - duration));
    }
    return _playhead;
  }

  /// Adds a photo or video overlay at the playhead on the first free lane,
  /// centred, 60 % of the canvas width (less for tall media, so it fits).
  String addOverlay({
    required String path,
    required OverlayKind kind,
    double mediaAspect = 16 / 9,
    double? sourceDuration,
  }) {
    assert(kind != OverlayKind.text, 'Use addTitle for titles.');
    final (:width, :height) = _project.outputSize;
    final aspect = mediaAspect.isFinite && mediaAspect > 0
        ? mediaAspect
        : 16 / 9;
    final widthFraction = math
        .min(0.6, 0.6 * aspect * height / width)
        .clamp(
          TimelineOverlay.minWidthFraction,
          TimelineOverlay.maxWidthFraction,
        )
        .toDouble();
    final isVideo = kind == OverlayKind.video;
    final draft = TimelineOverlay(
      id: _newId(),
      kind: kind,
      path: path,
      sourceDuration: isVideo ? sourceDuration : null,
      sourceEnd: isVideo ? sourceDuration : null,
      mediaAspect: aspect,
      widthFraction: widthFraction,
    );
    final start = _insertStart(draft.duration);
    final overlay = draft.copyWith(
      start: start,
      lane: _freeOverlayLane(start, start + draft.duration),
    );
    _commit(
      _project.copyWith(overlays: [..._project.overlays, overlay]),
      select: TimelineSelection.overlay(overlay.id),
    );
    return overlay.id;
  }

  ({double width, double height}) _measure(TitleSpec title) {
    final (:width, :height) = _project.outputSize;
    final measured = _titleMeasure(
      title.text.trim().isEmpty ? title.copyWith(text: 'Title') : title,
      width,
      height,
    );
    return (
      width: math.max(1.0, measured.width),
      height: math.max(1.0, measured.height),
    );
  }

  ({double widthFraction, double aspect}) _titleGeometry(
    TitleSpec title, {
    double scale = 1,
  }) {
    final size = _measure(title);
    return (
      widthFraction: (scale * size.width / _project.outputSize.width)
          .clamp(
            TimelineOverlay.minWidthFraction,
            TimelineOverlay.maxWidthFraction,
          )
          .toDouble(),
      aspect: size.width / size.height,
    );
  }

  /// How much bigger than its 1:1 rasterised size a title is shown; pinching
  /// it in the viewer changes this.
  double titleScale(TimelineOverlay overlay) {
    final title = overlay.title;
    if (title == null) return 1;
    final size = _measure(title);
    return overlay.widthFraction * _project.outputSize.width / size.width;
  }

  /// A title's shown text height as a fraction of the canvas height.
  double titleSize(TimelineOverlay overlay) =>
      (overlay.title?.fontScale ?? TitleSpec.defaultFontScale) *
      titleScale(overlay);

  /// Adds a title at the playhead on the first free lane, 3 s long.
  String addTitle({
    String text = 'Title',
    TitleStyle style = TitleStyle.classic,
  }) {
    final spec = TitleSpec(text: text, style: style);
    final geometry = _titleGeometry(spec);
    final draft = TimelineOverlay(
      id: _newId(),
      kind: OverlayKind.text,
      title: spec,
      centerY: style == TitleStyle.caption ? 0.86 : 0.5,
      widthFraction: geometry.widthFraction,
      mediaAspect: geometry.aspect,
    );
    final start = _insertStart(draft.duration);
    final overlay = draft.copyWith(
      start: start,
      lane: _freeOverlayLane(start, start + draft.duration),
    );
    _commit(
      _project.copyWith(overlays: [..._project.overlays, overlay]),
      select: TimelineSelection.overlay(overlay.id),
    );
    return overlay.id;
  }

  /// Changes a title's text or style and keeps its shown text size, so
  /// longer text widens the item rather than shrinking the letters.
  void updateTitle(String id, TitleSpec title) {
    final overlay = overlayById(id);
    if (overlay == null || overlay.title == null || overlay.title == title) {
      return;
    }
    final geometry = _titleGeometry(title, scale: titleScale(overlay));
    updateOverlay(
      id,
      (o) => o.copyWith(
        title: title,
        widthFraction: geometry.widthFraction,
        mediaAspect: geometry.aspect,
      ),
    );
  }

  /// Sets a title's shown text height, as a fraction of the canvas height.
  void setTitleSize(String id, double size) {
    final title = overlayById(id)?.title;
    if (title == null) return;
    final spec = title.copyWith(fontScale: size.clamp(0.02, 0.25).toDouble());
    final geometry = _titleGeometry(spec);
    updateOverlay(
      id,
      (o) => o.copyWith(
        title: spec,
        widthFraction: geometry.widthFraction,
        mediaAspect: geometry.aspect,
      ),
    );
  }

  /// Adds a sound at the playhead on the first free audio lane.
  String addAudio({
    required String path,
    String? name,
    double? sourceDuration,
    AudioRole role = AudioRole.music,
  }) {
    final draft = TimelineAudioClip(
      id: _newId(),
      path: path,
      name: name ?? p.basenameWithoutExtension(path),
      role: role,
      sourceDuration: sourceDuration,
      sourceEnd: sourceDuration,
    );
    final start = _insertStart(math.min(draft.duration, 3));
    final item = draft.copyWith(
      start: start,
      lane: _freeAudioLane(start, start + draft.duration),
    );
    _commit(
      _project.copyWith(audioClips: [..._project.audioClips, item]),
      select: TimelineSelection.audio(item.id),
    );
    return item.id;
  }

  /// The main video clip "Extract audio" works on: the selected clip, or the
  /// clip under the playhead.
  TimelineEntry? get extractAudioSource {
    final selected = selectedClip;
    final entry = selected != null ? entryFor(selected.id) : entryAtPlayhead;
    return entry != null && entry.clip.isVideo ? entry : null;
  }

  /// Moves a video clip's sound to its own audio item, aligned with the
  /// clip, and sets the clip's volume to 0. Returns the new item's id.
  String? extractAudio() {
    final entry = extractAudioSource;
    if (entry == null) return null;
    final clip = entry.clip;
    final draft = TimelineAudioClip(
      id: _newId(),
      path: clip.path,
      name: '${p.basenameWithoutExtension(clip.path)} audio',
      role: AudioRole.extracted,
      start: entry.start,
      sourceStart: clip.sourceStart,
      sourceEnd: clip.sourceStart + clip.sourceSpan,
      sourceDuration: clip.sourceDuration,
      volume: clip.gain > 0 ? clip.volume : 1,
    );
    final item = draft.copyWith(
      lane: _freeAudioLane(draft.start, draft.start + draft.duration),
    );
    _commit(
      _withClip(
        _project,
        clip.id,
        (c) => c.copyWith(volume: 0),
      ).copyWith(audioClips: [..._project.audioClips, item]),
      select: TimelineSelection.audio(item.id),
    );
    return item.id;
  }

  /// Times an overlay or sound can snap to: the movie's ends, the playhead,
  /// and the edges of every other item.
  List<double> snapPoints({String? exclude}) => [
    0,
    _playhead,
    layout.duration,
    for (final entry in layout.entries)
      if (entry.clip.id != exclude) ...[entry.start, entry.end],
    for (final o in _project.overlays)
      if (o.id != exclude) ...[math.max(0, o.start), o.end],
    for (final a in _project.audioClips)
      if (a.id != exclude) ...[math.max(0, a.start), a.end],
  ];

  /// [start] of an item [duration] long, moved onto the nearest snap point
  /// within [tolerance] seconds by its start or its end. [snappedTo] is the
  /// point it snapped to, or `null`.
  ({double start, double? snappedTo}) snapStart(
    double start,
    double duration, {
    String? exclude,
    double tolerance = snapSeconds,
  }) {
    var best = tolerance;
    double? snappedTo;
    var result = start;
    for (final point in snapPoints(exclude: exclude)) {
      final byStart = (point - start).abs();
      if (byStart <= best) {
        best = byStart;
        snappedTo = point;
        result = point;
      }
      final byEnd = (point - (start + duration)).abs();
      if (byEnd < best) {
        best = byEnd;
        snappedTo = point;
        result = point - duration;
      }
    }
    return (start: math.max(0.0, result), snappedTo: snappedTo);
  }

  /// [time] moved onto the nearest snap point within [tolerance], for trim
  /// edges.
  ({double time, double? snappedTo}) snapTime(
    double time, {
    String? exclude,
    double tolerance = snapSeconds,
  }) {
    var best = tolerance;
    double? snappedTo;
    for (final point in snapPoints(exclude: exclude)) {
      final delta = (point - time).abs();
      if (delta <= best) {
        best = delta;
        snappedTo = point;
      }
    }
    return (time: snappedTo ?? time, snappedTo: snappedTo);
  }

  /// Moves an overlay or sound to [start] and, optionally, [lane]. With
  /// [resolveConflicts], an item that would overlap another on its lane goes
  /// to the next free lane, as when a drag ends.
  void moveItem(
    String id, {
    double? start,
    int? lane,
    bool resolveConflicts = true,
  }) {
    final overlay = overlayById(id);
    if (overlay != null) {
      final s = math.max(0.0, start ?? overlay.start);
      var l = lane ?? overlay.lane;
      if (resolveConflicts) {
        l = _freeOverlayLane(s, s + overlay.duration, from: l, exclude: id);
      }
      if (s == overlay.start && l == overlay.lane) return;
      updateOverlay(id, (o) => o.copyWith(start: s, lane: l));
      return;
    }
    final audio = audioById(id);
    if (audio != null) {
      final s = math.max(0.0, start ?? audio.start);
      var l = lane ?? audio.lane;
      if (resolveConflicts) {
        l = _freeAudioLane(s, s + audio.duration, from: l, exclude: id);
      }
      if (s == audio.start && l == audio.lane) return;
      updateAudio(id, (a) => a.copyWith(start: s, lane: l));
    }
  }

  /// Moves one end of an item by [delta] timeline seconds from where it was
  /// when the current gesture began (or from now, outside a gesture). Main
  /// clips keep their place on the magnetic track and change length;
  /// overlays and sounds move their start when trimmed at the front.
  void trimItem(String id, TrimEdge edge, double delta) {
    final base = _gestureBase ?? _project;
    for (final c in base.clips) {
      if (c.id == id) {
        updateClip(id, (_) => _trimClip(c, edge, delta));
        return;
      }
    }
    for (final o in base.overlays) {
      if (o.id == id) {
        updateOverlay(id, (_) => _trimOverlay(o, edge, delta));
        return;
      }
    }
    for (final a in base.audioClips) {
      if (a.id == id) {
        updateAudio(id, (_) => _trimAudio(a, edge, delta));
        return;
      }
    }
  }

  static TimelineClip _trimClip(TimelineClip c, TrimEdge edge, double delta) {
    const min = TimelineClip.minSeconds;
    if (!c.isVideo) {
      final seconds =
          c.stillSeconds + (edge == TrimEdge.start ? -delta : delta);
      return c.copyWith(
        stillSeconds: seconds
            .clamp(min, TimelineClip.maxStillSeconds)
            .toDouble(),
      );
    }
    final speed = c.playbackSpeed;
    final end = c.sourceStart + c.sourceSpan;
    if (edge == TrimEdge.start) {
      final start = (c.sourceStart + delta * speed)
          .clamp(0.0, math.max(0.0, end - min * speed))
          .toDouble();
      return c.copyWith(sourceStart: start, sourceEnd: end);
    }
    final limit = c.sourceDuration ?? end;
    return c.copyWith(
      sourceEnd: (end + delta * speed)
          .clamp(c.sourceStart + min * speed, math.max(end, limit))
          .toDouble(),
    );
  }

  static TimelineOverlay _trimOverlay(
    TimelineOverlay o,
    TrimEdge edge,
    double delta,
  ) {
    const min = TimelineOverlay.minSeconds;
    final start = math.max(0.0, o.start);
    final speed = o.playbackSpeed;
    if (edge == TrimEdge.start) {
      var d = math.max(delta, -start);
      if (o.isVideo) d = math.max(d, -o.sourceStart / speed);
      d = math.min(d, o.duration - min);
      return o.isVideo
          ? o.copyWith(
              start: start + d,
              sourceStart: o.sourceStart + d * speed,
              sourceEnd: o.sourceStart + o.sourceSpan,
            )
          : o.copyWith(start: start + d, stillSeconds: o.stillSeconds - d);
    }
    if (!o.isVideo) {
      return o.copyWith(stillSeconds: math.max(min, o.stillSeconds + delta));
    }
    final end = o.sourceStart + o.sourceSpan;
    final limit = o.sourceDuration ?? end;
    return o.copyWith(
      sourceEnd: (end + delta * speed)
          .clamp(o.sourceStart + min * speed, math.max(end, limit))
          .toDouble(),
    );
  }

  static TimelineAudioClip _trimAudio(
    TimelineAudioClip a,
    TrimEdge edge,
    double delta,
  ) {
    const min = TimelineAudioClip.minSeconds;
    final start = math.max(0.0, a.start);
    final end = a.sourceStart + a.sourceSpan;
    if (edge == TrimEdge.start) {
      final d = math.min(
        math.max(delta, math.max(-start, -a.sourceStart)),
        a.duration - min,
      );
      return a.copyWith(
        start: start + d,
        sourceStart: a.sourceStart + d,
        sourceEnd: end,
      );
    }
    final limit = a.sourceDuration ?? end;
    return a.copyWith(
      sourceEnd: (end + delta)
          .clamp(a.sourceStart + min, math.max(end, limit))
          .toDouble(),
    );
  }

  /// Moves the selected overlay one layer up ([delta] > 0) or down. An
  /// overlay it would overlap on that lane trades places with it; at the top
  /// or bottom, an overlay sharing its lane gets a new lane of its own.
  void moveLayer(int delta) {
    final overlay = selectedOverlay;
    if (overlay == null || delta == 0) return;
    final lanes = _project.overlays.map((o) => o.lane).toSet().length;
    final alone = _project.overlays.every(
      (o) => o.id == overlay.id || o.lane != overlay.lane,
    );
    final target = overlay.lane + delta.sign;
    if ((target < 0 || target >= lanes) && alone) return;
    final start = math.max(0.0, overlay.start);
    _commit(
      _project.copyWith(
        overlays: [
          for (final o in _project.overlays)
            if (o.id == overlay.id)
              o.copyWith(lane: target)
            else if (o.lane == target &&
                _overlaps(start, overlay.end, math.max(0, o.start), o.end))
              o.copyWith(lane: overlay.lane)
            else
              o,
        ],
      ),
    );
  }

  /// Layer of the selected overlay (1 = lowest) and the number of layers.
  ({int layer, int of})? get selectedLayer {
    final overlay = selectedOverlay;
    if (overlay == null) return null;
    final lanes = _project.overlays.map((o) => o.lane).toSet().length;
    return (layer: overlay.lane + 1, of: lanes);
  }

  // ---------------------------------------------------------------------
  // Tools on the selection
  // ---------------------------------------------------------------------

  /// Playback speed of the selected video clip or video overlay.
  void setSpeed(double speed) {
    final value = TimelineSpeed.clamp(speed);
    switch (_selection) {
      case ClipSelection(:final id):
        updateClip(id, (c) => c.copyWith(speed: value));
      case OverlaySelection(:final id):
        updateOverlay(id, (o) => o.copyWith(speed: value));
      case NoSelection() || AudioSelection():
        return;
    }
  }

  /// Audio level, 0…1, of the selected clip, video overlay, or sound. Moving
  /// the level also turns a muted item back on.
  void setVolume(double volume) {
    final value = volume.clamp(0.0, 1.0).toDouble();
    switch (_selection) {
      case ClipSelection(:final id):
        updateClip(id, (c) => c.copyWith(volume: value, muted: false));
      case OverlaySelection(:final id):
        updateOverlay(id, (o) => o.copyWith(volume: value, muted: false));
      case AudioSelection(:final id):
        updateAudio(id, (a) => a.copyWith(volume: value));
      case NoSelection():
        return;
    }
  }

  /// Mutes or unmutes the selection. Sounds have no mute flag, so they go to
  /// 0 % and back to 100 %.
  void setMuted(bool muted) {
    switch (_selection) {
      case ClipSelection(:final id):
        updateClip(
          id,
          (c) => c.copyWith(
            muted: muted,
            volume: !muted && c.volume <= 0 ? 1 : null,
          ),
        );
      case OverlaySelection(:final id):
        updateOverlay(
          id,
          (o) => o.copyWith(
            muted: muted,
            volume: !muted && o.volume <= 0 ? 1 : null,
          ),
        );
      case AudioSelection(:final id):
        updateAudio(id, (a) => a.copyWith(volume: muted ? 0 : 1));
      case NoSelection():
        return;
    }
  }

  /// Fade lengths of the selected clip, overlay, or sound.
  void setFades({double? fadeIn, double? fadeOut}) {
    double? clean(double? v, double max) => v?.clamp(0.0, max).toDouble();
    switch (_selection) {
      case ClipSelection(:final id):
        updateClip(
          id,
          (c) => c.copyWith(
            fadeIn: clean(fadeIn, TimelineClip.maxFadeSeconds),
            fadeOut: clean(fadeOut, TimelineClip.maxFadeSeconds),
          ),
        );
      case OverlaySelection(:final id):
        updateOverlay(
          id,
          (o) => o.copyWith(
            fadeIn: clean(fadeIn, TimelineOverlay.maxFadeSeconds),
            fadeOut: clean(fadeOut, TimelineOverlay.maxFadeSeconds),
          ),
        );
      case AudioSelection(:final id):
        updateAudio(
          id,
          (a) => a.copyWith(
            fadeIn: clean(fadeIn, TimelineAudioClip.maxFadeSeconds),
            fadeOut: clean(fadeOut, TimelineAudioClip.maxFadeSeconds),
          ),
        );
      case NoSelection():
        return;
    }
  }

  void setFadeColor(FadeColor color) =>
      _updateSelected((c) => c.copyWith(fadeColor: color));

  /// The item the Effects tool edits: the selected clip or overlay, or the
  /// main clip under the playhead when nothing is selected.
  TimelineSelection get effectTarget => switch (_selection) {
    NoSelection() => switch (entryAtPlayhead) {
      final entry? => TimelineSelection.clip(entry.clip.id),
      null => const TimelineSelection.none(),
    },
    AudioSelection() => const TimelineSelection.none(),
    final other => other,
  };

  /// Effects of the [effectTarget].
  List<ClipEffect> get targetEffects => switch (effectTarget) {
    ClipSelection(:final id) => clipById(id)?.effects ?? const [],
    OverlaySelection(:final id) => overlayById(id)?.effects ?? const [],
    _ => const [],
  };

  void _updateTargetEffects(
    List<ClipEffect> Function(List<ClipEffect> effects) change,
  ) {
    switch (effectTarget) {
      case ClipSelection(:final id):
        updateClip(id, (c) => c.copyWith(effects: change(c.effects)));
      case OverlaySelection(:final id):
        updateOverlay(id, (o) => o.copyWith(effects: change(o.effects)));
      case NoSelection() || AudioSelection():
        return;
    }
  }

  /// Adds [type] to the [effectTarget], or removes it when it is there.
  /// Returns whether the effect is on afterwards.
  bool toggleEffect(EffectType type) {
    final target = effectTarget;
    if (target.isNone) return false;
    if (target is OverlaySelection && !type.overlayAllowed) return false;
    final on = targetEffects.any((e) => e.type == type);
    _updateTargetEffects(
      (effects) => on
          ? [
              for (final e in effects)
                if (e.type != type) e,
            ]
          : [...effects, ClipEffect(type)],
    );
    return !on;
  }

  void setEffectIntensity(EffectType type, double intensity) =>
      _updateTargetEffects(
        (effects) => [
          for (final e in effects)
            e.type == type ? e.copyWith(intensity: intensity) : e,
        ],
      );

  void removeEffect(EffectType type) => _updateTargetEffects(
    (effects) => [
      for (final e in effects)
        if (e.type != type) e,
    ],
  );

  void setOpacity(double opacity) {
    final overlay = selectedOverlay;
    if (overlay == null) return;
    updateOverlay(
      overlay.id,
      (o) => o.copyWith(opacity: opacity.clamp(0.0, 1.0).toDouble()),
    );
  }

  void setAnimation({
    OverlayAnimation? animationIn,
    OverlayAnimation? animationOut,
  }) {
    final overlay = selectedOverlay;
    if (overlay == null) return;
    updateOverlay(
      overlay.id,
      (o) => o.copyWith(animationIn: animationIn, animationOut: animationOut),
    );
  }

  // ---------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------

  void _scheduleSave() {
    final store = _store;
    if (store == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, () => unawaited(store.save(_project)));
  }

  /// Writes pending changes now, for example before leaving the page.
  Future<void> flush() async {
    final store = _store;
    if (store == null) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    await store.save(_project);
  }

  @override
  void dispose() {
    final store = _store;
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      if (store != null) unawaited(store.save(_project));
    }
    super.dispose();
  }
}
