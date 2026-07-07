import 'package:hive_ce/hive.dart';
import '../../core/utils/date_parsing.dart';

part 'processed_message.g.dart';

/// Coarse display state for a [ProcessedMessage], independent of any color
/// or icon choice — the view maps this to styling, never re-derives it.
enum MessageStatusKind {
  notTransaction,
  excludedManually,
  extracting,
  failed,
  done,
  unknown,
}

/// Central record for every SMS the app has ever processed.
/// Keyed in the `processed_messages` box by [msgKey] (stable per SMS),
/// which is what guarantees inference never runs twice for a message.
@HiveType(typeId: 2)
class ProcessedMessage extends HiveObject {
  // Identity / raw SMS ([key] is taken by HiveObject)
  @HiveField(0)
  final String msgKey;

  @HiveField(1)
  final String body;

  @HiveField(2)
  final String address;

  @HiveField(3)
  final DateTime smsDate;

  // Classifier verdict
  @HiveField(4)
  final bool classifiedAsTransaction;

  @HiveField(5)
  final double classifierProbability;

  // Extraction state: 'pending' | 'done' | 'failed' | 'skipped'
  @HiveField(6)
  String extractionStatus;

  @HiveField(7)
  String? rawLlmOutput;

  @HiveField(8)
  int extractionAttempts;

  // Parsed LLM fields
  @HiveField(9)
  String? aiType; // normalized 'credit' | 'debit'

  @HiveField(10)
  double? aiAmount;

  @HiveField(11)
  DateTime? aiDate;

  @HiveField(12)
  String? aiVendor;

  @HiveField(13)
  String? aiBank;

  @HiveField(14)
  String? aiAccount;

  @HiveField(15)
  double? aiBalance;

  @HiveField(16)
  String? aiReferenceId;

  @HiveField(17)
  String? aiCurrency;

  // User overrides (null = no override)
  @HiveField(18)
  String? overrideType;

  @HiveField(19)
  double? overrideAmount;

  @HiveField(20)
  String? overrideVendor;

  @HiveField(21)
  DateTime? overrideDate;

  @HiveField(22)
  bool excluded;

  @HiveField(23)
  String? overrideReason; // 'self_transfer'|'wrong_amount'|'wrong_type'|'not_a_transaction'|'missed_transaction'|'other'

  @HiveField(24)
  DateTime? overriddenAt;

  @HiveField(25)
  bool? userSaysTransaction; // null = agrees with classifier

  ProcessedMessage({
    required this.msgKey,
    required this.body,
    required this.address,
    required this.smsDate,
    required this.classifiedAsTransaction,
    required this.classifierProbability,
    required this.extractionStatus,
    this.rawLlmOutput,
    this.extractionAttempts = 0,
    this.aiType,
    this.aiAmount,
    this.aiDate,
    this.aiVendor,
    this.aiBank,
    this.aiAccount,
    this.aiBalance,
    this.aiReferenceId,
    this.aiCurrency,
    this.overrideType,
    this.overrideAmount,
    this.overrideVendor,
    this.overrideDate,
    this.excluded = false,
    this.overrideReason,
    this.overriddenAt,
    this.userSaysTransaction,
  });

  // Effective values: user override > LLM parse > SMS metadata.
  bool get isTransaction => userSaysTransaction ?? classifiedAsTransaction;
  bool get isIncluded =>
      isTransaction && !excluded && extractionStatus != 'skipped';
  String get effectiveType => overrideType ?? aiType ?? 'debit';
  double get effectiveAmount => overrideAmount ?? aiAmount ?? 0.0;
  /// AI date with the hallucination guard applied (falls back to smsDate).
  DateTime get guardedAiDate => guardedDate(aiDate, smsDate);
  DateTime get effectiveDate => overrideDate ?? guardedAiDate;
  String? get effectiveVendor => overrideVendor ?? aiVendor;
  bool get hasOverride => overriddenAt != null;

  /// '-' for a debit, '+' for a credit — the sign to prefix an amount with.
  String get amountSign => effectiveType == 'debit' ? '-' : '+';

  /// Which coarse state this record is in, for status-chip/icon display.
  MessageStatusKind get statusKind {
    if (!isTransaction) return MessageStatusKind.notTransaction;
    if (excluded) return MessageStatusKind.excludedManually;
    switch (extractionStatus) {
      case 'pending':
        return MessageStatusKind.extracting;
      case 'failed':
        return MessageStatusKind.failed;
      case 'done':
        return MessageStatusKind.done;
      default:
        return MessageStatusKind.unknown;
    }
  }

  /// Human-readable label matching [statusKind].
  String get statusLabel {
    switch (statusKind) {
      case MessageStatusKind.notTransaction:
        return userSaysTransaction == false
            ? 'Marked not a transaction'
            : 'Not a transaction';
      case MessageStatusKind.excludedManually:
        return 'Excluded (${overrideReason ?? 'manual'})';
      case MessageStatusKind.extracting:
        return 'Extracting…';
      case MessageStatusKind.failed:
        return 'Extraction failed — tap menu to retry';
      case MessageStatusKind.done:
        return effectiveVendor ?? aiBank ?? 'Transaction';
      case MessageStatusKind.unknown:
        return extractionStatus;
    }
  }

  /// Stable key for an SMS: prefer the provider id, fall back to
  /// timestamp + body hash.
  static String stableKey({int? id, DateTime? date, required String body}) {
    if (id != null) return id.toString();
    return '${date?.millisecondsSinceEpoch ?? 0}_${body.hashCode}';
  }
}
