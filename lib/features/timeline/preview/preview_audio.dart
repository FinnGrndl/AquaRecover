import 'dart:async';

import '../../../core/timeline/timeline_render_plan.dart';
import 'preview_math.dart';
import 'preview_player.dart';

/// Plays the project's audio items during preview playback.
///
/// Main-clip and video-overlay sound plays through their own video players;
/// this mixer only handles `PlanAudioOrigin.track` segments. While playing,
/// each segment under the playhead gets a player (at most [maxPlayers],
/// counting ones prepared [lookahead] seconds ahead), started at the right
/// source second, re-seeked when it drifts, and faded with throttled volume
/// calls. Scrubbing and pausing silence everything. Disabled where
/// `video_player` has no implementation (Windows).
class PreviewAudioMixer {
  PreviewAudioMixer({
    required PreviewPlayerFactory create,
    this.enabled = true,
    this.maxPlayers = 4,
    this.lookahead = 1.5,
    PreviewClock? clock,
  }) : _create = create,
       _clock = clock ?? stopwatchClock();

  final PreviewPlayerFactory _create;
  final PreviewClock _clock;
  final bool enabled;
  final int maxPlayers;
  final double lookahead;

  final Map<String, PreviewPlayerSlot> _slots = {};
  final Set<String> _failedPaths = {};
  bool _disposed = false;

  /// Segment ids with a live player, for tests.
  Iterable<String> get liveIds => _slots.keys;

  /// Drives the players for timeline time [t]. [segments] are the plan's
  /// audio items sorted by start.
  void update(List<PlanAudio> segments, double t, {required bool playing}) {
    if (!enabled || _disposed) return;
    if (!playing) {
      for (final slot in _slots.values) {
        slot.pause();
      }
      return;
    }
    final now = _clock();
    final admitted = <String, PlanAudio>{};
    // Sounding now first, then the ones about to start.
    for (final upcoming in const [false, true]) {
      for (final segment in segments) {
        if (segment.start > t + lookahead) break;
        final active = segment.start <= t && t < segment.end;
        final soon = segment.start > t;
        if (upcoming ? !soon : !active) continue;
        if (admitted.length >= maxPlayers) break;
        if (_admit(segment, admitted, now) != null) {
          admitted[segment.id] = segment;
        }
      }
    }
    for (final slot in _slots.values) {
      final segment = admitted[slot.id];
      if (segment == null) {
        slot.pause();
      } else if (segment.start > t) {
        slot.park(segment.sourceStart);
      } else {
        slot.showPlaying(
          segment.sourceStart + (t - segment.start) * segment.speed,
          now: now,
          speed: segment.speed,
          volume: PreviewAudioMath.gainAt(segment, t),
        );
      }
    }
  }

  PreviewPlayerSlot? _admit(
    PlanAudio segment,
    Map<String, PlanAudio> admitted,
    double now,
  ) {
    var slot = _slots[segment.id];
    if (slot != null && slot.path != segment.path) {
      _evict(slot);
      slot = null;
    }
    if (slot != null) {
      slot.lastUsed = now;
      return slot;
    }
    if (_failedPaths.contains(segment.path)) return null;
    for (final idle in _slots.values) {
      if (idle.path == segment.path && !admitted.containsKey(idle.id)) {
        _slots.remove(idle.id);
        idle
          ..id = segment.id
          ..lastUsed = now;
        return _slots[segment.id] = idle;
      }
    }
    if (_slots.length >= maxPlayers) {
      PreviewPlayerSlot? victim;
      for (final candidate in _slots.values) {
        if (admitted.containsKey(candidate.id)) continue;
        if (victim == null || candidate.lastUsed < victim.lastUsed) {
          victim = candidate;
        }
      }
      if (victim == null) return null;
      _evict(victim);
    }
    final PreviewPlayer player;
    try {
      player = _create(segment.path);
    } on Object {
      _failedPaths.add(segment.path);
      return null;
    }
    final created = PreviewPlayerSlot(segment.id, player, lastUsed: now);
    _slots[segment.id] = created;
    unawaited(
      player.initialize().then(
        (_) {
          if (created.disposed || _disposed) return;
          created.ready = true;
          // Silent until the first frame sets its level.
          unawaited(player.setVolume(0).catchError((Object _) {}));
        },
        onError: (Object _) {
          if (created.disposed || _disposed) return;
          created.failed = true;
          _failedPaths.add(segment.path);
          if (identical(_slots[created.id], created)) {
            _slots.remove(created.id);
          }
          created.dispose();
        },
      ),
    );
    return created;
  }

  void _evict(PreviewPlayerSlot slot) {
    if (identical(_slots[slot.id], slot)) _slots.remove(slot.id);
    slot.dispose();
  }

  /// Stops and releases every player.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final slot in _slots.values) {
      slot.dispose();
    }
    _slots.clear();
  }
}
