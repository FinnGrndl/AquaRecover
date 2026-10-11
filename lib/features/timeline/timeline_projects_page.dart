import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/timeline/timeline_project.dart';
import '../../core/timeline/timeline_project_store.dart';
import 'timeline_editor_page.dart';
import 'timeline_theme.dart';

/// Lists saved movies and starts new ones.
class TimelineProjectsPage extends StatefulWidget {
  const TimelineProjectsPage({super.key, this.store});

  final TimelineProjectStore? store;

  /// Opens the editor on [project], saving it first so it shows up here.
  static Future<void> open(
    BuildContext context,
    TimelineProject project, {
    TimelineProjectStore? store,
  }) async {
    final effectiveStore = store ?? TimelineProjectStore();
    await effectiveStore.save(project).catchError((Object _) {});
    if (!context.mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) =>
            TimelineEditorPage(project: project, store: effectiveStore),
      ),
    );
  }

  static String newProjectId() =>
      'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  @override
  State<TimelineProjectsPage> createState() => _TimelineProjectsPageState();
}

class _TimelineProjectsPageState extends State<TimelineProjectsPage> {
  late final TimelineProjectStore _store =
      widget.store ?? TimelineProjectStore();
  List<TimelineProject>? _projects;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final projects = await _store.list();
      if (mounted) setState(() => _projects = projects);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _openProject(TimelineProject project) async {
    await TimelineProjectsPage.open(context, project, store: _store);
    await _reload();
  }

  Future<void> _create() => _openProject(
    TimelineProject(
      id: TimelineProjectsPage.newProjectId(),
      name: 'Dive ${DateTime.now().day}.${DateTime.now().month}.',
    ),
  );

  Future<void> _delete(TimelineProject project) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete “${project.name}”?'),
        content: const Text(
          'Only the movie project is removed. Your photos, clips, and rendered movies stay.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.delete(project.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return CupertinoTheme(
      data: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: TimelineColors.accent,
      ),
      child: CupertinoPageScaffold(
        backgroundColor: TimelineColors.background,
        navigationBar: const CupertinoNavigationBar(
          backgroundColor: TimelineColors.panel,
          middle: Text('Movies', style: TextStyle(color: TimelineColors.text)),
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const Text(
                  'Build a short movie from photos and clips, grade each one, and render it on this device.',
                  style: TextStyle(
                    color: TimelineColors.secondaryText,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                CupertinoButton(
                  key: const Key('timeline_new_movie'),
                  color: TimelineColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _create,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.add, color: Color(0xff04131a)),
                      SizedBox(width: 6),
                      Text(
                        'New movie',
                        style: TextStyle(
                          color: Color(0xff04131a),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: TimelineColors.danger),
                  )
                else if (projects == null)
                  const Center(child: CupertinoActivityIndicator())
                else if (projects.isEmpty)
                  const Text(
                    'No movies yet.',
                    style: TextStyle(color: TimelineColors.secondaryText),
                  )
                else
                  for (final project in projects)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ProjectRow(
                        project: project,
                        onOpen: () => _openProject(project),
                        onDelete: () => _delete(project),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.onOpen,
    required this.onDelete,
  });

  final TimelineProject project;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: project.name,
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          decoration: BoxDecoration(
            color: TimelineColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: TimelineColors.stroke),
          ),
          child: Row(
            children: [
              const Icon(CupertinoIcons.film, color: TimelineColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TimelineColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${project.clips.length} items · '
                      '${formatTimecode(project.duration)} · '
                      '${project.aspect.label}',
                      style: const TextStyle(
                        color: TimelineColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Delete ${project.name}',
                child: CupertinoButton(
                  padding: const EdgeInsets.all(10),
                  onPressed: onDelete,
                  child: const Icon(
                    CupertinoIcons.trash,
                    size: 19,
                    color: TimelineColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
