import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import '../models/processed_message.dart';
import 'sms_classifier_service.dart';
import 'sms_service.dart';

/// Pulls new SMS from the inbox, classifies them instantly with TF-IDF and
/// persists a [ProcessedMessage] per SMS. Idempotent: already-known keys are
/// never touched, so classification/extraction results survive restarts.
class SmsSyncService extends GetxService {
  static const _watermarkKey = 'lastSyncedSmsDateMs';
  static const _firstRunWindow = Duration(days: 180);

  final isSyncing = false.obs;
  final lastSyncNewCount = 0.obs;

  final _smsService = SmsService();

  Box<ProcessedMessage> get _box =>
      Hive.box<ProcessedMessage>('processed_messages');
  Box get _meta => Hive.box('app_meta');

  /// Returns the keys of newly created transactional (pending) records,
  /// newest first, ready to be handed to the extraction queue.
  Future<List<String>> syncInbox() async {
    if (isSyncing.value) return const [];
    isSyncing.value = true;
    try {
      final watermarkMs = _meta.get(_watermarkKey) as int?;
      final since = watermarkMs != null
          ? DateTime.fromMillisecondsSinceEpoch(watermarkMs)
          : DateTime.now().subtract(_firstRunWindow);

      final messages = await _smsService.fetchMessages(since: since);
      final classifier = Get.find<SmsClassifierService>();

      final pendingKeys = <String>[];
      var newCount = 0;
      DateTime? maxDate;

      for (final msg in messages) {
        final body = msg.body ?? '';
        if (body.isEmpty) continue;

        final date = msg.date!;
        if (maxDate == null || date.isAfter(maxDate)) maxDate = date;

        final key = ProcessedMessage.stableKey(
            id: msg.id, date: msg.date, body: body);
        if (_box.containsKey(key)) continue; // never re-process

        final p = classifier.probability(body);
        final isTxn = p >= classifier.threshold;
        final record = ProcessedMessage(
          msgKey: key,
          body: body,
          address: msg.address ?? 'Unknown',
          smsDate: date,
          classifiedAsTransaction: isTxn,
          classifierProbability: p,
          extractionStatus: isTxn ? 'pending' : 'skipped',
        );
        await _box.put(key, record);
        newCount++;
        if (isTxn) pendingKeys.add(key);
      }

      if (maxDate != null) {
        await _meta.put(_watermarkKey, maxDate.millisecondsSinceEpoch);
      }

      lastSyncNewCount.value = newCount;
      debugPrint('[FLASHFLOW] Sync: $newCount new records '
          '(${pendingKeys.length} pending extraction)');

      // messages are already newest-first, so pendingKeys is too
      return pendingKeys;
    } finally {
      isSyncing.value = false;
    }
  }
}
