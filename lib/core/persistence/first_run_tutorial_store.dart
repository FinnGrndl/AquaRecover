import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class FirstRunTutorialStore {
  Future<bool> isCompleted();

  Future<void> markCompleted();
}

typedef ApplicationSupportDirectoryProvider = Future<Directory> Function();

class FileFirstRunTutorialStore implements FirstRunTutorialStore {
  FileFirstRunTutorialStore({
    ApplicationSupportDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const markerVersion = 'workflow-v1';

  final ApplicationSupportDirectoryProvider _directoryProvider;

  @override
  Future<bool> isCompleted() async => (await _markerFile()).exists();

  @override
  Future<void> markCompleted() async {
    final marker = await _markerFile();
    await marker.parent.create(recursive: true);
    await marker.writeAsString('completed\n', flush: true);
  }

  Future<File> _markerFile() async {
    final supportDirectory = await _directoryProvider();
    return File(
      p.join(
        supportDirectory.path,
        'AquaRecover',
        'Onboarding',
        '$markerVersion.seen',
      ),
    );
  }
}
