import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crypto_service.dart';
import '../services/report_service.dart';

enum _ScreenState {
  idle,
  previewing,
  encrypting,
  uploading,
  success,
  error,
}

class ShareReportScreen extends ConsumerStatefulWidget {
  const ShareReportScreen({super.key});

  @override
  ConsumerState<ShareReportScreen> createState() => _ShareReportScreenState();
}

class _ShareReportScreenState extends ConsumerState<ShareReportScreen> {
  late DateTime _fromDate;
  late DateTime _toDate;
  final TextEditingController _clinicianIdController = TextEditingController();
  final TextEditingController _publicKeyController = TextEditingController();

  _ScreenState _state = _ScreenState.idle;
  Map<String, dynamic>? _previewSummary;
  String? _reportId;
  String? _errorMessage;

  bool get _isBusy =>
      _state == _ScreenState.previewing ||
      _state == _ScreenState.encrypting ||
      _state == _ScreenState.uploading;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _toDate = now;
    _fromDate = now.subtract(const Duration(days: 7));
  }

  @override
  void dispose() {
    _clinicianIdController.dispose();
    _publicKeyController.dispose();
    super.dispose();
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate.toLocal(),
      firstDate: DateTime(2020),
      lastDate: _toDate.toLocal(),
    );

    if (picked == null) return;

    setState(() {
      _fromDate = DateTime.utc(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate.toLocal(),
      firstDate: _fromDate.toLocal(),
      lastDate: DateTime.now().toLocal(),
    );

    if (picked == null) return;

    setState(() {
      _toDate = DateTime.utc(picked.year, picked.month, picked.day, 23, 59, 59);
    });
  }

  Future<void> _loadPreview() async {
    setState(() {
      _state = _ScreenState.previewing;
      _errorMessage = null;
    });

    try {
      final summary = await ReportService.instance.generateSummary(
        from: _fromDate,
        to: _toDate,
      );
      if (!mounted) return;

      setState(() {
        _previewSummary = summary;
        _state = _ScreenState.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _state = _ScreenState.error;
      });
    }
  }

  Future<void> _encryptAndSend() async {
    final summary = _previewSummary;
    if (summary == null) return;

    final clinicianId = _clinicianIdController.text.trim();
    final publicKeyPem = _publicKeyController.text.trim();

    if (clinicianId.isEmpty || publicKeyPem.isEmpty) {
      setState(() {
        _state = _ScreenState.error;
        _errorMessage = 'Please enter both clinician ID and public key PEM.';
      });
      return;
    }

    try {
      setState(() {
        _state = _ScreenState.encrypting;
        _errorMessage = null;
      });

      final lockedBox = ReportService.instance.buildLockedBox(
        summary: summary,
        clinicianPublicKeyPem: publicKeyPem,
      );

      setState(() {
        _state = _ScreenState.uploading;
      });

      final reportId = await ReportService.instance.uploadLockedBox(
        lockedBox: lockedBox,
        clinicianId: clinicianId,
      );

      if (!mounted) return;
      setState(() {
        _reportId = reportId;
        _state = _ScreenState.success;
      });
    } on CryptoException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _state = _ScreenState.error;
      });
    } on ReportUploadException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Upload failed (${error.statusCode}): ${error.body.isEmpty ? 'No response body.' : error.body}';
        _state = _ScreenState.error;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _state = _ScreenState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _ScreenState.success) {
      return Scaffold(
        appBar: AppBar(title: const Text('Share with Clinician')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Encrypted report sent',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Report ID: ${_reportId ?? '-'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Share with Clinician')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Text(
                'Select date range',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _pickFromDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text('From ${_formatDate(_fromDate)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _pickToDate,
                      icon: const Icon(Icons.calendar_today_rounded),
                      label: Text('To ${_formatDate(_toDate)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Clinician ID',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _clinicianIdController,
                enabled: !_isBusy,
                decoration: const InputDecoration(
                  hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _publicKeyController,
                enabled: !_isBusy,
                minLines: 6,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: "Paste your clinician's public key here",
                ),
              ),
              const SizedBox(height: 20),
              if (_previewSummary != null) ...[
                Text(
                  'Preview Summary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                _SummaryPreviewCard(summary: _previewSummary!),
                const SizedBox(height: 8),
                Text(
                  'Raw journal text is NOT included.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
              ],
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isBusy ? null : _loadPreview,
                      child: const Text('Preview Summary'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_isBusy || _previewSummary == null)
                          ? null
                          : _encryptAndSend,
                      child: const Text('Encrypt & Send'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_isBusy)
            Container(
              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _SummaryPreviewCard extends StatelessWidget {
  const _SummaryPreviewCard({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final entryCount = summary['entry_count'] ?? 0;
    final avgMood = summary['avg_mood_score'] ?? 0;
    final riskCounts = summary['risk_flag_counts'];

    final topFlags = <MapEntry<String, int>>[];
    if (riskCounts is Map) {
      for (final entry in riskCounts.entries) {
        final value = entry.value;
        if (value is int) {
          topFlags.add(MapEntry(entry.key.toString(), value));
        }
      }
      topFlags.sort((a, b) => b.value.compareTo(a.value));
    }

    final topRiskText = topFlags
        .where((entry) => entry.value > 0)
        .take(3)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('  ·  ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Entries: $entryCount', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 6),
            Text('Average mood: $avgMood', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 6),
            Text(
              topRiskText.isEmpty ? 'Top risk flags: none in selected range' : 'Top risk flags: $topRiskText',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              const JsonEncoder.withIndent('  ').convert(
                <String, dynamic>{
                  'period': summary['period'],
                  'entry_count': summary['entry_count'],
                  'avg_mood_score': summary['avg_mood_score'],
                },
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
