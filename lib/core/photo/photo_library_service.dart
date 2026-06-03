import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../models/media_kind.dart';

class PhotoLibraryService {
  const PhotoLibraryService();

  Future<PermissionState> requestPermission() => PhotoManager.requestPermissionExtend();
  Future<void> openLimitedPicker() => PhotoManager.presentLimited();

  Future<List<AssetPathEntity>> loadAlbums() async {
    final permission = await requestPermission();
    if (!permission.hasAccess) throw StateError('Photos permission was not granted.');
    return PhotoManager.getAssetPathList(type: RequestType.common);
  }

  Future<List<AssetEntity>> loadAssets(AssetPathEntity album, {int page = 0, int size = 80}) => album.getAssetListPaged(page: page, size: size);

  Future<String?> localFilePathFor(AssetEntity asset) async {
    final file = await asset.originFile;
    if (file == null || !await file.exists()) return null;
    return file.path;
  }

  Future<void> saveExport(String outputPath, MediaKind kind) async {
    final permission = await requestPermission();
    if (!permission.hasAccess) throw StateError('Photos permission was not granted.');
    if (kind.isVideo) {
      await PhotoManager.editor.saveVideo(File(outputPath), title: p.basename(outputPath));
    } else {
      await PhotoManager.editor.saveImageWithPath(outputPath, title: p.basename(outputPath));
    }
  }
}
