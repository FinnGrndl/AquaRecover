import 'dart:io';

import 'package:aqua_recover/core/legal/app_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('privacy manifests declare file timestamp reasons and no tracking', () {
    for (final path in const [
      'ios/Runner/PrivacyInfo.xcprivacy',
      'macos/Runner/PrivacyInfo.xcprivacy',
    ]) {
      final manifest = File(path).readAsStringSync();
      expect(
        manifest,
        matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')),
        reason: path,
      );
      expect(
        manifest,
        contains('NSPrivacyAccessedAPICategoryFileTimestamp'),
        reason: '$path: the app reads file dates through dart:io and Swift.',
      );
      expect(manifest, contains('<string>C617.1</string>'), reason: path);
      expect(manifest, contains('<string>3B52.1</string>'), reason: path);
    }
  });

  test('Android can save exports to the gallery on Android 7 to 9', () {
    const write =
        '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />';
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains(write));
    // The bootstrap script regenerates the manifest with the same list.
    final bootstrap = File(
      'scripts/bootstrap_flutter_project.sh',
    ).readAsStringSync();
    final declared = RegExp(
      r'<uses-permission android:name="[^"]+"[^>]*/>',
    ).allMatches(manifest).map((m) => m.group(0)!);
    for (final permission in declared) {
      expect(bootstrap, contains(permission));
    }
  });

  test('desktop windows keep a minimum size', () {
    expect(
      File('macos/Runner/MainFlutterWindow.swift').readAsStringSync(),
      contains('contentMinSize'),
    );
    expect(
      File('windows/runner/win32_window.cpp').readAsStringSync(),
      contains('ptMinTrackSize'),
    );
  });

  test('macOS Info.plist has the Mac App Store category and export flag', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      matches(
        RegExp(r'<key>LSApplicationCategoryType</key>\s*<string>public\.app-'),
      ),
    );
    expect(
      plist,
      matches(RegExp(r'<key>ITSAppUsesNonExemptEncryption</key>\s*<false/>')),
    );
  });

  test('third-party notices list every direct dependency at its version', () {
    final lock = File('pubspec.lock').readAsStringSync();
    final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();
    final direct = RegExp(
      r'\n  (\S+):\n    dependency: "direct main"\n'
      r'(?:      .*\n|    description:.*\n)*?'
      r'    source: hosted\n    version: "([^"]+)"',
    ).allMatches(lock).toList();
    expect(direct, isNotEmpty);
    for (final match in direct) {
      final row = '| ${match[1]} | ${match[2]} |';
      expect(notices, contains(row), reason: 'Missing or stale: $row');
    }
  });

  group('registerAppLicenses', () {
    tearDown(LicenseRegistry.reset);

    Future<List<String>> packages(TargetPlatform platform) async {
      LicenseRegistry.reset();
      registerAppLicenses(platform: platform);
      final names = <String>[];
      await for (final entry in LicenseRegistry.licenses) {
        names.addAll(entry.packages);
      }
      return names;
    }

    test('adds the app and OpenStreetMap notices everywhere', () async {
      final names = await packages(TargetPlatform.iOS);
      expect(names, containsAll(['AquaRecover', 'OpenStreetMap']));
      expect(names, isNot(contains('AndroidX Media3')));
    });

    test('adds AndroidX Media3 on Android', () async {
      expect(
        await packages(TargetPlatform.android),
        contains('AndroidX Media3'),
      );
    });
  });
}
