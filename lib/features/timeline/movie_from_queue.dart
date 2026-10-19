import '../../core/models/media_edit_state.dart';
import '../../core/models/media_job.dart';
import '../../core/models/media_kind.dart';
import '../../core/timeline/timeline_project.dart';

/// Turns the editor queue into a movie: one clip per item in queue order,
/// each keeping the grade and look it was given in the editor. RAW video
/// descriptors are skipped because the timeline renderers cannot decode them.
TimelineProject movieFromQueue(
  List<MediaJob> jobs, {
  required Map<String, MediaEditState> editStates,
  required Map<String, Duration> videoDurations,
  required String id,
  String name = 'Dive movie',
}) {
  final clips = <TimelineClip>[];
  for (final job in jobs) {
    if (job.kind == MediaKind.rawVideo) continue;
    final state = editStates[job.id] ?? const MediaEditState();
    final duration = videoDurations[job.id];
    final seconds = duration == null || duration <= Duration.zero
        ? null
        : duration.inMicroseconds / 1e6;
    clips.add(
      TimelineClip(
        id: 'q${clips.length}-${job.id}',
        path: job.inputPath,
        kind: job.kind.isVideo
            ? TimelineClipKind.video
            : TimelineClipKind.image,
        sourceDuration: seconds,
        sourceEnd: job.kind.isVideo ? seconds : null,
        grade: state.settings,
        look: state.lutProfile,
        transition: clips.isEmpty
            ? ClipTransition.cut
            : ClipTransition.crossfade,
      ),
    );
  }
  return TimelineProject(id: id, name: name, clips: clips);
}
