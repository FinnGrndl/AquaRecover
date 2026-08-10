import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/media_kind.dart';
import '../models/media_metadata.dart';
import 'media_classifier.dart';

class MediaInspectionService {
  const MediaInspectionService();

  static const maxImageProbeBytes = 40 * 1024 * 1024;

  Future<MediaMetadata> inspect(String path) async {
    if (path.trim().isEmpty) {
      throw const FormatException('No media file was selected.');
    }
    final kind = MediaClassifier.classify(path);
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException(
        'Selected media file could not be found.',
        path,
      );
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw FileSystemException('Selected path is not a readable file.', path);
    }

    final dimensions = await _probeImageDimensions(file, kind);
    return MediaMetadata(
      path: path,
      fileName: p.basename(path),
      kind: kind,
      fileSizeBytes: stat.size,
      width: dimensions?.$1,
      height: dimensions?.$2,
    );
  }

  Future<(int, int)?> _probeImageDimensions(File file, MediaKind kind) async {
    if (kind != MediaKind.photo) return null;
    if (!MediaClassifier.dartDecodedImageExtensions.contains(
      MediaClassifier.extensionOf(file.path),
    )) {
      return null;
    }
    final length = await file.length();
    if (length > maxImageProbeBytes) return null;
    final bytes = await file.readAsBytes();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null) {
      throw const FormatException('The selected image could not be decoded.');
    }
    var width = info.width;
    var height = info.height;
    final extension = MediaClassifier.extensionOf(file.path);
    if (extension == 'jpg' || extension == 'jpeg') {
      final orientation = img.decodeJpgExif(bytes)?.imageIfd.orientation;
      if (orientation != null && orientation >= 5 && orientation <= 8) {
        (width, height) = (height, width);
      }
    }
    return (width, height);
  }
}
