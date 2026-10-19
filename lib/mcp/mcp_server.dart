import 'dart:async';
import 'dart:convert';

/// A tool the server exposes through `tools/list` and `tools/call`.
class McpTool {
  const McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.readOnly = false,
    this.destructive = false,
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final Future<McpToolResult> Function(
    Map<String, Object?> arguments,
    McpCallContext context,
  )
  handler;
  final bool readOnly;
  final bool destructive;

  Map<String, Object?> toJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': {
      'title': title,
      'readOnlyHint': readOnly,
      'destructiveHint': destructive,
      'idempotentHint': readOnly,
      'openWorldHint': false,
    },
  };
}

/// A prompt template exposed through `prompts/list` and `prompts/get`.
class McpPrompt {
  const McpPrompt({
    required this.name,
    required this.description,
    required this.arguments,
    required this.render,
  });

  final String name;
  final String description;
  final List<Map<String, Object?>> arguments;
  final String Function(Map<String, String> arguments) render;
}

/// One content block of a tool result.
sealed class McpContent {
  const McpContent();

  Map<String, Object?> toJson();
}

class McpText extends McpContent {
  const McpText(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};
}

class McpImage extends McpContent {
  const McpImage(this.base64Data, {this.mimeType = 'image/jpeg'});

  final String base64Data;
  final String mimeType;

  @override
  Map<String, Object?> toJson() => {
    'type': 'image',
    'data': base64Data,
    'mimeType': mimeType,
  };
}

class McpToolResult {
  const McpToolResult(this.content, {this.structured, this.isError = false});

  /// A JSON result rendered as text and as structured content.
  factory McpToolResult.json(
    Map<String, Object?> value, {
    List<McpContent> extra = const [],
  }) => McpToolResult([
    McpText(const JsonEncoder.withIndent('  ').convert(value)),
    ...extra,
  ], structured: value);

  factory McpToolResult.error(String message) =>
      McpToolResult([McpText(message)], isError: true);

  final List<McpContent> content;
  final Map<String, Object?>? structured;
  final bool isError;

  Map<String, Object?> toJson() => {
    'content': [for (final item in content) item.toJson()],
    'structuredContent': ?structured,
    if (isError) 'isError': true,
  };
}

/// Thrown by a tool for invalid arguments; reported as a tool error result so
/// the model can correct the call.
class McpToolError implements Exception {
  const McpToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Gives a running tool call a way to report progress when the client asked
/// for it with `_meta.progressToken`.
class McpCallContext {
  McpCallContext._(this._server, this._progressToken);

  final McpServer _server;
  final Object? _progressToken;

  void progress(num done, {num? total, String? message}) {
    final token = _progressToken;
    if (token == null) return;
    _server._notify('notifications/progress', {
      'progressToken': token,
      'progress': done,
      'total': ?total,
      'message': ?message,
    });
  }
}

/// A minimal Model Context Protocol server over newline-delimited JSON-RPC.
///
/// It implements the lifecycle (`initialize`, `ping`), tools and prompts.
/// Requests are handled concurrently; every response is written as one line,
/// and nothing but protocol messages goes to [output].
class McpServer {
  McpServer({
    required this.name,
    required this.version,
    required this.instructions,
    required List<McpTool> tools,
    List<McpPrompt> prompts = const [],
    void Function(String message)? log,
  }) : _tools = {for (final tool in tools) tool.name: tool},
       _prompts = {for (final prompt in prompts) prompt.name: prompt},
       _log = log ?? ((_) {});

  static const supportedProtocolVersions = <String>[
    '2025-06-18',
    '2025-03-26',
    '2024-11-05',
  ];

  final String name;
  final String version;
  final String instructions;
  final Map<String, McpTool> _tools;
  final Map<String, McpPrompt> _prompts;
  final void Function(String message) _log;
  void Function(String line)? _write;

  /// Serves [input] until it closes. Each line must be one JSON-RPC message.
  Future<void> serve(Stream<String> input, void Function(String line) output) {
    _write = output;
    final pending = <Future<void>>[];
    return input
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .forEach((line) => pending.add(handleLine(line)))
        .then((_) => Future.wait(pending));
  }

  /// Handles one incoming line and writes the response, if any.
  Future<void> handleLine(String line) async {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      _send(_error(null, -32700, 'Parse error'));
      return;
    }
    if (message is List) {
      // JSON-RPC batches were removed in 2025-06-18; answer each entry.
      for (final entry in message) {
        await _dispatch(entry);
      }
      return;
    }
    await _dispatch(message);
  }

  Future<void> _dispatch(Object? message) async {
    if (message is! Map) {
      _send(_error(null, -32600, 'Invalid request'));
      return;
    }
    final id = message['id'];
    final method = message['method'];
    if (method is! String) {
      // Responses to server-initiated requests are not used by this server.
      if (id == null || message.containsKey('result')) return;
      _send(_error(id, -32600, 'Invalid request'));
      return;
    }
    final params = message['params'];
    final paramMap = params is Map
        ? params.cast<String, Object?>()
        : const <String, Object?>{};
    if (id == null) {
      // Notifications (initialized, cancelled, ...) need no response.
      return;
    }
    try {
      final result = await _handle(method, paramMap);
      _send({'jsonrpc': '2.0', 'id': id, 'result': result});
    } on _RpcError catch (error) {
      _send(_error(id, error.code, error.message));
    } on Object catch (error, stackTrace) {
      _log('Unhandled error in $method: $error\n$stackTrace');
      _send(_error(id, -32603, 'Internal error: $error'));
    }
  }

  Future<Map<String, Object?>> _handle(
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'initialize':
        final requested = params['protocolVersion'];
        final version = supportedProtocolVersions.contains(requested)
            ? requested! as String
            : supportedProtocolVersions.first;
        return {
          'protocolVersion': version,
          'capabilities': {
            'tools': {'listChanged': false},
            if (_prompts.isNotEmpty) 'prompts': {'listChanged': false},
          },
          'serverInfo': {
            'name': name,
            'title': 'AquaRecover',
            'version': this.version,
          },
          'instructions': instructions,
        };
      case 'ping':
        return const {};
      case 'tools/list':
        return {
          'tools': [for (final tool in _tools.values) tool.toJson()],
        };
      case 'tools/call':
        return (await _callTool(params)).toJson();
      case 'prompts/list':
        return {
          'prompts': [
            for (final prompt in _prompts.values)
              {
                'name': prompt.name,
                'description': prompt.description,
                'arguments': prompt.arguments,
              },
          ],
        };
      case 'prompts/get':
        final prompt = _prompts[params['name']];
        if (prompt == null) {
          throw const _RpcError(-32602, 'Unknown prompt');
        }
        final rawArguments = params['arguments'];
        final arguments = <String, String>{
          if (rawArguments is Map)
            for (final entry in rawArguments.entries)
              '${entry.key}': '${entry.value}',
        };
        return {
          'description': prompt.description,
          'messages': [
            {
              'role': 'user',
              'content': {'type': 'text', 'text': prompt.render(arguments)},
            },
          ],
        };
      default:
        throw _RpcError(-32601, 'Method not found: $method');
    }
  }

  Future<McpToolResult> _callTool(Map<String, Object?> params) async {
    final tool = _tools[params['name']];
    if (tool == null) {
      throw _RpcError(-32602, 'Unknown tool: ${params['name']}');
    }
    final rawArguments = params['arguments'];
    final arguments = rawArguments is Map
        ? rawArguments.cast<String, Object?>()
        : const <String, Object?>{};
    final meta = params['_meta'];
    final context = McpCallContext._(
      this,
      meta is Map ? meta['progressToken'] : null,
    );
    try {
      return await tool.handler(arguments, context);
    } on McpToolError catch (error) {
      return McpToolResult.error(error.message);
    } on Object catch (error) {
      _log('Tool ${tool.name} failed: $error');
      return McpToolResult.error('${tool.name} failed: $error');
    }
  }

  void _notify(String method, Map<String, Object?> params) {
    _send({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  void _send(Map<String, Object?> message) {
    _write?.call(jsonEncode(message));
  }

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

class _RpcError implements Exception {
  const _RpcError(this.code, this.message);

  final int code;
  final String message;
}
