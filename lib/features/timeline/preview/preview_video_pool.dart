import 'dart:async';

import 'preview_player.dart';

/// A video the viewer wants this frame, in priority order.
class VideoRequest {
  const VideoRequest({
    required this.id,
    required this.path,
    required this.sourceTime,
    this.speed = 1,
    this.volume = 0,
    this.visible = true,
  });

  /// Clip or layer id; one player per item.
  final String id;
  final String path;

  /// Source second to show now (visible) or to wait at (upcoming).
  final double sourceTime;
  final double speed;

  /// Gain while playing, fades included.
  final double volume;

  /// On screen now; otherwise it starts soon and is only prepared.
  final bool visible;
}

/// Pooled video players for the preview.
///
/// At most [maxDecoding] visible items get a player that shows frames; the
/// rest show a poster. Up to [maxPlayers] players stay alive, so the next
/// clip can be prepared (initialised and parked on its first frame) before
/// the playhead reaches it, and scrubbing back over a recent cut does not
/// re-open the file. Players nobody asked for this frame are paused and
/// evicted least recently used first when a slot is needed; a player whose
/// file failed to open is not retried.
class PreviewVideoPool {
  PreviewVideoPool({
    required PreviewPlayerFactory create,
    this.maxDecoding = 2,
    this.maxPlayers = 3,
    PreviewClock? clock,
    this.onOpened,
  }) : assert(maxPlayers >= maxDecoding),
       _create = create,
       _clock = clock ?? stopwatchClock();

  final PreviewPlayerFactory _create;
  final PreviewClock _clock;
  final int maxDecoding;
  final int maxPlayers;

  /// Called (asynchronously) when the player of item `id` has opened, with
  /// `null` when its file could not be opened.
  final void Function(String id, PreviewPlayer? player)? onOpened;

  final Map<String, PreviewPlayerSlot> _slots = {};
  final Set<String> _failedPaths = {};
  final Set<String> _showing = {};
  bool _disposed = false;

  /// Ids with a live player, for tests and diagnostics.
  Iterable<String> get liveIds => _slots.keys;

  /// Whether item [id] has a player showing frames this frame.
  bool isShowing(String id) => _showing.contains(id);

  /// The opened player showing item [id] this frame, or `null` (poster).
  PreviewPlayer? playerFor(String id) {
    if (!_showing.contains(id)) return null;
    final slot = _slots[id];
    return slot != null && slot.ready ? slot.player : null;
  }

  /// Whether item [id] has a player that is still opening.
  bool isOpening(String id) {
    final slot = _slots[id];
    return slot != null && !slot.ready && !slot.failed;
  }

  /// Brings the pool in line with this frame's [requests] (visible first, by
  /// priority; then upcoming ones) and drives each player.
  void update(List<VideoRequest> requests, {required bool playing}) {
    if (_disposed) return;
    final now = _clock();
    _showing.clear();
    final admitted = <String, VideoRequest>{};
    // Visible items over the decode budget keep their player (they show a
    // poster), so an upcoming item never pushes out something on screen.
    final protected = {
      for (final request in requests)
        if (request.visible) request.id,
    };
    var decoding = 0;
    for (final request in requests) {
      if (admitted.containsKey(request.id)) continue;
      if (request.visible) {
        if (decoding >= maxDecoding) continue;
      } else if (!playing) {
        continue;
      }
      final slot = _admit(request, admitted, protected, now);
      if (slot == null) continue;
      admitted[request.id] = request;
      if (request.visible) {
        decoding++;
        _showing.add(request.id);
      }
    }
    for (final slot in _slots.values) {
      final request = admitted[slot.id];
      if (request == null) {
        slot.pause();
      } else if (!request.visible) {
        slot.park(request.sourceTime);
      } else if (playing) {
        slot.showPlaying(
          request.sourceTime,
          now: now,
          speed: request.speed,
          volume: request.volume,
        );
      } else {
        slot.showPaused(request.sourceTime);
      }
    }
  }

  PreviewPlayerSlot? _admit(
    VideoRequest request,
    Map<String, VideoRequest> admitted,
    Set<String> protected,
    double now,
  ) {
    var slot = _slots[request.id];
    if (slot != null && slot.path != request.path) {
      _evict(slot);
      slot = null;
    }
    if (slot != null) {
      slot.lastUsed = now;
      return slot;
    }
    if (_failedPaths.contains(request.path)) return null;
    // Take over an idle player of the same file (a split clip, a duplicate).
    for (final idle in _slots.values) {
      if (idle.path == request.path && !admitted.containsKey(idle.id)) {
        _slots.remove(idle.id);
        idle
          ..id = request.id
          ..lastUsed = now;
        return _slots[request.id] = idle;
      }
    }
    if (_slots.length >= maxPlayers) {
      final victim = _victim(admitted, request.visible ? const {} : protected);
      if (victim == null) return null;
      _evict(victim);
    }
    return _open(request, now);
  }

  /// The least recently used player not admitted this frame and not
  /// [protected].
  PreviewPlayerSlot? _victim(
    Map<String, VideoRequest> admitted,
    Set<String> protected,
  ) {
    PreviewPlayerSlot? best;
    for (final slot in _slots.values) {
      if (admitted.containsKey(slot.id) || protected.contains(slot.id)) {
        continue;
      }
      if (best == null || slot.lastUsed < best.lastUsed) best = slot;
    }
    return best;
  }

  PreviewPlayerSlot? _open(VideoRequest request, double now) {
    final PreviewPlayer player;
    try {
      player = _create(request.path);
    } on Object {
      _failedPaths.add(request.path);
      return null;
    }
    final slot = PreviewPlayerSlot(request.id, player, lastUsed: now);
    _slots[request.id] = slot;
    unawaited(
      player.initialize().then(
        (_) {
          if (slot.disposed || _disposed) return;
          slot.ready = true;
          onOpened?.call(slot.id, player);
        },
        onError: (Object _) {
          if (slot.disposed || _disposed) return;
          slot.failed = true;
          _failedPaths.add(request.path);
          if (identical(_slots[slot.id], slot)) _slots.remove(slot.id);
          slot.dispose();
          onOpened?.call(slot.id, null);
        },
      ),
    );
    return slot;
  }

  void _evict(PreviewPlayerSlot slot) {
    if (identical(_slots[slot.id], slot)) _slots.remove(slot.id);
    _showing.remove(slot.id);
    slot.dispose();
  }

  /// Releases every player.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final slot in _slots.values) {
      slot.dispose();
    }
    _slots.clear();
    _showing.clear();
  }
}
