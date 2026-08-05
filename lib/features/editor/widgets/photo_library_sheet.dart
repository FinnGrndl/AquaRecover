import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/photo/photo_library_service.dart';

class PhotoLibrarySheet extends StatefulWidget {
  const PhotoLibrarySheet({
    super.key,
    this.service = const PhotoLibraryService(),
  });
  final PhotoLibraryService service;
  @override
  State<PhotoLibrarySheet> createState() => _PhotoLibrarySheetState();
}

class _PhotoLibrarySheetState extends State<PhotoLibrarySheet> {
  final Set<String> _selectedIds = <String>{};
  final Map<String, AssetEntity> _selectedAssets = <String, AssetEntity>{};
  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  AssetPathEntity? _album;
  bool _loading = true;
  bool _importing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final albums = await widget.service.loadAlbums();
      final album = albums.isEmpty ? null : albums.first;
      final assets = album == null
          ? <AssetEntity>[]
          : await widget.service.loadAssets(album);
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _album = album;
        _assets = assets;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _changeAlbum(AssetPathEntity album) async {
    setState(() {
      _album = album;
      _assets = const [];
      _loading = true;
      _error = null;
    });
    try {
      final assets = await widget.service.loadAssets(album);
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPopupSurface(
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
              ? const CupertinoActivityIndicator()
              : Text('Import ${_selectedIds.length}'),
        ),
      ],
    ),
  );
  Widget _albumStrip(BuildContext context) => SizedBox(
    height: 48,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemBuilder: (context, index) {
        final album = _albums[index];
        final selected = album.id == _album?.id;
        return CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: selected
              ? CupertinoTheme.of(context).primaryColor.withValues(alpha: 0.16)
              : null,
          borderRadius: BorderRadius.circular(99),
          onPressed: selected ? null : () => _changeAlbum(album),
          child: Text(album.name),
        );
      },
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemCount: _albums.length,
    ),
  );
  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 16));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_friendly(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              CupertinoButton.filled(
                onPressed: _loadAlbums,
                child: const Text('Try again'),
              ),
              CupertinoButton(
                onPressed: () async {
                  await widget.service.openLimitedPicker();
                  if (mounted) await _loadAlbums();
                },
                child: const Text('Manage limited access'),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 132,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _assets.length,
      itemBuilder: (context, index) => _assetTile(context, _assets[index]),
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
              future: asset.thumbnailDataWithSize(
                const ThumbnailSize(240, 240),
                quality: 80,
              ),
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
      _error = null;
    });
    final paths = <String>[];
    try {
      for (final asset in _selectedAssets.values) {
        final path = await widget.service.localFilePathFor(asset);
        if (path != null) paths.add(path);
      }
      if (!mounted) return;
      Navigator.of(context).pop(paths);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _importing = false;
      });
    }
  }

  String _friendly(String message) {
    final oneLine = message.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return oneLine.length > 260 ? '${oneLine.substring(0, 260)}...' : oneLine;
  }
}
