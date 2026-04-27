import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/clinician_crypto_service.dart';
import '../services/report_service.dart';
import '../services/storage_service.dart';

final clinicianFeedProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final clinicianId = StorageService.instance.settingsBox.get('clinician_id');
  if (clinicianId == null || clinicianId is! String || clinicianId.isEmpty) {
    // This should ideally not happen if the user is on this screen.
    throw Exception('Clinician ID not found. Please log in again.');
  }
  return ReportService.instance.fetchFeedForClinician(clinicianId);
});

class PatientFeedTab extends ConsumerWidget {
  const PatientFeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(clinicianFeedProvider);

    return feedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error fetching feed: $err'),
        ),
      ),
      data: (feedItems) {
        if (feedItems.isEmpty) {
          return const Center(child: Text('No patient updates yet.'));
        }
        return RefreshIndicator(
          onRefresh: () => ref.refresh(clinicianFeedProvider.future),
          child: ListView.builder(
            itemCount: feedItems.length,
            itemBuilder: (context, index) {
              final item = feedItems[index];
              return FeedItemCard(item: item);
            },
          ),
        );
      },
    );
  }
}

class FeedItemCard extends StatelessWidget {
  const FeedItemCard({super.key, required this.item});

  final Map<String, dynamic> item;

  Map<String, dynamic> _decryptPayload(Map<String, dynamic> lockedBox) {
    try {
      final encryptedKey = lockedBox['encrypted_key'] as String;
      final encryptedPayload = (lockedBox['encrypted_payload'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value.toString()));

      final decryptedJson = ClinicianCryptoService.instance.decryptReportPayload(
        encryptedKeyB64: encryptedKey,
        encryptedPayload: encryptedPayload,
      );
      return jsonDecode(decryptedJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Decryption failed for item ${item['id']}: $e');
      return {'error': 'Failed to decrypt payload. The key may be incorrect or data corrupted.'};
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourceType = item['source_type'] as String?;
    final lockedBox = item['locked_box'] as Map<String, dynamic>?;
    
    Widget content;
    IconData icon;

    if (lockedBox != null) {
      final decrypted = _decryptPayload(lockedBox);

      if (decrypted.containsKey('error')) {
        content = Text('Error: ${decrypted['error']}', style: TextStyle(color: Theme.of(context).colorScheme.error));
        icon = Icons.error_outline;
      } else {
        switch (sourceType) {
          case 'mood_event':
            icon = Icons.sentiment_very_satisfied;
            content = _buildMoodEventContent(decrypted);
            break;
          case 'shared_entry':
            icon = Icons.article_outlined;
            content = _buildSharedEntryContent(decrypted);
            break;
          case 'emergency_alert':
            icon = Icons.warning_amber_rounded;
            content = _buildEmergencyAlertContent(decrypted);
            break;
          default:
            icon = Icons.question_mark;
            content = Text('Unknown event type: $sourceType');
        }
      }
    } else {
      icon = Icons.info_outline;
      content = Text('Event of type "$sourceType" with no details.');
    }

    final timestampStr = item['event_timestamp'] ?? item['created_at'];
    final timestamp = DateTime.tryParse(timestampStr ?? '')?.toLocal();
    final formattedTime = timestamp != null ? DateFormat.yMMMd().add_jm().format(timestamp) : 'Unknown time';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: _getIconColor(sourceType, context)),
        title: Text(
          '${_getTitle(sourceType)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            content,
            const SizedBox(height: 8),
            Text(
              'Patient ID: ${item['patient_device_id']}\n$formattedTime',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _getTitle(String? sourceType) {
    switch (sourceType) {
      case 'mood_event': return 'Mood Update';
      case 'shared_entry': return 'Shared Journal Entry';
      case 'emergency_alert': return 'Emergency Alert';
      default: return 'Update';
    }
  }

  Color? _getIconColor(String? sourceType, BuildContext context) {
    switch (sourceType) {
      case 'emergency_alert': return Theme.of(context).colorScheme.error;
      case 'shared_entry': return Theme.of(context).colorScheme.primary;
      case 'mood_event': return Colors.green.shade600;
      default: return Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    }
  }

  Widget _buildMoodEventContent(Map<String, dynamic> data) {
    final moodScore = data['mood_score'] as num?;
    final moodLabels = (data['mood_labels'] as List?)?.cast<String>() ?? [];
    return Text('Score: ${moodScore?.toStringAsFixed(2) ?? 'N/A'}\nLabels: ${moodLabels.join(', ')}');
  }

  Widget _buildSharedEntryContent(Map<String, dynamic> data) {
    final text = data['text'] as String?;
    return Text(text ?? 'No content shared.', maxLines: 2, overflow: TextOverflow.ellipsis);
  }

  Widget _buildEmergencyAlertContent(Map<String, dynamic> data) {
    final snippet = data['text_snippet'] as String?;
    return Text(
      'Trigger: "${snippet ?? 'N/A'}"',
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }
}