import 'dart:typed_data';

import 'package:aqua_recover/core/logbook/dive_log.dart';
import 'package:aqua_recover/core/logbook/dive_log_store.dart';
import 'package:aqua_recover/features/logbook/logbook_media.dart';
import 'package:aqua_recover/features/logbook/logbook_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore extends DiveLogStore {
  _MemoryStore(this.log);
  DiveLog log;

  @override
  Future<DiveLog> load() async => log;

  @override
  Future<void> save(DiveLog log) async => this.log = log;
}

class _FakeMedia extends LogbookMedia {
  const _FakeMedia();

  @override
  Future<Uint8List?> thumbnail(DiveMedia media) async => null;
}

final _log = DiveLog(
  sites: const [
    DiveSite(id: 's1', name: 'Blue Hole', latitude: 28.57, longitude: 34.54),
  ],
  dives: [
    Dive(
      id: 'd2',
      number: 8,
      start: DateTime(2026, 5, 2, 9, 15),
      maxDepth: 12,
      duration: const Duration(minutes: 40),
    ),
    Dive(
      id: 'd1',
      number: 7,
      start: DateTime(2026, 5, 1, 10),
      siteId: 's1',
      maxDepth: 18.4,
      duration: const Duration(minutes: 45),
      waterTemperature: 24,
      buddy: 'Anna Meer',
      notes: 'Turtle at the arch.',
      media: [
        DiveMedia(
          assetId: 'a1',
          isVideo: false,
          capturedAt: DateTime(2026, 5, 1, 10, 12),
          depth: 14.2,
        ),
        const DiveMedia(path: '/clips/b.mov', isVideo: true),
      ],
    ),
  ],
);

Widget _app(DiveLog log) => CupertinoApp(
  home: LogbookPage(
    store: _MemoryStore(log),
    media: const _FakeMedia(),
    mapBuilder: (context, sites, onTap) => Column(
      key: const Key('fake_map'),
      children: [
        for (final site in sites)
          CupertinoButton(
            onPressed: () => onTap(site),
            child: Text('pin ${site.name}'),
          ),
      ],
    ),
  ),
);

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void _expectNoShadows(WidgetTester tester) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) {
      expect(decoration.boxShadow, anyOf(isNull, isEmpty));
    }
  }
}

void main() {
  testWidgets('an empty logbook offers import and manual entry', (
    tester,
  ) async {
    _narrow(tester);
    await tester.pumpWidget(_app(const DiveLog()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logbook_empty')), findsOneWidget);
    expect(find.text('No dives yet'), findsOneWidget);
    expect(find.text('Import log'), findsOneWidget);
    expect(find.bySemanticsLabel('Add dive'), findsWidgets);
    expect(tester.takeException(), isNull);
    _expectNoShadows(tester);
  });

  testWidgets('lists dives newest first and maps their sites', (tester) async {
    _narrow(tester);
    await tester.pumpWidget(_app(_log));
    await tester.pumpAndSettle();
    expect(find.text('Dive 8'), findsOneWidget);
    expect(find.text('#7 Blue Hole'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Dive 8')).dy,
      lessThan(tester.getTopLeft(find.text('#7 Blue Hole')).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake_map')), findsOneWidget);
    await tester.tap(find.text('pin Blue Hole'));
    await tester.pumpAndSettle();
    expect(find.text('1 dive'), findsOneWidget);
    expect(find.textContaining('Dive 7 · May 1, 2026'), findsOneWidget);
  });

  testWidgets('a dive shows its log and linked media', (tester) async {
    _narrow(tester);
    await tester.pumpWidget(_app(_log));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#7 Blue Hole'));
    await tester.pumpAndSettle();

    expect(find.text('18.4 m'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('24.0 °C'), findsOneWidget);
    expect(find.text('Anna Meer'), findsOneWidget);
    expect(find.text('Turtle at the arch.'), findsOneWidget);
    expect(find.bySemanticsLabel('Photo, 10:12, 14.2 m deep'), findsOneWidget);
    expect(find.bySemanticsLabel('Video'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Make a movie from this dive'),
      100,
    );
    expect(find.text('Make a movie from this dive'), findsOneWidget);
    expect(tester.takeException(), isNull);
    _expectNoShadows(tester);
  });
}
