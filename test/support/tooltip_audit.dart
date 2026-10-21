import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Describes every on-screen icon-only control that has no tooltip.
///
/// A control is a [CupertinoButton], or a [GestureDetector] with a tap
/// handler that is not part of a button. It is icon-only when it draws an
/// [Icon] but no [Text]. It counts as covered when the nearest [RawTooltip]
/// above it wraps no other control.
List<String> iconControlsWithoutTooltip(WidgetTester tester) {
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  final missing = <String>{};
  for (final element in _controls()) {
    if (!_onScreen(element, view)) continue;
    if (!_iconOnly(element)) continue;
    if (_hasOwnTooltip(element)) continue;
    missing.add(_describe(element));
  }
  return missing.toList();
}

/// Describes every semantics node whose tooltip repeats its label, which
/// VoiceOver and TalkBack would read twice.
List<String> doubledTooltipSemantics(WidgetTester tester) {
  final doubled = <String>[];
  final root =
      tester.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode;
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.tooltip.isNotEmpty && data.label.contains(data.tooltip)) {
      doubled.add('"${data.label}" + tooltip "${data.tooltip}"');
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  return doubled;
}

Iterable<Element> _controls() sync* {
  yield* find.byType(CupertinoButton).evaluate();
  for (final element in find.byType(GestureDetector).evaluate()) {
    final detector = element.widget as GestureDetector;
    if (detector.onTap == null) continue;
    if (_hasAncestor<CupertinoButton>(element)) continue;
    if (_containsControl(element)) continue;
    yield element;
  }
}

bool _onScreen(Element element, Size view) {
  final box = element.renderObject;
  if (box is! RenderBox || !box.attached || !box.hasSize) return false;
  if (box.size.isEmpty) return false;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  return rect.overlaps(Offset.zero & view);
}

bool _iconOnly(Element element) {
  var icon = false;
  var text = false;
  void visit(Element child) {
    if (text) return;
    final widget = child.widget;
    if (widget is Icon) {
      icon = true;
      return;
    }
    if (widget is Text) {
      final plain = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      if (plain.trim().isNotEmpty) text = true;
      return;
    }
    if (widget is EditableText || widget is Image || widget is RawImage) {
      text = true;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return icon && !text;
}

bool _hasOwnTooltip(Element element) {
  Element? tooltip;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is RawTooltip) {
      tooltip = ancestor;
      return false;
    }
    return true;
  });
  final found = tooltip;
  if (found == null) return false;
  var controls = 0;
  void visit(Element child) {
    final widget = child.widget;
    if (widget is CupertinoButton ||
        (widget is GestureDetector && widget.onTap != null)) {
      if (widget is CupertinoButton || !_hasAncestor<CupertinoButton>(child)) {
        controls++;
      }
    }
    child.visitChildren(visit);
  }

  found.visitChildren(visit);
  return controls <= 1;
}

bool _hasAncestor<T extends Widget>(Element element) {
  var found = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget is T) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

bool _containsControl(Element element) {
  var found = false;
  void visit(Element child) {
    if (found) return;
    if (child.widget is CupertinoButton) {
      found = true;
      return;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  return found;
}

String _describe(Element element) {
  final widget = element.widget;
  String? key;
  element.visitAncestorElements((ancestor) {
    final k = ancestor.widget.key;
    if (k is ValueKey || k is ObjectKey) {
      key = '$k';
      return false;
    }
    return ancestor.widget is! Navigator;
  });
  String? icon;
  String? label;
  void visit(Element child) {
    final w = child.widget;
    if (w is Icon && icon == null) {
      icon = w.semanticLabel ?? 'U+${w.icon?.codePoint.toRadixString(16)}';
    }
    if (w is Semantics && label == null && w.properties.label != null) {
      label = w.properties.label;
    }
    child.visitChildren(visit);
  }

  element.visitChildren(visit);
  var depth = 0;
  element.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (label == null && w is Semantics && w.properties.label != null) {
      label = w.properties.label;
    }
    return label == null && ++depth < 6;
  });
  final box = element.renderObject as RenderBox;
  final at = box.localToGlobal(Offset.zero);
  return '${widget.runtimeType}${widget.key ?? ''} near ${key ?? '-'} '
      'icon $icon label ${label ?? '-'} '
      '@${at.dx.round()},${at.dy.round()}';
}
