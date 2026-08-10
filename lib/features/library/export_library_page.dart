import 'dart:io';

import 'package:flutter/cupertino.dart';

import '../../core/models/media_kind.dart';
import '../../core/persistence/export_library_service.dart';
import '../editor/widgets/video_preview_tile.dart';

class ExportLibraryPage extends StatefulWidget {
  const ExportLibraryPage({
    super.key,
    this.service = const ExportLibraryService(),
  });

  final ExportLibraryService service;

  @override
  State<ExportLibraryPage> createState() => _ExportLibraryPageState();
}

class _ExportLibraryPageState extends State<ExportLibraryPage> {
  List<LocalExportItem> _items = const [];
  final Set<String> _selectedPaths = {};
  bool _loading = true;
  bool _selectionMode = false;
  bool _deleting = false;
  Object? _loadError;

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
                          onPressed: _deleting ? null : _toggleSelectionMode,
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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
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
        padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        child: Row(
          children: [
            Text(
              '${_selectedPaths.length} selected',
              style: const TextStyle(color: CupertinoColors.systemGrey),
            ),
            const Spacer(),
            CupertinoButton(
              key: const Key('local_export_select_all'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              minimumSize: Size.zero,
              onPressed: _deleting ? null : _toggleSelectAll,
              child: Text(allSelected ? 'Deselect all' : 'Select all'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        children: [
          Text(
            '${_items.length} local export${_items.length == 1 ? '' : 's'}',
            style: const TextStyle(color: CupertinoColors.systemGrey),
          ),
          const Spacer(),
          CupertinoButton(
            key: const Key('delete_all_local_exports'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: Size.zero,
            onPressed: _deleting
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
          child: CupertinoButton(
            key: const Key('delete_selected_local_exports'),
            color: count == 0
                ? CupertinoColors.systemGrey
                : CupertinoColors.destructiveRed,
            borderRadius: BorderRadius.circular(14),
            onPressed: count == 0 || _deleting
                ? null
                : () => _confirmDelete(
                    _items
                        .where((item) => _selectedPaths.contains(item.path))
                        .toList(growable: false),
                  ),
            child: _deleting
                ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                : Text('Delete $count'),
          ),
        ),
      ),
    );
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
    return GestureDetector(
      key: Key('local_export_${item.fileName}'),
      onLongPress: _deleting ? null : () => _selectItem(item),
      onTap: _deleting
          ? null
          : () =>
                _selectionMode ? _toggleItem(item) : _openDetail(context, item),
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
        builder: (_) => ExportDetailPage(item: item, service: widget.service),
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
    if (items.isEmpty || _deleting) return;
    final count = items.length;
    final confirmed = await showCupertinoDialog<bool>(
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
      await showCupertinoDialog<void>(
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
  });

  final LocalExportItem item;
  final ExportLibraryService service;

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
        trailing: CupertinoButton(
          key: const Key('delete_local_export'),
          padding: EdgeInsets.zero,
          onPressed: () => _confirmDelete(context),
          child: const Icon(
            CupertinoIcons.trash,
            color: CupertinoColors.destructiveRed,
          ),
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

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
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
      await showCupertinoDialog<void>(
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
