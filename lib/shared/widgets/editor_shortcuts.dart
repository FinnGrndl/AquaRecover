import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether this platform uses ⌘ rather than Ctrl for its shortcuts.
bool get usesCommandKey => switch (defaultTargetPlatform) {
  TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

/// Whether help tags should name keyboard shortcuts: on computers, where a
/// keyboard is the norm.
bool get showsShortcutHints => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// [label] with its shortcut appended on computers, such as "Undo (⌘Z)" on
/// a Mac or "Undo (Ctrl+Z)" on Windows.
String withShortcut(String label, String key, {bool shift = false}) {
  if (!showsShortcutHints) return label;
  final keys = usesCommandKey
      ? '${shift ? '⇧' : ''}⌘$key'
      : 'Ctrl+${shift ? 'Shift+' : ''}$key';
  return '$label ($keys)';
}

/// The editors' keyboard shortcuts: ⌘Z / Ctrl+Z undo, ⇧⌘Z / Ctrl+Shift+Z
/// redo, Space plays or pauses, and Escape closes the open panel.
///
/// None of them fire while a text field has focus, so typing a space or
/// undoing typing keeps working there. Its own focus scope keeps them
/// working after a text field gives up focus.
class EditorShortcuts extends StatelessWidget {
  const EditorShortcuts({
    super.key,
    required this.child,
    this.canUndo,
    this.onUndo,
    this.canRedo,
    this.onRedo,
    this.onPlayPause,
    this.onEscape,
    this.canEscape,
  });

  final Widget child;
  final bool Function()? canUndo;
  final VoidCallback? onUndo;
  final bool Function()? canRedo;
  final VoidCallback? onRedo;

  /// Space. Null leaves Space alone.
  final VoidCallback? onPlayPause;

  /// Escape, while [canEscape] says there is something to close. Otherwise
  /// the key goes on, for example to close a sheet.
  final VoidCallback? onEscape;
  final bool Function()? canEscape;

  @override
  Widget build(BuildContext context) {
    final apple = usesCommandKey;
    return Shortcuts(
      shortcuts: {
        if (onUndo != null)
          SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: apple,
            control: !apple,
          ): const EditorUndoIntent(),
        if (onRedo != null) ...{
          SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: apple,
            control: !apple,
            shift: true,
          ): const EditorRedoIntent(),
          if (!apple)
            const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                const EditorRedoIntent(),
        },
        if (onPlayPause != null)
          const SingleActivator(LogicalKeyboardKey.space):
              const EditorPlayPauseIntent(),
        if (onEscape != null)
          const SingleActivator(LogicalKeyboardKey.escape):
              const EditorEscapeIntent(),
      },
      child: Actions(
        actions: {
          if (onUndo != null)
            EditorUndoIntent: _EditorAction<EditorUndoIntent>(
              canUndo ?? () => true,
              onUndo!,
            ),
          if (onRedo != null)
            EditorRedoIntent: _EditorAction<EditorRedoIntent>(
              canRedo ?? () => true,
              onRedo!,
            ),
          if (onPlayPause != null)
            EditorPlayPauseIntent: _EditorAction<EditorPlayPauseIntent>(
              () => true,
              onPlayPause!,
            ),
          if (onEscape != null)
            EditorEscapeIntent: _EditorAction<EditorEscapeIntent>(
              canEscape ?? () => true,
              onEscape!,
            ),
        },
        child: FocusScope(autofocus: true, child: child),
      ),
    );
  }
}

class EditorUndoIntent extends Intent {
  const EditorUndoIntent();
}

class EditorRedoIntent extends Intent {
  const EditorRedoIntent();
}

class EditorPlayPauseIntent extends Intent {
  const EditorPlayPauseIntent();
}

class EditorEscapeIntent extends Intent {
  const EditorEscapeIntent();
}

bool _editingText() {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused?.findAncestorStateOfType<EditableTextState>() != null;
}

class _EditorAction<T extends Intent> extends Action<T> {
  _EditorAction(this._canRun, this._run);

  final bool Function() _canRun;
  final VoidCallback _run;

  @override
  bool isEnabled(T intent) => !_editingText() && _canRun();

  @override
  Object? invoke(T intent) {
    _run();
    return null;
  }
}
