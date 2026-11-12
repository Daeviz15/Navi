import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Resolves cloud API keys from compile-time `--dart-define` values first,
/// falling back to the local git-ignored `env.json` asset so plain
/// `flutter run` and `flutter build` work out of the box.
class CloudEnvConfig {
  static Map<String, String>? _cached;

  static Future<String> resolveKey(String name, String current) async {
    final trimmed = current.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final map = await _loadAssetEnv();
    return (map[name] ?? '').trim();
  }

  static Future<Map<String, String>> _loadAssetEnv() async {
    final existing = _cached;
    if (existing != null) return existing;
    try {
      final raw = await rootBundle.loadString('env.json');
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final result = <String, String>{
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: (entry.value as String).trim(),
        };
        _cached = result;
        return result;
      }
    } catch (_) {
      // env.json is optional when keys are injected via --dart-define.
    }
    _cached = const {};
    return const {};
  }
}

class CloudHttpResponse {
  const CloudHttpResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class CloudHttpBytesResponse {
  const CloudHttpBytesResponse(this.statusCode, this.bytes);
  final int statusCode;
  final Uint8List bytes;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// Injectable HTTP transport for cloud STT and LLM calls.
abstract interface class CloudHttpTransport {
  Future<CloudHttpResponse> postMultipart({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required String contentType,
    required Uint8List fileBytes,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<CloudHttpResponse> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
  });

  Future<CloudHttpBytesResponse> postJsonBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
    int maxBytes = 4194304,
  }) => Future.value(CloudHttpBytesResponse(501, _emptyBytes));

  void close();
}

final Uint8List _emptyBytes = Uint8List(0);

class DartIoCloudHttpTransport implements CloudHttpTransport {
  DartIoCloudHttpTransport({
    Duration connectionTimeout = const Duration(seconds: 6),
    this.maxResponseBytes = 262144,
  }) : _client = HttpClient()..connectionTimeout = connectionTimeout;

  static const _boundary = '----NaviVoiceBoundary7MA4YWxkTrZu0gW';
  final HttpClient _client;
  final int maxResponseBytes;
  bool _closed = false;

  @override
  Future<CloudHttpResponse> postMultipart({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required String contentType,
    required Uint8List fileBytes,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_closed) throw const SocketException('HTTP transport is closed');
    final payload = _buildMultipartBody(
      fields: fields,
      fileField: fileField,
      fileName: fileName,
      contentType: contentType,
      fileBytes: fileBytes,
    );
    return _send(
      uri: uri,
      headers: {
        ...headers,
        HttpHeaders.contentTypeHeader:
            'multipart/form-data; boundary=$_boundary',
      },
      payload: payload,
      timeout: timeout,
    );
  }

  @override
  Future<CloudHttpResponse> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_closed) throw const SocketException('HTTP transport is closed');
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    return _send(
      uri: uri,
      headers: {
        ...headers,
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
      payload: payload,
      timeout: timeout,
    );
  }

  @override
  Future<CloudHttpBytesResponse> postJsonBytes({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 8),
    int maxBytes = 4194304,
  }) async {
    if (_closed) throw const SocketException('HTTP transport is closed');
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    return () async {
      final request = await _client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (builder.length + chunk.length > maxBytes) {
          throw const FormatException('Cloud binary response exceeded bound');
        }
        builder.add(chunk);
      }
      return CloudHttpBytesResponse(response.statusCode, builder.takeBytes());
    }().timeout(timeout);
  }

  Future<CloudHttpResponse> _send({
    required Uri uri,
    required Map<String, String> headers,
    required Uint8List payload,
    required Duration timeout,
  }) async {
    return () async {
      final request = await _client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (builder.length + chunk.length > maxResponseBytes) {
          throw const FormatException('Cloud response exceeded size bound');
        }
        builder.add(chunk);
      }
      final body = utf8.decode(builder.takeBytes(), allowMalformed: true);
      return CloudHttpResponse(response.statusCode, body);
    }().timeout(timeout);
  }

  Uint8List _buildMultipartBody({
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required String contentType,
    required Uint8List fileBytes,
  }) {
    final builder = BytesBuilder(copy: false);
    for (final entry in fields.entries) {
      builder.add(
        utf8.encode(
          '--$_boundary\r\n'
          'Content-Disposition: form-data; name="${entry.key}"\r\n\r\n'
          '${entry.value}\r\n',
        ),
      );
    }
    builder.add(
      utf8.encode(
        '--$_boundary\r\n'
        'Content-Disposition: form-data; name="$fileField"; filename="$fileName"\r\n'
        'Content-Type: $contentType\r\n\r\n',
      ),
    );
    builder.add(fileBytes);
    builder.add(utf8.encode('\r\n--$_boundary--\r\n'));
    return builder.takeBytes();
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}

