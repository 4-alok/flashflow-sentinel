import 'dart:async';
import 'dart:math' show log, ln10, pow;

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../../data/models/processed_message.dart';
import '../../../data/services/analytics_service.dart';
import '../../../data/services/extraction_queue_service.dart';

class DashboardController extends GetxController {
  final _analytics = AnalyticsService();
  ExtractionQueueService get _queue => Get.find<ExtractionQueueService>();

  final period = Period.daily.obs;
  final periodOffset = 0.obs;
  final creditTotal = 0.0.obs;
  final debitTotal = 0.0.obs;
  final topVendors = <MapEntry<String, double>>[].obs;
  final vendorTxns = <ProcessedMessage>[].obs;
  final vendorTxnsByVendor = <String, List<ProcessedMessage>>{}.obs;
  final chartTxns = <ProcessedMessage>[].obs;
  final includedCount = 0.obs;
  final hasAnyMessages = false.obs;
  final unprocessedCount = 0.obs;
  List<ProcessedMessage> _unprocessedInFocusRange = [];

  late final Box<ProcessedMessage> _box;
  StreamSubscription<BoxEvent>? _boxSub;
  Timer? _debounce;

  @override
  void onInit() {
    super.onInit();
    _box = Hive.box<ProcessedMessage>('processed_messages');
    _recompute();
    ever(period, (_) {
      periodOffset.value = 0;
      _recompute();
    });
    ever(periodOffset, (_) => _recompute());
    // The extraction queue saves records continuously — debounce recomputes.
    _boxSub = _box.watch().listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), _recompute);
    });
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _boxSub?.cancel();
    super.onClose();
  }

  /// "Now", shifted back by [periodOffset] periods (in the active period's
  /// unit) so the dashboard can page through earlier days/weeks/months.
  ///
  /// For a fully-completed past period (offset > 0) this returns the very
  /// end of that period (e.g. 23:59:59.999 of the target day), not today's
  /// current clock time — otherwise a past day's range would be truncated at
  /// "today's time of day", silently dropping everything that happened later
  /// in that day than right now. The live/current period (offset == 0) still
  /// uses the real `now`, since it's still in progress.
  DateTime get _anchorNow {
    final now = DateTime.now();
    final offset = periodOffset.value;
    if (offset == 0) return now;
    switch (period.value) {
      case Period.daily:
        final day = DateTime(now.year, now.month, now.day - offset);
        return DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
      case Period.weekly:
        final day = DateTime(now.year, now.month, now.day - 7 * offset);
        final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59, 999);
      case Period.monthly:
        final firstOfMonth = DateTime(now.year, now.month - offset, 1);
        final firstOfNextMonth = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
        return firstOfNextMonth.subtract(const Duration(milliseconds: 1));
    }
  }

  DateTimeRange get focusRange => _analytics.focusRange(period.value, now: _anchorNow);

  bool get canGoForward => periodOffset.value > 0;

  void goBack() => periodOffset.value++;

  void goForward() {
    if (canGoForward) periodOffset.value--;
  }

  /// Human-readable label for the currently-focused day/week/month.
  String get rangeLabel {
    final fr = focusRange;
    switch (period.value) {
      case Period.daily:
        return periodOffset.value == 0
            ? 'Today'
            : DateFormat('d MMM yyyy').format(fr.start);
      case Period.weekly:
        return periodOffset.value == 0
            ? 'This Week'
            : '${DateFormat('d MMM').format(fr.start)} – ${DateFormat('d MMM').format(fr.end)}';
      case Period.monthly:
        return periodOffset.value == 0
            ? 'This Month'
            : DateFormat('MMMM yyyy').format(fr.start);
    }
  }

  /// Queues the messages in the currently-focused period that haven't been
  /// extracted yet (see [ExtractionQueueService.unprocessedInRange]).
  void processUnprocessed() => _queue.enqueueRecords(_unprocessedInFocusRange);

  /// Title for the spending chart, reflecting the transaction count in the
  /// currently-focused day/week/month (the chart shows exactly this range,
  /// one bar per transaction — never a broader rolling window).
  String get chartTitle {
    final count = chartTransactions.length;
    final noun = count == 1 ? 'transaction' : 'transactions';
    switch (period.value) {
      case Period.daily:
        return '$count $noun today';
      case Period.weekly:
        return '$count $noun this week';
      case Period.monthly:
        return '$count $noun this month';
    }
  }

  /// Credit and debit transactions in the focused range, oldest first — one
  /// bar per transaction on the spending chart (colored by type). Reuses
  /// [chartTxns] (already computed in [_recompute]), just reversed for
  /// left-to-right chronological display order.
  List<ProcessedMessage> get chartTransactions => chartTxns.reversed.toList();

  /// Largest transaction amount in [chartTransactions] — the chart's raw Y
  /// ceiling.
  double get chartMaxY => chartTransactions.fold<double>(
      0, (m, t) => t.effectiveAmount > m ? t.effectiveAmount : m);

  /// [chartMaxY] with 20% headroom (so bars don't touch the top edge),
  /// falling back to a fixed ceiling when there's no data yet.
  double get barChartMaxY => chartMaxY == 0 ? 100 : chartMaxY * 1.2;

  /// Bottom-axis label thinning stride for the bar chart — shows roughly one
  /// label per 6 bars so a busy range doesn't overlap.
  int get chartLabelEvery => (chartTransactions.length / 6).ceil().clamp(1, 31);

  /// Picks a "nice" gridline step (1/2/5 × 10^n) targeting ~4-5 Y-axis labels.
  double yAxisInterval(double maxY) {
    if (maxY <= 0) return 25;
    final raw = maxY / 4;
    final magnitude = pow(10, (log(raw) / ln10).floor()).toDouble();
    final normalized = raw / magnitude;
    final niceStep =
        normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 5 ? 5 : 10;
    return niceStep * magnitude;
  }

  String formatCompactCurrency(double v) =>
      NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹').format(v);

  void _recompute() {
    final all = _box.values.toList();
    hasAnyMessages.value = all.isNotEmpty;

    final txns = _analytics.included(_box);
    final fr = focusRange;
    final t = _analytics.totals(txns, fr);
    creditTotal.value = t.credit;
    debitTotal.value = t.debit;
    topVendors.assignAll(_analytics.topVendors(txns, fr));
    final vt = _analytics.debitTransactionsInRange(txns, fr);
    vendorTxns.assignAll(vt);
    final byVendor = <String, List<ProcessedMessage>>{};
    for (final txn in vt) {
      final vendor = txn.effectiveVendor?.trim();
      if (vendor == null || vendor.isEmpty) continue;
      (byVendor[vendor] ??= []).add(txn);
    }
    vendorTxnsByVendor.assignAll(byVendor);
    chartTxns.assignAll(_analytics.transactionsInRange(txns, fr));
    includedCount.value = txns.length;

    _unprocessedInFocusRange = _queue.unprocessedInRange(all, fr);
    unprocessedCount.value = _unprocessedInFocusRange.length;
  }
}
