import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../../core/models/media_kind.dart';
import '../../core/persistence/export_library_service.dart';
import '../../core/platform/share_service.dart';
import '../editor/widgets/video_preview_tile.dart';
import '../../shared/widgets/app_tooltip.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/share_failed_dialog.dart';

class ExportLibraryPage extends StatefulWidget {
  const ExportLibraryPage({
    super.key,
    this.service = const ExportLibraryService(),
    this.shareService = const ShareService(),
  });

  final ExportLibraryService service;
  final ShareService shareService;

  @override
  State<ExportLibraryPage> createState() => _ExportLibraryPageState();
}

class _ExportLibraryPageState extends State<ExportLibraryPage> {
  List<LocalExportItem> _items = const [];
  final Set<String> _selectedPaths = {};
  bool _loading = true;
  bool _selectionMode = false;
  bool _deleting = false;
  bool _sharing = false;
  Object? _loadError;

  bool get _busy => _deleting || _sharing;

  @override
  void initState() {
    super.initState();
    _reload(showLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xff0b1115),
      child: CupertinoTheme(
        data: CupertinoTheme.of(context).copyWith(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xff0b1115),
        ),
        child: Builder(
          // The app's light text style is still the default here; without
          // this, file names draw black on the dark tiles.
          builder: (context) => DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle,
            child: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    CupertinoSliverNavigationBar(
                      largeTitle: const Text('Local Exports'),
                      backgroundColor: const Color(
                        0xff0b1115,
                      ).withValues(alpha: .92),
                      border: null,
                      trailing: _items.isEmpty
                          ? null
                          : CupertinoButton(
                              key: const Key('local_export_selection_mode'),
                              padding: EdgeInsets.zero,
                              onPressed: _busy ? null : _toggleSelectionMode,
                              child: Text(_selectionMode ? 'Cancel' : 'Select'),
                            ),
                    ),
                    CupertinoSliverRefreshControl(
                      onRefresh: () => _reload(showLoading: false),
                    ),
                    if (!_loading && _loadError == null && _items.isNotEmpty)
                      SliverToBoxAdapter(child: _libraryToolbar()),
                    _libraryContent(),
                  ],
                ),
                if (_selectionMode && _items.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _selectionActionBar(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _libraryContent() {
    if (_loading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }
    if (_loadError != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _message(
          CupertinoIcons.exclamationmark_triangle,
          'Exports could not be loaded.',
          action: 'Try again',
        ),
      );
    }
    if (_items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _message(CupertinoIcons.tray, 'No local exports yet.'),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, _selectionMode ? 116 : 32),
      sliver: SliverGrid(
        // Two columns on phones, more on iPad, Mac and Windows windows,
        // so tiles never grow to half a desktop window.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: .78,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _exportTile(context, _items[index]),
          childCount: _items.length,
        ),
      ),
    );
  }

  Widget _libraryToolbar() {
    if (_selectionMode) {
      final allSelected = _selectedPaths.length == _items.length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_selectedPaths.length} selected',
                style: const TextStyle(color: CupertinoColors.systemGrey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CupertinoButton(
              key: const Key('local_export_select_all'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(
                kMinInteractiveDimensionCupertino,
                kMinInteractiveDimensionCupertino,
              ),
              onPressed: _busy ? null : _toggleSelectAll,
              child: Text(allSelected ? 'Deselect all' : 'Select all'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_items.length} local export${_items.length == 1 ? '' : 's'}',
              style: const TextStyle(color: CupertinoColors.systemGrey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CupertinoButton(
            key: const Key('delete_all_local_exports'),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(
              kMinInteractiveDimensionCupertino,
              kMinInteractiveDimensionCupertino,
            ),
            onPressed: _busy
                ? null
                : () => _confirmDelete(_items, deleteAll: true),
            child: const Text(
              'Delete all',
              style: TextStyle(color: CupertinoColors.destructiveRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectionActionBar() {
    final count = _selectedPaths.length;
    final selected = _items
        .where((item) => _selectedPaths.contains(item.path))
        .toList(growable: false);
    final delete = CupertinoButton(
      key: const Key('delete_selected_local_exports'),
      foregroundColor: CupertinoColors.white,
      color: count == 0
          ? CupertinoColors.systemGrey
          : CupertinoColors.destructiveRed,
      borderRadius: BorderRadius.circular(14),
      onPressed: count == 0 || _busy ? null : () => _confirmDelete(selected),
      child: _deleting
          ? const CupertinoActivityIndicator(color: CupertinoColors.white)
          : Text('Delete $count'),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff171c20).withValues(alpha: .97),
        border: Border(
          top: BorderSide(color: CupertinoColors.white.withValues(alpha: .12)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: widget.shareService.isAvailable
              ? Row(
                  children: [
                    Expanded(
                      child: AppTooltip(
                        message: count == 1
                            ? 'Share the selected export'
                            : 'Share the selected exports',
                        child: Builder(
                          builder: (buttonContext) => CupertinoButton(
                            key: const Key('share_selected_local_exports'),
                            foregroundColor: CupertinoColors.white,
                            color: count == 0
                                ? CupertinoColors.systemGrey
                                : CupertinoColors.activeBlue,
                            borderRadius: BorderRadius.circular(14),
                            onPressed: count == 0 || _busy
                                ? null
                                : () => _share(
                                    selected,
                                    shareOriginOf(buttonContext),
                                  ),
                            child: _sharing
                                ? const CupertinoActivityIndicator(
                                    color: CupertinoColors.white,
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        CupertinoIcons.share,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Share $count',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: delete),
                  ],
                )
              : delete,
        ),
      ),
    );
  }

  Future<void> _share(List<LocalExportItem> items, Rect? origin) async {
    if (items.isEmpty || _busy) return;
    setState(() => _sharing = true);
    try {
      final outcome = await widget.shareService.shareFiles([
        for (final item in items) item.path,
      ], origin: origin);
      if (!mounted) return;
      if (outcome == ShareOutcome.shared) {
        setState(() {
          _selectionMode = false;
          _selectedPaths.clear();
        });
      }
    } on Object catch (error) {
      if (mounted) await showShareFailedDialog(context, error);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Widget _message(IconData icon, String message, {String? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: CupertinoColors.systemGrey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 10),
              CupertinoButton(onPressed: _reload, child: Text(action)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _exportTile(BuildContext context, LocalExportItem item) {
    final selected = _selectedPaths.contains(item.path);
    // Hover only: touch and hold selects the export. The tag shows the full
    // name the tile cuts short.
    return AppTooltip(
      trigger: AppTooltipTrigger.hoverOnly,
      message: item.fileName,
      child: GestureDetector(
        key: Key('local_export_${item.fileName}'),
        onLongPress: _busy ? null : () => _selectItem(item),
        onTap: _busy
            ? null
            : () => _selectionMode
                  ? _toggleItem(item)
                  : _openDetail(context, item),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xff1b2024),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.white.withValues(alpha: .10),
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _thumbnail(item)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.sizeLabel,
                            style: const TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_selectionMode)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  key: Key('local_export_selected_${item.fileName}'),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.black.withValues(alpha: .55),
                    shape: BoxShape.circle,
                    border: Border.all(color: CupertinoColors.white, width: 2),
                  ),
                  child: selected
                      ? const Icon(
                          CupertinoIcons.check_mark,
                          color: CupertinoColors.white,
                          size: 17,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(LocalExportItem item) {
    if (!item.kind.isImage) {
      return const ColoredBox(
        color: CupertinoColors.black,
        child: Center(
          child: Icon(
            CupertinoIcons.film,
            color: CupertinoColors.systemGrey,
            size: 42,
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: Image.file(
        File(item.path),
        fit: BoxFit.cover,
        cacheWidth: 520,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: CupertinoColors.black,
          child: Center(
            child: Icon(
              CupertinoIcons.photo,
              color: CupertinoColors.systemGrey,
              size: 38,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, LocalExportItem item) async {
    final deleted = await Navigator.of(context).push<bool>(
      CupertinoPageRoute<bool>(
        builder: (_) => ExportDetailPage(
          item: item,
          service: widget.service,
          shareService: widget.shareService,
        ),
      ),
    );
    if (deleted == true && mounted) await _reload(showLoading: false);
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedPaths.clear();
    });
  }

  void _selectItem(LocalExportItem item) {
    setState(() {
      _selectionMode = true;
      _selectedPaths.add(item.path);
    });
  }

  void _toggleItem(LocalExportItem item) {
    setState(() {
      if (!_selectedPaths.add(item.path)) _selectedPaths.remove(item.path);
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPaths.length == _items.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths
          ..clear()
          ..addAll(_items.map((item) => item.path));
      }
    });
  }

  Future<void> _confirmDelete(
    List<LocalExportItem> items, {
    bool deleteAll = false,
  }) async {
    if (items.isEmpty || _busy) return;
    final count = items.length;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(
          deleteAll
              ? 'Delete all local exports?'
              : 'Delete $count export${count == 1 ? '' : 's'}?',
        ),
        content: const Text(
          'The local files and their settings sidecars will be deleted. Imported originals and copies in Photos are not affected.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    var failures = 0;
    for (final item in items) {
      try {
        await widget.service.delete(item);
      } on Object {
        failures++;
      }
    }
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _selectionMode = false;
      _selectedPaths.clear();
    });
    await _reload(showLoading: false);
    if (failures > 0 && mounted) {
      await showAppDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Some exports could not be deleted'),
          content: Text(
            '$failures of $count files may have been moved or are currently unavailable.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _reload({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final items = await widget.service.load();
      if (!mounted) return;
      setState(() {
        _items = items;
        _selectedPaths.retainAll(items.map((item) => item.path).toSet());
        if (items.isEmpty) _selectionMode = false;
        _loading = false;
        _loadError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }
}

class ExportDetailPage extends StatelessWidget {
  const ExportDetailPage({
    super.key,
    required this.item,
    this.service = const ExportLibraryService(),
    this.shareService = const ShareService(),
  });

  final LocalExportItem item;
  final ExportLibraryService service;
  final ShareService shareService;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black.withValues(alpha: .86),
        border: null,
        middle: Text(
          item.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shareService.isAvailable)
              AppTooltip(
                message: 'Share export',
                child: Semantics(
                  button: true,
                  label: 'Share export',
                  excludeSemantics: true,
                  child: Builder(
                    builder: (buttonContext) => CupertinoButton(
                      key: const Key('share_local_export'),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(
                        kMinInteractiveDimensionCupertino,
                        kMinInteractiveDimensionCupertino,
                      ),
                      onPressed: () =>
                          _share(buttonContext, shareOriginOf(buttonContext)),
                      child: const Icon(CupertinoIcons.share),
                    ),
                  ),
                ),
              ),
            AppTooltip(
              message: 'Delete export',
              child: Semantics(
                button: true,
                label: 'Delete export',
                excludeSemantics: true,
                child: CupertinoButton(
                  key: const Key('delete_local_export'),
                  padding: EdgeInsets.zero,
                  onPressed: () => _confirmDelete(context),
                  child: const Icon(
                    CupertinoIcons.trash,
                    color: CupertinoColors.destructiveRed,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: item.kind.isImage
                  ? InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Center(
                        child: Image.file(
                          File(item.path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text(
                            'Preview unavailable.',
                            style: TextStyle(color: CupertinoColors.white),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      key: const Key('local_export_video_player'),
                      child: VideoPreviewTile(path: item.path),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CupertinoColors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    item.sizeLabel,
                    style: const TextStyle(color: CupertinoColors.systemGrey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, Rect? origin) async {
    try {
      await shareService.shareFiles([item.path], origin: origin);
    } on Object catch (error) {
      if (context.mounted) await showShareFailedDialog(context, error);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete local export?'),
        content: const Text(
          'The local file and its settings sidecar will be deleted. The imported original and any copy in Photos are not affected.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await service.delete(item);
      if (context.mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!context.mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('Export could not be deleted'),
          content: const Text(
            'The file may have been moved or is currently unavailable.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
