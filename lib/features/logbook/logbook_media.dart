import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/logbook/dive_log.dart';
import '../../core/logbook/media_matching.dart';
import '../../core/media/capture_metadata.dart';
import '../../core/media/media_classifier.dart';
import '../../core/models/media_kind.dart';
import '../../core/photo/photo_library_service.dart';
import '../timeline/timeline_media_picker.dart';

/// Finds, previews and resolves the photos and videos a dive links to.
/// Widget tests replace it with a fake.
class LogbookMedia {
  const LogbookMedia();

  /// Photos and videos the person picks as files, with their capture time
  /// from EXIF or the video header where the file has one, else the file's
  /// modification time.
  Future<List<MediaCandidate>> pickFiles() async {
    final paths = await pickTimelineMedia();
    final candidates = <MediaCandidate>[];
    for (final path in paths) {
      final MediaKind kind;
      try {
        kind = MediaClassifier.classify(path);
      } on UnsupportedError {
        continue;
      }
      candidates.add(
        MediaCandidate(
          path: path,
          isVideo: kind.isVideo,
          capturedAt: await _captureTime(path),
        ),
      );
    }
    return candidates;
  }

  /// Library photos and videos created between [from] and [to]. Asks for
  /// photo-library access; returns an empty list without it.
  Future<List<MediaCandidate>> libraryCandidates(
    DateTime from,
    DateTime to,
  ) async {
    final permission = await const PhotoLibraryService().requestPermission();
    if (!permission.hasAccess) return const [];
    final filter = FilterOptionGroup(
      createTimeCond: DateTimeCond(min: from, max: to),
    );
    final candidates = <MediaCandidate>[];
    for (var page = 0; ; page++) {
      final assets = await PhotoManager.getAssetListPaged(
        page: page,
        pageCount: 200,
        filterOption: filter,
      );
      for (final asset in assets) {
        candidates.add(
          MediaCandidate(
            assetId: asset.id,
            isVideo: asset.type == AssetType.video,
            capturedAt: asset.createDateTime,
          ),
        );
      }
      if (assets.length < 200) break;
    }
    return candidates;
  }

  Future<Uint8List?> thumbnail(DiveMedia media) async {
    try {
      if (media.assetId != null) {
        final asset = await AssetEntity.fromId(media.assetId!);
        return asset?.thumbnailDataWithSize(const ThumbnailSize(240, 240));
      }
      if (media.isVideo) return null;
      final file = File(media.path!);
      return await file.exists() ? await file.readAsBytes() : null;
    } on Object {
      return null;
    }
  }

  /// A local file for [media], downloading an iCloud original if needed.
  Future<String?> filePath(DiveMedia media) async {
    if (media.path != null) {
      return await File(media.path!).exists() ? media.path : null;
    }
    try {
      final asset = await AssetEntity.fromId(media.assetId!);
      if (asset == null) return null;
      return await const PhotoLibraryService().localFilePathFor(asset);
    } on Object {
      return null;
    }
  }

  /// Saves [bytes] where the person chooses. Returns false when cancelled.
  Future<bool> saveFile(
    String fileName,
    Uint8List bytes, {
    String mimeType = 'application/octet-stream',
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri != null;
  }

  /// Lets the person choose a UDDF file and returns its text.
  Future<String?> pickLogText() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['uddf', 'xml'],
    );
    if (files.isEmpty) return null;
    final path = files.first.path;
    if (path == null) return null;
    final bytes = await File(path).readAsBytes();
    return String.fromCharCodes(bytes).contains('�')
        ? null
        : _decodeUtf8(bytes);
  }
}

String _decodeUtf8(Uint8List bytes) =>
    const Utf8Codec(allowMalformed: true).decode(bytes);

Future<DateTime> _captureTime(String path) async =>
    await CaptureMetadata.captureDateForFile(path) ??
    await File(path).lastModified();
