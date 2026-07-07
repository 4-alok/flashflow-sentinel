import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../../data/models/processed_message.dart';
import '../../../data/services/correction_service.dart';
import '../../../data/services/extraction_queue_service.dart';
import '../../../data/services/generative_extractor_service.dart';
import '../../../data/services/sms_sync_service.dart';
import '../views/widgets/edit_transaction_sheet.dart';

class HomeController extends GetxController {
  final messages = <ProcessedMessage>[].obs;
  final isScanning = false.obs;
  final hideNonTransactions = false.obs;
  final olderPendingCount = 0.obs;
  final searchQuery = ''.obs;

  /// [messages] filtered to transactions only when [hideNonTransactions] is on,
  /// and filtered by [searchQuery] if not empty.
  List<ProcessedMessage> get visibleMessages {
    final query = searchQuery.value.trim().toLowerCase();
    final list = hideNonTransactions.value
        ? messages.where((m) => m.isTransaction).toList()
        : messages;
    if (query.isEmpty) return list;
    return list.where((m) {
      final matchesAddress = m.address.toLowerCase().contains(query);
      final matchesBody = m.body.toLowerCase().contains(query);
      final matchesVendor = (m.effectiveVendor ?? '').toLowerCase().contains(query);
      return matchesAddress || matchesBody || matchesVendor;
    }).toList();
  }

  void toggleHideNonTransactions() => hideNonTransactions.toggle();

  late final Box<ProcessedMessage> _box;
  StreamSubscription<BoxEvent>? _boxSub;
  Timer? _refreshDebounce;

  SmsSyncService get _sync => Get.find<SmsSyncService>();
  ExtractionQueueService get queue => Get.find<ExtractionQueueService>();
  CorrectionService get _corrections => Get.find<CorrectionService>();
  GenerativeExtractorService get _generativeService =>
      Get.find<GenerativeExtractorService>();

  RxBool get isModelLoaded => _generativeService.isLoaded;
  RxBool get isModelLoading => _generativeService.isLoading;

  @override
  void onInit() {
    super.onInit();
    _box = Hive.box<ProcessedMessage>('processed_messages');
    refreshFromBox();
    // Extraction queue and edits save records continuously; debounce so the
    // list doesn't re-sort on every single write.
    _boxSub = _box.watch().listen((_) {
      _refreshDebounce?.cancel();
      _refreshDebounce =
          Timer(const Duration(milliseconds: 200), refreshFromBox);
    });
    syncInbox();
  }

  @override
  void onClose() {
    _refreshDebounce?.cancel();
    _boxSub?.cancel();
    super.onClose();
  }

  void refreshFromBox() {
    final list = _box.values.toList()
      ..sort((a, b) => b.smsDate.compareTo(a.smsDate));
    messages.assignAll(list);
    olderPendingCount.value = queue.countOlderPending(list);
  }

  /// Queues the extraction backlog older than the auto-extract window
  /// (see [ExtractionQueueService.autoExtractWindow]).
  void processOlderMessages() => queue.enqueueOlderPending(messages);

  /// Fetches new SMS (first run: last 6 months), classifies them instantly
  /// and queues transactional ones for background extraction.
  Future<void> syncInbox() async {
    if (isScanning.value) return;
    isScanning.value = true;
    try {
      await _sync.syncInbox();
      refreshFromBox();
      // Covers both the fresh keys and records left pending by an app kill.
      queue.enqueueAllPending();
    } catch (e) {
      Get.snackbar('Sync Error', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isScanning.value = false;
    }
  }

  // --- Manual corrections ---

  void openEditor(ProcessedMessage record) {
    Get.bottomSheet(
      EditTransactionSheet(record: record),
      isScrollControlled: true,
      backgroundColor: Get.theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  Future<void> applyOverride({
    required ProcessedMessage record,
    String? type,
    double? amount,
    String? vendor,
    DateTime? date,
    bool? excluded,
    required String reason,
  }) async {
    await _corrections.applyFieldOverride(
      record: record,
      type: type,
      amount: amount,
      vendor: vendor,
      date: date,
      excluded: excluded,
      reason: reason,
    );
    messages.refresh();
  }

  /// Diffs the edit sheet's raw form values against the record's AI-derived
  /// originals and applies only the fields the user actually changed — the
  /// sheet itself just collects input, this decides what counts as an edit.
  Future<void> applyEditFromSheet({
    required ProcessedMessage record,
    required String type,
    required String amountText,
    required String vendorText,
    required DateTime date,
    required bool excluded,
    required String reason,
  }) async {
    final newAmount = double.tryParse(amountText.replaceAll(',', ''));
    final newVendor = vendorText.trim();

    await applyOverride(
      record: record,
      type: type != (record.aiType ?? 'debit') ? type : null,
      amount:
          newAmount != null && newAmount != record.aiAmount ? newAmount : null,
      vendor: newVendor.isNotEmpty && newVendor != (record.aiVendor ?? '')
          ? newVendor
          : null,
      date: _sameMinute(date, record.guardedAiDate) ? null : date,
      excluded: excluded != record.excluded ? excluded : null,
      reason: excluded && !record.excluded ? 'self_transfer' : reason,
    );
  }

  bool _sameMinute(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  Future<void> toggleExcluded(ProcessedMessage record) async {
    await _corrections.applyFieldOverride(
      record: record,
      excluded: !record.excluded,
      reason: 'self_transfer',
    );
    messages.refresh();
  }

  Future<void> markNotTransaction(ProcessedMessage record) async {
    await _corrections.markNotATransaction(record);
    messages.refresh();
  }

  Future<void> markMissedTransaction(ProcessedMessage record) async {
    await _corrections.markAsTransaction(record, queue);
    messages.refresh();
  }

  Future<void> clearOverride(ProcessedMessage record) async {
    await _corrections.clearOverride(record);
    messages.refresh();
  }

  Future<void> retryExtraction(ProcessedMessage record) async {
    await queue.retry(record.msgKey);
  }

  // --- Model memory management ---

  Future<void> toggleModelLoad() async {
    if (isModelLoaded.value) {
      queue.pause();
      await _generativeService.unloadModel();
      Get.snackbar('Model Unloaded', 'AI model has been unloaded from RAM.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black87,
          colorText: Colors.white);
    } else {
      await _generativeService.loadModel();
      if (isModelLoaded.value) {
        queue.resume();
        Get.snackbar('Model Loaded', 'AI model has been loaded into RAM.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.black87,
            colorText: Colors.white);
      } else {
        Get.snackbar('Error', 'Failed to load AI model.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.redAccent,
            colorText: Colors.white);
      }
    }
  }
}
