import 'package:flutter_test/flutter_test.dart';
import 'package:flashflow_sentinel/app/data/models/processed_message.dart';

ProcessedMessage _record({
  bool classified = true,
  String status = 'done',
}) {
  return ProcessedMessage(
    msgKey: 'k1',
    body: 'Rs.500 debited from A/c XX123',
    address: 'HDFCBK',
    smsDate: DateTime(2026, 6, 15, 10),
    classifiedAsTransaction: classified,
    classifierProbability: classified ? 0.95 : 0.1,
    extractionStatus: status,
  );
}

void main() {
  test('effective values fall back to AI fields, then defaults', () {
    final r = _record()
      ..aiType = 'credit'
      ..aiAmount = 500.0
      ..aiVendor = 'Zomato';
    expect(r.effectiveType, 'credit');
    expect(r.effectiveAmount, 500.0);
    expect(r.effectiveVendor, 'Zomato');
    expect(r.effectiveDate, r.smsDate); // no aiDate
  });

  test('user override wins over AI values', () {
    final r = _record()
      ..aiType = 'credit'
      ..aiAmount = 500.0
      ..overrideType = 'debit'
      ..overrideAmount = 450.0
      ..overriddenAt = DateTime.now();
    expect(r.effectiveType, 'debit');
    expect(r.effectiveAmount, 450.0);
    expect(r.hasOverride, isTrue);
  });

  test('hallucinated aiDate is replaced by smsDate', () {
    final r = _record()..aiDate = DateTime(2020, 1, 1);
    expect(r.effectiveDate, r.smsDate);
  });

  test('close aiDate is trusted', () {
    final r = _record()..aiDate = DateTime(2026, 6, 14, 22);
    expect(r.effectiveDate, DateTime(2026, 6, 14, 22));
  });

  test('exclusion and user classification flags drive isIncluded', () {
    expect(_record().isIncluded, isTrue);
    expect((_record()..excluded = true).isIncluded, isFalse);
    expect((_record()..userSaysTransaction = false).isIncluded, isFalse);
    expect(_record(classified: false, status: 'skipped').isIncluded, isFalse);
    // user rescues a classifier false negative
    final rescued = _record(classified: false, status: 'done')
      ..userSaysTransaction = true;
    expect(rescued.isIncluded, isTrue);
  });
}
