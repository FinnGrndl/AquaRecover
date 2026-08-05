import 'package:aqua_recover/main.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  const encodedNames = String.fromEnvironment('AQUA_TEST_MEDIA_NAMES');
  const openPhotos = bool.fromEnvironment('AQUA_OPEN_PHOTOS_PICKER');
  WidgetsFlutterBinding.ensureInitialized();
  final names = encodedNames.isEmpty
      ? const <String>[]
      : encodedNames.split('|');
  final documents = await getApplicationDocumentsDirectory();
  final paths = [
    for (final name in names) p.join(documents.path, 'TestMedia', name),
  ];
  runApp(AquaRecoverApp(initialPaths: paths, openPhotosOnStart: openPhotos));
}
