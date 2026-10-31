import 'package:flutter/cupertino.dart';

import '../../timeline_controller.dart';
import '../../timeline_theme.dart';
import 'tool_controls.dart';
import '../../../../l10n/l10n.dart';

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
    final l10n = context.l10n;
    final source = controller.extractAudioSource;
    return ToolPanelBody(
      header: ToolHeader(title: l10n.toolAudio),
      children: [
        ToolActionRow(
          key: const Key('timeline_audio_music'),
          icon: CupertinoIcons.music_note,
          label: l10n.musicFromFiles,
          detail: l10n.audioFormatsDetail,
          onPressed: onPickMusic,
        ),
        ToolActionRow(
          key: const Key('timeline_audio_extract'),
          icon: CupertinoIcons.waveform,
          label: l10n.extractAudioFromClip,
          detail: source == null
              ? l10n.putPlayheadOnVideo
              : l10n.clipGoesSilent(source.index + 1),
          onPressed: source == null ? null : () => controller.extractAudio(),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.protectedMusicNote,
          style: const TextStyle(
            color: TimelineColors.secondaryText,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
