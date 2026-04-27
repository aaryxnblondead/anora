import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/env.dart';
import 'storage_service.dart';

class ApiEndpointService {
  ApiEndpointService._();

  static final ApiEndpointService instance = ApiEndpointService._();

  static const _overrideKey = 'api_base_url_override';
  int _currentUrlIndex = 0;

  List<String> get _baseUrls {
    final urls = <String>{};

    final override = overrideBaseUrl;
    if (override != null) {
      urls.add(_normalize(override));
    }

    urls.add(_normalize(Env.apiBaseUrl));

    final backup = Env.backupApiBaseUrl;
    if (backup != null && backup.isNotEmpty) {
      urls.add(_normalize(backup));
    }

    return urls.toList(growable: false);
  }

  String get baseUrl {
    final urls = _baseUrls;
    if (urls.isEmpty) {
      return _normalize(Env.apiBaseUrl);
    }
    if (_currentUrlIndex >= urls.length) {
      _currentUrlIndex = 0;
    }
    return urls[_currentUrlIndex];
  }

  String? get overrideBaseUrl {
    final raw = StorageService.instance.settingsBox.get(_overrideKey);
    if (raw is! String) {
      return null;
    }

    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !_isSupportedScheme(parsed.scheme) || parsed.host.trim().isEmpty) {
      return null;
    }

    if (!_isLocalhostAllowed(parsed.host)) {
      return null;
    }

    return _normalize(trimmed);
  }

  Future<void> setOverrideBaseUrl(String? rawUrl) async {
    final trimmed = (rawUrl ?? '').trim();
    if (trimmed.isEmpty) {
      await StorageService.instance.settingsBox.delete(_overrideKey);
      return;
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !_isSupportedScheme(parsed.scheme) || parsed.host.trim().isEmpty) {
      throw ArgumentError('Use a valid http or https URL.');
    }

    if (!_isLocalhostAllowed(parsed.host)) {
      throw ArgumentError('localhost is only allowed in debug builds. Use a cloud URL.');
    }

    await StorageService.instance.settingsBox.put(_overrideKey, _normalize(trimmed));
  }

  Uri buildUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath').replace(queryParameters: queryParameters);
  }

  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final candidates = _candidateUris(uri);
    Object? lastError;
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      try {
        final response = await _requestWithRetry(() => http.get(candidate, headers: headers).timeout(timeout));
        if (response.statusCode == 421 && candidate != candidates.last) {
          _rotateBaseUrl();
          continue;
        }
        _currentUrlIndex = index % _baseUrls.length;
        return response;
      } catch (error) {
        lastError = error;
        if (!_isHostLookupFailure(error) || candidate == candidates.last) {
          rethrow;
        }
        _rotateBaseUrl();
      }
    }
    throw StateError('Request failed: $lastError');
  }

  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final candidates = _candidateUris(uri);
    Object? lastError;
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      try {
        final response = await _requestWithRetry(
          () => http.post(
            candidate,
            headers: headers,
            body: body,
            encoding: encoding,
          ).timeout(timeout),
        );
        if (response.statusCode == 421 && candidate != candidates.last) {
          _rotateBaseUrl();
          continue;
        }
        _currentUrlIndex = index % _baseUrls.length;
        return response;
      } catch (error) {
        lastError = error;
        if (!_isHostLookupFailure(error) || candidate == candidates.last) {
          rethrow;
        }
        _rotateBaseUrl();
      }
    }
    throw StateError('Request failed: $lastError');
  }

  Future<void> ping({Duration timeout = const Duration(seconds: 8)}) async {
    final uri = buildUri('/health');
    final response = await get(uri, timeout: timeout);
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode} from $uri');
    }
  }

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request,
  ) async {
    const maxAttempts = 3;
    const retryDelays = <Duration>[
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];

    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await request();
      } catch (error) {
        lastError = error;
        if (!_isRetryableNetworkError(error) || attempt == maxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(retryDelays[attempt - 1]);
      }
    }

    throw StateError('Request failed: $lastError');
  }

  bool _isRetryableNetworkError(Object error) {
    if (error is TimeoutException) {
      return true;
    }
    if (error is! SocketException) {
      return false;
    }

    final message = error.message.toLowerCase();
    final code = error.osError?.errorCode;
    return message.contains('failed host lookup') ||
        message.contains('temporary failure in name resolution') ||
        code == 7 ||
        code == 110 ||
        code == 11;
  }

  bool _isHostLookupFailure(Object error) {
    if (error is! SocketException) {
      return false;
    }
    final message = error.message.toLowerCase();
    final code = error.osError?.errorCode;
    return message.contains('failed host lookup') || code == 7;
  }

  List<Uri> _candidateUris(Uri original) {
    final urls = _baseUrls;
    if (urls.length <= 1) {
      return <Uri>[original];
    }

    final candidateUris = <Uri>[];
    for (var offset = 0; offset < urls.length; offset++) {
      final urlIndex = (_currentUrlIndex + offset) % urls.length;
      final base = Uri.tryParse(urls[urlIndex]);
      if (base == null || base.host.isEmpty) {
        continue;
      }
      final candidate = Uri(
        scheme: base.scheme,
        userInfo: base.userInfo,
        host: base.host,
        port: base.hasPort ? base.port : 443,
        path: original.path,
        query: original.query,
        fragment: original.fragment,
      );
      if (!candidateUris.any((existing) => existing.toString() == candidate.toString())) {
        candidateUris.add(candidate);
      }
    }

    return candidateUris.isEmpty ? <Uri>[original] : candidateUris;
  }

  void _rotateBaseUrl() {
    final urls = _baseUrls;
    if (urls.length <= 1) {
      return;
    }
    _currentUrlIndex = (_currentUrlIndex + 1) % urls.length;
  }

  bool _isSupportedScheme(String scheme) {
    return scheme == 'http' || scheme == 'https';
  }

  bool _isLocalhostAllowed(String host) {
    if (kDebugMode) {
      return true;
    }
    final lowered = host.toLowerCase();
    return lowered != 'localhost' && lowered != '127.0.0.1' && lowered != '::1';
  }

  String _normalize(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty) {
      return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
    }

    final sanitized = Uri(
      scheme: parsed.scheme,
      userInfo: parsed.userInfo,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: parsed.path,
    ).toString();

    if (sanitized.endsWith('/')) {
      return sanitized.substring(0, sanitized.length - 1);
    }
    return sanitized;
  }
}
