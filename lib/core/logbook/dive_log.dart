import '../timeline/timeline_json.dart';

/// One reading of a dive computer profile, [seconds] after the dive started.
class DiveSample {
  const DiveSample({required this.seconds, this.depth, this.temperature});

  final double seconds;

  /// Metres below the surface.
  final double? depth;

  /// Degrees Celsius.
  final double? temperature;

  Map<String, Object?> toJson() => {
    't': seconds,
    if (depth != null) 'd': depth,
    if (temperature != null) 'c': temperature,
  };

  factory DiveSample.fromJson(Map<String, Object?> json) => DiveSample(
    seconds: jsonDouble(json, 't', 0),
    depth: jsonOptionalDouble(json, 'd'),
    temperature: jsonOptionalDouble(json, 'c'),
  );
}

/// A photo or video linked to a dive. It is never copied: [assetId] names a
/// photo-library asset and [path] a file the user chose.
class DiveMedia {
  const DiveMedia({
    this.assetId,
    this.path,
    required this.isVideo,
    this.capturedAt,
    this.depth,
  }) : assert(assetId != null || path != null);

  final String? assetId;
  final String? path;
  final bool isVideo;
  final DateTime? capturedAt;

  /// Depth in metres at [capturedAt], when the dive has a profile.
  final double? depth;

  /// Identifies the medium across dives.
  String get key => assetId != null ? 'asset:$assetId' : 'file:$path';

  Map<String, Object?> toJson() => {
    if (assetId != null) 'assetId': assetId,
    if (path != null) 'path': path,
    'video': isVideo,
    if (capturedAt != null) 'capturedAt': capturedAt!.toIso8601String(),
    if (depth != null) 'depth': depth,
  };

  static DiveMedia? fromJson(Map<String, Object?> json) {
    final assetId = json['assetId'];
    final path = json['path'];
    if (assetId is! String && path is! String) return null;
    return DiveMedia(
      assetId: assetId is String ? assetId : null,
      path: path is String ? path : null,
      isVideo: json['video'] == true,
      capturedAt: _date(json['capturedAt']),
      depth: jsonOptionalDouble(json, 'depth'),
    );
  }
}

class DiveSite {
  const DiveSite({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final double? latitude;
  final double? longitude;

  bool get hasPosition => latitude != null && longitude != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (latitude != null) 'lat': latitude,
    if (longitude != null) 'lon': longitude,
  };

  static DiveSite? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String) return null;
    final name = json['name'];
    return DiveSite(
      id: id,
      name: name is String ? name : '',
      latitude: jsonOptionalDouble(json, 'lat'),
      longitude: jsonOptionalDouble(json, 'lon'),
    );
  }
}

class Dive {
  const Dive({
    required this.id,
    required this.number,
    required this.start,
    this.siteId,
    this.maxDepth,
    this.duration,
    this.waterTemperature,
    this.buddy = '',
    this.notes = '',
    this.samples = const [],
    this.media = const [],
  });

  final String id;
  final int number;

  /// Local wall-clock time of the descent, as dive computers and cameras
  /// record it.
  final DateTime start;
  final String? siteId;

  /// Metres.
  final double? maxDepth;
  final Duration? duration;

  /// Degrees Celsius.
  final double? waterTemperature;
  final String buddy;
  final String notes;
  final List<DiveSample> samples;
  final List<DiveMedia> media;

  DateTime get end => start.add(duration ?? Duration.zero);

  Dive copyWith({
    int? number,
    DateTime? start,
    String? siteId,
    double? maxDepth,
    Duration? duration,
    double? waterTemperature,
    String? buddy,
    String? notes,
    List<DiveSample>? samples,
    List<DiveMedia>? media,
  }) => Dive(
    id: id,
    number: number ?? this.number,
    start: start ?? this.start,
    siteId: siteId ?? this.siteId,
    maxDepth: maxDepth ?? this.maxDepth,
    duration: duration ?? this.duration,
    waterTemperature: waterTemperature ?? this.waterTemperature,
    buddy: buddy ?? this.buddy,
    notes: notes ?? this.notes,
    samples: samples ?? this.samples,
    media: media ?? this.media,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'start': start.toIso8601String(),
    if (siteId != null) 'siteId': siteId,
    if (maxDepth != null) 'maxDepth': maxDepth,
    if (duration != null) 'durationSeconds': duration!.inSeconds,
    if (waterTemperature != null) 'waterTemperature': waterTemperature,
    if (buddy.isNotEmpty) 'buddy': buddy,
    if (notes.isNotEmpty) 'notes': notes,
    if (samples.isNotEmpty) 'samples': [for (final s in samples) s.toJson()],
    if (media.isNotEmpty) 'media': [for (final m in media) m.toJson()],
  };

  static Dive? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final start = _date(json['start']);
    if (id is! String || start == null) return null;
    final seconds = json['durationSeconds'];
    final buddy = json['buddy'];
    final notes = json['notes'];
    final siteId = json['siteId'];
    return Dive(
      id: id,
      number: jsonInt(json, 'number', 0),
      start: start,
      siteId: siteId is String ? siteId : null,
      maxDepth: jsonOptionalDouble(json, 'maxDepth'),
      duration: seconds is num ? Duration(seconds: seconds.toInt()) : null,
      waterTemperature: jsonOptionalDouble(json, 'waterTemperature'),
      buddy: buddy is String ? buddy : '',
      notes: notes is String ? notes : '',
      samples: [
        for (final s in jsonMaps(json, 'samples')) DiveSample.fromJson(s),
      ],
      media: [for (final m in jsonMaps(json, 'media')) ?DiveMedia.fromJson(m)],
    );
  }
}

/// Every site and dive on the device.
class DiveLog {
  const DiveLog({this.sites = const [], this.dives = const []});

  final List<DiveSite> sites;

  /// Newest first.
  final List<Dive> dives;

  DiveSite? site(String? id) {
    for (final site in sites) {
      if (site.id == id) return site;
    }
    return null;
  }

  List<Dive> divesAt(String siteId) => [
    for (final dive in dives)
      if (dive.siteId == siteId) dive,
  ];

  int get nextNumber =>
      dives.fold(0, (max, d) => d.number > max ? d.number : max) + 1;

  /// Adds or replaces [dive] (by id) and keeps the newest-first order.
  DiveLog withDive(Dive dive) => DiveLog(
    sites: sites,
    dives: _sorted([
      for (final d in dives)
        if (d.id != dive.id) d,
      dive,
    ]),
  );

  DiveLog withoutDive(String id) => DiveLog(
    sites: sites,
    dives: [
      for (final d in dives)
        if (d.id != id) d,
    ],
  );

  DiveLog withSite(DiveSite site) => DiveLog(
    sites: [
      for (final s in sites)
        if (s.id != site.id) s,
      site,
    ],
    dives: dives,
  );

  /// Merges imported dives and sites. A dive that starts at the same minute
  /// as one already logged is skipped, so importing a log twice is harmless.
  /// Sites with the same name are reused. Returns the merged log and how many
  /// dives were new.
  (DiveLog, int) merge(DiveLog imported) {
    final siteIds = <String, String>{};
    final mergedSites = [...sites];
    for (final site in imported.sites) {
      final existing = mergedSites
          .where(
            (s) =>
                s.name.trim().toLowerCase() == site.name.trim().toLowerCase(),
          )
          .firstOrNull;
      if (existing != null && site.name.trim().isNotEmpty) {
        siteIds[site.id] = existing.id;
        if (!existing.hasPosition && site.hasPosition) {
          mergedSites[mergedSites.indexOf(existing)] = DiveSite(
            id: existing.id,
            name: existing.name,
            latitude: site.latitude,
            longitude: site.longitude,
          );
        }
      } else {
        final id = uniqueId('s', {for (final s in mergedSites) s.id});
        siteIds[site.id] = id;
        mergedSites.add(
          DiveSite(
            id: id,
            name: site.name,
            latitude: site.latitude,
            longitude: site.longitude,
          ),
        );
      }
    }
    final minutes = {for (final d in dives) _minute(d.start)};
    final ids = {for (final d in dives) d.id};
    final added = <Dive>[];
    for (final dive in imported.dives) {
      if (!minutes.add(_minute(dive.start))) continue;
      final id = uniqueId('d', ids);
      ids.add(id);
      added.add(
        Dive(
          id: id,
          number: dive.number,
          start: dive.start,
          siteId: siteIds[dive.siteId],
          maxDepth: dive.maxDepth,
          duration: dive.duration,
          waterTemperature: dive.waterTemperature,
          buddy: dive.buddy,
          notes: dive.notes,
          samples: dive.samples,
          media: dive.media,
        ),
      );
    }
    return (
      DiveLog(sites: mergedSites, dives: _sorted([...dives, ...added])),
      added.length,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'sites': [for (final s in sites) s.toJson()],
    'dives': [for (final d in dives) d.toJson()],
  };

  factory DiveLog.fromJson(Map<String, Object?> json) => DiveLog(
    sites: [for (final s in jsonMaps(json, 'sites')) ?DiveSite.fromJson(s)],
    dives: _sorted([
      for (final d in jsonMaps(json, 'dives')) ?Dive.fromJson(d),
    ]),
  );

  static List<Dive> _sorted(List<Dive> dives) =>
      dives..sort((a, b) => b.start.compareTo(a.start));

  static int _minute(DateTime t) => t.millisecondsSinceEpoch ~/ 60000;
}

int _idCounter = 0;

/// A short id with [prefix] that is not in [taken].
String uniqueId(String prefix, Set<String> taken) {
  while (true) {
    final id =
        '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${(_idCounter++).toRadixString(36)}';
    if (!taken.contains(id)) return id;
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
