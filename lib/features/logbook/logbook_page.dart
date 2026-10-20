import 'dart:convert';

import 'package:flutter/cupertino.dart';

import '../../core/logbook/dive_export.dart';
import '../../core/logbook/dive_log.dart';
import '../../core/logbook/dive_log_store.dart';
import '../../core/logbook/uddf.dart';
import '../timeline/timeline_theme.dart';
import 'dive_edit_page.dart';
import 'dive_page.dart';
import 'dive_site_map.dart';
import 'logbook_controller.dart';
import 'logbook_media.dart';
import 'logbook_widgets.dart';

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
    return CupertinoTheme(
      data: timelineTheme(context),
      child: CupertinoPageScaffold(
        backgroundColor: TimelineColors.background,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: TimelineColors.background,
          middle: const Text('Logbook'),
          previousPageTitle: 'Back',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LogbookIconButton(
                key: const Key('logbook_more'),
                icon: CupertinoIcons.ellipsis,
                label: 'Import and export',
                onPressed: _showMore,
              ),
              const SizedBox(width: 8),
              LogbookIconButton(
                key: const Key('logbook_add'),
                icon: CupertinoIcons.add,
                label: 'Add dive',
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
                        children: const {
                          _View.list: Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text('Dives'),
                          ),
                          _View.map: Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text('Map'),
                          ),
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: _view == _View.list ? _list() : _map(context),
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
            const Icon(
              CupertinoIcons.book,
              color: TimelineColors.secondaryText,
              size: 48,
              semanticLabel: 'Logbook',
            ),
            const SizedBox(height: 16),
            const Text(
              'No dives yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: TimelineColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Import a UDDF log from your dive computer or Subsurface, or '
              'add a dive by hand. Your logbook stays on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(
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
                  label: 'Import log',
                  primary: true,
                  onPressed: _import,
                ),
                LogbookActionButton(
                  icon: CupertinoIcons.add,
                  label: 'Add dive',
                  onPressed: _addDive,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _list() {
    final log = _controller.log;
    return ListView.separated(
      key: const Key('logbook_list'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: log.dives.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final dive = log.dives[i];
        final site = log.site(dive.siteId);
        final stats = formatDiveStats(dive);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CupertinoButton(
              key: Key('dive_${dive.id}'),
              padding: const EdgeInsets.all(14),
              minimumSize: const Size(44, 44),
              color: TimelineColors.fill,
              borderRadius: BorderRadius.circular(14),
              onPressed: () => _openDive(dive),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diveTitle(dive, site),
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
                            formatDiveDate(dive.start),
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
                      semanticLabel: '${dive.media.length} linked media',
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No dive site has a position yet. Add latitude and longitude '
            'to a dive to see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TimelineColors.secondaryText, fontSize: 15),
          ),
        ),
      );
    }
    final builder = widget.mapBuilder ?? DiveSiteMap.builder;
    return builder(context, sites, _showSite);
  }

  void _showSite(DiveSite site) {
    final dives = _controller.log.divesAt(site.id);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (popup) => CupertinoActionSheet(
        title: Text(site.name.isEmpty ? 'Dive site' : site.name),
        message: Text(dives.length == 1 ? '1 dive' : '${dives.length} dives'),
        actions: [
          for (final dive in dives)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(popup).pop();
                _openDive(dive);
              },
              child: Text(
                '${diveTitle(dive, null)} · ${formatDiveDate(dive.start)}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popup).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _openDive(Dive dive) {
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
        return CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => run(_import),
              child: const Text('Import UDDF log'),
            ),
            if (hasDives) ...[
              CupertinoActionSheetAction(
                onPressed: () => run(_matchLibrary),
                child: const Text('Link photos by capture time'),
              ),
              CupertinoActionSheetAction(
                onPressed: () =>
                    run(() => _export('gpx', 'application/gpx+xml', writeGpx)),
                child: const Text('Export GPX'),
              ),
              CupertinoActionSheetAction(
                onPressed: () =>
                    run(() => _export('uddf', 'application/xml', writeUddf)),
                child: const Text('Export UDDF'),
              ),
              CupertinoActionSheetAction(
                onPressed: () => run(
                  () =>
                      _export('geojson', 'application/geo+json', writeGeoJson),
                ),
                child: const Text('Export GeoJSON'),
              ),
            ],
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(popup).pop(),
            child: const Text('Cancel'),
          ),
        );
      },
    );
  }

  Future<void> _import() async {
    try {
      final text = await _media.pickLogText();
      if (text == null) return;
      final added = await _controller.importLog(parseUddf(text));
      await _alert(
        'Log imported',
        added == 0
            ? 'Every dive in this log is already in your logbook.'
            : added == 1
            ? '1 new dive was added.'
            : '$added new dives were added.',
      );
    } on UddfFormatException catch (e) {
      await _alert('Can’t import this file', e.message);
    } on Object catch (e) {
      await _alert('Can’t import this file', '$e');
    }
  }

  Future<void> _matchLibrary() async {
    final dives = _controller.log.dives.where((d) => d.duration != null);
    if (dives.isEmpty) {
      await _alert(
        'No dive times',
        'Dives need a start time and duration to match photos.',
      );
      return;
    }
    try {
      final from = dives.last.start.subtract(const Duration(minutes: 2));
      final to = dives.first.end.add(const Duration(minutes: 2));
      final linked = await _controller.linkByTime(
        await _media.libraryCandidates(from, to),
      );
      await _alert(
        'Photos linked',
        linked == 0
            ? 'No new photos or videos were taken during your dives.'
            : '$linked photos and videos were linked to their dives.',
      );
    } on Object catch (e) {
      await _alert('Can’t read the photo library', '$e');
    }
  }

  Future<void> _export(
    String extension,
    String mimeType,
    String Function(DiveLog) write,
  ) async {
    try {
      await _media.saveFile(
        'AquaRecover logbook.$extension',
        utf8.encode(write(_controller.log)),
        mimeType: mimeType,
      );
    } on Object catch (e) {
      await _alert('Export failed', '$e');
    }
  }

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
