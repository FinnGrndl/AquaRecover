import '../models/media_edit_state.dart';
import '../models/media_job.dart';

enum EditorWorkflowStep { import, edit, export }

extension EditorWorkflowStepX on EditorWorkflowStep {
  String get label => switch (this) {
    EditorWorkflowStep.import => 'Import',
    EditorWorkflowStep.edit => 'Edit',
    EditorWorkflowStep.export => 'Export',
  };

  String get shortLabel => switch (this) {
    EditorWorkflowStep.import => '1',
    EditorWorkflowStep.edit => '2',
    EditorWorkflowStep.export => '3',
  };
}

class MediaQueueSelection {
  const MediaQueueSelection({required this.jobs, required this.selectedIndex});

  final List<MediaJob> jobs;
  final int selectedIndex;
}

MediaQueueSelection removeMediaJobFromQueue({
  required List<MediaJob> jobs,
  required int selectedIndex,
  required String id,
}) {
  final removedIndex = jobs.indexWhere((job) => job.id == id);
  if (removedIndex < 0) {
    return MediaQueueSelection(
      jobs: jobs,
      selectedIndex: jobs.isEmpty
          ? 0
          : selectedIndex.clamp(0, jobs.length - 1).toInt(),
    );
  }
  final remaining = [...jobs]..removeAt(removedIndex);
  if (remaining.isEmpty) {
    return const MediaQueueSelection(jobs: [], selectedIndex: 0);
  }
  final nextIndex = removedIndex < selectedIndex
      ? selectedIndex - 1
      : selectedIndex.clamp(0, remaining.length - 1).toInt();
  return MediaQueueSelection(jobs: remaining, selectedIndex: nextIndex);
}

Map<String, MediaEditState> copyMediaEditStateToTargets({
  required Map<String, MediaEditState> states,
  required String sourceId,
  required Iterable<String> targetIds,
}) {
  final source = states[sourceId];
  final result = Map<String, MediaEditState>.of(states);
  if (source == null) return result;
  for (final targetId in targetIds) {
    if (targetId != sourceId) result[targetId] = source;
  }
  return result;
}

class EditorWorkflowState {
  const EditorWorkflowState({
    required this.step,
    required this.hasSelection,
    this.busy = false,
  });

  final EditorWorkflowStep step;
  final bool hasSelection;
  final bool busy;

  bool canEnter(EditorWorkflowStep target) {
    if (busy && target != step) return false;
    return switch (target) {
      EditorWorkflowStep.import => true,
      EditorWorkflowStep.edit => hasSelection,
      EditorWorkflowStep.export => hasSelection,
    };
  }

  bool get canGoBack => switch (step) {
    EditorWorkflowStep.import => false,
    EditorWorkflowStep.edit => true,
    EditorWorkflowStep.export => true,
  };

  bool get canGoForward => switch (step) {
    EditorWorkflowStep.import => hasSelection && !busy,
    EditorWorkflowStep.edit => hasSelection && !busy,
    EditorWorkflowStep.export => false,
  };

  EditorWorkflowStep get previous => switch (step) {
    EditorWorkflowStep.import => EditorWorkflowStep.import,
    EditorWorkflowStep.edit => EditorWorkflowStep.import,
    EditorWorkflowStep.export => EditorWorkflowStep.edit,
  };

  EditorWorkflowStep get next => switch (step) {
    EditorWorkflowStep.import => EditorWorkflowStep.edit,
    EditorWorkflowStep.edit => EditorWorkflowStep.export,
    EditorWorkflowStep.export => EditorWorkflowStep.export,
  };
}
