import 'package:flutter/foundation.dart';

import '../../core/logbook/dive_log.dart';
import '../../core/logbook/dive_log_store.dart';
import '../../core/logbook/media_matching.dart';

/// Holds the logbook while its screens are open and saves every change.
class LogbookController extends ChangeNotifier {
  LogbookController({DiveLogStore? store}) : _store = store ?? DiveLogStore();

  final DiveLogStore _store;
  DiveLog _log = const DiveLog();
  bool _loading = true;

  DiveLog get log => _log;
  bool get loading => _loading;

  Future<void> load() async {
    try {
      _log = await _store.load();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _set(DiveLog log) async {
    _log = log;
    notifyListeners();
    await _store.save(log);
  }

  Dive? dive(String id) {
    for (final dive in _log.dives) {
      if (dive.id == id) return dive;
    }
    return null;
  }

  /// Saves [dive] at a site called [siteName]. A site with that name is
  /// reused and given the new position; otherwise a new one is created.
  Future<void> saveDive(
    Dive dive, {
    required String siteName,
    double? latitude,
    double? longitude,
  }) async {
    var log = _log;
    String? siteId;
    final name = siteName.trim();
    if (name.isNotEmpty) {
      final existing = log.sites
          .where((s) => s.name.trim().toLowerCase() == name.toLowerCase())
          .firstOrNull;
      siteId = existing?.id ?? uniqueId('s', {for (final s in log.sites) s.id});
      log = log.withSite(
        DiveSite(
          id: siteId,
          name: name,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }
    await _set(
      log.withDive(
        Dive(
          id: dive.id,
          number: dive.number,
          start: dive.start,
          siteId: siteId,
          maxDepth: dive.maxDepth,
          duration: dive.duration,
          waterTemperature: dive.waterTemperature,
          buddy: dive.buddy,
          notes: dive.notes,
          samples: dive.samples,
          media: dive.media,
        ),
      ),
    );
  }

  Future<void> updateDive(Dive dive) => _set(_log.withDive(dive));

  Future<void> deleteDive(String id) => _set(_log.withoutDive(id));

  /// Adds the dives and sites of an imported log; returns how many dives
  /// were new.
  Future<int> importLog(DiveLog imported) async {
    final (merged, added) = _log.merge(imported);
    await _set(merged);
    return added;
  }

  /// Links [candidates] to the dives they were captured during; returns how
  /// many links were made.
  Future<int> linkByTime(Iterable<MediaCandidate> candidates) async {
    final (changed, linked) = matchMediaToDives(_log.dives, candidates);
    if (changed.isEmpty) return 0;
    var log = _log;
    for (final dive in changed) {
      log = log.withDive(dive);
    }
    await _set(log);
    return linked;
  }
}
