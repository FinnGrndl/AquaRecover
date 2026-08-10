import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares complete privacy purpose strings', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    const requiredKeys = <String>[
      'NSCameraUsageDescription',
      'NSLocationWhenInUseUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
    ];

    for (final key in requiredKeys) {
      final match = RegExp(
        '<key>${RegExp.escape(key)}</key>\\s*<string>([^<]+)</string>',
      ).firstMatch(plist);
      expect(match, isNotNull, reason: '$key must be present in Info.plist.');
      expect(
        match!.group(1)!.trim().length,
        greaterThanOrEqualTo(30),
        reason: '$key must clearly explain why access may be requested.',
      );
    }
  });

  test('iOS build configurations require iOS 15 or newer', () {
    for (final path in const <String>[
      'ios/Flutter/Debug.xcconfig',
      'ios/Flutter/Release.xcconfig',
    ]) {
      final configuration = File(path).readAsStringSync();
      expect(
        configuration,
        contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0'),
        reason: '$path must keep the App Store deployment target current.',
      );
    }
  });

  test('iOS declares that it uses no non-exempt encryption', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      RegExp(
        '<key>ITSAppUsesNonExemptEncryption</key>\\s*<false\\s*/>',
      ).hasMatch(plist),
      isTrue,
      reason:
          'App Store uploads must declare that AquaRecover uses no '
          'non-exempt encryption.',
    );
  });

  test('iOS video export requests finite background execution time', () {
    final source = File(
      'ios/Runner/IosVideoProcessor.swift',
    ).readAsStringSync();
    expect(source, contains('beginBackgroundTask'));
    expect(source, contains('endBackgroundTask'));
  });
}
