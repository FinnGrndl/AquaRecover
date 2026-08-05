import 'dart:io';

import 'package:path/path.dart' as p;

import '../media/media_classifier.dart';
import '../models/media_kind.dart';
import '../utils/output_paths.dart';

class LocalExportItem {
  const LocalExportItem({
    required this.path,
    required this.kind,
    required this.sizeBytes,
    required this.modified,
  });

  final String path;
  final MediaKind kind;
  final int sizeBytes;
  final DateTime modified;

  String get fileName => p.basename(path);

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ExportLibraryService {
  const ExportLibraryService();

  Future<List<LocalExportItem>> load() async {
    final directory = await OutputPaths.outputDirectory();
    final items = <LocalExportItem>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || entity.path.endsWith('.aquarecover.json')) {
        continue;
      }
      try {
        final kind = MediaClassifier.classify(entity.path);
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        items.add(
          LocalExportItem(
            path: entity.path,
            kind: kind,
            sizeBytes: stat.size,
            modified: stat.modified,
          ),
        );
      } on UnsupportedError {
        continue;
      }
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  Future<void> delete(LocalExportItem item) async {
    final directory = await OutputPaths.outputDirectory();
    final root = p.canonicalize(directory.path);
    final target = p.canonicalize(item.path);
    if (!p.isWithin(root, target)) {
      throw StateError('The selected file is outside the export directory.');
    }
    final output = File(target);
    if (await output.exists()) await output.delete();
    final sidecar = File('$target.aquarecover.json');
    if (await sidecar.exists()) await sidecar.delete();
  }
}
