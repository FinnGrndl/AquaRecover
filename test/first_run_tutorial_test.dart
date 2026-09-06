import 'dart:io';

import 'package:aqua_recover/core/persistence/first_run_tutorial_store.dart';
import 'package:aqua_recover/features/onboarding/first_run_tutorial.dart';
import 'package:aqua_recover/features/onboarding/first_run_tutorial_gate.dart';
import 'package:aqua_recover/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'file tutorial store persists its versioned completion marker',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'aquarecover_tutorial_store_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileFirstRunTutorialStore(
        directoryProvider: () async => directory,
      );

      expect(await store.isCompleted(), isFalse);
      await store.markCompleted();
      expect(await store.isCompleted(), isTrue);
    },
  );

  testWidgets('first-run tutorial appears once and Skip persists completion', (
    tester,
  ) async {
    final store = _FakeTutorialStore();

    await tester.pumpWidget(_testHost(store));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('first_run_tutorial')), findsOneWidget);
    expect(find.text('Restore color with a clear workflow'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutorial_skip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('first_run_tutorial')), findsNothing);
    expect(store.completed, isTrue);
    expect(store.markCalls, 1);

    await tester.pumpWidget(_testHost(store));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('first_run_tutorial')), findsNothing);
  });

  testWidgets('tutorial teaches batch, editing, compare, and export', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _FakeTutorialStore();

    await tester.pumpWidget(_testHost(store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tutorial_next')));
    await tester.pumpAndSettle();
    expect(find.text('One photo or a complete batch'), findsOneWidget);

    await tester.tap(find.text('Batch'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'tutorial_queue_item_',
            ),
      ),
      findsNWidgets(3),
    );

    await tester.tap(find.byKey(const Key('tutorial_next')));
    await tester.pumpAndSettle();
    expect(find.text('Edit, inspect, and compare'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('tutorial_tool_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tutorial_tool_2')));
    await tester.pump();
    expect(find.text('Crop: Crop, rotate, and flip.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tutorial_compare_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Original / Edited'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('tutorial_compare_demo'))),
    );
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.text('Original'), findsOneWidget);
    await gesture.up();
    await tester.pump();

    await tester.tap(find.byKey(const Key('tutorial_next')));
    await tester.pumpAndSettle();
    expect(find.text('You choose when and where to save'), findsOneWidget);
    expect(
      find.byKey(const Key('tutorial_export_destination_0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tutorial_export_destination_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('tutorial_export_destination_2')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('tutorial_export_destination_2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tutorial_export_destination_2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tutorial_next')));
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunTutorial), findsNothing);
    expect(store.completed, isTrue);
  });

  testWidgets('info dialog can reopen the Quick Tour', (tester) async {
    final store = _FakeTutorialStore(completed: true);

    await tester.pumpWidget(
      AquaRecoverApp(showTutorialOnLaunch: false, tutorialStore: store),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start_about')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick Tour'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('first_run_tutorial')), findsOneWidget);
    expect(store.markCalls, 0);
  });

  testWidgets('tutorial remains usable on a compact display with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(_testHost(_FakeTutorialStore()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('first_run_tutorial')), findsOneWidget);
    expect(find.byKey(const Key('tutorial_skip')), findsOneWidget);
    expect(find.byKey(const Key('tutorial_next')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('tutorial_next')));
    await tester.pumpAndSettle();
    expect(find.text('One photo or a complete batch'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tutorial uses a centered bounded sheet on iPad', (tester) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testHost(_FakeTutorialStore()));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('first_run_tutorial'));
    expect(tester.getSize(sheet), const Size(560, 680));
    expect(tester.getCenter(sheet), const Offset(512, 683));
    expect(tester.takeException(), isNull);
  });
}

Widget _testHost(_FakeTutorialStore store) {
  return CupertinoApp(
    home: FirstRunTutorialGate(
      store: store,
      builder: (_, _) => const CupertinoPageScaffold(
        child: Center(child: Text('AquaRecover home')),
      ),
    ),
  );
}

class _FakeTutorialStore implements FirstRunTutorialStore {
  _FakeTutorialStore({this.completed = false});

  bool completed;
  int markCalls = 0;

  @override
  Future<bool> isCompleted() async => completed;

  @override
  Future<void> markCompleted() async {
    markCalls += 1;
    completed = true;
  }
}
