import 'package:aqua_recover/core/models/export_options.dart';
import 'package:aqua_recover/core/models/video_edit_settings.dart';
import 'package:aqua_recover/core/processing/ffmpeg_video_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the duration from the ffmpeg banner', () {
    expect(
      FfmpegVideoBackend.parseDuration(
        '  Duration: 00:01:02.50, start: 0.000000, bitrate: 1200 kb/s',
      ),
      62.5,
    );
    expect(FfmpegVideoBackend.parseDuration('no banner'), isNull);
  });

  test('export arguments apply the baked cube and keep paths out of the '
      'filter graph', () {
    final args = FfmpegVideoBackend.exportArguments(
      inputPath: r'C:\Dives\clip:1.mp4',
      outputPath: r'C:\Out\clip.mp4',
      trim: const VideoEditSettings(
        enabled: true,
        startSeconds: 2,
        endSeconds: 5,
      ),
      exportOptions: const ExportOptions(keepAudio: false),
    );
    expect(
      args,
      containsAllInOrder(['-ss', '2', '-i', r'C:\Dives\clip:1.mp4']),
    );
    expect(
      args[args.indexOf('-vf') + 1],
      'lut3d=file=restore.cube:interp=tetrahedral',
    );
    expect(args, contains('-an'));
    expect(args, containsAllInOrder(['-t', '3', '-movflags']));
    expect(args.last, r'C:\Out\clip.mp4');
  });

  test('redacts full paths from logs', () {
    final log = FfmpegVideoBackend.redactLog(
      '/Users/me/in.mp4: error\nwriting /tmp/out.mp4',
      '/Users/me/in.mp4',
      '/tmp/out.mp4',
    );
    expect(log, 'in.mp4: error writing out.mp4');
  });
}
