import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/env.dart';
import 'storage_service.dart';

class ApiEndpointService {
  ApiEndpointService._();

  static final ApiEndpointService instance = ApiEndpointService._();

  static const _overrideKey = 'api_base_url_override';

  String get baseUrl {
    final override = overrideBaseUrl;
    if (override != null) {
      return override;
    }
    return _normalize(Env.apiBaseUrl);
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

  Future<void> ping({Duration timeout = const Duration(seconds: 8)}) async {
    final uri = buildUri('/health');
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode} from $uri');
    }
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
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }
}
