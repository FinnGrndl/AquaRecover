import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/media/media_classifier.dart';
import '../../core/models/media_kind.dart';

/// Lets the user pick photos and clips for a movie. On phones this is the
/// system photo picker, which needs no library permission; on desktops it is
/// a file dialog limited to supported formats.
Future<List<String>> pickTimelineMedia() async {
  final mobile = Platform.isIOS || Platform.isAndroid;
  final files = await FilePicker.pickFiles(
    type: mobile ? FileType.media : FileType.custom,
    allowedExtensions: mobile
        ? null
        : [
            ...MediaClassifier.imageExtensions,
            ...MediaClassifier.rawPhotoExtensions,
            ...MediaClassifier.videoExtensions,
          ],
  );
  return files.map((f) => f.path).whereType<String>().toList();
}

/// Reads a video's length with the platform player, or returns null for
/// photos and unreadable files.
Future<double?> probeVideoDuration(String path) async {
  final MediaKind kind;
  try {
    kind = MediaClassifier.classify(path);
  } on UnsupportedError {
    return null;
  }
  if (kind != MediaKind.video) return null;
  final player = VideoPlayerController.file(File(path));
  try {
    await player.initialize().timeout(const Duration(seconds: 8));
    final seconds = player.value.duration.inMicroseconds / 1e6;
    return seconds > 0 ? seconds : null;
  } on Object {
    return null;
  } finally {
    unawaited(player.dispose());
  }
}
