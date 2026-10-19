import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/timeline/timeline_project.dart';
import '../../core/timeline/timeline_project_store.dart';
import '../../shared/widgets/ocean_backdrop.dart';
import '../editor/widgets/glass_navigation_bar.dart';
import 'timeline_editor_page.dart';
import 'timeline_media_picker.dart';
import 'timeline_theme.dart';

/// Lists saved movies and starts new ones.
class TimelineProjectsPage extends StatefulWidget {
  const TimelineProjectsPage({super.key, this.store, this.mediaPicker});

  final TimelineProjectStore? store;

  /// Overrides the system picker in widget tests.
  final Future<List<String>> Function()? mediaPicker;

  /// Opens the editor on [project], saving it first so it shows up here.
  static Future<void> open(
    BuildContext context,
    TimelineProject project, {
    TimelineProjectStore? store,
    List<String> initialMedia = const [],
  }) async {
    final effectiveStore = store ?? TimelineProjectStore();
    await effectiveStore.save(project).catchError((Object _) {});
    if (!context.mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => TimelineEditorPage(
          project: project,
          store: effectiveStore,
          initialMedia: initialMedia,
        ),
      ),
    );
  }

  /// "Dive, Oct 11": short, readable, and sorts nothing away.
  static String defaultName(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return 'Dive, ${months[date.month - 1]} ${date.day}';
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

  /// Like iMovie: pick the media first, then the editor opens with it.
  /// Cancelling the picker creates nothing.
  Future<void> _create() async {
    final paths = await (widget.mediaPicker ?? pickTimelineMedia)();
    if (paths.isEmpty || !mounted) return;
    await TimelineProjectsPage.open(
      context,
      TimelineProject(
        id: TimelineProjectsPage.newProjectId(),
        name: TimelineProjectsPage.defaultName(DateTime.now()),
      ),
      store: _store,
      initialMedia: paths,
    );
    await _reload();
  }

  Future<bool> _confirmDelete(TimelineProject project) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete “${project.name}”?'),
        content: const Text(
          'Only the movie project is removed. Your photos, clips, and exported movies stay.',
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
    return confirmed ?? false;
  }

  Future<void> _delete(TimelineProject project) async {
    if (!await _confirmDelete(project)) return;
    await _remove(project);
  }

  Future<void> _remove(TimelineProject project) async {
    setState(
      () => _projects = [
        for (final p in _projects ?? const <TimelineProject>[])
          if (p.id != project.id) p,
      ],
    );
    await _store.delete(project.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    final count = projects?.length ?? 0;
    return CupertinoTheme(
      data: timelineTheme(context),
      child: CupertinoPageScaffold(
        backgroundColor: OceanBackdrop.base,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: OceanBackdrop(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: GlassNavigationBar(
                      leadingLabel: 'Library',
                      onLeadingPressed: () => Navigator.of(context).maybePop(),
                      title: 'Movies',
                      subtitle: projects == null || count == 0
                          ? 'Made on this device'
                          : '$count movie${count == 1 ? '' : 's'}',
                      trailingWidth: 46,
                      trailingTint: CupertinoColors.activeBlue,
                      trailing: Tooltip(
                        message: 'New movie',
                        child: Semantics(
                          button: true,
                          label: 'New movie',
                          child: CupertinoButton(
                            key: const Key('timeline_new_movie'),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(44, 44),
                            borderRadius: BorderRadius.circular(99),
                            color: CupertinoColors.activeBlue,
                            onPressed: _create,
                            child: const Icon(
                              CupertinoIcons.add,
                              color: CupertinoColors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: _body(projects)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(List<TimelineProject>? projects) {
    final bottom = MediaQuery.paddingOf(context).bottom + 24;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: TimelineColors.danger),
          ),
        ),
      );
    }
    if (projects == null) {
      return const Center(
        child: CupertinoActivityIndicator(color: CupertinoColors.white),
      );
    }
    if (projects.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(32, 24, 32, bottom),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: CupertinoColors.activeBlue.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    CupertinoIcons.film,
                    color: CupertinoColors.activeBlue,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Turn a dive into a movie',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TimelineColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Line up photos and clips, give each the colour it needs, '
                  'and export a movie without leaving this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TimelineColors.secondaryText,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                CupertinoButton(
                  key: const Key('timeline_new_movie_empty'),
                  color: CupertinoColors.activeBlue,
                  borderRadius: BorderRadius.circular(99),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 13,
                  ),
                  onPressed: _create,
                  child: const Text(
                    'New movie',
                    style: TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return CupertinoScrollbar(
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 22, 16, bottom),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Recent',
              style: TextStyle(
                color: TimelineColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
              ),
            ),
          ),
          for (final project in projects)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey('movie-${project.id}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(project),
                onDismissed: (_) => unawaited(_remove(project)),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 22),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    CupertinoIcons.trash,
                    color: CupertinoColors.white,
                  ),
                ),
                child: _ProjectRow(
                  project: project,
                  onOpen: () => _openProject(project),
                  onDelete: () => _delete(project),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Swipe left on a movie to delete it.',
              style: TextStyle(
                color: TimelineColors.secondaryText,
                fontSize: 12,
              ),
            ),
          ),
        ],
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

  String? get _posterPath {
    for (final clip in project.clips) {
      if (!clip.isVideo) return clip.path;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final poster = _posterPath;
    final clips = project.clips.length;
    return Semantics(
      button: true,
      label: project.name,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Delete'): onDelete,
      },
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        pressedOpacity: .7,
        onPressed: onOpen,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: CupertinoColors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: CupertinoColors.white.withValues(alpha: .14),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: poster == null
                      ? ColoredBox(
                          color: CupertinoColors.activeBlue.withValues(
                            alpha: .18,
                          ),
                          child: const Icon(
                            CupertinoIcons.film,
                            color: CupertinoColors.activeBlue,
                          ),
                        )
                      : Image.file(
                          File(poster),
                          fit: BoxFit.cover,
                          cacheWidth: 192,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: TimelineColors.photoClip),
                        ),
                ),
              ),
              const SizedBox(width: 14),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$clips item${clips == 1 ? '' : 's'} · '
                      '${formatTimecode(project.duration, tenths: false)} · '
                      '${project.aspect.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TimelineColors.secondaryText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 17,
                  color: TimelineColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
