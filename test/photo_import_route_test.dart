import 'dart:typed_data';

import 'package:aqua_recover/core/photo/photo_library_service.dart';
import 'package:aqua_recover/features/editor/widgets/photo_library_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

void main() {
  group('PhotoLibraryService.routeFor', () {
    test('uses permission-free pickers on phones and Android', () {
      expect(
        PhotoLibraryService.routeFor(operatingSystem: 'ios'),
        PhotoImportRoute.systemPicker,
      );
      expect(
        PhotoLibraryService.routeFor(operatingSystem: 'android'),
        PhotoImportRoute.systemPicker,
      );
    });

    test('keeps the in-app browser on iPad', () {
      expect(
        PhotoLibraryService.routeFor(operatingSystem: 'ios', isIPad: true),
        PhotoImportRoute.librarySheet,
      );
    });

    test('uses PHPicker on macOS 13+ and falls back before that', () {
      expect(
        PhotoLibraryService.routeFor(
          operatingSystem: 'macos',
          macPickerAvailable: true,
        ),
        PhotoImportRoute.macSystemPicker,
      );
      expect(
        PhotoLibraryService.routeFor(operatingSystem: 'macos'),
        PhotoImportRoute.librarySheet,
      );
    });
  });

  group('PhotoLibraryService.parsePickerResponse', () {
    test('reads paths and failures from the macOS picker', () {
      final picked = PhotoLibraryService.parsePickerResponse({
        'paths': ['/tmp/a.heic', 7, '/tmp/b.mov'],
        'failures': 2,
      });
      expect(picked.paths, ['/tmp/a.heic', '/tmp/b.mov']);
      expect(picked.failures, 2);
    });

    test('accepts a plain list and ignores unexpected values', () {
      expect(PhotoLibraryService.parsePickerResponse(['/tmp/a.jpg']).paths, [
        '/tmp/a.jpg',
      ]);
      expect(PhotoLibraryService.parsePickerResponse(null).paths, isEmpty);
    });
  });

  testWidgets('library sheet pages through large albums', (tester) async {
    final service = _PagedPhotoLibraryService(total: 300);
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(child: PhotoLibrarySheet(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.requestedPages, [0]);

    await tester.drag(find.byType(GridView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(GridView), const Offset(0, -20000));
    await tester.pumpAndSettle();

    expect(service.requestedPages, [0, 1, 2]);
    // Each visible tile requests its thumbnail once, even across rebuilds.
    expect(service.thumbnailRequests.values.every((count) => count == 1), true);
  });
}

class _PagedPhotoLibraryService extends PhotoLibraryService {
  _PagedPhotoLibraryService({required this.total});

  final int total;
  final List<int> requestedPages = [];
  final Map<String, int> thumbnailRequests = {};
  final _album = AssetPathEntity(id: 'all', name: 'Recents');

  @override
  Future<List<AssetPathEntity>> loadAlbums() async => [_album];

  @override
  Future<int> assetCount(AssetPathEntity album) async => total;

  @override
  Future<List<AssetEntity>> loadAssets(
    AssetPathEntity album, {
    int page = 0,
    int size = PhotoLibraryService.pageSize,
  }) async {
    requestedPages.add(page);
    final start = page * size;
    if (start >= total) return const [];
    final end = (start + size).clamp(0, total);
    return [
      for (var i = start; i < end; i++)
        AssetEntity(id: 'asset-$i', typeInt: 1, width: 100, height: 100),
    ];
  }

  @override
  Future<Uint8List?> thumbnailFor(AssetEntity asset) async {
    thumbnailRequests.update(asset.id, (count) => count + 1, ifAbsent: () => 1);
    return null;
  }
}
