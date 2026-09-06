import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../core/persistence/first_run_tutorial_store.dart';
import 'first_run_tutorial.dart';

typedef FirstRunTutorialHostBuilder =
    Widget Function(BuildContext context, VoidCallback showTutorial);

class FirstRunTutorialGate extends StatefulWidget {
  const FirstRunTutorialGate({
    super.key,
    required this.store,
    required this.builder,
    this.showOnLaunch = true,
  });

  final FirstRunTutorialStore store;
  final FirstRunTutorialHostBuilder builder;
  final bool showOnLaunch;

  @override
  State<FirstRunTutorialGate> createState() => _FirstRunTutorialGateState();
}

class _FirstRunTutorialGateState extends State<FirstRunTutorialGate> {
  bool _presenting = false;

  @override
  void initState() {
    super.initState();
    if (widget.showOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showOnFirstLaunch());
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    () => unawaited(_presentTutorial(markCompleted: false)),
  );

  Future<void> _showOnFirstLaunch() async {
    bool completed;
    try {
      completed = await widget.store.isCompleted();
    } on Object {
      return;
    }
    if (!mounted || completed) return;
    await _presentTutorial(markCompleted: true);
  }

  Future<void> _presentTutorial({required bool markCompleted}) async {
    if (!mounted || _presenting) return;
    _presenting = true;
    try {
      await showFirstRunTutorial(context);
      if (markCompleted) {
        try {
          await widget.store.markCompleted();
        } on Object {
          // A failed marker write must never prevent people from using the app.
        }
      }
    } finally {
      _presenting = false;
    }
  }
}
