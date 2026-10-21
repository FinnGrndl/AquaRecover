import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/editor/widgets/editor_bottom_panel.dart';
import 'package:aqua_recover/features/editor/widgets/editor_preview_stage.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_strip.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_toolbar.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_viewer.dart';
import 'package:aqua_recover/shared/widgets/resizable_split.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
);

EditorPage _photoEditor() => EditorPage(
  initialPaths: const [_photo],
  initialToolGroup: EditorToolGroup.light,
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

final _handle = find.byKey(ResizableSplit.handleKey);

Future<void> _drag(WidgetTester tester, Offset by) async {
  await tester.drag(_handle, by);
  await _settle(tester);
}

Future<void> _doubleTap(WidgetTester tester) async {
  await tester.tap(_handle);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(_handle);
  await _settle(tester);
}

Rect _photoRect(WidgetTester tester) =>
    tester.getRect(find.byType(EditorPreviewStage));

Rect _viewer(WidgetTester tester) =>
    tester.getRect(find.byType(TimelineViewer));

double _panelHeight(WidgetTester tester) =>
    tester.getSize(find.byType(GlassBottomPanel)).height;

void main() {
  setUp(PreviewSplitMemory.clear);

  group('photo editor', () {
    testWidgets('side by side: the divider drags the photo wider', (
      tester,
    ) async {
      _size(tester, const Size(844, 390), bottom: 21);
      await _show(tester, _photoEditor());
      final start = _photoRect(tester).width;

      await _drag(tester, const Offset(-120, 0));
      expect(_photoRect(tester).width, closeTo(start - 120, 1));
      await _drag(tester, const Offset(80, 0));
      expect(_photoRect(tester).width, closeTo(start - 40, 1));

      // Clamped at both ends.
      await _drag(tester, const Offset(-2000, 0));
      expect(_photoRect(tester).width, closeTo(300, 1));
      await _drag(tester, const Offset(2000, 0));
      expect(844 - _photoRect(tester).right, closeTo(280, 1));
      expect(tester.takeException(), isNull);

      await _doubleTap(tester);
      expect(_photoRect(tester).width, closeTo(start, .5));
    });

    testWidgets('stacked: the divider trades height with the tool panel', (
      tester,
    ) async {
      _size(tester, const Size(390, 844), top: 47, bottom: 34);
      await _show(tester, _photoEditor());
      double inset() => tester
          .widget<EditorPreviewStage>(find.byType(EditorPreviewStage))
          .immersiveBottomInset;
      final panel = _panelHeight(tester);
      final photoInset = inset();
      // The grabber sits on the panel's top edge.
      expect(
        tester.getRect(_handle).bottom,
        closeTo(tester.getRect(find.byType(GlassBottomPanel)).top, 1),
      );

      await _drag(tester, const Offset(0, -100));
      expect(_panelHeight(tester), closeTo(panel + 100, 1));
      expect(inset(), closeTo(photoInset + 100, 1));

      await _drag(tester, const Offset(0, -2000));
      final previewTop = tester.getRect(find.byKey(const Key('editor_undo')));
      // At least 150 pt of photo between the floating buttons' row and the
      // panel.
      expect(
        tester.getRect(find.byType(GlassBottomPanel)).top -
            (previewTop.top - 8),
        greaterThanOrEqualTo(150 - 1),
      );
      await _drag(tester, const Offset(0, 2000));
      // 200 pt and the panel's margin.
      expect(_panelHeight(tester), closeTo(207, 1));
      expect(tester.takeException(), isNull);

      await _doubleTap(tester);
      expect(_panelHeight(tester), closeTo(panel, .5));
    });

    testWidgets('a closed panel leaves the photo alone', (tester) async {
      _size(tester, const Size(390, 844), top: 47, bottom: 34);
      await _show(tester, _photoEditor());
      await tester.tap(find.byKey(const Key('editor_tool_panel_close')));
      await _settle(tester);
      expect(_handle, findsNothing);
    });
  });

  group('movie editor', () {
    testWidgets('side by side: the divider drags the viewer wider', (
      tester,
    ) async {
      _size(tester, const Size(844, 390), bottom: 21);
      await _show(tester, TimelineEditorPage(project: _project()));
      final start = _viewer(tester).width;

      await _drag(tester, const Offset(-100, 0));
      expect(_viewer(tester).width, closeTo(start - 100, 1));

      await _drag(tester, const Offset(-2000, 0));
      // The viewer area keeps 150 pt; the viewer pads it by 12 a side.
      expect(_viewer(tester).width, closeTo(150 - 24, 1));
      await _drag(tester, const Offset(2000, 0));
      expect(
        844 - tester.getRect(find.byType(TimelineToolbar)).left,
        greaterThan(280),
      );
      expect(tester.takeException(), isNull);

      await _doubleTap(tester);
      expect(_viewer(tester).width, closeTo(start, .5));
    });

    testWidgets('stacked: the divider drags the viewer taller', (tester) async {
      _size(tester, const Size(390, 844), top: 47, bottom: 34);
      await _show(tester, TimelineEditorPage(project: _project()));
      final start = _viewer(tester).height;

      await _drag(tester, const Offset(0, -100));
      expect(_viewer(tester).height, closeTo(start - 100, 1));

      await _drag(tester, const Offset(0, 2000));
      // Taller until only the transport and toolbar are left below it.
      expect(_viewer(tester).height, greaterThan(start + 50));
      expect(
        tester.getRect(find.byType(TimelineToolbar)).bottom,
        lessThanOrEqualTo(844),
      );
      await _drag(tester, const Offset(0, -2000));
      expect(_viewer(tester).height, closeTo(150 - 8, 1));
      expect(tester.takeException(), isNull);

      await _doubleTap(tester);
      expect(_viewer(tester).height, closeTo(start, .5));
    });

    testWidgets('wide: the divider drags the viewer above the timeline', (
      tester,
    ) async {
      _size(tester, const Size(1440, 900));
      await _show(tester, TimelineEditorPage(project: _project()));
      final start = _viewer(tester).height;
      await _drag(tester, const Offset(0, -150));
      expect(_viewer(tester).height, closeTo(start - 150, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a taller viewer settles where the strip leaves no gap', (
      tester,
    ) async {
      _size(tester, const Size(1440, 900));
      await _show(tester, TimelineEditorPage(project: _project()));
      final start = _viewer(tester).height;
      double gap() {
        final strip = find.byType(TimelineStrip);
        final above = strip.evaluate().isEmpty
            ? _viewer(tester).bottom + 4 + 52
            : tester.getRect(strip).bottom;
        return tester.getRect(find.byType(TimelineToolbar)).top - above;
      }

      expect(gap(), closeTo(8, 1));
      for (final step in [40.0, 40.0, 40.0]) {
        await _drag(tester, Offset(0, step));
        expect(gap(), closeTo(8, 1));
      }
      expect(_viewer(tester).height, greaterThan(start + 100));
      // And back down, through the same stops.
      await _drag(tester, const Offset(0, -40));
      expect(gap(), closeTo(8, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the size lasts for the session', (tester) async {
      _size(tester, const Size(844, 390), bottom: 21);
      await _show(tester, TimelineEditorPage(project: _project()));
      final start = _viewer(tester).width;
      await _drag(tester, const Offset(-100, 0));
      await tester.pumpWidget(const SizedBox());
      await _show(tester, TimelineEditorPage(project: _project()));
      expect(_viewer(tester).width, closeTo(start - 100, 1));
    });
  });

  testWidgets('a drag near the default snaps to it', (tester) async {
    _size(tester, const Size(844, 390), bottom: 21);
    await _show(tester, TimelineEditorPage(project: _project()));
    final start = _viewer(tester).width;
    await _drag(tester, const Offset(20, 0));
    expect(_viewer(tester).width, closeTo(start, .5));
    expect(PreviewSplitMemory.ratioOf('movie.sideBySide'), isNull);
  });

  testWidgets('Reduce Motion resets without animating', (tester) async {
    _size(tester, const Size(844, 390), bottom: 21);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: CupertinoApp(
          debugShowCheckedModeBanner: false,
          home: TimelineEditorPage(project: _project()),
        ),
      ),
    );
    await _settle(tester);
    final start = _viewer(tester).width;
    await _drag(tester, const Offset(-100, 0));
    await tester.tap(_handle);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(_handle);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_viewer(tester).width, closeTo(start, .5));
  });

  testWidgets('arrow keys resize the focused divider', (tester) async {
    _size(tester, const Size(844, 390), bottom: 21);
    await _show(tester, TimelineEditorPage(project: _project()));
    final start = _viewer(tester).width;
    Focus.of(tester.element(_handle)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(_viewer(tester).width, lessThan(start - 60));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(_viewer(tester).width, closeTo(start, .5));

    // Stacked layouts take up and down.
    await tester.pumpWidget(const SizedBox());
    _size(tester, const Size(390, 844), top: 47, bottom: 34);
    await _show(tester, TimelineEditorPage(project: _project()));
    final height = _viewer(tester).height;
    Focus.of(tester.element(_handle)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester);
    expect(_viewer(tester).height, lessThan(height - 30));
  });

  testWidgets('VoiceOver adjusts the divider in steps', (tester) async {
    final semantics = tester.ensureSemantics();
    _size(tester, const Size(844, 390), bottom: 21);
    await _show(tester, _photoEditor());
    final start = _photoRect(tester).width;
    var node = tester.getSemantics(_handle);
    expect(node.label, 'Preview size');
    expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.decrease);
    await _settle(tester);
    expect(_photoRect(tester).width, lessThan(start - 30));
    node = tester.getSemantics(_handle);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    await _settle(tester);
    expect(_photoRect(tester).width, closeTo(start, .5));
    semantics.dispose();
  });

  group('no overflow at the extremes', () {
    const screens = {
      'iPhone SE': (size: Size(320, 568), top: 20.0, bottom: 0.0),
      'iPhone landscape': (size: Size(844, 390), top: 0.0, bottom: 21.0),
      'iPad': (size: Size(820, 1180), top: 24.0, bottom: 20.0),
      'Mac 800 × 600': (size: Size(800, 600), top: 0.0, bottom: 0.0),
    };
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      for (final movie in [false, true]) {
        testWidgets('${movie ? 'movie' : 'photo'} editor on $name', (
          tester,
        ) async {
          _size(tester, screen.size, top: screen.top, bottom: screen.bottom);
          await _show(
            tester,
            movie ? TimelineEditorPage(project: _project()) : _photoEditor(),
          );
          Future<void> extremes() async {
            expect(_handle, findsOneWidget);
            final side =
                screen.size.width > screen.size.height &&
                screen.size.height < 500;
            for (final d in [-2000.0, 2000.0, -2000.0]) {
              final by = side ? Offset(d, 0) : Offset(0, d);
              final gesture = await tester.startGesture(
                tester.getCenter(_handle),
              );
              // Live, frame by frame.
              for (var i = 0; i < 8; i++) {
                await gesture.moveBy(by / 8);
                await tester.pump();
                expect(tester.takeException(), isNull);
              }
              await gesture.up();
              await _settle(tester);
              expect(tester.takeException(), isNull);
              expect(
                tester.getRect(_handle).center.dx,
                inInclusiveRange(0, screen.size.width),
              );
            }
          }

          await extremes();
          if (movie) {
            // With a tool panel open as well.
            await tester.tap(find.byKey(const Key('timeline_clip_c1')));
            await _settle(tester);
            await tester.tap(find.byKey(const Key('timeline_tool_effects')));
            await _settle(tester);
            await extremes();
          }
        });
      }
    }
  });
}
