import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/logbook/dive_export.dart';
import '../../core/logbook/dive_log.dart';
import '../../core/logbook/dive_log_store.dart';
import '../../core/logbook/uddf.dart';
import '../../l10n/l10n.dart';
import '../timeline/timeline_theme.dart';
import 'dive_edit_page.dart';
import 'dive_page.dart';
import 'dive_site_map.dart';
import 'logbook_controller.dart';
import 'logbook_media.dart';
import 'logbook_widgets.dart';
import '../../shared/widgets/app_dialog.dart';

/// The dive logbook: every dive as a list or its sites on a map. It lives
/// only on the device.
class LogbookPage extends StatefulWidget {
  const LogbookPage({super.key, this.store, this.media, this.mapBuilder});

  final DiveLogStore? store;
  final LogbookMedia? media;

  /// Replaces the OpenStreetMap view, for tests without network.
  final DiveMapBuilder? mapBuilder;

  @override
  State<LogbookPage> createState() => _LogbookPageState();
}

enum _View { list, map }

class _LogbookPageState extends State<LogbookPage> {
  late final LogbookController _controller = LogbookController(
    store: widget.store,
  );
  late final LogbookMedia _media = widget.media ?? const LogbookMedia();
  var _view = _View.list;

  /// The dive shown beside the list on wide screens.
  String? _selectedDiveId;

  /// Whether the list has a detail column beside it.
  bool _split = false;

  /// From this width the list shows the selected dive beside it, as in
  /// Mail and Notes on iPad and Mac.
  static const splitWidth = 900.0;

  @override
  void initState() {
    super.initState();
    _controller.load().catchError((Object _) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TimelineTheme(
      child: CupertinoPageScaffold(
        backgroundColor: TimelineColors.background,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: TimelineColors.background,
          middle: Text(l10n.logbook),
          previousPageTitle: l10n.back,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LogbookIconButton(
                key: const Key('logbook_more'),
                icon: CupertinoIcons.ellipsis,
                label: l10n.importAndExport,
                onPressed: _showMore,
              ),
              const SizedBox(width: 8),
              LogbookIconButton(
                key: const Key('logbook_add'),
                icon: CupertinoIcons.add,
                label: l10n.addDive,
                onPressed: _addDive,
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              if (_controller.loading) {
                return const Center(child: CupertinoActivityIndicator());
              }
              if (_controller.log.dives.isEmpty) return _emptyState();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoSlidingSegmentedControl<_View>(
                        groupValue: _view,
                        onValueChanged: (v) => setState(() => _view = v!),
                        children: {
                          _View.list: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(l10n.dives),
                          ),
                          _View.map: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(l10n.map),
                          ),
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: _view == _View.list
                        ? LayoutBuilder(builder: _listOrSplit)
                        : _map(context),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
    key: const Key('logbook_empty'),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.book,
              color: TimelineColors.secondaryText,
              size: 48,
              semanticLabel: context.l10n.logbook,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.noDivesYet,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TimelineColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.noDivesYetBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: TimelineColors.secondaryText,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                LogbookActionButton(
                  key: const Key('logbook_import'),
                  icon: CupertinoIcons.arrow_down_doc,
                  label: context.l10n.importLog,
                  primary: true,
                  onPressed: _import,
                ),
                LogbookActionButton(
                  icon: CupertinoIcons.add,
                  label: context.l10n.addDive,
                  onPressed: _addDive,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _listOrSplit(BuildContext context, BoxConstraints constraints) {
    _split = constraints.maxWidth >= splitWidth;
    if (!_split) return _list();
    final dives = _controller.log.dives;
    final selected = dives.any((d) => d.id == _selectedDiveId)
        ? _selectedDiveId!
        : dives.first.id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: math.min(420, constraints.maxWidth * .36),
          child: _list(selectedId: selected),
        ),
        Container(width: .5, color: TimelineColors.stroke),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: DivePage(
              key: ValueKey('dive_detail_$selected'),
              controller: _controller,
              diveId: selected,
              media: _media,
              embedded: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _list({String? selectedId}) {
    final log = _controller.log;
    return ListView.separated(
      key: const Key('logbook_list'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: log.dives.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final dive = log.dives[i];
        final site = log.site(dive.siteId);
        final l10n = context.l10n;
        final stats = formatDiveStats(l10n, dive);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CupertinoButton(
              key: Key('dive_${dive.id}'),
              padding: const EdgeInsets.all(14),
              minimumSize: const Size(44, 44),
              color: dive.id == selectedId
                  ? TimelineColors.accent.withValues(alpha: .28)
                  : TimelineColors.fill,
              borderRadius: BorderRadius.circular(14),
              onPressed: () => _openDive(dive),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diveTitleIn(l10n, dive, site),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TimelineColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            formatDiveDate(l10n, dive.start),
                            if (stats.isNotEmpty) stats,
                          ].join('\n'),
                          style: const TextStyle(
                            color: TimelineColors.secondaryText,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (dive.media.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.photo_on_rectangle,
                      color: TimelineColors.secondaryText,
                      size: 18,
                      semanticLabel: l10n.linkedMediaCount(dive.media.length),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(
                    CupertinoIcons.chevron_forward,
                    color: TimelineColors.secondaryText,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _map(BuildContext context) {
    final sites = [
      for (final site in _controller.log.sites)
        if (site.hasPosition && _controller.log.divesAt(site.id).isNotEmpty)
          site,
    ];
    if (sites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.noSitePositions,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: TimelineColors.secondaryText,
              fontSize: 15,
            ),
          ),
        ),
      );
    }
    final builder = widget.mapBuilder ?? DiveSiteMap.builder;
    return builder(context, sites, _showSite);
  }

  void _showSite(DiveSite site) {
    final dives = _controller.log.divesAt(site.id);
    final l10n = context.l10n;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (popup) => CupertinoActionSheet(
        title: Text(site.name.isEmpty ? l10n.diveSite : site.name),
        message: Text(l10n.diveCount(dives.length)),
        actions: [
          for (final dive in dives)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popup).pop();
                _openDive(dive);
              },
              child: Text(
                '${diveTitleIn(l10n, dive, null)} · '
                '${formatDiveDate(l10n, dive.start)}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popup).pop(),
          child: Text(l10n.cancel),
        ),
      ),
    );
  }

  void _openDive(Dive dive) {
    if (_split && _view == _View.list) {
      setState(() => _selectedDiveId = dive.id);
      return;
    }
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) =>
            DivePage(controller: _controller, diveId: dive.id, media: _media),
      ),
    );
  }

  void _addDive() {
    final now = DateTime.now();
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => DiveEditPage(
          controller: _controller,
          dive: Dive(
            id: uniqueId('d', {for (final d in _controller.log.dives) d.id}),
            number: _controller.log.nextNumber,
            start: DateTime(now.year, now.month, now.day, now.hour),
          ),
        ),
      ),
    );
  }

  void _showMore() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (popup) {
        void run(Future<void> Function() action) {
          Navigator.of(popup).pop();
          action();
        }

        final hasDives = _controller.log.dives.isNotEmpty;
        final l10n = context.l10n;
        return CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => run(_import),
              child: Text(l10n.importUddfLog),
            ),
            if (hasDives) ...[
              CupertinoActionSheetAction(
                onPressed: () => run(_matchLibrary),
                child: Text(l10n.linkPhotosByTime),
              ),
              CupertinoActionSheetAction(
                onPressed: () =>
                    run(() => _export('gpx', 'application/gpx+xml', writeGpx)),
                child: Text(l10n.exportGpx),
              ),
              CupertinoActionSheetAction(
                onPressed: () =>
                    run(() => _export('uddf', 'application/xml', writeUddf)),
                child: Text(l10n.exportUddf),
              ),
              CupertinoActionSheetAction(
                onPressed: () => run(
                  () =>
                      _export('geojson', 'application/geo+json', writeGeoJson),
                ),
                child: Text(l10n.exportGeoJson),
              ),
            ],
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popup).pop(),
            child: Text(l10n.cancel),
          ),
        );
      },
    );
  }

  Future<void> _import() async {
    final l10n = context.l10n;
    try {
      final text = await _media.pickLogText();
      if (text == null) return;
      final added = await _controller.importLog(parseUddf(text));
      await _alert(l10n.logImported, l10n.logImportedBody(added));
    } on UddfFormatException catch (e) {
      await _alert(l10n.cannotImportFile, e.message);
    } on Object catch (e) {
      await _alert(l10n.cannotImportFile, '$e');
    }
  }

  Future<void> _matchLibrary() async {
    final dives = _controller.log.dives.where((d) => d.duration != null);
    final l10n = context.l10n;
    if (dives.isEmpty) {
      await _alert(l10n.noDiveTimes, l10n.noDiveTimesBody);
      return;
    }
    try {
      final from = dives.last.start.subtract(const Duration(minutes: 2));
      final to = dives.first.end.add(const Duration(minutes: 2));
      final linked = await _controller.linkByTime(
        await _media.libraryCandidates(from, to),
      );
      await _alert(l10n.photosLinked, l10n.photosLinkedBody(linked));
    } on Object catch (e) {
      await _alert(l10n.cannotReadPhotoLibrary, '$e');
    }
  }

  Future<void> _export(
    String extension,
    String mimeType,
    String Function(DiveLog) write,
  ) async {
    final l10n = context.l10n;
    try {
      await _media.saveFile(
        'AquaRecover logbook.$extension',
        utf8.encode(write(_controller.log)),
        mimeType: mimeType,
      );
    } on Object catch (e) {
      await _alert(l10n.exportFailed, '$e');
    }
  }

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
