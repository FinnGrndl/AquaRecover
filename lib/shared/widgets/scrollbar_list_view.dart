import 'package:flutter/cupertino.dart';

/// A [ListView] inside a [CupertinoScrollbar], sharing a controller of
/// their own.
///
/// A scrollbar without a controller follows the route's
/// PrimaryScrollController. That breaks as soon as two such lists share a
/// screen, like the editor's tool panel and side pane on iPad, and on macOS
/// and Windows, where lists do not attach to it at all.
class ScrollbarListView extends StatefulWidget {
  const ScrollbarListView({super.key, this.padding, required this.children});

  final EdgeInsetsGeometry? padding;
  final List<Widget> children;

  @override
  State<ScrollbarListView> createState() => _ScrollbarListViewState();
}

class _ScrollbarListViewState extends State<ScrollbarListView> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoScrollbar(
    controller: _controller,
    child: ListView(
      controller: _controller,
      padding: widget.padding,
      children: widget.children,
    ),
  );
}
