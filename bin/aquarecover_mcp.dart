import 'dart:convert';
import 'dart:io';

import 'package:aqua_recover/core/app_version.dart';
import 'package:aqua_recover/mcp/aquarecover_tools.dart';
import 'package:aqua_recover/mcp/media_host.dart';

const _usage =
    '''
AquaRecover MCP server $aquaRecoverVersion

Serves the Model Context Protocol over stdin/stdout so Claude can analyse,
preview and restore underwater photos and videos on this computer.

Usage: aquarecover_mcp [--allow <folder>]...

  --allow <folder>  Only read and write inside this folder (repeatable).
                    Without --allow every local path the client names is
                    allowed. AQUARECOVER_MCP_ALLOW (path-separator list)
                    works the same way.
  --help            Show this text.
''';

Future<void> main(List<String> args) async {
  final roots = <String>[
    ...?Platform.environment['AQUARECOVER_MCP_ALLOW']
        ?.split(Platform.isWindows ? ';' : ':')
        .where((root) => root.isNotEmpty),
  ];
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--allow' when i + 1 < args.length:
        roots.add(args[++i]);
      case '--help' || '-h':
        stdout.write(_usage);
        return;
      default:
        stderr.write('Unknown argument ${args[i]}\n\n$_usage');
        exitCode = 64;
        return;
    }
  }
  final server = buildAquaRecoverMcpServer(
    policy: PathPolicy(roots),
    log: (message) => stderr.writeln('[aquarecover-mcp] $message'),
  );
  await server.serve(stdin.transform(utf8.decoder), stdout.writeln);
}
