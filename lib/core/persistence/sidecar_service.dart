import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/export_options.dart';
import '../models/lut_profile.dart';
import '../models/raw_video_descriptor.dart';
import '../models/restoration_settings.dart';
import '../models/video_edit_settings.dart';

class SidecarService {
  const SidecarService();

  Future<String> write({
    required String inputPath,
    required String outputPath,
    required RestorationSettings settings,
    required ExportOptions exportOptions,
    required LutProfile lutProfile,
    required VideoEditSettings trim,
    RawVideoDescriptor? rawVideoDescriptor,
  }) async {
    final sidecarPath = '$outputPath.aquarecover.json';
    final payload = <String, Object?>{
      'schema': 'com.aquarecover.edit-sidecar.v1',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'inputName': p.basename(inputPath),
      'outputName': p.basename(outputPath),
      'settings': settings.toJson(),
      'export': exportOptions.toJson(),
      'lut': lutProfile.toJson(),
      'trim': trim.toJson(),
      if (rawVideoDescriptor != null) 'rawVideoDescriptor': rawVideoDescriptor.toJson(),
    };
    final file = File(sidecarPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return sidecarPath;
  }
}
