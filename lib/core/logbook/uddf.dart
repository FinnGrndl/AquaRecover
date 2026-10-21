import 'package:xml/xml.dart';

import 'dive_log.dart';

/// Thrown when a file is not a readable UDDF log.
class UddfFormatException implements Exception {
  const UddfFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads a UDDF (Universal Dive Data Format) log, as Subsurface and many
/// dive computer tools export it. Pure: no I/O. Site and dive ids in the
/// result are the file's own; [DiveLog.merge] assigns local ones.
///
/// UDDF stores depths in metres, times in seconds and temperatures in
/// kelvin; the result uses metres, seconds and degrees Celsius.
DiveLog parseUddf(String source) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(source);
  } on XmlException catch (e) {
    throw UddfFormatException('The file is not valid XML: ${e.message}');
  }
  final root = doc.rootElement;
  if (root.localName != 'uddf') {
    throw const UddfFormatException('The file is not a UDDF dive log.');
  }

  final buddies = <String, String>{};
  for (final buddy in root.findAllElements('buddy')) {
    final id = buddy.getAttribute('id');
    if (id == null) continue;
    final first = _text(buddy, 'firstname') ?? '';
    final last = _text(buddy, 'lastname') ?? '';
    buddies[id] = '$first $last'.trim();
  }

  final sites = <DiveSite>[];
  for (final site in root.findAllElements('site')) {
    final id = site.getAttribute('id');
    if (id == null) continue;
    final geography = site.getElement('geography');
    sites.add(
      DiveSite(
        id: id,
        name: _childText(site, 'name') ?? '',
        latitude: _number(geography?.getElement('latitude')?.innerText),
        longitude: _number(geography?.getElement('longitude')?.innerText),
      ),
    );
  }
  final siteIds = {for (final s in sites) s.id};

  final dives = <Dive>[];
  for (final dive in root.findAllElements('dive')) {
    final before = dive.getElement('informationbeforedive');
    final after = dive.getElement('informationafterdive');
    final start = _dateTime(
      before?.getElement('datetime')?.innerText ??
          dive.getElement('datetime')?.innerText,
    );
    if (start == null) continue;

    String? siteId;
    final buddyNames = <String>[];
    for (final link in before?.findElements('link') ?? <XmlElement>[]) {
      final ref = link.getAttribute('ref');
      if (siteIds.contains(ref)) siteId = ref;
      final buddy = buddies[ref];
      if (buddy != null && buddy.isNotEmpty) buddyNames.add(buddy);
    }

    final samples = <DiveSample>[];
    for (final point in dive.findAllElements('waypoint')) {
      final seconds = _number(point.getElement('divetime')?.innerText);
      if (seconds == null) continue;
      samples.add(
        DiveSample(
          seconds: seconds,
          depth: _number(point.getElement('depth')?.innerText),
          temperature: _celsius(point.getElement('temperature')?.innerText),
        ),
      );
    }
    samples.sort((a, b) => a.seconds.compareTo(b.seconds));

    final depths = [
      for (final s in samples)
        if (s.depth != null) s.depth!,
    ];
    final temperatures = [
      for (final s in samples)
        if (s.temperature != null) s.temperature!,
    ];
    final durationSeconds =
        _number(after?.getElement('diveduration')?.innerText) ??
        (samples.isEmpty ? null : samples.last.seconds);
    final notes = after?.getElement('notes');

    dives.add(
      Dive(
        id: dive.getAttribute('id') ?? 'dive${dives.length}',
        number:
            int.tryParse(
              before?.getElement('divenumber')?.innerText.trim() ?? '',
            ) ??
            0,
        start: start,
        siteId: siteId,
        maxDepth:
            _number(after?.getElement('greatestdepth')?.innerText) ??
            (depths.isEmpty ? null : depths.reduce((a, b) => a > b ? a : b)),
        duration: durationSeconds == null
            ? null
            : Duration(seconds: durationSeconds.round()),
        waterTemperature:
            _celsius(after?.getElement('lowesttemperature')?.innerText) ??
            (temperatures.isEmpty
                ? null
                : temperatures.reduce((a, b) => a < b ? a : b)),
        buddy: buddyNames.join(', '),
        notes: notes == null
            ? ''
            : [
                for (final para in notes.findElements('para'))
                  para.innerText.trim(),
              ].where((t) => t.isNotEmpty).join('\n'),
        samples: samples,
      ),
    );
  }
  return DiveLog(sites: sites, dives: dives);
}

/// Writes [log] as UDDF 3.2, readable by Subsurface and other tools.
String writeUddf(DiveLog log, {String generator = 'AquaRecover'}) {
  final buddies = <String, String>{};
  for (final dive in log.dives) {
    for (final name in _splitBuddies(dive.buddy)) {
      buddies.putIfAbsent(name, () => 'buddy${buddies.length + 1}');
    }
  }
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8"');
  b.element(
    'uddf',
    attributes: {'xmlns': 'http://www.streit.cc/uddf/3.2/', 'version': '3.2.0'},
    nest: () {
      b.element('generator', nest: () => b.element('name', nest: generator));
      b.element(
        'diver',
        nest: () {
          b.element('owner', attributes: {'id': 'owner'});
          for (final MapEntry(key: name, value: id) in buddies.entries) {
            b.element(
              'buddy',
              attributes: {'id': id},
              nest: () => b.element(
                'personal',
                nest: () => b.element('firstname', nest: name),
              ),
            );
          }
        },
      );
      b.element(
        'divesite',
        nest: () {
          for (final site in log.sites) {
            b.element(
              'site',
              attributes: {'id': site.id},
              nest: () {
                b.element('name', nest: site.name);
                if (site.hasPosition) {
                  b.element(
                    'geography',
                    nest: () {
                      b.element('latitude', nest: '${site.latitude}');
                      b.element('longitude', nest: '${site.longitude}');
                    },
                  );
                }
              },
            );
          }
        },
      );
      b.element(
        'profiledata',
        nest: () => b.element(
          'repetitiongroup',
          attributes: {'id': 'rg1'},
          nest: () {
            for (final dive in log.dives.reversed) {
              _writeDive(b, dive, buddies);
            }
          },
        ),
      );
    },
  );
  return b.buildDocument().toXmlString(pretty: true);
}

void _writeDive(XmlBuilder b, Dive dive, Map<String, String> buddies) {
  b.element(
    'dive',
    attributes: {'id': dive.id},
    nest: () {
      b.element(
        'informationbeforedive',
        nest: () {
          if (dive.siteId != null) {
            b.element('link', attributes: {'ref': dive.siteId!});
          }
          for (final name in _splitBuddies(dive.buddy)) {
            b.element('link', attributes: {'ref': buddies[name]!});
          }
          b.element('divenumber', nest: '${dive.number}');
          b.element('datetime', nest: _formatDateTime(dive.start));
        },
      );
      if (dive.samples.isNotEmpty) {
        b.element(
          'samples',
          nest: () {
            for (final s in dive.samples) {
              b.element(
                'waypoint',
                nest: () {
                  if (s.depth != null) b.element('depth', nest: '${s.depth}');
                  b.element('divetime', nest: _number2(s.seconds));
                  if (s.temperature != null) {
                    b.element(
                      'temperature',
                      nest: _number2(s.temperature! + 273.15),
                    );
                  }
                },
              );
            }
          },
        );
      }
      b.element(
        'informationafterdive',
        nest: () {
          if (dive.maxDepth != null) {
            b.element('greatestdepth', nest: '${dive.maxDepth}');
          }
          if (dive.duration != null) {
            b.element('diveduration', nest: '${dive.duration!.inSeconds}');
          }
          if (dive.waterTemperature != null) {
            b.element(
              'lowesttemperature',
              nest: _number2(dive.waterTemperature! + 273.15),
            );
          }
          if (dive.notes.isNotEmpty) {
            b.element(
              'notes',
              nest: () {
                for (final line in dive.notes.split('\n')) {
                  b.element('para', nest: line);
                }
              },
            );
          }
        },
      );
    },
  );
}

Iterable<String> _splitBuddies(String buddy) =>
    buddy.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);

String _number2(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}

String _formatDateTime(DateTime t) =>
    t.toIso8601String().split('.').first.replaceFirst(RegExp('Z\$'), '');

String? _text(XmlElement parent, String name) {
  final element = parent.findAllElements(name).firstOrNull;
  final text = element?.innerText.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _childText(XmlElement parent, String name) {
  final text = parent.getElement(name)?.innerText.trim();
  return text == null || text.isEmpty ? null : text;
}

double? _number(String? text) {
  final value = double.tryParse(text?.trim() ?? '');
  return value != null && value.isFinite ? value : null;
}

/// UDDF temperatures are kelvin; a few exporters write Celsius anyway.
double? _celsius(String? text) {
  final value = _number(text);
  if (value == null) return null;
  return value > 150 ? value - 273.15 : value;
}

final _wallClock = RegExp(r'^\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?)');

/// The local wall-clock time; a zone offset is dropped because cameras
/// record wall-clock time too.
DateTime? _dateTime(String? text) {
  final match = _wallClock.firstMatch(text ?? '');
  return match == null ? null : DateTime.tryParse(match.group(1)!);
}
