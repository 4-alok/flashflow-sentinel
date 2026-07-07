import 'package:hive_ce/hive.dart';

part 'dataset_message.g.dart';

@HiveType(typeId: 1)
class DatasetMessage extends HiveObject {
  @HiveField(0)
  final String body;

  @HiveField(1)
  final String address;

  @HiveField(2)
  final DateTime date;

  @HiveField(3)
  final bool isTransaction;

  @HiveField(4)
  final Map<String, String>? labels; // Amount, Bank, etc. if manually entered

  DatasetMessage({
    required this.body,
    required this.address,
    required this.date,
    this.isTransaction = true,
    this.labels,
  });
}
