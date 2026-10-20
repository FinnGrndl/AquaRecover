import 'package:aqua_recover/core/timeline/timeline_project.dart';
import 'package:aqua_recover/core/timeline/timeline_render_plan.dart';
import 'package:aqua_recover/features/timeline/timeline_controller.dart';
import 'package:aqua_recover/features/timeline/timeline_editor_page.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_strip.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_viewer.dart';
import 'package:aqua_recover/features/timeline/widgets/tools/speed_panel.dart';
import 'package:aqua_recover/features/timeline/widgets/viewer_selection_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

const _photo = TimelineClip(
  id: 'a',
  path: '/m/a.jpg',
  kind: TimelineClipKind.image,
);

const _video = TimelineClip(
  id: 'v',
  path: '/m/clip.mov',
  kind: TimelineClipKind.video,
  sourceDuration: 10,
);

void _phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpEditor(
  WidgetTester tester,
  TimelineProject project, {
  Future<List<String>> Function()? audioPicker,
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: TimelineEditorPage(
        project: project,
        audioPicker: audioPicker,
        audioProbe: (_) async => 30,
        today: DateTime(2026, 10, 19),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

TimelineViewer _viewer(WidgetTester tester) =>
    tester.widget<TimelineViewer>(find.byType(TimelineViewer));

TimelineProject _project(WidgetTester tester) => _viewer(tester).project;

TimelineRenderPlan _plan(WidgetTester tester) => _viewer(tester).plan!;

Finder _keyPrefix(String prefix) => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith(prefix);
});

void main() {
  testWidgets('the toolbar follows the selection', (tester) async {
    _phone(tester);
    await _pumpEditor(
      tester,
      const TimelineProject(
        id: 'w',
        clips: [_photo, _video],
        overlays: [
          TimelineOverlay(
            id: 't',
            kind: OverlayKind.text,
            lane: 0,
            title: TitleSpec(text: 'Reef'),
          ),
        ],
        audioClips: [
          TimelineAudioClip(id: 's', path: '/m/song.m4a', sourceDuration: 8),
        ],
      ),
    );
    // Nothing selected: the root tools.
    for (final id in ['edit', 'audio', 'text', 'overlay', 'effects']) {
      expect(find.byKey(Key('timeline_tool_$id')), findsOneWidget);
    }
    expect(find.byKey(const Key('timeline_tool_back')), findsNothing);

    // A photo clip offers Duration and Motion instead of Speed and Volume.
    await tester.tap(find.byKey(const Key('timeline_tool_edit')));
    await tester.pump();
    expect(find.byKey(const Key('timeline_split')), findsOneWidget);
    expect(find.byKey(const Key('timeline_tool_duration')), findsOneWidget);
    expect(find.byKey(const Key('timeline_tool_speed')), findsNothing);

    // A title: Edit, Opacity, Animate, Layer.
    await tester.tap(find.byKey(const Key('timeline_overlay_t')));
    await tester.pump();
    expect(find.byKey(const Key('timeline_tool_text')), findsOneWidget);
    expect(find.byKey(const Key('timeline_tool_layer')), findsOneWidget);
    expect(find.byKey(const Key('timeline_tool_duration')), findsNothing);

    // A sound: Volume and Fade.
    // Long items run past the screen edge, so tap near their start.
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('timeline_audio_s'))) +
          const Offset(24, 12),
    );
    await tester.pump();
    expect(find.byKey(const Key('timeline_tool_volume')), findsOneWidget);
    expect(find.byKey(const Key('timeline_tool_fade')), findsOneWidget);
    expect(find.byKey(const Key('timeline_tool_effects')), findsNothing);

    // Done goes back to the root tools.
    await tester.tap(find.byKey(const Key('timeline_tool_back')));
    await tester.pump();
    expect(find.byKey(const Key('timeline_tool_format')), findsOneWidget);
  });

  testWidgets('Text adds a title on an overlay lane and in the plan', (
    tester,
  ) async {
    _phone(tester);
    await _pumpEditor(tester, const TimelineProject(id: 'w', clips: [_photo]));
    expect(_keyPrefix('timeline_overlay_'), findsNothing);

    await tester.tap(find.byKey(const Key('timeline_tool_text')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('timeline_text_field')), findsOneWidget);
    expect(_keyPrefix('timeline_overlay_'), findsOneWidget);

    final title = _project(tester).overlays.single;
    expect(title.title, isNotNull);
    final layer = _plan(tester).layers.singleWhere((l) => l.id == title.id);
    expect(layer.kind, PlanLayerKind.image);

    await tester.enterText(
      find.byKey(const Key('timeline_text_field')),
      'Manta point',
    );
    await tester.pump();
    expect(_project(tester).overlays.single.title!.text, 'Manta point');
  });

  testWidgets('an effect changes the clip and the plan’s filters', (
    tester,
  ) async {
    _phone(tester);
    await _pumpEditor(tester, const TimelineProject(id: 'w', clips: [_photo]));
    expect(_plan(tester).clips.single.filters.colorMatrix, isNull);

    await _tap(tester, 'timeline_tool_edit');
    await _tap(tester, 'timeline_tool_effects');
    await _tap(tester, 'timeline_effect_${EffectType.mono.id}');
    expect(_project(tester).clips.single.effects.map((e) => e.type), [
      EffectType.mono,
    ]);
    expect(_plan(tester).clips.single.filters.colorMatrix, isNotNull);

    // Tapping the focused effect again removes it; Undo brings it back.
    await _tap(tester, 'timeline_effect_${EffectType.mono.id}');
    expect(_project(tester).clips.single.effects, isEmpty);
    await _tap(tester, 'timeline_undo');
    expect(_project(tester).clips.single.effects, hasLength(1));
    await _tap(tester, 'timeline_redo');
    expect(_project(tester).clips.single.effects, isEmpty);
  });

  testWidgets('2× speed halves the clip on the timeline', (tester) async {
    _phone(tester);
    await _pumpEditor(tester, const TimelineProject(id: 'w', clips: [_video]));
    final before = tester.getSize(find.byKey(const Key('timeline_clip_v')));
    String label() => tester
        .widget<Text>(find.byKey(const Key('timeline_clip_duration_v')))
        .data!;
    final labelBefore = label();

    await _tap(tester, 'timeline_tool_edit');
    await _tap(tester, 'timeline_tool_speed');
    final slider = tester.widget<CupertinoSlider>(
      find.byKey(const Key('timeline_speed_slider')),
    );
    slider.onChangeStart?.call(slider.value);
    slider.onChanged!(SpeedPanel.positionOf(2));
    slider.onChangeEnd?.call(SpeedPanel.positionOf(2));
    await tester.pump();

    expect(_project(tester).clips.single.speed, 2);
    expect(_project(tester).duration, closeTo(5, 1e-6));
    final after = tester.getSize(find.byKey(const Key('timeline_clip_v')));
    expect(after.width, closeTo(before.width / 2, 1.5));
    expect(label(), isNot(labelBefore));
    expect(find.byKey(const Key('timeline_speed_value')), findsOneWidget);
  });

  testWidgets('Audio adds music from the picker to an audio lane', (
    tester,
  ) async {
    _phone(tester);
    await _pumpEditor(
      tester,
      const TimelineProject(id: 'w', clips: [_photo]),
      audioPicker: () async => ['/m/Blue Hour.m4a'],
    );
    await _tap(tester, 'timeline_tool_audio');
    await _tap(tester, 'timeline_audio_music');
    await tester.pump();

    final audio = _project(tester).audioClips.single;
    expect(audio.name, 'Blue Hour');
    expect(audio.sourceDuration, 30);
    expect(find.byKey(Key('timeline_audio_${audio.id}')), findsOneWidget);
    final segment = _plan(tester).audio.singleWhere((a) => a.id == audio.id);
    expect(segment.origin, PlanAudioOrigin.track);
  });

  testWidgets('empty text, overlay and audio lanes show before use', (
    tester,
  ) async {
    _phone(tester);
    await _pumpEditor(
      tester,
      const TimelineProject(id: 'w', clips: [_photo]),
      audioPicker: () async => ['/m/Blue Hour.m4a'],
    );
    for (final key in [
      'timeline_add_text',
      'timeline_add_overlay',
      'timeline_add_audio',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }

    await _tap(tester, 'timeline_add_audio');
    await _tap(tester, 'timeline_audio_music');
    await tester.pump();
    expect(_project(tester).audioClips, hasLength(1));
    // A new empty lane stays below the one that now holds the sound.
    expect(find.byKey(const Key('timeline_add_audio')), findsOneWidget);

    await _tap(tester, 'timeline_add_text');
    expect(_project(tester).overlays.single.title, isNotNull);
  });

  testWidgets('extract audio silences the clip and adds a sound', (
    tester,
  ) async {
    _phone(tester);
    await _pumpEditor(tester, const TimelineProject(id: 'w', clips: [_video]));
    await _tap(tester, 'timeline_tool_audio');
    await _tap(tester, 'timeline_audio_extract');

    var project = _project(tester);
    expect(project.clips.single.volume, 0);
    final sound = project.audioClips.single;
    expect(sound.role, AudioRole.extracted);
    expect(sound.path, _video.path);
    expect(find.byKey(Key('timeline_audio_${sound.id}')), findsOneWidget);

    await _tap(tester, 'timeline_undo');
    project = _project(tester);
    expect(project.clips.single.volume, 1);
    expect(project.audioClips, isEmpty);
    await _tap(tester, 'timeline_redo');
    expect(_project(tester).audioClips, hasLength(1));
  });

  testWidgets('dragging an overlay in the viewer moves it', (tester) async {
    final controller = TimelineController(
      const TimelineProject(
        id: 'w',
        clips: [_photo],
        overlays: [
          TimelineOverlay(
            id: 'o',
            kind: OverlayKind.image,
            path: '/m/o.jpg',
            centerX: .3,
            centerY: .3,
            widthFraction: .3,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    controller.select('o');
    const canvas = Size(400, 225);
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: SizedBox.fromSize(
            size: canvas,
            child: ViewerSelectionOverlay(
              controller: controller,
              canvasSize: canvas,
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(
      find.byKey(const Key('timeline_viewer_canvas')),
    );
    final start = origin + const Offset(120, 67.5);
    final gesture = await tester.startGesture(start);
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(start + Offset(6.0 * i, 3.0 * i));
      await tester.pump();
    }
    await gesture.up();
    // Let the double-tap timer run out.
    await tester.pump(const Duration(seconds: 1));

    final moved = controller.overlayById('o')!;
    expect(moved.centerX, greaterThan(.4));
    expect(moved.centerY, greaterThan(.36));
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(controller.overlayById('o')!.centerX, .3);
  });

  testWidgets('dragging a lane item snaps its start and changes lane', (
    tester,
  ) async {
    _phone(tester);
    final controller = TimelineController(
      const TimelineProject(
        id: 'w',
        clips: [_photo, _photo],
        overlays: [
          TimelineOverlay(id: 'o', kind: OverlayKind.image, path: '/m/o.jpg'),
          TimelineOverlay(
            id: 'p',
            kind: OverlayKind.image,
            path: '/m/p.jpg',
            lane: 1,
            start: 4.5,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    final zoom = TimelineZoom(60);
    addTearDown(zoom.dispose);
    await tester.pumpWidget(
      CupertinoApp(
        home: Align(
          alignment: Alignment.bottomCenter,
          child: TimelineStrip(controller: controller, zoom: zoom),
        ),
      ),
    );
    controller.select('o');
    await tester.pump();
    final clipEnd = controller.layout.entries.first.end;
    final o = controller.overlayById('o')!;
    final upper = tester.getRect(find.byKey(const Key('timeline_overlay_p')));
    final lower = tester.getRect(find.byKey(const Key('timeline_overlay_o')));
    // Within the snap tolerance of the first clip's end, one lane up.
    final dx = (clipEnd - o.start - .08) * zoom.value;
    final dy = upper.center.dy - lower.center.dy;
    final from = lower.center;
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(from + Offset(dx * i / 12, dy * i / 12));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final moved = controller.overlayById('o')!;
    expect(moved.start, closeTo(clipEnd, 1e-9));
    expect(moved.lane, 1);
    controller.undo();
    expect(controller.overlayById('o')!.start, 0);
    expect(controller.overlayById('o')!.lane, 0);
  });

  testWidgets('v1 projects and dip transitions open in the editor', (
    tester,
  ) async {
    _phone(tester);
    final v1 = TimelineProject.fromJson({
      'format': 'aquarecover.timeline',
      'version': 1,
      'id': 'old',
      'name': 'Old dive',
      'clips': [
        {'id': 'c', 'path': '/c.jpg', 'kind': 'image', 'stillSeconds': 3},
        {
          'id': 'd',
          'path': '/d.jpg',
          'kind': 'image',
          'stillSeconds': 3,
          'transition': 'crossfade',
        },
      ],
    });
    expect(v1.toJson()['version'], TimelineProject.formatVersion);
    await _pumpEditor(tester, v1);
    expect(find.text('Old dive'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Every transition, dips included, can be chosen at the junction.
    await _tap(tester, 'timeline_junction_1');
    for (final t in ClipTransition.values) {
      await _tap(tester, 'timeline_transition_${t.name}');
      expect(_project(tester).clips[1].transition, t);
    }
  });

  testWidgets('works at 320 pt and keeps every surface shadow-free', (
    tester,
  ) async {
    _phone(tester, width: 320, height: 568);
    await _pumpEditor(
      tester,
      const TimelineProject(
        id: 'w',
        clips: [_photo, _video],
        overlays: [
          TimelineOverlay(
            id: 't',
            kind: OverlayKind.text,
            title: TitleSpec(text: 'Reef'),
          ),
        ],
        audioClips: [TimelineAudioClip(id: 's', path: '/m/song.m4a')],
      ),
    );
    await _tap(tester, 'timeline_tool_edit');
    for (final tool in ['duration', 'effects', 'color', 'more']) {
      await _tap(tester, 'timeline_tool_$tool');
      expect(tester.takeException(), isNull, reason: tool);
    }
    _expectNoShadows(tester);
  });

  testWidgets('on iPad the open tool becomes an inspector column', (
    tester,
  ) async {
    _phone(tester, width: 1024, height: 1366);
    await _pumpEditor(
      tester,
      const TimelineProject(id: 'w', clips: [_photo, _video]),
    );
    await _tap(tester, 'timeline_tool_edit');
    await _tap(tester, 'timeline_tool_effects');
    final panel = tester.getRect(
      find.byKey(const Key('timeline_effect_${'mono'}')),
    );
    final viewer = tester.getRect(find.byType(TimelineViewer));
    // The inspector sits beside the viewer, not under it.
    expect(panel.left, greaterThan(viewer.right));
    expect(tester.takeException(), isNull);
    _expectNoShadows(tester);
  });
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
  for (final box in tester.widgetList<Container>(find.byType(Container))) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) {
      expect(decoration.boxShadow, anyOf(isNull, isEmpty));
    }
  }
}
