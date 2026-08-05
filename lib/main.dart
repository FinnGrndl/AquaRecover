import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'features/editor/editor_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('LICENSE');
    yield LicenseEntryWithLineBreaks(const ['AquaRecover'], license);
  });
  runApp(const AquaRecoverApp());
}

class AquaRecoverApp extends StatelessWidget {
  const AquaRecoverApp({
    super.key,
    this.initialPaths = const [],
    this.openPhotosOnStart = false,
  });

  final List<String> initialPaths;
  final bool openPhotosOnStart;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      debugShowCheckedModeBanner: false,
      title: 'AquaRecover',
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.activeBlue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
        barBackgroundColor: CupertinoColors.systemBackground,
      ),
      home: EditorPage(
        initialPaths: initialPaths,
        openPhotosOnStart: openPhotosOnStart,
      ),
    );
  }
}
