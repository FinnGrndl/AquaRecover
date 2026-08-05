import 'dart:io';

import 'package:path/path.dart' as p;

class FolderExportService {
  const FolderExportService();

  Future<String> copyToDirectory({
    required String sourcePath,
    required String directoryPath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Export source not found.', sourcePath);
    }
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw FileSystemException(
        'The selected export folder is unavailable.',
        directoryPath,
      );
    }

    var destination = p.join(directory.path, p.basename(source.path));
    if (p.equals(p.canonicalize(source.path), p.canonicalize(destination))) {
      return source.path;
    }
    destination = await _availablePath(destination);
    await source.copy(destination);
    return destination;
  }

  Future<String> _availablePath(String requestedPath) async {
    if (!await File(requestedPath).exists()) return requestedPath;
    final directory = p.dirname(requestedPath);
    final stem = p.basenameWithoutExtension(requestedPath);
    final extension = p.extension(requestedPath);
    for (var suffix = 2; suffix < 10000; suffix++) {
      final candidate = p.join(directory, '${stem}_$suffix$extension');
      if (!await File(candidate).exists()) return candidate;
    }
    throw FileSystemException(
      'Could not create a unique export file name.',
      requestedPath,
    );
  }
}
