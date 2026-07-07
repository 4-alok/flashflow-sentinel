import 'package:hive_ce/hive.dart';
import '../../core/utils/date_parsing.dart';

part 'transaction.g.dart';

@HiveType(typeId: 0)
class Transaction extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String rawText;

  @HiveField(2)
  final String? bank;

  @HiveField(3)
  final double amount;

  @HiveField(4)
  final DateTime date;

  @HiveField(5)
  final String type; // 'debit' or 'credit'

  @HiveField(6)
  final String? vendor;

  @HiveField(7)
  final String? account;

  @HiveField(8)
  final double? balance;

  @HiveField(9)
  final String? tid;

  Transaction({
    required this.id,
    required this.rawText,
    this.bank,
    required this.amount,
    required this.date,
    required this.type,
    this.vendor,
    this.account,
    this.balance,
    this.tid,
  });

  // Helper method to create from Generative AI results
  factory Transaction.fromGenerative({
    required String id,
    required String text,
    required Map<String, dynamic> json,
    required DateTime smsDate,
  }) {
    // Extract amount
    double amount = 0.0;
    if (json['amount'] is num) {
      amount = (json['amount'] as num).toDouble();
    } else if (json['amount'] is String) {
      amount = double.tryParse(json['amount'].replaceAll(',', '')) ?? 0.0;
    }

    return Transaction(
      id: id,
      rawText: text,
      bank: json['sender_bank'] ?? json['receiver_bank'],
      amount: amount,
      date: resolveDate(json, smsDate),
      type: json['transaction_type']?.toString().toLowerCase().contains('credit') == true || 
             json['transaction_type']?.toString().toLowerCase().contains('receive') == true
          ? 'credit' 
          : 'debit',
      vendor: json['counterparty'],
      account: json['sender_acc'] ?? json['receiver_acc'],
      balance: (json['balance'] as num?)?.toDouble(),
      tid: json['reference_id'] ?? json['reference_ID'] ?? json['referenceId'],
    );
  }
}
