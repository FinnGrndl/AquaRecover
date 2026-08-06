import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'features/editor/editor_page.dart';
import 'features/editor/editor_tools.dart';

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
    this.initialToolGroup,
    this.initialCompareMode,
    this.reviewExportOnStart = false,
    this.libraryOnStart = false,
  });

  final List<String> initialPaths;
  final bool openPhotosOnStart;
  final EditorToolGroup? initialToolGroup;
  final EditorCompareMode? initialCompareMode;
  final bool reviewExportOnStart;
  final bool libraryOnStart;

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
        initialToolGroup: initialToolGroup,
        initialCompareMode: initialCompareMode,
        reviewExportOnStart: reviewExportOnStart,
        libraryOnStart: libraryOnStart,
      ),
    );
  }
}
