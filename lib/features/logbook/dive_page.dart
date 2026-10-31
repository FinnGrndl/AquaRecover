import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../../core/logbook/dive_log.dart';
import '../../core/logbook/media_matching.dart';
import '../timeline/timeline_media_picker.dart';
import '../timeline/timeline_projects_page.dart';
import '../../l10n/l10n.dart';
import '../timeline/timeline_theme.dart';
import 'dive_edit_page.dart';
import 'logbook_controller.dart';
import 'logbook_media.dart';
import 'logbook_widgets.dart';
import '../../shared/widgets/app_dialog.dart';

/// One dive: its log fields, its linked photos and videos, and a way to
/// turn them into a movie.
class DivePage extends StatefulWidget {
  const DivePage({
    super.key,
    required this.controller,
    required this.diveId,
    required this.media,
    this.embedded = false,
  });

  /// Shown beside the dive list on wide screens rather than pushed: no
  /// back button, and deleting the dive leaves the logbook open.
  final bool embedded;

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
              automaticallyImplyLeading: !widget.embedded,
              // Beside the list the logbook's own bar is the route's hero.
              transitionBetweenRoutes: !widget.embedded,
              previousPageTitle: widget.embedded ? null : context.l10n.logbook,
              middle: Text(diveTitleIn(context.l10n, dive, site)),
              trailing: LogbookIconButton(
                key: const Key('dive_edit'),
                icon: CupertinoIcons.pencil,
                label: context.l10n.editDive,
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
    final l10n = context.l10n;
    return [
      _section([
        _field(l10n.date, formatDiveDate(l10n, dive.start)),
        _field(l10n.site, site?.name ?? l10n.notSet),
        if (site?.hasPosition ?? false)
          _field(
            l10n.position,
            l10n.coordinatePair(
              l10n.decimal(site!.latitude!, digits: 5),
              l10n.decimal(site.longitude!, digits: 5),
            ),
          ),
        _field(
          l10n.maxDepth,
          dive.maxDepth == null ? '–' : l10n.depthValue(dive.maxDepth!),
        ),
        _field(
          l10n.duration,
          dive.duration == null
              ? '–'
              : l10n.minutesValue(dive.duration!.inMinutes),
        ),
        _field(
          l10n.waterTemperature,
          dive.waterTemperature == null
              ? '–'
              : l10n.temperatureValue(dive.waterTemperature!, digits: 1),
        ),
        _field(l10n.buddy, dive.buddy.isEmpty ? '–' : dive.buddy),
        if (depths > 0) _field(l10n.profile, l10n.depthReadings(depths)),
      ]),
      if (dive.notes.isNotEmpty) ...[
        const SizedBox(height: 16),
        _heading(l10n.notes),
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
      _heading(l10n.photosAndVideos),
      if (sorted.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.nothingLinked,
            style: const TextStyle(
              color: TimelineColors.secondaryText,
              fontSize: 13,
            ),
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
            label: l10n.makeMovieFromDive,
            primary: true,
            onPressed: sorted.isEmpty || _busy
                ? null
                : () => _makeMovie(dive, site, sorted),
          ),
          LogbookActionButton(
            key: const Key('dive_add_media'),
            icon: CupertinoIcons.plus_rectangle_on_rectangle,
            label: l10n.addPhotosAndVideos,
            onPressed: _busy ? null : () => _addFiles(dive),
          ),
          if (dive.duration != null)
            LogbookActionButton(
              key: const Key('dive_find_photos'),
              icon: CupertinoIcons.photo_on_rectangle,
              label: l10n.findInPhotos,
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
    final l10n = context.l10n;
    final kind = media.isVideo ? l10n.mediaKindVideo : l10n.mediaKindPhoto;
    final time = media.capturedAt == null
        ? ''
        : ', ${l10n.time24(media.capturedAt!)}';
    final depth = media.depth == null
        ? ''
        : l10n.mediaDepthSuffix(l10n.depthValue(media.depth!));
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
                                l10n.depthValue(media.depth!),
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
            child: Text(context.l10n.removeFromDive),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popup).pop(),
          child: Text(context.l10n.cancel),
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
          onDeleted: () {
            if (!widget.embedded) Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _busyWhile(Future<void> Function() action) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (e) {
      await _alert(l10n.somethingWentWrong, '$e');
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
    final l10n = context.l10n;
    const margin = Duration(minutes: 2);
    final candidates = await widget.media.libraryCandidates(
      dive.start.subtract(margin),
      dive.end.add(margin),
    );
    final linked = await widget.controller.linkByTime(candidates);
    await _alert(l10n.photosTitle, l10n.diveMediaLinkedBody(linked));
  });

  Future<void> _makeMovie(Dive dive, DiveSite? site, List<DiveMedia> media) =>
      _busyWhile(() async {
        final l10n = context.l10n;
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
          await _alert(l10n.mediaNotFound, l10n.mediaNotFoundBody);
          return;
        }
        if (!mounted) return;
        final project = movieFromDive(
          items,
          id: TimelineProjectsPage.newProjectId(),
          name: diveTitleIn(l10n, dive, site),
        );
        await TimelineProjectsPage.open(context, project);
      });

  Future<void> _alert(String title, String message) async {
    if (!mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(context.l10n.ok),
          ),
        ],
      ),
    );
  }
}
