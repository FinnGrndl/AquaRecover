import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import '../models/media_kind.dart';

/// How a "Choose from Photos" request is fulfilled on the current device.
enum PhotoImportRoute {
  /// The platform's out-of-process picker (PHPicker on iPhone, the Android
  /// Photo Picker). It needs no library permission.
  systemPicker,

  /// The macOS 13+ PHPicker sheet presented by the native runner. It needs no
  /// library permission either.
  macSystemPicker,

  /// AquaRecover's in-app PhotoKit/MediaStore browser. It requires read
  /// access to the library and is used where a large browsing surface helps.
  librarySheet,
}

/// Files copied from a native picker, plus the number of selected items that
/// could not be copied (for example iCloud originals that are not local).
class PickedPhotoFiles {
  const PickedPhotoFiles(this.paths, {this.failures = 0});

  final List<String> paths;
  final int failures;
}

class PhotoLibraryPermissionException implements Exception {
  const PhotoLibraryPermissionException(this.state);

  final PermissionState state;

  bool get canOpenSettings => state == PermissionState.denied;

  String get message => switch (state) {
    PermissionState.denied =>
      'Photos access is turned off. Allow AquaRecover to access your photo library in System Settings, then try again.',
    PermissionState.restricted =>
      'Photos access is restricted by the system or device settings.',
    PermissionState.notDetermined =>
      'Photos access has not been granted yet. Try again to show the system permission request.',
    PermissionState.authorized ||
    PermissionState.limited => 'Photos access is available.',
  };

  @override
  String toString() => message;
}

class PhotoLibraryService {
  const PhotoLibraryService({
    MethodChannel deviceChannel = const MethodChannel('aqua_recover/device'),
    MethodChannel pickerChannel = const MethodChannel(
      'aqua_recover/photo_picker',
    ),
  }) : _deviceChannel = deviceChannel,
       _pickerChannel = pickerChannel;

  static const pageSize = 120;

  final MethodChannel _deviceChannel;
  final MethodChannel _pickerChannel;

  Future<PermissionState> requestPermission() =>
      PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          iosAccessLevel: IosAccessLevel.readWrite,
        ),
      );
  Future<void> openLimitedPicker() => PhotoManager.presentLimited();
  Future<void> openSettings() => PhotoManager.openSetting();

  Future<List<AssetPathEntity>> loadAlbums() async {
    final permission = await requestPermission();
    if (!permission.hasAccess) {
      throw PhotoLibraryPermissionException(permission);
    }
    return PhotoManager.getAssetPathList(type: RequestType.common);
  }

  Future<List<AssetEntity>> loadAssets(
    AssetPathEntity album, {
    int page = 0,
    int size = pageSize,
  }) => album.getAssetListPaged(page: page, size: size);

  Future<int> assetCount(AssetPathEntity album) => album.assetCountAsync;

  Future<Uint8List?> thumbnailFor(AssetEntity asset) =>
      asset.thumbnailDataWithSize(const ThumbnailSize(240, 240), quality: 80);

  /// Resolves the original file of [asset]. iCloud originals are downloaded
  /// when they are not stored locally; [onProgress] receives 0–1 updates.
  Future<String?> localFilePathFor(
    AssetEntity asset, {
    void Function(double progress)? onProgress,
  }) async {
    final handler = PMProgressHandler();
    final subscription = onProgress == null
        ? null
        : handler.stream.listen((state) => onProgress(state.progress));
    final File? file;
    try {
      file = await asset.loadFile(isOrigin: true, progressHandler: handler);
    } finally {
      await subscription?.cancel();
    }
    if (file == null) {
      throw StateError(
        'The selected Photos item is not available locally. Open it in Photos to download the original from iCloud, then import it again.',
      );
    }
    if (!await file.exists()) {
      throw StateError(
        'The selected Photos item could not be read from local storage. Choose another item or download the original first.',
      );
    }
    return file.path;
  }

  static bool useSystemPicker({required bool isIOS, required bool isIPad}) =>
      isIOS && !isIPad;

  /// Chooses the import surface for [operatingSystem].
  ///
  /// Permission-free system pickers are preferred everywhere except iPad,
  /// where the in-app browser makes better use of the large screen. macOS
  /// falls back to the in-app browser before macOS 13, where PHPicker is
  /// unavailable.
  static PhotoImportRoute routeFor({
    required String operatingSystem,
    bool isIPad = false,
    bool macPickerAvailable = false,
  }) => switch (operatingSystem) {
    'ios' =>
      useSystemPicker(isIOS: true, isIPad: isIPad)
          ? PhotoImportRoute.systemPicker
          : PhotoImportRoute.librarySheet,
    'android' => PhotoImportRoute.systemPicker,
    'macos' =>
      macPickerAvailable
          ? PhotoImportRoute.macSystemPicker
          : PhotoImportRoute.librarySheet,
    _ => PhotoImportRoute.librarySheet,
  };

  Future<PhotoImportRoute> resolveImportRoute({
    required double fallbackShortestSide,
    String? operatingSystem,
  }) async {
    final os = operatingSystem ?? Platform.operatingSystem;
    return switch (os) {
      'ios' => routeFor(
        operatingSystem: os,
        isIPad: await _isIPad(fallbackShortestSide),
      ),
      'macos' => routeFor(
        operatingSystem: os,
        macPickerAvailable: await _isMacPickerAvailable(),
      ),
      _ => routeFor(operatingSystem: os),
    };
  }

  Future<bool> shouldUseSystemPicker({
    required bool isIOS,
    required double fallbackShortestSide,
  }) async {
    if (!isIOS) return false;
    return useSystemPicker(
      isIOS: true,
      isIPad: await _isIPad(fallbackShortestSide),
    );
  }

  Future<bool> _isIPad(double fallbackShortestSide) async {
    try {
      return await _deviceChannel.invokeMethod<bool>('isPad') ?? false;
    } on PlatformException {
      return fallbackShortestSide >= 600;
    } on MissingPluginException {
      return fallbackShortestSide >= 600;
    }
  }

  Future<bool> _isMacPickerAvailable() async {
    try {
      return await _pickerChannel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Presents the native macOS Photos picker. Returns `null` when the picker
  /// is not available so callers can fall back to the in-app browser.
  Future<PickedPhotoFiles?> pickWithMacSystemPicker() async {
    try {
      final response = await _pickerChannel.invokeMethod<Object?>(
        'pickMedia',
        const {'selectionLimit': 0},
      );
      return parsePickerResponse(response);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'UNAVAILABLE' || error.code == 'NO_WINDOW') {
        return null;
      }
      throw StateError(error.message ?? 'The Photos picker failed.');
    }
  }

  static PickedPhotoFiles parsePickerResponse(Object? response) {
    if (response is List) {
      return PickedPhotoFiles(response.whereType<String>().toList());
    }
    if (response is Map) {
      final paths = response['paths'];
      final failures = response['failures'];
      return PickedPhotoFiles(
        paths is List ? paths.whereType<String>().toList() : const [],
        failures: failures is num ? failures.toInt() : 0,
      );
    }
    return const PickedPhotoFiles([]);
  }

  Future<void> saveExport(String outputPath, MediaKind kind) async {
    final permission = await PhotoManager.requestPermissionExtend(
      // Saving only needs add-only access on Apple platforms; this avoids
      // asking for full library read access just to export a file.
      requestOption: Platform.isIOS || Platform.isMacOS
          ? const PermissionRequestOption(
              iosAccessLevel: IosAccessLevel.addOnly,
            )
          : const PermissionRequestOption(),
    );
    if (!permission.hasAccess) {
      throw StateError('Photos permission was not granted.');
    }
    if (kind.isVideo) {
      await PhotoManager.editor.saveVideo(
        File(outputPath),
        title: p.basename(outputPath),
      );
    } else {
      await PhotoManager.editor.saveImageWithPath(
        outputPath,
        title: p.basename(outputPath),
      );
    }
  }
}
