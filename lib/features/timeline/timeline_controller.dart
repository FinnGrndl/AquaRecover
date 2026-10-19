import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/media/media_classifier.dart';
import '../../core/models/lut_profile.dart';
import '../../core/models/media_kind.dart';
import '../../core/models/restoration_settings.dart';
import '../../core/timeline/timeline_project.dart';
import '../../core/timeline/timeline_project_store.dart';

/// Editing state of one timeline: the project, the selected clip, the
/// playhead, and undo history. Every edit replaces the immutable project, so
/// undo is a list of earlier projects.
class TimelineController extends ChangeNotifier {
  TimelineController(
    TimelineProject project, {
    TimelineProjectStore? store,
    this.autosaveDelay = const Duration(milliseconds: 600),
  }) : _project = project,
       _store = store,
       _selectedId = project.clips.isEmpty ? null : project.clips.first.id;

  static const maxUndo = 50;

  final TimelineProjectStore? _store;
  final Duration autosaveDelay;
  TimelineProject _project;
  String? _selectedId;
  double _playhead = 0;
  final List<TimelineProject> _undo = [];
  final List<TimelineProject> _redo = [];
  Timer? _saveTimer;
  int _idCounter = 0;

  TimelineProject get project => _project;
  double get playhead => _playhead;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  TimelineClip? get selectedClip {
    for (final clip in _project.clips) {
      if (clip.id == _selectedId) return clip;
    }
    return null;
  }

  int get selectedIndex =>
      _project.clips.indexWhere((clip) => clip.id == _selectedId);

  TimelineEntry? get entryAtPlayhead => _project.layout.entryAt(_playhead);

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_idCounter++).toRadixString(36)}';

  void _commit(TimelineProject next, {String? select}) {
    _undo.add(_project);
    if (_undo.length > maxUndo) _undo.removeAt(0);
    _redo.clear();
    _project = next;
    if (select != null) _selectedId = select;
    if (selectedClip == null) {
      _selectedId = next.clips.isEmpty ? null : next.clips.first.id;
    }
    _playhead = _playhead.clamp(0.0, next.duration).toDouble();
    _scheduleSave();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_project);
    _project = _undo.removeLast();
    if (selectedClip == null && _project.clips.isNotEmpty) {
      _selectedId = _project.clips.first.id;
    }
    _playhead = _playhead.clamp(0.0, _project.duration).toDouble();
    _scheduleSave();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_project);
    _project = _redo.removeLast();
    _playhead = _playhead.clamp(0.0, _project.duration).toDouble();
    _scheduleSave();
    notifyListeners();
  }

  void select(String id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Moves the playhead and selects the clip under it.
  void seek(double seconds, {bool selectClip = true}) {
    _playhead = seconds.clamp(0.0, _project.duration).toDouble();
    if (selectClip) {
      final entry = entryAtPlayhead;
      if (entry != null) _selectedId = entry.clip.id;
    }
    notifyListeners();
  }

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
    _commit(_project.copyWith(clips: clips), select: added.first.id);
    return skipped;
  }

  /// Fills in a video's length once a player has read it, without an undo
  /// step, because the user did not change anything.
  void setSourceDuration(String id, double seconds) {
    if (!seconds.isFinite || seconds <= 0) return;
    final clips = [
      for (final clip in _project.clips)
        if (clip.id == id && clip.sourceDuration != seconds)
          clip.copyWith(
            sourceDuration: seconds,
            sourceEnd: clip.sourceEnd == null || clip.sourceEnd! > seconds
                ? seconds
                : clip.sourceEnd,
          )
        else
          clip,
    ];
    _project = _project.copyWith(clips: clips);
    _scheduleSave();
    notifyListeners();
  }

  void _updateSelected(TimelineClip Function(TimelineClip clip) change) {
    final selected = selectedClip;
    if (selected == null) return;
    _commit(
      _project.copyWith(
        clips: [
          for (final clip in _project.clips)
            clip.id == selected.id ? change(clip) : clip,
        ],
      ),
    );
  }

  /// Blade tool: splits the clip under the playhead.
  bool splitAtPlayhead() {
    final entry = entryAtPlayhead;
    if (entry == null) return false;
    final parts = entry.clip.splitAt(
      entry.localTime(_playhead),
      newId: _newId(),
    );
    if (parts == null) return false;
    final (left, right) = parts;
    final clips = [..._project.clips];
    clips
      ..removeAt(entry.index)
      ..insertAll(entry.index, [left, right.copyWith()]);
    _commit(_project.copyWith(clips: clips), select: right.id);
    return true;
  }

  void deleteSelected() {
    final index = selectedIndex;
    if (index < 0) return;
    final clips = [..._project.clips]..removeAt(index);
    if (clips.isNotEmpty && index == 0) {
      clips[0] = clips[0].copyWith(transition: ClipTransition.cut);
    }
    final next = clips.isEmpty
        ? null
        : clips[math.min(index, clips.length - 1)];
    _commit(_project.copyWith(clips: clips), select: next?.id);
  }

  void duplicateSelected() {
    final index = selectedIndex;
    if (index < 0) return;
    final copy = TimelineClip.fromJson({
      ..._project.clips[index].toJson(),
      'id': _newId(),
    });
    final clips = [..._project.clips]..insert(index + 1, copy);
    _commit(_project.copyWith(clips: clips), select: copy.id);
  }

  /// Moves the selected clip by [delta] places.
  void moveSelected(int delta) {
    final index = selectedIndex;
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _project.clips.length) return;
    reorder(index, target);
  }

  void reorder(int from, int to) {
    if (from == to) return;
    final clips = [..._project.clips];
    final clip = clips.removeAt(from);
    clips.insert(to.clamp(0, clips.length), clip);
    // The first clip never transitions in.
    clips[0] = clips[0].copyWith(transition: ClipTransition.cut);
    _commit(_project.copyWith(clips: clips), select: clip.id);
  }

  void setTransition(ClipTransition transition) {
    if (selectedIndex <= 0) return;
    _updateSelected((clip) => clip.copyWith(transition: transition));
  }

  void setStillSeconds(double seconds) => _updateSelected(
    (clip) => clip.copyWith(
      stillSeconds: seconds
          .clamp(TimelineClip.minSeconds, TimelineClip.maxStillSeconds)
          .toDouble(),
    ),
  );

  /// Sets the in point of the selected video to the playhead.
  bool trimStartToPlayhead() {
    final entry = entryAtPlayhead;
    final clip = selectedClip;
    if (entry == null || clip == null || entry.clip.id != clip.id) {
      return false;
    }
    if (!clip.isVideo) return false;
    final local = entry.localTime(_playhead);
    if (clip.duration - local < TimelineClip.minSeconds) return false;
    _commit(
      _project.copyWith(
        clips: [
          for (final c in _project.clips)
            c.id == clip.id
                ? c.copyWith(sourceStart: c.sourceTimeAt(local))
                : c,
        ],
      ),
    );
    _playhead = entry.start;
    notifyListeners();
    return true;
  }

  /// Sets the out point of the selected video to the playhead.
  bool trimEndToPlayhead() {
    final entry = entryAtPlayhead;
    final clip = selectedClip;
    if (entry == null || clip == null || entry.clip.id != clip.id) {
      return false;
    }
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

  void setGrade(RestorationSettings grade) =>
      _updateSelected((clip) => clip.copyWith(grade: grade));

  void setLook(LutProfile look) =>
      _updateSelected((clip) => clip.copyWith(look: look));

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

  void updateProject(TimelineProject Function(TimelineProject) change) =>
      _commit(change(_project));

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
