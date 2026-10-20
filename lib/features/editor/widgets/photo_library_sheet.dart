import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/photo/photo_library_service.dart';
import '../../../core/utils/bounded_concurrency.dart';
import '../../../shared/widgets/mouse_drag_scroll.dart';
import '../../../shared/widgets/sheet_width.dart';

class PhotoLibrarySheet extends StatefulWidget {
  const PhotoLibrarySheet({
    super.key,
    this.service = const PhotoLibraryService(),
  });
  final PhotoLibraryService service;
  @override
  State<PhotoLibrarySheet> createState() => _PhotoLibrarySheetState();
}

class _PhotoLibrarySheetState extends State<PhotoLibrarySheet>
    with WidgetsBindingObserver {
  final Set<String> _selectedIds = <String>{};
  final Map<String, AssetEntity> _selectedAssets = <String, AssetEntity>{};
  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  final Map<String, Future<Uint8List?>> _thumbnails =
      <String, Future<Uint8List?>>{};
  final ScrollController _scrollController = ScrollController();
  AssetPathEntity? _album;
  int _albumAssetCount = 0;
  int _nextPage = 0;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _importing = false;
  double? _importProgress;
  String? _error;
  PhotoLibraryPermissionException? _permissionError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_maybeLoadMore);
    _loadAlbums();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasMore => _assets.length < _albumAssetCount;

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || _loading || _loadingMore) return;
    final position = _scrollController.position;
    if (position.extentAfter < 600 && _hasMore) _loadNextPage();
  }

  Future<void> _loadFirstPage(AssetPathEntity album, int generation) async {
    final results = await Future.wait<Object>([
      widget.service.loadAssets(album),
      widget.service.assetCount(album),
    ]);
    if (!mounted || generation != _loadGeneration) return;
    final assets = results[0] as List<AssetEntity>;
    _albumAssetCount = results[1] as int;
    _assets = assets;
    _nextPage = 1;
  }

  Future<void> _loadNextPage() async {
    final album = _album;
    if (album == null) return;
    final generation = _loadGeneration;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.loadAssets(album, page: _nextPage);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _assets = [..._assets, ...page];
        _nextPage++;
        if (page.isEmpty) _albumAssetCount = _assets.length;
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _loadingMore = false;
      });
    }
  }

  Future<Uint8List?> _thumbnail(AssetEntity asset) => _thumbnails.putIfAbsent(
    asset.id,
    () => widget.service.thumbnailFor(asset),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _permissionError != null &&
        !_loading) {
      _loadAlbums();
    }
  }

  Future<void> _loadAlbums() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _permissionError = null;
    });
    try {
      final albums = await widget.service.loadAlbums();
      final album = albums.isEmpty ? null : albums.first;
      if (album == null) {
        _assets = const [];
        _albumAssetCount = 0;
      } else {
        await _loadFirstPage(album, generation);
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _albums = albums;
        _album = album;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _permissionError = error is PhotoLibraryPermissionException
            ? error
            : null;
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changeAlbum(AssetPathEntity album) async {
    final generation = ++_loadGeneration;
    setState(() {
      _album = album;
      _assets = const [];
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    try {
      await _loadFirstPage(album, generation);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loading = false);
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetWidth(
      maxWidth: 960,
      child: CupertinoPopupSurface(
        isSurfacePainted: true,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.86,
            child: Column(
              children: [
                _header(context),
                if (_albums.length > 1) _albumStrip(context),
                Expanded(child: _body(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Row(
      children: [
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const Spacer(),
        Text(
          'Photos',
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const Spacer(),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _selectedIds.isEmpty || _importing
              ? null
              : _importSelected,
          child: _importing
              ? _importProgress == null
                    ? const CupertinoActivityIndicator()
                    : Text('${(_importProgress! * 100).round()}%')
              : Text('Import ${_selectedIds.length}'),
        ),
      ],
    ),
  );
  Widget _albumStrip(BuildContext context) => SizedBox(
    height: 48,
    child: MouseDragScroll(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final album = _albums[index];
          final selected = album.id == _album?.id;
          return CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: selected
                ? CupertinoTheme.of(
                    context,
                  ).primaryColor.withValues(alpha: 0.16)
                : null,
            borderRadius: BorderRadius.circular(99),
            onPressed: selected ? null : () => _changeAlbum(album),
            child: Text(album.name),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemCount: _albums.length,
      ),
    ),
  );
  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 16));
    }
    if (_error != null) {
      final permissionError = _permissionError;
      // Scrolls in short landscape and desktop windows.
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                permissionError == null
                    ? CupertinoIcons.exclamationmark_triangle
                    : CupertinoIcons.photo_on_rectangle,
                size: 34,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              const SizedBox(height: 12),
              Text(_friendly(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (permissionError?.canOpenSettings ?? false)
                CupertinoButton.filled(
                  onPressed: widget.service.openSettings,
                  child: const Text('Open System Settings'),
                )
              else
                CupertinoButton.filled(
                  onPressed: _loadAlbums,
                  child: const Text('Try again'),
                ),
              if (permissionError?.canOpenSettings ?? false)
                CupertinoButton(
                  onPressed: _loadAlbums,
                  child: const Text('Try again'),
                ),
            ],
          ),
        ),
      );
    }
    if (_assets.isEmpty) {
      return const Center(child: Text('No photos or videos found.'));
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _assets.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) => index >= _assets.length
          ? const Center(child: CupertinoActivityIndicator())
          : _assetTile(context, _assets[index]),
    );
  }

  Widget _assetTile(BuildContext context, AssetEntity asset) {
    final selected = _selectedIds.contains(asset.id);
    return GestureDetector(
      onTap: () => _toggle(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FutureBuilder<Uint8List?>(
              future: _thumbnail(asset),
              builder: (context, snapshot) {
                final data = snapshot.data;
                return data == null
                    ? const ColoredBox(color: CupertinoColors.systemGrey5)
                    : Image.memory(
                        data,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      );
              },
            ),
          ),
          if (asset.type == AssetType.video)
            const Positioned(
              left: 8,
              bottom: 8,
              child: Icon(
                CupertinoIcons.play_circle_fill,
                color: CupertinoColors.white,
                size: 22,
              ),
            ),
          Positioned(
            right: 8,
            top: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? CupertinoTheme.of(context).primaryColor
                    : CupertinoColors.black.withValues(alpha: 0.42),
                shape: BoxShape.circle,
                border: Border.all(color: CupertinoColors.white, width: 1.2),
              ),
              child: SizedBox(
                width: 24,
                height: 24,
                child: selected
                    ? const Icon(
                        CupertinoIcons.check_mark,
                        color: CupertinoColors.white,
                        size: 16,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggle(AssetEntity asset) => setState(() {
    if (_selectedIds.contains(asset.id)) {
      _selectedIds.remove(asset.id);
      _selectedAssets.remove(asset.id);
    } else {
      _selectedIds.add(asset.id);
      _selectedAssets[asset.id] = asset;
    }
  });
  Future<void> _importSelected() async {
    setState(() {
      _importing = true;
      _importProgress = null;
      _error = null;
    });
    final selected = _selectedAssets.values.toList(growable: false);
    final progress = List<double>.filled(selected.length, 0);
    void report(int index, double value) {
      progress[index] = value.clamp(0.0, 1.0);
      if (!mounted) return;
      final total = progress.fold<double>(0, (sum, item) => sum + item);
      setState(() => _importProgress = total / progress.length);
    }

    try {
      final resolved = await mapWithConcurrencyLimit<int, String?>(
        List<int>.generate(selected.length, (index) => index),
        maxConcurrent: 3,
        operation: (index) async {
          try {
            final path = await widget.service.localFilePathFor(
              selected[index],
              onProgress: (value) => report(index, value),
            );
            report(index, 1);
            return path;
          } on Object {
            report(index, 1);
            return null;
          }
        },
      );
      final paths = <String>[];
      var failures = 0;
      for (final path in resolved) {
        if (path != null) {
          paths.add(path);
        } else {
          failures++;
        }
      }
      if (!mounted) return;
      if (paths.isEmpty) {
        throw StateError(
          'None of the selected Photos items could be downloaded. Open them in Photos first, then try again.',
        );
      }
      if (failures > 0) {
        await showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Some items were skipped'),
            content: Text(
              '$failures selected item${failures == 1 ? '' : 's'} could not be downloaded from Photos. The remaining ${paths.length} will be imported.',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (!mounted) return;
      }
      Navigator.of(context).pop(paths);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _importing = false;
        _importProgress = null;
      });
    }
  }

  String _friendly(String message) {
    final oneLine = message.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return oneLine.length > 260 ? '${oneLine.substring(0, 260)}...' : oneLine;
  }
}
