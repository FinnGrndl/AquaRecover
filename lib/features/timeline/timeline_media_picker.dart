import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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

/// Lets the user pick a song or sound for the movie's audio lanes.
Future<List<String>> pickTimelineAudio() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff'],
  );
  return files.map((f) => f.path).whereType<String>().toList();
}

/// What the editor needs to know about a picture-in-picture item before it
/// goes on the canvas.
typedef OverlayMediaInfo = ({double aspect, double? duration});

/// Reads a photo's or clip's shape (width / height) and a clip's length.
/// Unreadable files fall back to 16:9 so the overlay still appears.
Future<OverlayMediaInfo> probeOverlayMedia(String path) async {
  final MediaKind kind;
  try {
    kind = MediaClassifier.classify(path);
  } on UnsupportedError {
    return (aspect: 16 / 9, duration: null);
  }
  if (kind == MediaKind.video) {
    final player = VideoPlayerController.file(File(path));
    try {
      await player.initialize().timeout(const Duration(seconds: 8));
      final size = player.value.size;
      final seconds = player.value.duration.inMicroseconds / 1e6;
      return (
        aspect: size.width > 0 && size.height > 0
            ? size.width / size.height
            : 16 / 9,
        duration: seconds > 0 ? seconds : null,
      );
    } on Object {
      return (aspect: 16 / 9, duration: null);
    } finally {
      unawaited(player.dispose());
    }
  }
  try {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final aspect = descriptor.height > 0
        ? descriptor.width / descriptor.height
        : 16 / 9;
    descriptor.dispose();
    buffer.dispose();
    return (aspect: aspect, duration: null);
  } on Object {
    return (aspect: 16 / 9, duration: null);
  }
}

/// Reads a sound file's length with the platform player.
Future<double?> probeAudioDuration(String path) async {
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
