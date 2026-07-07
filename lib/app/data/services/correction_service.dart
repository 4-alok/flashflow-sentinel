import 'dart:convert';

import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import '../models/correction_record.dart';
import '../models/processed_message.dart';
import 'extraction_queue_service.dart';

/// Applies user corrections to [ProcessedMessage] records and keeps the
/// append-only [CorrectionRecord] log used to build retraining datasets.
class CorrectionService extends GetxService {
  Box<CorrectionRecord> get _corrections =>
      Hive.box<CorrectionRecord>('corrections');

  /// Overrides one or more extracted fields and/or the exclusion flag.
  /// Only non-null parameters are applied; original ai* values are untouched.
  Future<void> applyFieldOverride({
    required ProcessedMessage record,
    String? type,
    double? amount,
    String? vendor,
    DateTime? date,
    bool? excluded,
    required String reason,
  }) async {
    if (type != null) record.overrideType = type;
    if (amount != null) record.overrideAmount = amount;
    if (vendor != null) record.overrideVendor = vendor;
    if (date != null) record.overrideDate = date;
    if (excluded != null) record.excluded = excluded;
    record.overrideReason = reason;
    record.overriddenAt = DateTime.now();
    await record.save();

    await _log(
      record,
      kind: excluded == true ? 'exclusion' : 'extraction_fix',
      reason: reason,
    );
  }

  /// The classifier (or the user previously) said transaction, but it isn't
  /// one — e.g. an OTP that slipped through. Keeps ai* fields for the record.
  Future<void> markNotATransaction(ProcessedMessage record) async {
    record.userSaysTransaction = false;
    record.extractionStatus = 'skipped';
    record.overrideReason = 'not_a_transaction';
    record.overriddenAt = DateTime.now();
    await record.save();

    await _log(
      record,
      kind: 'classifier_false_positive',
      reason: 'not_a_transaction',
    );
  }

  /// The classifier skipped this message but it IS a transaction —
  /// queue it for extraction.
  Future<void> markAsTransaction(
      ProcessedMessage record, ExtractionQueueService queue) async {
    record.userSaysTransaction = true;
    record.extractionStatus = 'pending';
    record.extractionAttempts = 0;
    record.overrideReason = 'missed_transaction';
    record.overriddenAt = DateTime.now();
    await record.save();

    await _log(
      record,
      kind: 'classifier_false_negative',
      reason: 'missed_transaction',
    );

    queue.enqueue([record.msgKey]);
    queue.resume();
  }

  /// Removes all overrides (keeps the correction log — it is append-only).
  Future<void> clearOverride(ProcessedMessage record) async {
    record.overrideType = null;
    record.overrideAmount = null;
    record.overrideVendor = null;
    record.overrideDate = null;
    record.excluded = false;
    record.overrideReason = null;
    record.overriddenAt = null;
    record.userSaysTransaction = null;
    await record.save();
  }

  Future<void> _log(ProcessedMessage record,
      {required String kind, required String reason}) async {
    await _corrections.add(CorrectionRecord(
      messageKey: record.msgKey,
      smsBody: record.body,
      smsAddress: record.address,
      smsDate: record.smsDate,
      originalAiJson: record.rawLlmOutput,
      correctedJson: jsonEncode({
        'transaction_type': record.isTransaction ? record.effectiveType : null,
        'amount': record.isTransaction ? record.effectiveAmount : null,
        'counterparty_name': record.effectiveVendor,
        'date': record.effectiveDate.toIso8601String(),
        'excluded': record.excluded,
        'is_transaction': record.isTransaction,
      }),
      reason: reason,
      timestamp: DateTime.now(),
      kind: kind,
      classifierProbability: record.classifierProbability,
    ));
  }
}
