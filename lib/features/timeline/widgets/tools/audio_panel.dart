import 'package:flutter/cupertino.dart';

import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';

/// Ways to add sound: music from Files, or the sound of the video clip
/// under the playhead on its own lane.
class AudioAddPanel extends StatelessWidget {
  const AudioAddPanel({
    super.key,
    required this.controller,
    required this.onPickMusic,
  });

  final TimelineController controller;
  final VoidCallback onPickMusic;

  @override
  Widget build(BuildContext context) {
    final source = controller.extractAudioSource;
    return ToolPanelBody(
      header: const ToolHeader(title: 'Audio'),
      children: [
        ToolActionRow(
          key: const Key('timeline_audio_music'),
          icon: CupertinoIcons.music_note,
          label: 'Music from Files',
          detail: 'MP3, M4A, AAC, WAV, or AIFF',
          onPressed: onPickMusic,
        ),
        ToolActionRow(
          key: const Key('timeline_audio_extract'),
          icon: CupertinoIcons.waveform,
          label: 'Extract Audio from Clip',
          detail: source == null
              ? 'Put the playhead on a video clip'
              : 'Clip ${source.index + 1} goes silent; its sound gets a lane',
          onPressed: source == null ? null : () => controller.extractAudio(),
        ),
        const SizedBox(height: 8),
        const Text(
          'Music from Apple Music and other protected tracks can’t be used.',
          style: TextStyle(color: TimelineColors.secondaryText, fontSize: 12),
        ),
      ],
    );
  }
}
