import 'package:flutter/cupertino.dart';

import 'features/editor/editor_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AquaRecoverApp());
}

class AquaRecoverApp extends StatelessWidget {
  const AquaRecoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      title: 'AquaRecover',
      theme: CupertinoThemeData(
        primaryColor: CupertinoColors.activeBlue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
        barBackgroundColor: CupertinoColors.systemBackground,
      ),
      home: EditorPage(),
    );
  }
}
