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
