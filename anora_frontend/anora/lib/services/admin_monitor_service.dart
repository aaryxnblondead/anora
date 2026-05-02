import 'dart:convert';

import 'api_endpoint_service.dart';
import 'storage_service.dart';

class AdminMonitorService {
  AdminMonitorService._();

  static final AdminMonitorService instance = AdminMonitorService._();

  static const String _adminApiKeySetting = 'admin_monitor_api_key';

  String? get storedAdminApiKey {
    final raw = StorageService.instance.settingsBox.get(_adminApiKeySetting);
    if (raw is! String) {
      return null;
    }

    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<void> saveAdminApiKey(String? rawKey) async {
    final trimmed = (rawKey ?? '').trim();
    if (trimmed.isEmpty) {
      await StorageService.instance.settingsBox.delete(_adminApiKeySetting);
      return;
    }
    await StorageService.instance.settingsBox.put(_adminApiKeySetting, trimmed);
  }

  Future<Map<String, dynamic>> fetchOverview({String? adminApiKey}) async {
    final key = (adminApiKey ?? storedAdminApiKey ?? '').trim();
    final headers = <String, String>{
      if (key.isNotEmpty) 'X-Admin-Key': key,
    };

    final response = await ApiEndpointService.instance.get(
      ApiEndpointService.instance.buildUri('/admin/monitor/overview'),
      headers: headers,
      timeout: const Duration(seconds: 45),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Admin access denied. Verify ADMIN_MONITOR_API_KEY.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Admin monitor request failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid admin monitor payload.');
    }

    return decoded;
  }
}
