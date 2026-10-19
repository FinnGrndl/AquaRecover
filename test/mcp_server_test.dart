import 'dart:convert';
import 'dart:io';

import 'package:aqua_recover/mcp/aquarecover_tools.dart';
import 'package:aqua_recover/mcp/media_host.dart';
import 'package:aqua_recover/mcp/mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class _Client {
  _Client(this.server);

  final McpServer server;
  final List<Map<String, Object?>> sent = [];
  var _id = 0;

  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?>? params,
  ]) async {
    final id = ++_id;
    await server.handleLine(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    return sent.lastWhere((message) => message['id'] == id);
  }

  Future<Map<String, Object?>> call(
    String tool,
    Map<String, Object?> arguments,
  ) async {
    final response = await request('tools/call', {
      'name': tool,
      'arguments': arguments,
    });
    return (response['result']! as Map).cast<String, Object?>();
  }
}

void main() {
  late Directory directory;
  late String photo;
  late _Client client;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aqua-mcp');
    final image = img.Image(width: 96, height: 64);
    for (final pixel in image) {
      pixel
        ..r = 30 + pixel.x ~/ 8
        ..g = 120
        ..b = 160 + pixel.y ~/ 4;
    }
    photo = p.join(directory.path, 'reef.jpg');
    await File(photo).writeAsBytes(img.encodeJpg(image));
    final server = buildAquaRecoverMcpServer(
      policy: PathPolicy([directory.path]),
      hostTools: const HostTools.none(),
    );
    client = _Client(server);
    server.serve(const Stream<String>.empty(), (line) {
      client.sent.add((jsonDecode(line) as Map).cast<String, Object?>());
    });
  });

  tearDown(() => directory.delete(recursive: true));

  test('initialize negotiates the protocol and lists tools', () async {
    final init = await client.request('initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'test', 'version': '1'},
    });
    final result = init['result']! as Map;
    expect(result['protocolVersion'], '2025-03-26');
    expect((result['serverInfo']! as Map)['name'], 'aquarecover');

    final tools = await client.request('tools/list');
    final names = [
      for (final tool in ((tools['result']! as Map)['tools']! as List))
        (tool as Map)['name'],
    ];
    expect(
      names,
      containsAll([
        'analyze_media',
        'preview_restoration',
        'restore_image',
        'batch_restore',
        'restore_video',
      ]),
    );
  });

  test('unknown methods return a JSON-RPC error', () async {
    final response = await client.request('resources/list');
    expect((response['error']! as Map)['code'], -32601);
  });

  test('analyze_media suggests a preset for blue water', () async {
    final result = await client.call('analyze_media', {'path': photo});
    final data = result['structuredContent']! as Map;
    expect(data['waterType'], 'blue');
    expect(data['suggestedPreset'], isNotNull);
    expect(data['redLoss'], greaterThan(.5));
  });

  test('preview_restoration returns an image without writing', () async {
    final result = await client.call('preview_restoration', {
      'path': photo,
      'layout': 'side_by_side',
      'adjustments': {'exposure': .2},
    });
    final image = (result['content']! as List).cast<Map>().firstWhere(
      (item) => item['type'] == 'image',
    );
    final decoded = img.decodeJpg(base64Decode(image['data']! as String))!;
    expect(decoded.width, greaterThan(decoded.height * 2));
    expect(directory.listSync(), hasLength(1));
  });

  test(
    'restore_image writes output and sidecar and never overwrites',
    () async {
      final first = await client.call('restore_image', {
        'path': photo,
        'preset': 'vivid',
      });
      final data = first['structuredContent']! as Map;
      expect(File(data['output']! as String).existsSync(), isTrue);
      expect(File(data['sidecar']! as String).existsSync(), isTrue);

      final second = await client.call('restore_image', {'path': photo});
      expect(second['isError'], isTrue);

      final sidecar = await client.call('read_sidecar', {
        'path': data['output'],
      });
      expect((sidecar['structuredContent']! as Map)['preset'], 'vivid');
    },
  );

  test('rejects paths outside the allowed folders and bad arguments', () async {
    final outside = await client.call('analyze_media', {
      'path': p.join(Directory.systemTemp.path, 'elsewhere.jpg'),
    });
    expect(outside['isError'], isTrue);

    final badAdjustment = await client.call('preview_restoration', {
      'path': photo,
      'adjustments': {'warpDrive': 1},
    });
    expect(badAdjustment['isError'], isTrue);
    expect(
      ((badAdjustment['content']! as List).first as Map)['text'],
      contains('warpDrive'),
    );
  });

  test('batch_restore skips earlier exports', () async {
    await client.call('restore_image', {'path': photo});
    final result = await client.call('batch_restore', {
      'directory': directory.path,
      'auto_preset': true,
    });
    final data = result['structuredContent']! as Map;
    expect(data['restored'], 1);
    expect(data['failed'], 0);
  });

  test('video tools explain that ffmpeg is missing', () async {
    final video = p.join(directory.path, 'clip.mp4');
    await File(video).writeAsBytes([0, 1, 2]);
    final result = await client.call('restore_video', {'path': video});
    expect(result['isError'], isTrue);
    expect(
      ((result['content']! as List).first as Map)['text'],
      contains('ffmpeg'),
    );
  });
}
