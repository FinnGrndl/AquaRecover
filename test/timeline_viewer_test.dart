import 'dart:ui' as ui;

import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:aqua_recover/features/timeline/preview/preview_frame.dart';
import 'package:aqua_recover/features/timeline/preview/preview_player.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_viewer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// A player that opens at once and records calls.
class _Player implements PreviewPlayer {
  _Player(this.path);

  @override
  final String path;
  final calls = <String>[];
  final seeks = <double>[];
  bool disposed = false;

  @override
  bool isInitialized = false;

  @override
  Duration position = Duration.zero;

  @override
  Duration get duration => const Duration(seconds: 20);

  @override
  Size get size => const Size(1280, 720);

  @override
  Future<void> initialize() async => isInitialized = true;

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seekTo(Duration to) async {
    seeks.add(to.inMicroseconds / 1e6);
    position = to;
  }

  @override
  Future<void> setVolume(double volume) async => calls.add('volume $volume');

  @override
  Future<void> setPlaybackSpeed(double speed) async =>
      calls.add('speed $speed');

  @override
  Widget buildView() =>
      ColoredBox(key: ValueKey('view $path'), color: const Color(0xFF336699));

  @override
  Future<void> dispose() async => disposed = true;
}

const _photo = TimelineClip(
  id: 'a',
  path: '/m/a.jpg',
  kind: TimelineClipKind.image,
  stillSeconds: 4,
);

const _title = TimelineOverlay(
  id: 'title',
  kind: OverlayKind.text,
  lane: 1,
  stillSeconds: 3,
  centerY: 0.8,
  widthFraction: 0.45,
  title: TitleSpec(text: 'Blue Hole', style: TitleStyle.outline),
);

const _overlay = TimelineOverlay(
  id: 'photo',
  kind: OverlayKind.image,
  path: '/m/o.png',
  stillSeconds: 3,
  centerX: 0.75,
  centerY: 0.3,
  widthFraction: 0.3,
  mediaAspect: 1.5,
);

Future<void> _setView(WidgetTester tester) async {
  tester.view.physicalSize = const Size(640, 360);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('draws a title and an overlay where the plan puts them', (
    tester,
  ) async {
    await _setView(tester);
    final image = (await tester.runAsync(() => _image(16, 4)))!;
    addTearDown(image.dispose);
    final specs = <GeneratedSpec>[];
    final services = PreviewServices(
      rasterize: (spec) async {
        specs.add(spec);
        return image.clone();
      },
    );
    const project = TimelineProject(
      id: 'p',
      clips: [_photo],
      overlays: [_title, _overlay],
    );
    PreviewCanvas? canvas;
    await tester.pumpWidget(
      CupertinoApp(
        home: TimelineViewer(
          project: project,
          playhead: 1,
          playing: false,
          services: services,
          canvasOverlay: (context, c) {
            canvas = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pump();

    // 1920 × 1080 shown at 640 × 360: one view point is three pixels.
    final plan = compilePreviewPlan(project);
    final key = TimelineRenderPlan.evaluateLayer(
      plan.layers.firstWhere((l) => l.id == 'title'),
      1,
    );
    final titleBox = find.byKey(const ValueKey('preview-layer-title'));
    final rect = tester.getRect(titleBox);
    expect(rect.left, closeTo(key.x / 3, 1e-6));
    expect(rect.top, closeTo(key.y / 3, 1e-6));
    expect(rect.width, closeTo(key.w / 3, 1e-6));
    expect(rect.height, closeTo(key.h / 3, 1e-6));
    // Centred, 45 % of the width, centre at 80 % of the height.
    expect(rect.center.dx, closeTo(320, 1e-6));
    expect(rect.center.dy, closeTo(288, 1e-6));
    expect(rect.width, closeTo(288, 1e-6));

    // Rasterised once at view size, drawn without a save layer.
    final title = specs.single as TitleTexture;
    expect(title.width, 288);
    expect(title.title.text, 'Blue Hole');
    final raw = tester.widget<RawImage>(
      find.descendant(of: titleBox, matching: find.byType(RawImage)),
    );
    expect(raw.image, isNotNull);
    expect(
      find.descendant(of: titleBox, matching: find.byType(Opacity)),
      findsNothing,
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('preview-layer-photo'))),
      const Rect.fromLTWH(384, 44, 192, 128),
    );
    expect(canvas!.layerRect('photo'), const Rect.fromLTWH(384, 44, 192, 128));
    expect(canvas!.scale, 1 / 3);

    // After the title ends only the overlay remains.
    await tester.pumpWidget(
      CupertinoApp(
        home: TimelineViewer(
          project: project,
          playhead: 3.5,
          playing: false,
          services: services,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('preview-layer-title')), findsNothing);
    expect(find.byKey(const ValueKey('preview-layer-photo')), findsNothing);
    expect(specs, hasLength(1));
  });

  testWidgets('videos come from the pool, synced to the playhead', (
    tester,
  ) async {
    await _setView(tester);
    final players = <_Player>[];
    final durations = <String, double>{};
    final services = PreviewServices(
      videoPlayer: (path) {
        final player = _Player(path);
        players.add(player);
        return player;
      },
      audioEnabled: false,
    );
    const project = TimelineProject(
      id: 'p',
      clips: [
        TimelineClip(
          id: 'v',
          path: '/m/v.mov',
          kind: TimelineClipKind.video,
          sourceStart: 2,
          sourceDuration: 12,
          speed: 2,
          volume: 0.5,
        ),
      ],
      overlays: [
        TimelineOverlay(
          id: 'pip',
          kind: OverlayKind.video,
          path: '/m/pip.mov',
          start: 1,
          sourceDuration: 6,
          centerX: 0.8,
          centerY: 0.8,
          widthFraction: 0.3,
          volume: 0,
        ),
      ],
    );
    Widget viewer(double t, {bool playing = false}) => CupertinoApp(
      home: TimelineViewer(
        project: project,
        playhead: t,
        playing: playing,
        services: services,
        onVideoDuration: (id, seconds) => durations[id] = seconds,
      ),
    );

    await tester.pumpWidget(viewer(1.5));
    await tester.pump();
    expect(players.map((p) => p.path), ['/m/v.mov', '/m/pip.mov']);
    expect(durations, {'v': 20.0});
    expect(find.byKey(const ValueKey('view /m/v.mov')), findsOneWidget);
    expect(find.byKey(const ValueKey('view /m/pip.mov')), findsOneWidget);
    // Main clip: source 2 + 1.5 s × 2; overlay: 0.5 s in.
    expect(players[0].seeks.last, closeTo(5, 1e-6));
    expect(players[1].seeks.last, closeTo(0.5, 1e-6));
    // A 1280 × 720 frame fills the 16:9 canvas.
    expect(
      tester.getRect(find.byKey(const ValueKey('view /m/v.mov'))),
      const Rect.fromLTWH(0, 0, 640, 360),
    );

    await tester.pumpWidget(viewer(1.6, playing: true));
    expect(players[0].calls, containsAllInOrder(['speed 2.0', 'volume 0.5']));
    expect(players[0].calls.last, 'play');
    expect(players[1].calls, contains('volume 0.0'));

    await tester.pumpWidget(const SizedBox());
    expect(players.every((p) => p.disposed), isTrue);
  });

  testWidgets('an empty movie shows a black canvas', (tester) async {
    await _setView(tester);
    await tester.pumpWidget(
      const CupertinoApp(
        home: TimelineViewer(
          project: TimelineProject(id: 'e'),
          playhead: 0,
          playing: false,
        ),
      ),
    );
    expect(find.byType(RawImage), findsNothing);
    expect(
      find.descendant(
        of: find.byType(TimelineViewer),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
  });

  test('the viewer compiles plans as the export does', () {
    const project = TimelineProject(
      id: 'p',
      clips: [_photo],
      overlays: [_title],
    );
    final layer = compilePreviewPlan(project).layers.single;
    // The title's rect has the measured aspect, not the stored 16:9.
    expect(layer.keys.last.w / layer.keys.last.h, isNot(closeTo(16 / 9, 0.01)));
  });
}

Future<ui.Image> _image(int w, int h) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(w, h);
}
