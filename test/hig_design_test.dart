import 'dart:io';

import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/lut_profile.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/models/restoration_settings.dart';
import 'package:aqua_recover/core/persistence/export_library_service.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_project_store.dart';
import 'package:aqua_recover/core/timeline/timeline_render_service.dart';
import 'package:aqua_recover/features/editor/edit_history.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/editor/widgets/adjustment_browser.dart';
import 'package:aqua_recover/features/editor/widgets/glass_navigation_bar.dart';
import 'package:aqua_recover/features/library/export_library_page.dart';
import 'package:aqua_recover/features/timeline/timeline_controller.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/features/timeline/timeline_projects_page.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_panels.dart';
import 'package:aqua_recover/shared/reduce_motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('EditHistory', () {
    test('undoes and redoes in order, and a new edit clears redo', () {
      final history = EditHistory<int>();
      expect(history.canUndo, isFalse);

      history.record(0);
      history.record(1);
      expect(history.undo(2), 1);
      expect(history.undo(1), 0);
      expect(history.undo(0), isNull);
      expect(history.redo(0), 1);
      expect(history.canRedo, isTrue);

      history.record(1);
      expect(history.canRedo, isFalse);
    });

    test('drops the oldest steps beyond the limit', () {
      final history = EditHistory<int>(limit: 2);
      for (var i = 0; i < 4; i++) {
        history.record(i);
      }
      expect(history.undo(4), 3);
      expect(history.undo(3), 2);
      expect(history.canUndo, isFalse);
    });
  });

  testWidgets('reduce motion follows the iOS accessibility setting', (
    tester,
  ) async {
    late bool reduced;
    late Duration duration;
    Widget probe() => CupertinoApp(
      home: Builder(
        builder: (context) {
          reduced = reduceMotionOf(context);
          duration = motionDuration(context, const Duration(seconds: 1));
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(probe());
    expect(reduced, isFalse);
    expect(duration, const Duration(seconds: 1));

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(probe());
    expect(reduced, isTrue);
    expect(duration, Duration.zero);
  });

  group('photo editor', () {
    testWidgets('draws its floating chrome without shadows', (tester) async {
      await _pumpPhotoEditor(tester, count: 2);

      expect(find.byType(GlassNavigationBar), findsOneWidget);
      _expectNoShadows(tester);
    });

    testWidgets('undo and redo step through one item’s edits', (tester) async {
      await _pumpPhotoEditor(tester, count: 2);
      GlassIconButton button(String key) =>
          tester.widget<GlassIconButton>(find.byKey(Key(key)));

      expect(button('editor_undo').onPressed, isNull);
      expect(button('editor_redo').onPressed, isNull);

      await _choosePreset(tester, 'preset_deep');
      expect(find.text('Deep dive - Photo'), findsOneWidget);
      await _choosePreset(tester, 'preset_none');
      expect(find.text('None - Photo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor_undo')));
      await tester.pump();
      expect(find.text('Deep dive - Photo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('editor_undo')));
      await tester.pump();
      expect(find.text('Auto - Photo'), findsOneWidget);
      expect(button('editor_undo').onPressed, isNull);

      await tester.tap(find.byKey(const Key('editor_redo')));
      await tester.pump();
      expect(find.text('Deep dive - Photo'), findsOneWidget);

      // The other photo keeps its own, empty history.
      await tester.tap(find.byKey(const Key('editor_next_item')));
      await tester.pump();
      expect(find.text('Auto - Photo'), findsOneWidget);
      expect(button('editor_undo').onPressed, isNull);
      await tester.tap(find.byKey(const Key('editor_previous_item')));
      await tester.pump();
      expect(button('editor_undo').onPressed, isNotNull);
      expect(button('editor_redo').onPressed, isNotNull);
    });

    testWidgets(
      'Cmd-Z and Shift-Cmd-Z undo and redo',
      (tester) async {
        await _pumpPhotoEditor(tester, count: 1);
        await _choosePreset(tester, 'preset_deep');
        expect(find.text('Deep dive - Photo'), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(find.text('Auto - Photo'), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(find.text('Deep dive - Photo'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('small controls keep a 44 pt hit region', (tester) async {
      await _pumpPhotoEditor(tester, count: 2);
      for (final key in const [
        'editor_previous_item',
        'editor_next_item',
        'editor_copy_edits',
        'editor_open_queue',
        'editor_undo',
        'editor_redo',
        'editor_tool_panel_close',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(44), reason: key);
        expect(size.height, greaterThanOrEqualTo(44), reason: key);
      }
    });

    testWidgets('LUT choice pills keep a 44 pt hit region', (tester) async {
      await _pumpPhotoEditor(
        tester,
        count: 1,
        toolGroup: EditorToolGroup.effects,
      );
      for (final profile in LutProfile.builtIns) {
        final pill = find
            .ancestor(
              of: find.text(profile.name),
              matching: find.byType(CupertinoButton),
            )
            .first;
        final size = tester.getSize(pill);
        expect(size.width, greaterThanOrEqualTo(44), reason: profile.name);
        expect(size.height, greaterThanOrEqualTo(44), reason: profile.name);
      }
    });

    testWidgets('the adjustment strip grows with Dynamic Type', (tester) async {
      // xxLarge, xxxLarge and two accessibility sizes, in the tool panel of
      // a 320 pt wide window.
      for (final scale in const [1.0, 1.24, 1.35, 2.0, 3.0]) {
        await tester.pumpWidget(
          CupertinoApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            // Scrolls like the tool panel it lives in.
            home: CupertinoPageScaffold(
              child: Center(
                child: SizedBox(
                  width: 256,
                  child: SingleChildScrollView(
                    child: AdjustmentBrowser(
                      controls: allImageAdjustmentControls,
                      settings: const RestorationSettings(),
                      presetSettings: const RestorationSettings(),
                      selectedId: allImageAdjustmentControls.first.id,
                      onSelected: (_) {},
                      onChanged: (_) {},
                      trailing: CupertinoButton(
                        onPressed: () {},
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.eyedropper, size: 16),
                            SizedBox(width: 4),
                            Flexible(child: Text('White balance')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'text scale $scale');
      }
    });
  });

  testWidgets('local export toolbar buttons keep a 44 pt hit region', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('aquarecover_hig_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/reef_aqua.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    final service = _ExportLibrary([
      LocalExportItem(
        path: file.path,
        kind: MediaKind.photo,
        sizeBytes: file.lengthSync(),
        modified: DateTime(2026, 10, 12),
      ),
    ]);
    await tester.pumpWidget(
      CupertinoApp(home: ExportLibraryPage(service: service)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    void expectHitRegion(String key) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
    }

    expectHitRegion('delete_all_local_exports');
    await tester.tap(find.byKey(const Key('local_export_selection_mode')));
    await tester.pump();
    expectHitRegion('local_export_select_all');
  });

  group('movie editor', () {
    testWidgets('a failed edit explains itself in an alert', (tester) async {
      _phoneViewport(tester);
      await tester.pumpWidget(
        const CupertinoApp(
          home: TimelineEditorPage(
            project: TimelineProject(
              id: 'w',
              clips: [
                TimelineClip(
                  id: 'a',
                  path: '/m/a.jpg',
                  kind: TimelineClipKind.image,
                ),
              ],
            ),
          ),
        ),
      );

      // The playhead sits on the clip's first frame, so it cannot split.
      await tester.tap(find.byKey(const Key('timeline_split')));
      await tester.pump();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('Can’t split here'), findsOneWidget);

      // It stays until dismissed instead of timing out.
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CupertinoAlertDialog), findsNothing);
    });

    testWidgets('a failed render stops showing progress behind its alert', (
      tester,
    ) async {
      _phoneViewport(tester);
      final directory = Directory.systemTemp.createTempSync('aquarecover_hig_');
      addTearDown(() => directory.delete(recursive: true));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => directory.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      await tester.pumpWidget(
        CupertinoApp(
          home: TimelineEditorPage(
            store: _MemoryStore(),
            renderService: _FailingRenderService(),
            project: const TimelineProject(
              id: 'w',
              clips: [
                TimelineClip(
                  id: 'a',
                  path: '/m/a.jpg',
                  kind: TimelineClipKind.image,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('timeline_page_export')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('timeline_render')));
      // Finding the export folder touches the real file system, which can
      // take a while on a busy machine, so wait for the alert instead of a
      // fixed number of turns.
      for (
        var i = 0;
        i < 250 && find.text('Export failed').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Export failed'), findsOneWidget);
      expect(
        tester.widget<DeliverPanel>(find.byType(DeliverPanel)).rendering,
        isFalse,
      );
      expect(find.byKey(const Key('timeline_cancel_render')), findsNothing);
    });

    testWidgets('export settings are disabled, not inert, while rendering', (
      tester,
    ) async {
      final controller = TimelineController(
        const TimelineProject(
          id: 'w',
          clips: [
            TimelineClip(
              id: 'a',
              path: '/m/a.jpg',
              kind: TimelineClipKind.image,
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: DeliverPanel(
              controller: controller,
              rendering: true,
              progress: .4,
              outputPath: null,
              onRender: () {},
              onCancel: () {},
              onSaveToPhotos: null,
              onOpenLibrary: () {},
            ),
          ),
        ),
      );

      final controls = tester.widgetList<CupertinoSlidingSegmentedControl>(
        find.byWidgetPredicate((w) => w is CupertinoSlidingSegmentedControl),
      );
      expect(controls, hasLength(4));
      for (final control in controls) {
        expect(control.disabledChildren, containsAll(control.children.keys));
      }

      final frameRate = controller.project.frameRate;
      await tester.tap(find.text('60'));
      await tester.pump();
      expect(controller.project.frameRate, frameRate);

      // And they look it: the labels dim compared with an idle panel.
      Color? labelColor() => tester
          .widget<RichText>(
            find.descendant(
              of: find.text('60'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;
      final renderingColor = labelColor();
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: DeliverPanel(
              controller: controller,
              rendering: false,
              progress: 0,
              outputPath: null,
              onRender: () {},
              onCancel: () {},
              onSaveToPhotos: null,
              onOpenLibrary: () {},
            ),
          ),
        ),
      );
      expect(renderingColor, isNotNull);
      expect(labelColor(), isNot(renderingColor));
    });

    testWidgets('touch and hold a movie to delete it', (tester) async {
      _phoneViewport(tester);
      final store = _MemoryStore()
        ..projects['m'] = const TimelineProject(
          id: 'm',
          name: 'Reef',
          clips: [
            TimelineClip(
              id: 'a',
              path: '/m/a.mov',
              kind: TimelineClipKind.video,
            ),
          ],
        );
      await tester.pumpWidget(
        CupertinoApp(home: TimelineProjectsPage(store: store)),
      );
      await tester.pump();
      expect(find.text('Reef'), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Reef')),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('movie_delete_m')), findsOneWidget);
      expect(find.byType(TimelineEditorPage), findsNothing);

      await tester.tap(find.byKey(const Key('movie_delete_m')));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Reef”?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(store.projects, isEmpty);
      expect(find.text('Reef'), findsNothing);
    });

    testWidgets('tapping the lifted movie closes its menu, then opens it', (
      tester,
    ) async {
      _phoneViewport(tester);
      final store = _MemoryStore()
        ..projects['m'] = const TimelineProject(
          id: 'm',
          name: 'Reef',
          clips: [
            TimelineClip(
              id: 'a',
              path: '/m/a.jpg',
              kind: TimelineClipKind.image,
            ),
          ],
        );
      await tester.pumpWidget(
        CupertinoApp(home: TimelineProjectsPage(store: store)),
      );
      await tester.pump();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Reef')),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('movie_delete_m')), findsOneWidget);

      // The menu's actions are dark like the page behind them.
      final open = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.widgetWithText(CupertinoContextMenuAction, 'Open'),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(open.color.computeLuminance(), lessThan(.1));

      await tester.tap(find.text('Reef').last);
      await tester.pump();
      expect(find.byType(TimelineEditorPage), findsNothing);
      // The editor keeps animating, so step through the transitions.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('movie_delete_m')), findsNothing);
      expect(find.byType(TimelineEditorPage), findsOneWidget);
    });
  });
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpPhotoEditor(
  WidgetTester tester, {
  required int count,
  EditorToolGroup? toolGroup,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final directory = Directory.systemTemp.createTempSync('aquarecover_hig_');
  addTearDown(() => directory.delete(recursive: true));
  final bytes = img.encodeJpg(img.Image(width: 16, height: 12), quality: 90);
  final paths = [
    for (var i = 0; i < count; i++)
      (File('${directory.path}/photo_$i.jpg')..writeAsBytesSync(bytes)).path,
  ];
  await tester.pumpWidget(
    CupertinoApp(
      home: EditorPage(
        initialPaths: paths,
        initialToolGroup: toolGroup,
        inspectionService: const _PhotoInspectionService(),
      ),
    ),
  );
  for (var i = 0; i < 7; i++) {
    await tester.pump();
  }
}

/// Picks a preset and waits out the pause that closes the undo step.
Future<void> _choosePreset(WidgetTester tester, String key) async {
  // The list builds lazily, so later presets need a scroll to exist.
  final list = find.descendant(
    of: find.byKey(const Key('preset_list')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(list).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(find.byKey(Key(key)), 120, scrollable: list);
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void _expectNoShadows(WidgetTester tester) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) {
      expect(decoration.boxShadow, anyOf(isNull, isEmpty));
    } else if (decoration is ShapeDecoration) {
      expect(decoration.shadows, anyOf(isNull, isEmpty));
    }
  }
  for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
    text.text.visitChildren((span) {
      expect(span.style?.shadows, anyOf(isNull, isEmpty));
      return true;
    });
  }
}

class _PhotoInspectionService extends MediaInspectionService {
  const _PhotoInspectionService();

  @override
  Future<MediaMetadata> inspect(String path) async => MediaMetadata(
    path: path,
    fileName: File(path).uri.pathSegments.last,
    kind: MediaKind.photo,
    fileSizeBytes: 256,
    width: 16,
    height: 12,
  );
}

class _MemoryStore extends TimelineProjectStore {
  final projects = <String, TimelineProject>{};

  @override
  Future<void> save(TimelineProject project) {
    projects[project.id] = project;
    return Future.value();
  }

  @override
  Future<List<TimelineProject>> list() =>
      SynchronousFuture(projects.values.toList());

  @override
  Future<void> delete(String id) {
    projects.remove(id);
    return Future.value();
  }
}

class _ExportLibrary extends ExportLibraryService {
  _ExportLibrary(this.items);

  final List<LocalExportItem> items;

  @override
  Future<List<LocalExportItem>> load() async => [...items];
}

class _FailingRenderService extends TimelineRenderService {
  @override
  Future<String> render(
    TimelineProject project, {
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async => throw StateError('No encoder available.');
}
