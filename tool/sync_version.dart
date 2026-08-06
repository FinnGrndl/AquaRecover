import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty || arguments.length > 2) {
    _fail('Usage: dart run tool/sync_version.dart <version> [build-number]');
  }

  final requestedVersion = arguments.first.replaceFirst(RegExp(r'^v'), '');
  if (!RegExp(
    r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$',
  ).hasMatch(requestedVersion)) {
    _fail('Invalid semantic version: ${arguments.first}');
  }

  final pubspec = File('pubspec.yaml');
  final pubspecText = pubspec.readAsStringSync();
  final match = RegExp(
    r'^version: (\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(\d+)$',
    multiLine: true,
  ).firstMatch(pubspecText);
  if (match == null) {
    _fail('pubspec.yaml must contain version: <semver>+<build-number>.');
  }

  final currentVersion = match.group(1)!;
  final currentBuildNumber = int.parse(match.group(2)!);
  final requestedBuildNumber = arguments.length == 2
      ? int.tryParse(arguments[1])
      : null;
  if (arguments.length == 2 &&
      (requestedBuildNumber == null || requestedBuildNumber < 1)) {
    _fail('Build number must be a positive integer.');
  }
  final buildNumber =
      requestedBuildNumber ??
      (requestedVersion == currentVersion
          ? currentBuildNumber
          : currentBuildNumber + 1);
  final versionWithBuild = '$requestedVersion+$buildNumber';

  _replaceExactlyOnce(
    pubspec,
    RegExp(r'^version: .+$', multiLine: true),
    'version: $versionWithBuild',
  );
  _replaceExactlyOnce(
    File('lib/core/app_version.dart'),
    RegExp(r"^const String aquaRecoverVersion = '.+';$", multiLine: true),
    "const String aquaRecoverVersion = '$requestedVersion';",
  );
  _replaceExactlyOnce(
    File('lib/core/app_version.dart'),
    RegExp(r'^const int aquaRecoverBuildNumber = \d+;$', multiLine: true),
    'const int aquaRecoverBuildNumber = $buildNumber;',
  );
  _replaceExactlyOnce(
    File('lib/core/app_version.dart'),
    RegExp(
      r"^const String aquaRecoverVersionWithBuild = '.+';$",
      multiLine: true,
    ),
    "const String aquaRecoverVersionWithBuild = '$versionWithBuild';",
  );
  _replaceExactlyOnce(
    File('README.md'),
    RegExp(r'^Current source version: `[^`]+`\.$', multiLine: true),
    'Current source version: `$versionWithBuild`.',
  );
  _replaceExactlyOnce(
    File('THIRD_PARTY_NOTICES.md'),
    RegExp(r'^Direct dependencies in version [^:]+:$', multiLine: true),
    'Direct dependencies in version $requestedVersion:',
  );
  _replaceExactlyOnce(
    File('.github/ISSUE_TEMPLATE/bug_report.yml'),
    RegExp(r'^      placeholder: .+ or commit SHA$', multiLine: true),
    '      placeholder: $versionWithBuild or commit SHA',
  );

  stdout.writeln(versionWithBuild);
}

void _replaceExactlyOnce(File file, RegExp pattern, String replacement) {
  if (!file.existsSync()) {
    _fail('Missing version target: ${file.path}');
  }
  final input = file.readAsStringSync();
  final matches = pattern.allMatches(input).length;
  if (matches != 1) {
    _fail(
      'Expected one version marker in ${file.path}, found $matches. '
      'Update tool/sync_version.dart with the file format.',
    );
  }
  file.writeAsStringSync(input.replaceFirst(pattern, replacement));
}

Never _fail(String message) {
  stderr.writeln(message);
  exitCode = 64;
  exit(64);
}
