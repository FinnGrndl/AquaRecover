import 'package:aqua_recover/core/logbook/dive_log.dart';
import 'package:aqua_recover/core/logbook/dive_log_store.dart';
import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/persistence/export_library_service.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_project_store.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/editor/widgets/editor_bottom_panel.dart';
import 'package:aqua_recover/features/library/export_library_page.dart';
import 'package:aqua_recover/features/logbook/dive_page.dart';
import 'package:aqua_recover/features/logbook/logbook_media.dart';
import 'package:aqua_recover/features/logbook/logbook_page.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/features/timeline/timeline_projects_page.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_strip.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_toolbar.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_viewer.dart';
import 'package:aqua_recover/shared/widgets/app_dialog.dart';
import 'package:aqua_recover/shared/widgets/app_tooltip.dart';
import 'package:aqua_recover/shared/widgets/editor_shortcuts.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/tooltip_audit.dart';

const _photo = 'docs/assets/demo-underwater-source.jpg';

class _Inspect extends MediaInspectionService {
  const _Inspect();
  @override
  Future<MediaMetadata> inspect(String path) async => MediaMetadata(
    path: path,
    fileName: path.split('/').last,
    kind: MediaKind.photo,
    fileSizeBytes: 2560000,
    width: 1600,
    height: 1200,
  );
}

class _Store extends TimelineProjectStore {
  _Store(this.items);
  final List<TimelineProject> items;
  @override
  Future<void> save(TimelineProject project) async {}
  @override
  Future<List<TimelineProject>> list() => SynchronousFuture(items);
  @override
  Future<void> delete(String id) async {}
}

class _Library extends ExportLibraryService {
  const _Library(this.items);
  final List<LocalExportItem> items;
  @override
  Future<List<LocalExportItem>> load() async => items;
}

class _LogStore extends DiveLogStore {
  _LogStore(this.log);
  DiveLog log;
  @override
  Future<DiveLog> load() async => log;
  @override
  Future<void> save(DiveLog log) async => this.log = log;
}

class _Media extends LogbookMedia {
  const _Media();
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
      buddy: 'Anna Meer',
    ),
  ],
);

Widget _logbook() => LogbookPage(
  store: _LogStore(_log),
  media: const _Media(),
  mapBuilder: (context, sites, onTap) => const SizedBox(key: Key('fake_map')),
);

TimelineProject _project() => TimelineProject(
  id: 'demo',
  name: 'Blue Corner',
  clips: [
    for (var i = 0; i < 3; i++)
      TimelineClip(
        id: 'c$i',
        path: _photo,
        kind: TimelineClipKind.image,
        transition: i == 0 ? ClipTransition.cut : ClipTransition.crossfade,
      ),
  ],
  overlays: const [
    TimelineOverlay(
      id: 'title',
      kind: OverlayKind.text,
      lane: 0,
      start: 0,
      stillSeconds: 4,
      title: TitleSpec(text: 'Blue Corner Wall', style: TitleStyle.boldBox),
    ),
  ],
);

EditorPage _editor({EditorToolGroup? group}) => EditorPage(
  initialPaths: const [_photo, '$_photo?2'],
  initialToolGroup: group,
  inspectionService: const _Inspect(),
  onShowTutorial: () {},
);

void _size(
  WidgetTester tester,
  Size size, {
  double top = 0,
  double bottom = 0,
}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: top * 2, bottom: bottom * 2);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _show(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    CupertinoApp(debugShowCheckedModeBanner: false, home: home),
  );
  await _settle(tester);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)).first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(Key(key)).first, warnIfMissed: false);
  await _settle(tester);
}

void _expectTooltips(WidgetTester tester, String screen) {
  expect(
    iconControlsWithoutTooltip(tester),
    isEmpty,
    reason: '$screen: icon-only controls need a tooltip',
  );
  expect(
    doubledTooltipSemantics(tester),
    isEmpty,
    reason: '$screen: a tooltip must not repeat its control’s label',
  );
}

typedef _Screen = (String, Widget Function(), List<String>);

final _screens = <_Screen>[
  ('start', () => EditorPage(onShowTutorial: () {}), []),
  for (final group in EditorToolGroup.values.where(
    (g) => g != EditorToolGroup.video,
  ))
    ('photo editor ${group.name}', () => _editor(group: group), []),
  ('photo queue', _editor, ['editor_open_queue']),
  ('movies', () => TimelineProjectsPage(store: _Store([_project()])), []),
  ('movie editor', () => TimelineEditorPage(project: _project()), []),
  (
    'movie clip',
    () => TimelineEditorPage(project: _project()),
    ['timeline_clip_c1'],
  ),
  (
    'movie clip duration',
    () => TimelineEditorPage(project: _project()),
    ['timeline_clip_c1', 'timeline_tool_duration'],
  ),
  (
    'movie title text',
    () => TimelineEditorPage(project: _project()),
    ['timeline_overlay_title', 'timeline_tool_text'],
  ),
  (
    'movie transition',
    () => TimelineEditorPage(project: _project()),
    ['timeline_junction_1'],
  ),
  (
    'movie export',
    () => TimelineEditorPage(project: _project()),
    ['timeline_open_export'],
  ),
  ('logbook', _logbook, []),
  ('dive', _logbook, ['dive_d1']),
  (
    'library',
    () => ExportLibraryPage(
      service: _Library([
        LocalExportItem(
          path: _photo,
          kind: MediaKind.photo,
          sizeBytes: 1234,
          modified: DateTime(2026, 5, 1),
        ),
      ]),
    ),
    [],
  ),
  (
    'library detail',
    () => ExportDetailPage(
      item: LocalExportItem(
        path: _photo,
        kind: MediaKind.photo,
        sizeBytes: 1234,
        modified: DateTime(2026, 5, 1),
      ),
      service: const _Library([]),
    ),
    [],
  ),
];

void main() {
  group('every icon-only control has a tooltip', () {
    for (final (name, build, taps) in _screens) {
      testWidgets(name, (tester) async {
        final handle = tester.ensureSemantics();
        for (final size in const [Size(390, 844), Size(1440, 900)]) {
          _size(tester, size);
          await _show(tester, build());
          for (final key in taps) {
            await _tapKey(tester, key);
          }
          _expectTooltips(tester, '$name at $size');
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 2));
        }
        handle.dispose();
      });
    }
  });

  group('AppTooltip', () {
    Widget host(AppTooltipTrigger trigger, {VoidCallback? onLongPress}) =>
        CupertinoApp(
          home: Center(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: AppTooltip(
                message: 'Split',
                trigger: trigger,
                child: CupertinoButton(
                  onPressed: () {},
                  child: const Icon(CupertinoIcons.scissors),
                ),
              ),
            ),
          ),
        );

    testWidgets('shows on touch and hold', (tester) async {
      await tester.pumpWidget(host(AppTooltipTrigger.longPressOrHover));
      await tester.longPress(find.byType(CupertinoButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppTooltipLabel), findsOneWidget);
      // Dark glass, no shadow.
      final boxes = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(AppTooltipLabel),
          matching: find.byType(DecoratedBox),
        ),
      );
      for (final box in boxes) {
        expect((box.decoration as BoxDecoration).boxShadow, isNull);
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AppTooltipLabel), findsNothing);
    });

    testWidgets('shows on hover after a short rest', (tester) async {
      await tester.pumpWidget(host(AppTooltipTrigger.hoverOnly));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(CupertinoButton)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AppTooltipLabel), findsNothing);
      await tester.pump(AppTooltip.hoverDelay);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppTooltipLabel), findsOneWidget);
    });

    testWidgets('hover-only leaves touch and hold to the control', (
      tester,
    ) async {
      var held = false;
      await tester.pumpWidget(
        host(AppTooltipTrigger.hoverOnly, onLongPress: () => held = true),
      );
      await tester.longPress(find.byType(CupertinoButton));
      await tester.pump(const Duration(milliseconds: 300));
      expect(held, isTrue);
      expect(find.byType(AppTooltipLabel), findsNothing);
    });
  });

  testWidgets('holding a clip still reorders it', (tester) async {
    _size(tester, const Size(390, 844));
    await _show(tester, TimelineEditorPage(project: _project()));
    final clip = find.byKey(const Key('timeline_clip_c0'));
    final gesture = await tester.startGesture(tester.getCenter(clip));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(AppTooltipLabel), findsNothing);
    await gesture.moveBy(const Offset(260, 0));
    await tester.pump();
    await gesture.up();
    await _settle(tester);
    final strip = tester.widget<TimelineStrip>(find.byType(TimelineStrip));
    expect(strip.controller.project.clips.first.id, isNot('c0'));
  });

  group('phone landscape movie editor', () {
    testWidgets('puts the viewer beside the controls at full height', (
      tester,
    ) async {
      _size(tester, const Size(844, 390), bottom: 21);
      await _show(tester, TimelineEditorPage(project: _project()));
      final viewer = tester.getRect(find.byType(TimelineViewer));
      final toolbar = tester.getRect(find.byType(TimelineToolbar));
      expect(viewer.height, greaterThan(390 * .8));
      expect(viewer.width, greaterThan(844 * .5));
      expect(toolbar.left, greaterThanOrEqualTo(viewer.right - 1));
      expect(toolbar.bottom, lessThanOrEqualTo(390));
      expect(find.byType(TimelineStrip), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tapKey(tester, 'timeline_clip_c1');
      await _tapKey(tester, 'timeline_tool_effects');
      final panel = tester.getRect(find.byType(GlassBottomPanel));
      expect(panel.left, greaterThanOrEqualTo(viewer.right - 1));
      expect(panel.height, greaterThan(200));
      expect(tester.getRect(find.byType(TimelineViewer)), viewer);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short landscape window keeps the controls on screen', (
      tester,
    ) async {
      _size(tester, const Size(568, 320));
      await _show(tester, TimelineEditorPage(project: _project()));
      expect(
        tester.getRect(find.byType(TimelineToolbar)).bottom,
        lessThan(320),
      );
      expect(
        tester.getRect(find.byType(TimelineViewer)).height,
        greaterThan(250),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('desktop shortcuts', () {
    testWidgets(
      'movie editor',
      variant: const TargetPlatformVariant({
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
      (tester) async {
        final modifier = defaultTargetPlatform == TargetPlatform.macOS
            ? LogicalKeyboardKey.meta
            : LogicalKeyboardKey.control;
        _size(tester, const Size(1280, 800));
        await _show(tester, TimelineEditorPage(project: _project()));

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.bySemanticsLabel('Pause'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(find.bySemanticsLabel('Play'), findsOneWidget);

        await _tapKey(tester, 'timeline_clip_c1');
        await _tapKey(tester, 'timeline_delete');
        expect(find.byKey(const Key('timeline_clip_c1')), findsNothing);
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(modifier);
        await _settle(tester);
        expect(find.byKey(const Key('timeline_clip_c1')), findsOneWidget);
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyUpEvent(modifier);
        await _settle(tester);
        expect(find.byKey(const Key('timeline_clip_c1')), findsNothing);

        // Escape closes the panel, then clears the selection.
        await _tapKey(tester, 'timeline_clip_c0');
        await _tapKey(tester, 'timeline_tool_effects');
        expect(find.byType(GlassBottomPanel), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(find.byType(GlassBottomPanel), findsNothing);
        expect(find.byKey(const Key('timeline_tool_back')), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(find.byKey(const Key('timeline_tool_back')), findsNothing);
      },
    );

    test('help tags name the shortcut on a computer only', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(withShortcut('Undo', 'Z'), 'Undo (⌘Z)');
      expect(withShortcut('Redo', 'Z', shift: true), 'Redo (⇧⌘Z)');
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(withShortcut('Redo', 'Z', shift: true), 'Redo (Ctrl+Shift+Z)');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(withShortcut('Undo', 'Z'), 'Undo');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'Space types a space in a text field',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        _size(tester, const Size(1280, 800));
        await _show(tester, TimelineEditorPage(project: _project()));
        await _tapKey(tester, 'timeline_overlay_title');
        await _tapKey(tester, 'timeline_tool_text');
        final field = find.byKey(const Key('timeline_text_field'));
        await tester.tap(field);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(find.bySemanticsLabel('Pause'), findsNothing);
      },
    );

    Widget dialogHost(void Function(Object?) done, {bool field = false}) =>
        CupertinoApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () async {
                done(
                  await showAppDialog<String>(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('Delete?'),
                      content: field
                          ? const CupertinoTextField(autofocus: true)
                          : null,
                      actions: [
                        CupertinoDialogAction(
                          onPressed: () => Navigator.of(context).pop('ok'),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        );

    testWidgets(
      'Escape cancels an alert',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        Object? result = 'open';
        await tester.pumpWidget(dialogHost((r) => result = r));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoAlertDialog), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoAlertDialog), findsNothing);
        expect(result, isNull);
      },
    );

    testWidgets('an alert’s text field keeps its autofocus', (tester) async {
      await tester.pumpWidget(dialogHost((_) {}, field: true));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
    });

    testWidgets(
      'Escape collapses the photo tool panel',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        _size(tester, const Size(800, 600));
        await _show(tester, _editor(group: EditorToolGroup.light));
        expect(
          find.byKey(const Key('editor_tool_panel_close')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(find.byKey(const Key('editor_tool_panel_close')), findsNothing);
        expect(find.byKey(const Key('editor_tool_panel_open')), findsOneWidget);
      },
    );
  });

  group('wide screens', () {
    testWidgets('the photo tool panel moves into the side pane', (
      tester,
    ) async {
      _size(tester, const Size(1440, 900));
      await _show(tester, _editor(group: EditorToolGroup.light));
      final close = find.byKey(const Key('editor_tool_panel_close'));
      expect(close, findsOneWidget);
      expect(tester.getRect(close).left, greaterThan(1440 - 400));
      // Nothing covers the bottom of the preview but the slim rail.
      final rail = tester.getRect(
        find.byKey(const Key('editor_tool_light')).first,
      );
      expect(rail.top, greaterThan(900 - 120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a landscape phone shows the photo tools beside the photo', (
      tester,
    ) async {
      _size(tester, const Size(844, 390), bottom: 21);
      await _show(tester, _editor(group: EditorToolGroup.light));
      final close = find.byKey(const Key('editor_tool_panel_close'));
      expect(close, findsOneWidget);
      expect(tester.getRect(close).left, greaterThan(844 - 340));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the logbook shows the selected dive beside the list', (
      tester,
    ) async {
      _size(tester, const Size(1440, 900));
      await _show(tester, _logbook());
      expect(find.byType(DivePage), findsOneWidget);
      expect(find.text('12.0 m'), findsWidgets);
      await _tapKey(tester, 'dive_d1');
      expect(find.text('Anna Meer'), findsOneWidget);
      // Still one page: the list stays beside the dive.
      expect(find.byKey(const Key('logbook_list')), findsOneWidget);
      expect(find.byType(DivePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow logbook still pushes the dive', (tester) async {
      _size(tester, const Size(390, 844));
      await _show(tester, _logbook());
      expect(find.byType(DivePage), findsNothing);
      await _tapKey(tester, 'dive_d1');
      await tester.pumpAndSettle();
      expect(find.byType(DivePage), findsOneWidget);
      expect(find.text('Anna Meer'), findsOneWidget);
    });
  });
}
