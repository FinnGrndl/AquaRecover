import 'package:aqua_recover/main.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:aqua_recover/features/library/export_library_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  const encodedNames = String.fromEnvironment('AQUA_TEST_MEDIA_NAMES');
  const openPhotos = bool.fromEnvironment('AQUA_OPEN_PHOTOS_PICKER');
  const initialGroupName = String.fromEnvironment('AQUA_INITIAL_TOOL_GROUP');
  const initialCompareName = String.fromEnvironment(
    'AQUA_INITIAL_COMPARE_MODE',
  );
  const reviewExport = bool.fromEnvironment('AQUA_REVIEW_EXPORT_ON_START');
  const openLocalExports = bool.fromEnvironment(
    'AQUA_OPEN_LOCAL_EXPORTS_ON_START',
  );
  WidgetsFlutterBinding.ensureInitialized();
  final names = encodedNames.isEmpty
      ? const <String>[]
      : encodedNames.split('|');
  final documents = await getApplicationDocumentsDirectory();
  final paths = [
    for (final name in names) p.join(documents.path, 'TestMedia', name),
  ];
  EditorToolGroup? initialGroup;
  for (final group in EditorToolGroup.values) {
    if (group.name == initialGroupName) initialGroup = group;
  }
  EditorCompareMode? initialCompareMode;
  for (final mode in EditorCompareMode.values) {
    if (mode.name == initialCompareName) initialCompareMode = mode;
  }
  if (openLocalExports) {
    runApp(
      const CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(brightness: Brightness.dark),
        home: ExportLibraryPage(),
      ),
    );
    return;
  }
  runApp(
    AquaRecoverApp(
      initialPaths: paths,
      openPhotosOnStart: openPhotos,
      initialToolGroup: initialGroup,
      initialCompareMode: initialCompareMode,
      reviewExportOnStart: reviewExport,
    ),
  );
}
