import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dive_log.dart';

/// Keeps the logbook as one JSON file in the app documents directory, like
/// the timeline project store. Photos and videos are only referenced.
class DiveLogStore {
  DiveLogStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'AquaRecover Logbook'));
  }

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'logbook.aqlog.json'));
  }

  /// The saved log, or an empty one when nothing was saved yet. A damaged
  /// file is kept aside as `.damaged` instead of being overwritten later.
  Future<DiveLog> load() async {
    final file = await _file();
    if (!await file.exists()) return const DiveLog();
    try {
      final json = jsonDecode(await file.readAsString());
      return DiveLog.fromJson((json as Map).cast<String, Object?>());
    } on Object {
      await file.rename('${file.path}.damaged');
      return const DiveLog();
    }
  }

  Future<void> save(DiveLog log) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(log.toJson()),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
