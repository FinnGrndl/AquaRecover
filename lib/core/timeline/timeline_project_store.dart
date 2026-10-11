import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'timeline_project.dart';

/// Saves timelines as small JSON files in the app documents directory. Media
/// stays where it is; projects only reference it by path.
class TimelineProjectStore {
  TimelineProjectStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'AquaRecover Timelines'));
  }

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  Future<File> _fileFor(String id) async {
    if (!_safeId.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'is not a safe project id');
    }
    final dir = await _directory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, '$id.aqtimeline.json'));
  }

  Future<void> save(TimelineProject project) async {
    final file = await _fileFor(project.id);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(project.toJson()),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<TimelineProject?> load(String id) async {
    final file = await _fileFor(id);
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString());
    return TimelineProject.fromJson((json as Map).cast<String, Object?>());
  }

  /// Saved projects, most recently changed first. Unreadable files are
  /// skipped rather than failing the whole list.
  Future<List<TimelineProject>> list() async {
    final dir = await _directory();
    if (!await dir.exists()) return const [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.aqtimeline.json'))
        .cast<File>()
        .toList();
    final stamped = <(DateTime, TimelineProject)>[];
    for (final file in files) {
      try {
        final json = jsonDecode(await file.readAsString());
        stamped.add((
          await file.lastModified(),
          TimelineProject.fromJson((json as Map).cast<String, Object?>()),
        ));
      } on Object {
        continue;
      }
    }
    stamped.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final (_, project) in stamped) project];
  }

  Future<void> delete(String id) async {
    final file = await _fileFor(id);
    if (await file.exists()) await file.delete();
  }
}
