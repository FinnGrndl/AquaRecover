import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../../core/logbook/dive_export.dart';
import '../../core/logbook/dive_log.dart';
import '../../core/logbook/media_matching.dart';
import '../timeline/timeline_media_picker.dart';
import '../timeline/timeline_projects_page.dart';
import '../timeline/timeline_theme.dart';
import 'dive_edit_page.dart';
import 'logbook_controller.dart';
import 'logbook_media.dart';
import 'logbook_widgets.dart';

/// One dive: its log fields, its linked photos and videos, and a way to
/// turn them into a movie.
class DivePage extends StatefulWidget {
  const DivePage({
    super.key,
    required this.controller,
    required this.diveId,
    required this.media,
  });

  final LogbookController controller;
  final String diveId;
  final LogbookMedia media;

  @override
  State<DivePage> createState() => _DivePageState();
}

class _DivePageState extends State<DivePage> {
  final _thumbnails = <String, Future<Uint8List?>>{};
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    return TimelineTheme(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final dive = widget.controller.dive(widget.diveId);
          if (dive == null) {
            return const CupertinoPageScaffold(
              backgroundColor: TimelineColors.background,
              child: SizedBox.expand(),
            );
          }
          final site = widget.controller.log.site(dive.siteId);
          return CupertinoPageScaffold(
            backgroundColor: TimelineColors.background,
            navigationBar: CupertinoNavigationBar(
              backgroundColor: TimelineColors.background,
              previousPageTitle: 'Logbook',
              middle: Text(diveTitle(dive, site)),
              trailing: LogbookIconButton(
                key: const Key('dive_edit'),
                icon: CupertinoIcons.pencil,
                label: 'Edit dive',
                onPressed: () => _edit(dive, site),
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _content(dive, site),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _content(Dive dive, DiveSite? site) {
    final sorted = [...dive.media]
      ..sort(
        (a, b) =>
            (a.capturedAt ?? dive.start).compareTo(b.capturedAt ?? dive.start),
      );
    final depths = dive.samples.where((s) => s.depth != null).length;
    return [
      _section([
        _field('Date', formatDiveDate(dive.start)),
        _field('Site', site?.name ?? 'Not set'),
        if (site?.hasPosition ?? false)
          _field(
            'Position',
            '${site!.latitude!.toStringAsFixed(5)}, '
                '${site.longitude!.toStringAsFixed(5)}',
          ),
        _field(
          'Max depth',
          dive.maxDepth == null
              ? '–'
              : '${dive.maxDepth!.toStringAsFixed(1)} m',
        ),
        _field(
          'Duration',
          dive.duration == null ? '–' : '${dive.duration!.inMinutes} min',
        ),
        _field(
          'Water temperature',
          dive.waterTemperature == null
              ? '–'
              : '${dive.waterTemperature!.toStringAsFixed(1)} °C',
        ),
        _field('Buddy', dive.buddy.isEmpty ? '–' : dive.buddy),
        if (depths > 0) _field('Profile', '$depths depth readings'),
      ]),
      if (dive.notes.isNotEmpty) ...[
        const SizedBox(height: 16),
        _heading('Notes'),
        _section([
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              dive.notes,
              style: const TextStyle(color: TimelineColors.text, fontSize: 15),
            ),
          ),
        ]),
      ],
      const SizedBox(height: 20),
      _heading('Photos and videos'),
      if (sorted.isEmpty)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Nothing linked yet. Linked media stays where it is; the logbook '
            'never copies it.',
            style: TextStyle(color: TimelineColors.secondaryText, fontSize: 13),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            key: const Key('dive_media'),
            spacing: 8,
            runSpacing: 8,
            children: [for (final m in sorted) _mediaTile(dive, m)],
          ),
        ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.all(12),
          child: CupertinoActivityIndicator(),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          LogbookActionButton(
            key: const Key('dive_make_movie'),
            icon: CupertinoIcons.film,
            label: 'Make a movie from this dive',
            primary: true,
            onPressed: sorted.isEmpty || _busy
                ? null
                : () => _makeMovie(dive, site, sorted),
          ),
          LogbookActionButton(
            key: const Key('dive_add_media'),
            icon: CupertinoIcons.plus_rectangle_on_rectangle,
            label: 'Add photos and videos',
            onPressed: _busy ? null : () => _addFiles(dive),
          ),
          if (dive.duration != null)
            LogbookActionButton(
              key: const Key('dive_find_photos'),
              icon: CupertinoIcons.photo_on_rectangle,
              label: 'Find in Photos',
              onPressed: _busy ? null : () => _findInLibrary(dive),
            ),
        ],
      ),
    ];
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          color: TimelineColors.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _section(List<Widget> children) => DecoratedBox(
    decoration: BoxDecoration(
      color: TimelineColors.fill,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: TimelineColors.stroke),
    ),
    child: Column(children: children),
  );

  Widget _field(String label, String value) => MergeSemantics(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: TimelineColors.secondaryText,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: TimelineColors.text, fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _mediaTile(Dive dive, DiveMedia media) {
    final thumb = _thumbnails.putIfAbsent(
      media.key,
      () => widget.media.thumbnail(media),
    );
    final kind = media.isVideo ? 'Video' : 'Photo';
    final time = media.capturedAt == null
        ? ''
        : ', ${formatDiveDate(media.capturedAt!).split(' · ').last}';
    final depth = media.depth == null
        ? ''
        : ', ${media.depth!.toStringAsFixed(1)} m deep';
    return Semantics(
      label: '$kind$time$depth',
      button: true,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _mediaActions(dive, media),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: TimelineColors.fill,
                  child: FutureBuilder<Uint8List?>(
                    future: thumb,
                    builder: (context, snapshot) => snapshot.data == null
                        ? Icon(
                            media.isVideo
                                ? CupertinoIcons.film
                                : CupertinoIcons.photo,
                            color: TimelineColors.secondaryText,
                          )
                        : Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            cacheWidth: 240,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
                if (media.isVideo || media.depth != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: const Color(0xb3000000),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Row(
                          children: [
                            if (media.isVideo)
                              const Icon(
                                CupertinoIcons.videocam_fill,
                                color: CupertinoColors.white,
                                size: 13,
                              ),
                            const Spacer(),
                            if (media.depth != null)
                              Text(
                                '${media.depth!.toStringAsFixed(1)} m',
                                style: const TextStyle(
                                  color: CupertinoColors.white,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mediaActions(Dive dive, DiveMedia media) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (popup) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(popup).pop();
              widget.controller.updateDive(
                dive.copyWith(
                  media: [
                    for (final m in dive.media)
                      if (m.key != media.key) m,
                  ],
                ),
              );
            },
            child: const Text('Remove from dive'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popup).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _edit(Dive dive, DiveSite? site) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DiveEditPage(
          controller: widget.controller,
          dive: dive,
          site: site,
          onDeleted: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _busyWhile(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      await _alert('Something went wrong', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Files the person chose belong to this dive, wherever their time lies.
  Future<void> _addFiles(Dive dive) => _busyWhile(() async {
    final picked = await widget.media.pickFiles();
    if (picked.isEmpty) return;
    final current = widget.controller.dive(dive.id) ?? dive;
    final keys = {for (final m in current.media) m.key};
    final added = [
      for (final c in picked)
        DiveMedia(
          path: c.path,
          assetId: c.assetId,
          isVideo: c.isVideo,
          capturedAt: c.capturedAt,
          depth: depthAt(current, c.capturedAt),
        ),
    ].where((m) => keys.add(m.key));
    await widget.controller.updateDive(
      current.copyWith(media: [...current.media, ...added]),
    );
  });

  Future<void> _findInLibrary(Dive dive) => _busyWhile(() async {
    const margin = Duration(minutes: 2);
    final candidates = await widget.media.libraryCandidates(
      dive.start.subtract(margin),
      dive.end.add(margin),
    );
    final linked = await widget.controller.linkByTime(candidates);
    await _alert(
      'Photos',
      linked == 0
          ? 'No new photos or videos from this dive were found.'
          : linked == 1
          ? '1 photo or video was linked.'
          : '$linked photos and videos were linked.',
    );
  });

  Future<void> _makeMovie(Dive dive, DiveSite? site, List<DiveMedia> media) =>
      _busyWhile(() async {
        final items = <({String path, bool isVideo, double? seconds})>[];
        for (final m in media) {
          final path = await widget.media.filePath(m);
          if (path == null) continue;
          items.add((
            path: path,
            isVideo: m.isVideo,
            seconds: m.isVideo ? await probeVideoDuration(path) : null,
          ));
        }
        if (items.isEmpty) {
          await _alert(
            'Media not found',
            'None of the linked photos or videos can be opened. They may '
                'have been moved or deleted.',
          );
          return;
        }
        if (!mounted) return;
        final project = movieFromDive(
          items,
          id: TimelineProjectsPage.newProjectId(),
          name: diveTitle(dive, site),
        );
        await TimelineProjectsPage.open(context, project);
      });

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
