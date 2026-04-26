import 'package:anora/state/clinician_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Clinician inbox state', () {
    test('emergency alerts are created unread', () {
      final alert = PatientRecord.fromEmergencyAlert(
        {
          'alert_id': 'alert-123',
          'clinician_id': 'clinician-9',
          'priority': 'high',
          'created_at': '2026-04-26T09:30:00Z',
        },
      );

      expect(alert.reportId, 'alert-123');
      expect(alert.clinicianId, 'clinician-9');
      expect(alert.isEmergencyAlert, isTrue);
      expect(alert.isUnread, isTrue);
      expect(alert.alertPriority, 'high');
    });

    test('inbox records sort newest first across reports and alerts', () {
      final olderReport = PatientRecord(
        patientLabel: 'Patient A',
        reportId: 'report-old',
        receivedAt: DateTime.utc(2026, 4, 25, 8, 0),
        clinicianId: 'clinician-9',
        entryCount: 3,
        avgMoodScore: 0.7,
        riskFlagCounts: const <String, int>{},
        topEmotion: 'Calm',
        isDecrypted: false,
        encryptedKeyB64: null,
        encryptedPayload: null,
        riskTrend: null,
      );
      final newerAlert = PatientRecord.fromEmergencyAlert(
        {
          'alert_id': 'alert-new',
          'clinician_id': 'clinician-9',
          'priority': 'critical',
          'created_at': '2026-04-26T10:00:00Z',
        },
      );

      final state = ClinicianReportsState(
        records: [olderReport],
        alerts: [newerAlert],
        unreadAlertIds: {'alert-new'},
      );

      final inbox = state.inboxRecords;

      expect(inbox.first.reportId, 'alert-new');
      expect(inbox.last.reportId, 'report-old');
      expect(state.unreadAlertCount, 1);
    });
  });
}