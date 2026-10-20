import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Attribution for the OpenStreetMap tiles in the dive logbook map.
const openStreetMapNotice =
    'Map data © OpenStreetMap contributors.\n\n'
    'The dive logbook map loads tiles from the OpenStreetMap Foundation tile '
    'servers. OpenStreetMap data is available under the Open Data Commons '
    'Open Database License (ODbL) 1.0.\n\n'
    'https://www.openstreetmap.org/copyright\n'
    'https://opendatacommons.org/licenses/odbl/1-0/';

/// Adds licenses that pub packages do not register on their own: the app's
/// own license, the OpenStreetMap attribution, and, on Android, the AndroidX
/// Media3 libraries linked by the native video export.
void registerAppLicenses({AssetBundle? bundle, TargetPlatform? platform}) {
  final assets = bundle ?? rootBundle;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'AquaRecover',
    ], await assets.loadString('LICENSE'));
    yield const LicenseEntryWithLineBreaks([
      'OpenStreetMap',
    ], openStreetMapNotice);
    if ((platform ?? defaultTargetPlatform) == TargetPlatform.android) {
      final apache = await assets.loadString('assets/licenses/APACHE-2.0.txt');
      yield LicenseEntryWithLineBreaks(
        const ['AndroidX Media3'],
        'AndroidX Media3 (media3-transformer, media3-effect, media3-common) '
        'and the AndroidX and Guava libraries it depends on.\n'
        'Copyright The Android Open Source Project and Google LLC.\n\n'
        '$apache',
      );
    }
  });
}
