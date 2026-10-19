/// Undo and redo stacks for one queue item's edits.
///
/// Each entry is the state before a change. Recording a new change clears
/// the redo stack, as in Photos.
class EditHistory<T> {
  EditHistory({this.limit = 100});

  /// The oldest steps are dropped beyond this many.
  final int limit;

  final List<T> _undo = [];
  final List<T> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Records [before], the state a new change starts from.
  void record(T before) {
    _undo.add(before);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Notes that the current step changed again without starting a new one,
  /// which still makes the redo stack stale.
  void amend() => _redo.clear();

  /// Steps back from [current]; returns the state to restore, or null.
  T? undo(T current) {
    if (!canUndo) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  /// Steps forward from [current]; returns the state to restore, or null.
  T? redo(T current) {
    if (!canRedo) return null;
    _undo.add(current);
    return _redo.removeLast();
  }
}
