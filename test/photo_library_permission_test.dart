import 'package:aqua_recover/core/photo/photo_library_service.dart';
import 'package:aqua_recover/features/editor/widgets/photo_library_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  testWidgets('denied Photos access links to System Settings', (tester) async {
    final service = _DeniedPhotoLibraryService();

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(child: PhotoLibrarySheet(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Photos access is turned off'), findsOneWidget);
    expect(find.text('Open System Settings'), findsOneWidget);
    expect(find.text('Manage limited access'), findsNothing);

    await tester.tap(find.text('Open System Settings'));
    await tester.pump();

    expect(service.openSettingsCount, 1);
  });
}

class _DeniedPhotoLibraryService extends PhotoLibraryService {
  var openSettingsCount = 0;

  @override
  Future<List<AssetPathEntity>> loadAlbums() async {
    throw const PhotoLibraryPermissionException(PermissionState.denied);
  }

  @override
  Future<void> openSettings() async {
    openSettingsCount++;
  }
}
