import 'package:flutter/material.dart' show DateTimeRange;
import 'package:hive_ce/hive.dart';
import '../models/processed_message.dart';

enum Period { daily, weekly, monthly }

/// Pure aggregation over ProcessedMessage records. All math uses the
/// effective (override-aware) values so manual corrections and exclusions
/// are always respected.
class AnalyticsService {
  /// Records that count towards analytics.
  List<ProcessedMessage> included(Box<ProcessedMessage> box) {
    return box.values
        .where((r) => r.isIncluded && r.extractionStatus == 'done')
        .toList();
  }

  ({double credit, double debit}) totals(
      List<ProcessedMessage> txns, DateTimeRange range) {
    var credit = 0.0;
    var debit = 0.0;
    for (final t in txns) {
      if (!_inRange(t.effectiveDate, range)) continue;
      if (t.effectiveType == 'credit') {
        credit += t.effectiveAmount;
      } else {
        debit += t.effectiveAmount;
      }
    }
    return (credit: credit, debit: debit);
  }

  List<MapEntry<String, double>> topVendors(
      List<ProcessedMessage> txns, DateTimeRange range) {
    final byVendor = <String, double>{};
    for (final t in txns) {
      if (t.effectiveType != 'debit') continue;
      if (!_inRange(t.effectiveDate, range)) continue;
      final vendor = t.effectiveVendor?.trim();
      if (vendor == null || vendor.isEmpty) continue;
      byVendor[vendor] = (byVendor[vendor] ?? 0.0) + t.effectiveAmount;
    }
    final entries = byVendor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Debit transactions within [range], most-recent first — powers the
  /// per-vendor expansion detail rows (vendor spend is debit-only).
  List<ProcessedMessage> debitTransactionsInRange(
      List<ProcessedMessage> txns, DateTimeRange range) {
    final result = txns
        .where((t) => t.effectiveType == 'debit' && _inRange(t.effectiveDate, range))
        .toList()
      ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    return result;
  }

  /// All transactions (credit and debit) within [range], most-recent first —
  /// powers the dashboard's spending chart (one bar per transaction, colored
  /// by type).
  List<ProcessedMessage> transactionsInRange(
      List<ProcessedMessage> txns, DateTimeRange range) {
    final result = txns.where((t) => _inRange(t.effectiveDate, range)).toList()
      ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    return result;
  }

  /// Tight "current period" window used for summary totals, the vendor
  /// breakdown, and the spending chart — exactly the selected day/week/month,
  /// never a broader rolling window.
  DateTimeRange focusRange(Period period, {DateTime? now}) {
    final n = now ?? DateTime.now();
    switch (period) {
      case Period.daily:
        return DateTimeRange(start: DateTime(n.year, n.month, n.day), end: n);
      case Period.weekly:
        final monday = DateTime(n.year, n.month, n.day - (n.weekday - 1));
        return DateTimeRange(start: monday, end: n);
      case Period.monthly:
        return DateTimeRange(start: DateTime(n.year, n.month, 1), end: n);
    }
  }

  bool _inRange(DateTime d, DateTimeRange range) =>
      !d.isBefore(range.start) && !d.isAfter(range.end);
}
