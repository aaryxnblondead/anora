import 'dart:async';

import 'package:flutter/material.dart';

import '../services/admin_monitor_service.dart';
import '../theme/anora_theme.dart';

class AdminWebPortalGate extends StatefulWidget {
  const AdminWebPortalGate({super.key});

  @override
  State<AdminWebPortalGate> createState() => _AdminWebPortalGateState();
}

class _AdminWebPortalGateState extends State<AdminWebPortalGate> {
  final TextEditingController _apiKeyController = TextEditingController();

  Timer? _refreshTimer;
  Map<String, dynamic>? _overview;
  String? _adminApiKey;
  String? _error;
  DateTime? _lastUpdatedAt;
  bool _isLoading = false;
  bool _isSavingKey = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _adminApiKey = AdminMonitorService.instance.storedAdminApiKey;
    if (_adminApiKey != null) {
      _apiKeyController.text = _adminApiKey!;
      unawaited(_refreshOverview());
      _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKeyAndLoad() async {
    final normalized = _apiKeyController.text.trim();
    if (normalized.isEmpty) {
      setState(() {
        _error = 'Admin API key is required.';
      });
      return;
    }

    setState(() {
      _isSavingKey = true;
      _error = null;
    });

    try {
      await AdminMonitorService.instance.saveAdminApiKey(normalized);
      if (!mounted) return;
      setState(() {
        _adminApiKey = normalized;
        _isSavingKey = false;
      });
      await _refreshOverview();
      _startAutoRefresh();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingKey = false;
        _error = 'Failed to save admin key: $error';
      });
    }
  }

  Future<void> _clearApiKey() async {
    _refreshTimer?.cancel();
    await AdminMonitorService.instance.saveAdminApiKey(null);
    if (!mounted) return;
    setState(() {
      _adminApiKey = null;
      _overview = null;
      _error = null;
      _lastUpdatedAt = null;
      _apiKeyController.clear();
    });
  }

  Future<void> _refreshOverview({bool silent = false}) async {
    if (_adminApiKey == null || _adminApiKey!.isEmpty) {
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final overview = await AdminMonitorService.instance.fetchOverview(
        adminApiKey: _adminApiKey,
      );

      if (!mounted) return;
      setState(() {
        _overview = overview;
        _lastUpdatedAt = DateTime.now();
        _isLoading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$error';
      });
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshOverview(silent: true)),
    );
  }

  Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return const <String, dynamic>{};
  }

  int _asInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw) ?? 0;
    }
    return 0;
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Never';
    final local = timestamp.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm:$ss';
  }

  String _formatUptime(int totalSeconds) {
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    }
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    if (_adminApiKey == null || _adminApiKey!.isEmpty) {
      return _AdminApiKeySetup(
        controller: _apiKeyController,
        obscureKey: _obscureKey,
        isSaving: _isSavingKey,
        error: _error,
        onToggleObscure: () => setState(() => _obscureKey = !_obscureKey),
        onSubmit: _saveApiKeyAndLoad,
      );
    }

    final overview = _overview ?? const <String, dynamic>{};
    final service = _asMap(overview['service']);
    final auth = _asMap(overview['auth']);
    final activity = _asMap(overview['activity']);
    final fl = _asMap(overview['federated_learning']);
    final flClients = _asMap(fl['clients']);
    final flRounds = _asMap(fl['rounds']);
    final flModels = _asMap(fl['models']);
    final latestRoundMetrics = _asMap(fl['latest_round_metrics']);
    final recentEvents = overview['recent_events'] is List<dynamic>
        ? overview['recent_events'] as List<dynamic>
        : const <dynamic>[];

    final status = (service['status'] as String?) ?? 'unknown';
    final statusColor = status == 'ok' ? AnoraPalette.success : AnoraPalette.danger;

    return AnoraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Admin Operations Dashboard'),
          actions: [
            IconButton(
              onPressed: _isLoading ? null : () => unawaited(_refreshOverview()),
              tooltip: 'Refresh now',
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              onPressed: _clearApiKey,
              tooltip: 'Sign out admin key',
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            children: [
              AnoraStaggeredReveal(
                order: 0,
                child: AnoraScreenHeader(
                  title: 'Live Monitoring',
                  subtitle: 'Use this view during implementation review to show system health, auth activity, and FL progression.',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: statusColor.withValues(alpha: 0.55)),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              AnoraStaggeredReveal(
                order: 1,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatusChip(
                      label: 'DB Ready',
                      value: ((service['db_ready'] as bool?) ?? false) ? 'Yes' : 'No',
                    ),
                    _StatusChip(
                      label: 'DB Connected',
                      value: ((service['db_connected'] as bool?) ?? false) ? 'Yes' : 'No',
                    ),
                    _StatusChip(
                      label: 'Uptime',
                      value: _formatUptime(_asInt(service['uptime_seconds'])),
                    ),
                    _StatusChip(
                      label: 'Last refresh',
                      value: _formatTimestamp(_lastUpdatedAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AnoraStaggeredReveal(
                order: 2,
                child: _MetricSection(
                  title: 'Authentication & OTP',
                  tiles: [
                    _MetricTileData(title: 'Users', value: _asInt(auth['users_total']).toString(), subtitle: 'total accounts'),
                    _MetricTileData(title: 'Patients', value: _asInt(auth['users_patients']).toString(), subtitle: 'registered'),
                    _MetricTileData(title: 'Clinicians', value: _asInt(auth['users_clinicians']).toString(), subtitle: 'registered'),
                    _MetricTileData(title: 'Active (24h)', value: _asInt(auth['users_active_24h']).toString(), subtitle: 'recent logins'),
                    _MetricTileData(title: 'OTP Requested', value: _asInt(auth['otp_requested_1h']).toString(), subtitle: 'past 1 hour'),
                    _MetricTileData(title: 'OTP Verified', value: _asInt(auth['otp_verified_1h']).toString(), subtitle: 'past 1 hour'),
                    _MetricTileData(title: 'OTP Pending', value: _asInt(auth['otp_pending']).toString(), subtitle: 'unverified'),
                    _MetricTileData(title: 'OTP Locked', value: _asInt(auth['otp_locked_out']).toString(), subtitle: 'attempts exhausted'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AnoraStaggeredReveal(
                order: 3,
                child: _MetricSection(
                  title: 'Care Activity',
                  tiles: [
                    _MetricTileData(title: 'Patient Links', value: _asInt(activity['patient_links_total']).toString(), subtitle: 'active links'),
                    _MetricTileData(title: 'Reports', value: _asInt(activity['reports_total']).toString(), subtitle: 'all time'),
                    _MetricTileData(title: 'Reports (24h)', value: _asInt(activity['reports_24h']).toString(), subtitle: 'new uploads'),
                    _MetricTileData(title: 'Mood Events (24h)', value: _asInt(activity['mood_events_24h']).toString(), subtitle: 'captured'),
                    _MetricTileData(title: 'Alerts (24h)', value: _asInt(activity['emergency_alerts_24h']).toString(), subtitle: 'emergency'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AnoraStaggeredReveal(
                order: 4,
                child: _MetricSection(
                  title: 'Federated Learning',
                  tiles: [
                    _MetricTileData(title: 'FL Clients', value: _asInt(flClients['total']).toString(), subtitle: 'registered'),
                    _MetricTileData(title: 'Active Rounds', value: _asInt(flRounds['active']).toString(), subtitle: 'in progress'),
                    _MetricTileData(title: 'Completed Rounds', value: _asInt(flRounds['completed']).toString(), subtitle: 'historical'),
                    _MetricTileData(title: 'Latest Round', value: _asInt(flRounds['latest_id']).toString(), subtitle: 'round id'),
                    _MetricTileData(title: 'Model Version', value: _asInt(flModels['latest_version']).toString(), subtitle: 'latest deployed'),
                    _MetricTileData(title: 'Client Contributions', value: _asInt(flModels['total_clients_contributed']).toString(), subtitle: 'aggregated'),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AnoraStaggeredReveal(
                order: 5,
                child: AnoraSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Latest FL Metrics',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      if (latestRoundMetrics.isEmpty)
                        Text(
                          'No latest-round metrics available yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        ...latestRoundMetrics.entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${entry.key}: ${entry.value}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AnoraStaggeredReveal(
                order: 6,
                child: AnoraSectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent Activity Feed',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      if (_isLoading && _overview == null)
                        const Center(child: CircularProgressIndicator())
                      else if (recentEvents.isEmpty)
                        Text(
                          'No recent events yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        ...recentEvents.map((event) {
                          final row = event is Map<String, dynamic>
                              ? event
                              : const <String, dynamic>{};
                          final type = (row['event_type'] as String?) ?? 'event';
                          final subject = (row['subject'] as String?) ?? 'unknown';
                          final time = (row['event_time'] as String?) ?? '-';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.bolt_rounded, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$type - $subject',
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  time,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminApiKeySetup extends StatelessWidget {
  const _AdminApiKeySetup({
    required this.controller,
    required this.obscureKey,
    required this.isSaving,
    required this.error,
    required this.onToggleObscure,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool obscureKey;
  final bool isSaving;
  final String? error;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final layout = AnoraLayoutSpec.of(context);

    return AnoraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.isExpanded ? 620 : 540),
            child: Padding(
              padding: EdgeInsets.all(layout.isCompact ? 16 : 24),
              child: AnoraSectionCard(
                emphasis: true,
                padding: EdgeInsets.all(layout.isExpanded ? 30 : 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AnoraScreenHeader(
                      title: 'Admin Review Portal',
                      subtitle: 'Enter ADMIN_MONITOR_API_KEY to open the live operational dashboard.',
                    ),
                    SizedBox(height: layout.sectionGap + 2),
                    TextField(
                      controller: controller,
                      obscureText: obscureKey,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onSubmit(),
                      decoration: InputDecoration(
                        labelText: 'Admin API Key',
                        hintText: 'Paste your ADMIN_MONITOR_API_KEY',
                        suffixIcon: IconButton(
                          onPressed: onToggleObscure,
                          icon: Icon(
                            obscureKey ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    SizedBox(height: layout.minorGap + 8),
                    FilledButton.icon(
                      onPressed: isSaving ? null : onSubmit,
                      icon: const Icon(Icons.admin_panel_settings_rounded),
                      label: Text(isSaving ? 'Opening...' : 'Open Admin Dashboard'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AnoraPalette.border),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AnoraPalette.ink,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _MetricTileData {
  const _MetricTileData({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;
}

class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.title,
    required this.tiles,
  });

  final String title;
  final List<_MetricTileData> tiles;

  @override
  Widget build(BuildContext context) {
    return AnoraSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: tiles
                .map(
                  (tile) => _MetricTile(
                    title: tile.title,
                    value: tile.value,
                    subtitle: tile.subtitle,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AnoraPalette.panelSoft.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AnoraPalette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AnoraPalette.primary,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
