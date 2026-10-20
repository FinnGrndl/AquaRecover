import 'dart:convert';

import 'package:xml/xml.dart';

import 'dive_log.dart';

/// GPX 1.1: one waypoint per dive at its site. Dives at sites without a
/// position are left out because GPX needs coordinates.
String writeGpx(DiveLog log) {
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element(
    'gpx',
    attributes: {
      'xmlns': 'http://www.topografix.com/GPX/1/1',
      'version': '1.1',
      'creator': 'AquaRecover',
    },
    nest: () {
      for (final dive in log.dives.reversed) {
        final site = log.site(dive.siteId);
        if (site == null || !site.hasPosition) continue;
        b.element(
          'wpt',
          attributes: {'lat': '${site.latitude}', 'lon': '${site.longitude}'},
          nest: () {
            b.element(
              'time',
              nest: '${dive.start.toUtc().toIso8601String().split('.').first}Z',
            );
            b.element('name', nest: diveTitle(dive, site));
            final desc = _summary(dive);
            if (desc.isNotEmpty) b.element('desc', nest: desc);
            b.element('type', nest: 'Dive');
          },
        );
      }
    },
  );
  return b.buildDocument().toXmlString(pretty: true);
}

/// GeoJSON FeatureCollection: one Point per dive at a site with a position.
String writeGeoJson(DiveLog log) {
  final features = <Map<String, Object?>>[];
  for (final dive in log.dives.reversed) {
    final site = log.site(dive.siteId);
    if (site == null || !site.hasPosition) continue;
    features.add({
      'type': 'Feature',
      // GeoJSON orders coordinates longitude first.
      'geometry': {
        'type': 'Point',
        'coordinates': [site.longitude, site.latitude],
      },
      'properties': {
        'number': dive.number,
        'start': dive.start.toIso8601String(),
        'site': site.name,
        'maxDepthM': ?dive.maxDepth,
        'durationMin': ?dive.duration?.inMinutes,
        'waterTemperatureC': ?dive.waterTemperature,
        if (dive.buddy.isNotEmpty) 'buddy': dive.buddy,
        if (dive.notes.isNotEmpty) 'notes': dive.notes,
      },
    });
  }
  return const JsonEncoder.withIndent(
    '  ',
  ).convert({'type': 'FeatureCollection', 'features': features});
}

/// "#12 Blue Hole", or "Dive 12" without a site.
String diveTitle(Dive dive, DiveSite? site) {
  final name = site?.name.trim() ?? '';
  if (dive.number <= 0) return name.isEmpty ? 'Dive' : name;
  return name.isEmpty ? 'Dive ${dive.number}' : '#${dive.number} $name';
}

String _summary(Dive dive) => [
  if (dive.maxDepth != null) '${dive.maxDepth!.toStringAsFixed(1)} m',
  if (dive.duration != null) '${dive.duration!.inMinutes} min',
  if (dive.waterTemperature != null)
    '${dive.waterTemperature!.toStringAsFixed(0)} °C',
  if (dive.buddy.isNotEmpty) 'with ${dive.buddy}',
].join(', ');
