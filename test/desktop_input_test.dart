import 'dart:io';

import 'package:aqua_recover/core/media/media_inspection_service.dart';
import 'package:aqua_recover/core/models/media_kind.dart';
import 'package:aqua_recover/core/models/media_metadata.dart';
import 'package:aqua_recover/features/editor/editor_page.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/editor/widgets/precision_wheel.dart';
import 'package:aqua_recover/features/timeline/widgets/timeline_toolbar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Windows PC, or a Mac with a mouse instead of a trackpad, has no touch
/// drag, so horizontal strips must accept a mouse drag.
void main() {
  const desktops = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.macOS,
  });

  testWidgets('a mouse drag moves the precision wheel', variant: desktops, (
    tester,
  ) async {
    var value = 0.0;
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => PrecisionWheel(
                  value: value,
                  min: -1,
                  max: 1,
                  onChanged: (v) => setState(() => value = v),
                  valueFormatter: (v) => v.toStringAsFixed(2),
                  hapticFeedback: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byKey(const Key('precision_wheel')));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(-12, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(value, greaterThan(0));
  });

  testWidgets('a mouse drag scrolls the movie toolbar', variant: desktops, (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: TimelineToolbar(
              items: [
                for (var i = 0; i < 10; i++)
                  TimelineToolItem(
                    id: 't$i',
                    icon: CupertinoIcons.star,
                    label: 'Tool $i',
                    onPressed: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final first = find.byKey(const Key('timeline_tool_t0'));
    final before = tester.getTopLeft(first).dx;
    await tester.dragFrom(
      tester.getCenter(find.byKey(const Key('timeline_tool_t3'))),
      const Offset(-200, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first).dx, lessThan(before - 100));
  });

  testWidgets(
    'the editor panels scroll without scrollbar errors',
    variant: const TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
    (tester) async {
      // iPad landscape and desktop windows show the tool panel and the side
      // pane together.
      tester.view.physicalSize = const Size(1180, 820) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const CupertinoApp(
          home: EditorPage(
            initialPaths: ['docs/assets/demo-underwater-source.jpg'],
            initialToolGroup: EditorToolGroup.light,
            inspectionService: _Inspect(),
          ),
        ),
      );
      for (var i = 0; i < 7; i++) {
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('open_neutral_picker')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    },
  );
}

class _Inspect extends MediaInspectionService {
  const _Inspect();

  @override
  Future<MediaMetadata> inspect(String path) async => MediaMetadata(
    path: path,
    fileName: File(path).uri.pathSegments.last,
    kind: MediaKind.photo,
    fileSizeBytes: 2048,
    width: 1600,
    height: 1200,
  );
}
