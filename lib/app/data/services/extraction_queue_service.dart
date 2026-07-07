import 'dart:collection';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/utils/date_parsing.dart';
import '../models/processed_message.dart';
import 'generative_extractor_service.dart';

/// Sequential background queue that runs the generative SLM over pending
/// [ProcessedMessage] records. Each result is persisted immediately, so a
/// message is extracted at most once for the lifetime of the install.
class ExtractionQueueService extends GetxService with WidgetsBindingObserver {
  static const _maxAttempts = 2;

  /// Only messages within this window of "now" are auto-queued for
  /// extraction after a sync; older ones wait for an explicit user request
  /// (see [enqueueOlderPending]) so a fresh install doesn't burn battery/time
  /// running inference over months of historical SMS nobody asked for yet.
  static const autoExtractWindow = Duration(days: 60);

  final isRunning = false.obs;
  final isPaused = false.obs;
  final totalQueued = 0.obs;
  final completedCount = 0.obs;
  final currentKey = RxnString();

  final _queue = Queue<String>();
  final _queued = <String>{};

  Box<ProcessedMessage> get _box =>
      Hive.box<ProcessedMessage>('processed_messages');
  GenerativeExtractorService get _extractor =>
      Get.find<GenerativeExtractorService>();

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    // Keep the screen on while actively extracting so a long extraction run
    // isn't interrupted by the device dimming/locking mid-inference.
    ever(isRunning, (running) {
      if (running) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      pause();
    } else if (state == AppLifecycleState.resumed) {
      resume();
    }
  }

  /// Adds keys to the queue (deduped, callers pass newest-first) and starts
  /// the loop if idle.
  void enqueue(List<String> keys) {
    for (final key in keys) {
      if (_queued.add(key)) {
        _queue.add(key);
        totalQueued.value++;
      }
    }
    _startLoop();
  }

  bool _isRetryable(ProcessedMessage r) =>
      r.extractionStatus == 'pending' ||
      (r.extractionStatus == 'failed' && r.extractionAttempts < _maxAttempts);

  /// Queues every record left 'pending' (e.g. after an app kill) plus
  /// 'failed' ones that still have attempts left — but only within
  /// [autoExtractWindow] of now. Older backlog is surfaced via
  /// [countOlderPending] and processed on demand via [enqueueOlderPending].
  void enqueueAllPending() {
    final cutoff = DateTime.now().subtract(autoExtractWindow);
    final keys = _box.values
        .where((r) => _isRetryable(r) && !r.smsDate.isBefore(cutoff))
        .toList()
      ..sort((a, b) => b.smsDate.compareTo(a.smsDate));
    enqueue(keys.map((r) => r.msgKey).toList());
  }

  /// Count of retryable records older than [autoExtractWindow] — the backlog
  /// not auto-queued by [enqueueAllPending].
  int countOlderPending(Iterable<ProcessedMessage> records) {
    final cutoff = DateTime.now().subtract(autoExtractWindow);
    return records
        .where((r) => _isRetryable(r) && r.smsDate.isBefore(cutoff))
        .length;
  }

  /// Explicitly queues the older backlog (see [countOlderPending]) and
  /// resumes the queue if it was idle/paused.
  void enqueueOlderPending(Iterable<ProcessedMessage> records) {
    final cutoff = DateTime.now().subtract(autoExtractWindow);
    final keys = records
        .where((r) => _isRetryable(r) && r.smsDate.isBefore(cutoff))
        .toList()
      ..sort((a, b) => b.smsDate.compareTo(a.smsDate));
    enqueue(keys.map((r) => r.msgKey).toList());
    resume();
  }

  /// Retryable records whose [ProcessedMessage.smsDate] falls in [range] —
  /// used by the Dashboard to explain (and offer to fix) a period that looks
  /// empty only because its messages haven't been extracted yet.
  List<ProcessedMessage> unprocessedInRange(
      Iterable<ProcessedMessage> records, DateTimeRange range) {
    return records
        .where((r) =>
            _isRetryable(r) &&
            !r.smsDate.isBefore(range.start) &&
            !r.smsDate.isAfter(range.end))
        .toList()
      ..sort((a, b) => b.smsDate.compareTo(a.smsDate));
  }

  /// Queues an arbitrary set of records (already filtered by the caller, e.g.
  /// via [unprocessedInRange]) and resumes the queue if it was idle/paused.
  void enqueueRecords(Iterable<ProcessedMessage> records) {
    final keys = records.where(_isRetryable).toList()
      ..sort((a, b) => b.smsDate.compareTo(a.smsDate));
    enqueue(keys.map((r) => r.msgKey).toList());
    resume();
  }

  /// Halts after the in-flight message finishes.
  void pause() => isPaused.value = true;

  void resume() {
    isPaused.value = false;
    _startLoop();
  }

  /// Resets a record's attempts and re-runs it.
  Future<void> retry(String key) async {
    final record = _box.get(key);
    if (record == null) return;
    record.extractionAttempts = 0;
    record.extractionStatus = 'pending';
    await record.save();
    _queued.remove(key);
    enqueue([key]);
    resume();
  }

  void _startLoop() {
    if (isRunning.value || isPaused.value || _queue.isEmpty) return;
    isRunning.value = true;
    _runLoop();
  }

  Future<void> _runLoop() async {
    try {
      while (_queue.isNotEmpty && !isPaused.value) {
        final key = _queue.removeFirst();
        _queued.remove(key);
        currentKey.value = key;

        final record = _box.get(key);
        if (record == null ||
            record.extractionStatus == 'done' ||
            record.userSaysTransaction == false ||
            record.extractionAttempts >= _maxAttempts) {
          completedCount.value++;
          continue;
        }

        if (!_extractor.isLoaded.value) {
          await _extractor.loadModel();
          if (!_extractor.isLoaded.value) {
            // Model unavailable — put the key back and stop; resume() retries.
            if (_queued.add(key)) _queue.addFirst(key);
            isPaused.value = true;
            break;
          }
        }

        final result = await _extractor.extractFromSms(record.body);
        record.extractionAttempts++;

        if (result.containsKey('raw_output')) {
          record.rawLlmOutput = result['raw_output'].toString();
        }

        if (result.containsKey('error')) {
          record.extractionStatus =
              record.extractionAttempts >= _maxAttempts ? 'failed' : 'pending';
          if (record.extractionStatus == 'pending' && _queued.add(key)) {
            _queue.add(key); // one more try at the back of the queue
            totalQueued.value++;
          }
        } else {
          _applyResult(record, result);
          record.extractionStatus = 'done';
        }

        await record.save();
        completedCount.value++;
        // Yield so list scrolling stays smooth between inferences.
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      debugPrint('[FLASHFLOW] Extraction queue error: $e');
    } finally {
      currentKey.value = null;
      isRunning.value = false;
      if (_queue.isEmpty) {
        totalQueued.value = 0;
        completedCount.value = 0;
      }
    }
  }

  void _applyResult(ProcessedMessage record, Map<String, dynamic> json) {
    record.aiType = normalizeType(json['transaction_type']);
    record.aiAmount = parseAmount(json['amount']);
    record.aiDate = parseLlmDate(json, record.smsDate);
    record.aiVendor =
        (json['counterparty_name'] ?? json['counterparty'])?.toString();
    record.aiBank = (json['sender_bank'] ?? json['receiver_bank'])?.toString();
    record.aiAccount =
        (json['sender_acc'] ?? json['receiver_acc'])?.toString();
    record.aiBalance = parseAmount(json['balance_after'] ?? json['balance']);
    record.aiReferenceId = (json['reference_id'] ??
            json['reference_ID'] ??
            json['referenceId'])
        ?.toString();
    record.aiCurrency = json['currency']?.toString();
  }

  /// Same credit/receive heuristic as Transaction.fromGenerative.
  static String normalizeType(dynamic transactionType) {
    final t = transactionType?.toString().toLowerCase() ?? '';
    return (t.contains('credit') || t.contains('receive'))
        ? 'credit'
        : 'debit';
  }

  static double? parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', ''));
    return null;
  }
}
