import 'dart:convert';
import 'dart:io';

import 'package:aqua_recover/core/logbook/dive_export.dart';
import 'package:aqua_recover/core/logbook/dive_log.dart';
import 'package:aqua_recover/core/logbook/dive_log_store.dart';
import 'package:aqua_recover/core/logbook/media_matching.dart';
import 'package:aqua_recover/core/logbook/uddf.dart';
import 'package:aqua_recover/features/logbook/logbook_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// Shaped like a Subsurface 6 UDDF export.
const subsurfaceUddf = '''<?xml version="1.0" encoding="UTF-8"?>
<uddf xmlns="http://www.streit.cc/uddf/3.2/" version="3.2.0">
  <generator><name>Subsurface Divelog</name><version>6.0</version></generator>
  <diver>
    <owner id="owner"><personal><firstname>Finn</firstname></personal></owner>
    <buddy id="b1"><personal><firstname>Anna</firstname><lastname>Meer</lastname></personal></buddy>
  </diver>
  <divesite>
    <site id="s1">
      <name>Blue Hole</name>
      <geography><location>Dahab</location><latitude>28.5722</latitude><longitude>34.5372</longitude></geography>
    </site>
  </divesite>
  <profiledata>
    <repetitiongroup id="rg1">
      <dive id="dive7">
        <informationbeforedive>
          <link ref="s1"/>
          <link ref="b1"/>
          <divenumber>7</divenumber>
          <datetime>2026-05-01T10:00:00+02:00</datetime>
        </informationbeforedive>
        <samples>
          <waypoint><depth>0</depth><divetime>0</divetime><temperature>299.15</temperature></waypoint>
          <waypoint><depth>10</depth><divetime>300</divetime><temperature>298.15</temperature></waypoint>
          <waypoint><depth>20</depth><divetime>600</divetime><temperature>297.15</temperature></waypoint>
          <waypoint><depth>0</depth><divetime>1800</divetime><temperature>298.15</temperature></waypoint>
        </samples>
        <informationafterdive>
          <greatestdepth>20.4</greatestdepth>
          <diveduration>1800</diveduration>
          <lowesttemperature>297.15</lowesttemperature>
          <notes><para>Turtle at the arch.</para><para>Strong current.</para></notes>
        </informationafterdive>
      </dive>
      <dive id="dive8">
        <informationbeforedive>
          <divenumber>8</divenumber>
          <datetime>2026-05-01T14:30:00</datetime>
        </informationbeforedive>
        <samples>
          <waypoint><depth>12</depth><divetime>1200</divetime></waypoint>
        </samples>
      </dive>
    </repetitiongroup>
  </profiledata>
</uddf>
''';

void main() {
  group('UDDF import', () {
    test('reads sites, dives, buddies, notes and profiles', () {
      final log = parseUddf(subsurfaceUddf);
      expect(log.sites.single.name, 'Blue Hole');
      expect(log.sites.single.latitude, 28.5722);
      expect(log.sites.single.longitude, 34.5372);
      expect(log.dives, hasLength(2));

      final dive = log.dives.first;
      expect(dive.number, 7);
      // The zone offset is dropped: cameras record wall-clock time too.
      expect(dive.start, DateTime(2026, 5, 1, 10));
      expect(dive.siteId, 's1');
      expect(dive.buddy, 'Anna Meer');
      expect(dive.maxDepth, 20.4);
      expect(dive.duration, const Duration(minutes: 30));
      expect(dive.waterTemperature, closeTo(24, 1e-9));
      expect(dive.notes, 'Turtle at the arch.\nStrong current.');
      expect(dive.samples, hasLength(4));
      expect(dive.samples.first.temperature, closeTo(26, 1e-9));
    });

    test('falls back to the profile for missing summary values', () {
      final dive = parseUddf(subsurfaceUddf).dives.last;
      expect(dive.maxDepth, 12);
      expect(dive.duration, const Duration(minutes: 20));
      expect(dive.siteId, isNull);
      expect(dive.waterTemperature, isNull);
    });

    test('rejects files that are not UDDF', () {
      expect(() => parseUddf('not xml'), throwsA(isA<UddfFormatException>()));
      expect(
        () => parseUddf('<gpx></gpx>'),
        throwsA(isA<UddfFormatException>()),
      );
    });

    test('merging the same log twice adds its dives once', () {
      final imported = parseUddf(subsurfaceUddf);
      final (once, added) = const DiveLog().merge(imported);
      expect(added, 2);
      expect(once.sites, hasLength(1));
      expect(
        once.dives.first.siteId ?? once.dives.last.siteId,
        once.sites.single.id,
      );
      final (twice, addedAgain) = once.merge(imported);
      expect(addedAgain, 0);
      expect(twice.dives, hasLength(2));
      expect(twice.sites, hasLength(1));
    });
  });

  group('time matching', () {
    final dive = parseUddf(subsurfaceUddf).dives.first;

    test('interpolates depth from the profile', () {
      expect(depthAt(dive, DateTime(2026, 5, 1, 10, 7, 30)), closeTo(15, 1e-9));
      expect(depthAt(dive, DateTime(2026, 5, 1, 9, 59)), isNull);
      expect(depthAt(dive.copyWith(samples: []), dive.start), isNull);
    });

    test('links media captured during a dive, once', () {
      final candidates = [
        MediaCandidate(
          assetId: 'a1',
          isVideo: false,
          capturedAt: DateTime(2026, 5, 1, 10, 5),
        ),
        MediaCandidate(
          path: '/clips/b.mov',
          isVideo: true,
          capturedAt: DateTime(2026, 5, 1, 10, 31),
        ),
        MediaCandidate(
          assetId: 'lunch',
          isVideo: false,
          capturedAt: DateTime(2026, 5, 1, 12),
        ),
      ];
      final (changed, linked) = matchMediaToDives([dive], candidates);
      expect(linked, 2);
      final media = changed.single.media;
      expect(media.map((m) => m.key), ['asset:a1', 'file:/clips/b.mov']);
      expect(media.first.depth, closeTo(10, 1e-9));
      // Within the margin after surfacing, past the profile: no depth.
      expect(media.last.depth, isNull);

      final (again, relinked) = matchMediaToDives(changed, candidates);
      expect(relinked, 0);
      expect(again, isEmpty);
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('logbook'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('saves and loads the log with linked media', () async {
      final store = DiveLogStore(directory: () async => dir);
      expect((await store.load()).dives, isEmpty);
      final (log, _) = const DiveLog().merge(parseUddf(subsurfaceUddf));
      final first = log.dives.last.copyWith(
        media: [
          DiveMedia(
            assetId: 'x',
            isVideo: true,
            capturedAt: DateTime(2026, 5, 1, 10, 5),
            depth: 10,
          ),
        ],
      );
      await store.save(log.withDive(first));

      final loaded = await store.load();
      expect(loaded.sites.single.name, 'Blue Hole');
      expect(loaded.dives.map((d) => d.number), [8, 7]);
      final reloaded = loaded.dives.last;
      expect(reloaded.samples, hasLength(4));
      expect(reloaded.media.single.assetId, 'x');
      expect(reloaded.media.single.isVideo, isTrue);
      expect(reloaded.media.single.depth, 10);
      expect(reloaded.buddy, 'Anna Meer');
    });

    test('keeps a damaged file aside instead of failing', () async {
      File('${dir.path}/logbook.aqlog.json').writeAsStringSync('{broken');
      final log = await DiveLogStore(directory: () async => dir).load();
      expect(log.dives, isEmpty);
      expect(
        File('${dir.path}/logbook.aqlog.json.damaged').existsSync(),
        isTrue,
      );
    });
  });

  group('export', () {
    final (log, _) = const DiveLog().merge(parseUddf(subsurfaceUddf));

    test('GPX has a waypoint per dive with a position', () {
      final gpx = XmlDocument.parse(writeGpx(log));
      final points = gpx.findAllElements('wpt').toList();
      expect(points, hasLength(1));
      expect(points.single.getAttribute('lat'), '28.5722');
      expect(points.single.getElement('name')!.innerText, '#7 Blue Hole');
    });

    test('GeoJSON puts longitude first', () {
      final json = jsonDecode(writeGeoJson(log)) as Map<String, dynamic>;
      final feature = (json['features'] as List).single as Map;
      expect(feature['geometry']['coordinates'], [34.5372, 28.5722]);
      expect(feature['properties']['maxDepthM'], 20.4);
      expect(feature['properties']['buddy'], 'Anna Meer');
    });

    test('UDDF round-trips through the importer', () {
      final back = parseUddf(writeUddf(log));
      expect(back.sites.single.name, 'Blue Hole');
      expect(back.dives, hasLength(2));
      final dive = back.dives.firstWhere((d) => d.number == 7);
      expect(dive.start, DateTime(2026, 5, 1, 10));
      expect(dive.buddy, 'Anna Meer');
      expect(dive.maxDepth, 20.4);
      expect(dive.duration, const Duration(minutes: 30));
      expect(dive.waterTemperature, closeTo(24, 1e-9));
      expect(dive.notes, 'Turtle at the arch.\nStrong current.');
      expect(dive.samples.map((s) => s.depth), [0, 10, 20, 0]);
      expect(back.site(dive.siteId)!.latitude, 28.5722);
    });
  });

  test('a dive movie has one clip per medium', () {
    final project = movieFromDive(
      [
        (path: '/a.jpg', isVideo: false, seconds: null),
        (path: '/b.mov', isVideo: true, seconds: 12.0),
      ],
      id: 'm1',
      name: '#7 Blue Hole',
    );
    expect(project.clips.map((c) => c.path), ['/a.jpg', '/b.mov']);
    expect(project.clips.last.sourceEnd, 12);
    expect(project.name, '#7 Blue Hole');
  });
}
