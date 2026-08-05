import 'package:path/path.dart' as p;

import '../models/media_kind.dart';

class MediaClassifier {
  static const dartDecodedImageExtensions = <String>{
    'jpg',
    'jpeg',
    'png',
    'webp',
    'tif',
    'tiff',
  };

  static const platformDecodedImageExtensions = <String>{'heic', 'heif'};

  static const imageExtensions = <String>{
    ...dartDecodedImageExtensions,
    ...platformDecodedImageExtensions,
  };

  static const rawPhotoExtensions = <String>{
    'dng',
    'cr2',
    'cr3',
    'nef',
    'nrw',
    'arw',
    'srf',
    'sr2',
    'raf',
    'rw2',
    'orf',
    'pef',
    'rwl',
    '3fr',
    'fff',
    'iiq',
  };

  static const videoExtensions = <String>{
    'mp4',
    'mov',
    'm4v',
    'mkv',
    'avi',
    'webm',
    'mxf',
    'mts',
    'm2ts',
  };

  static const rawVideoExtensions = <String>{'raw', 'yuv', 'rgb', 'rgba'};

  static List<String> get allExtensions => [
    ...imageExtensions,
    ...rawPhotoExtensions,
    ...videoExtensions,
    ...rawVideoExtensions,
  ]..sort();

  static MediaKind classify(String path) {
    final ext = extensionOf(path);
    if (rawPhotoExtensions.contains(ext)) return MediaKind.rawPhoto;
    if (rawVideoExtensions.contains(ext)) return MediaKind.rawVideo;
    if (imageExtensions.contains(ext)) return MediaKind.photo;
    if (videoExtensions.contains(ext)) return MediaKind.video;
    throw UnsupportedError('Unsupported media extension: .$ext');
  }

  static String extensionOf(String path) {
    return p.extension(path).replaceFirst('.', '').toLowerCase();
  }

  static bool requiresPlatformImageDecode(String path) {
    return platformDecodedImageExtensions.contains(extensionOf(path));
  }
}
