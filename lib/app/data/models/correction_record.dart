import 'package:hive_ce/hive.dart';

part 'correction_record.g.dart';

/// Append-only audit log of user corrections, exported as JSONL to improve
/// the training datasets. Never deleted when an override is cleared.
@HiveType(typeId: 3)
class CorrectionRecord extends HiveObject {
  @HiveField(0)
  final String messageKey;

  @HiveField(1)
  final String smsBody;

  @HiveField(2)
  final String smsAddress;

  @HiveField(3)
  final DateTime smsDate;

  @HiveField(4)
  final String? originalAiJson; // rawLlmOutput at time of correction

  @HiveField(5)
  final String correctedJson; // jsonEncode of corrected field map

  @HiveField(6)
  final String reason;

  @HiveField(7)
  final DateTime timestamp;

  @HiveField(8)
  final String kind; // 'extraction_fix'|'classifier_false_positive'|'classifier_false_negative'|'exclusion'

  @HiveField(9)
  final double? classifierProbability;

  CorrectionRecord({
    required this.messageKey,
    required this.smsBody,
    required this.smsAddress,
    required this.smsDate,
    required this.originalAiJson,
    required this.correctedJson,
    required this.reason,
    required this.timestamp,
    required this.kind,
    this.classifierProbability,
  });
}
