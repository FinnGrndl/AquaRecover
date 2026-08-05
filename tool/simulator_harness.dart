import 'package:aqua_recover/main.dart';
import 'package:aqua_recover/features/editor/editor_tools.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  const encodedNames = String.fromEnvironment('AQUA_TEST_MEDIA_NAMES');
  const openPhotos = bool.fromEnvironment('AQUA_OPEN_PHOTOS_PICKER');
  const initialGroupName = String.fromEnvironment('AQUA_INITIAL_TOOL_GROUP');
  const initialCompareName = String.fromEnvironment(
    'AQUA_INITIAL_COMPARE_MODE',
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
  runApp(
    AquaRecoverApp(
      initialPaths: paths,
      openPhotosOnStart: openPhotos,
      initialToolGroup: initialGroup,
      initialCompareMode: initialCompareMode,
    ),
  );
}
