import 'dart:async';

import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../../data/models/correction_record.dart';
import '../../../data/models/processed_message.dart';
import '../../../data/services/export_service.dart';
import '../../../data/services/extraction_queue_service.dart';

/// Stats + actions for the Data tab: extraction/correction counts (grouped
/// from the Hive boxes) and the re-run/export entry points.
class DataController extends GetxController {
  final messagesProcessed = 0.obs;
  final messagesByStatus = <String, int>{}.obs;
  final correctionsByKind = <String, int>{}.obs;
  final hasCorrections = false.obs;

  late final Box<ProcessedMessage> _messagesBox;
  late final Box<CorrectionRecord> _correctionsBox;
  StreamSubscription<BoxEvent>? _messagesSub;
  StreamSubscription<BoxEvent>? _correctionsSub;

  ExtractionQueueService get _queue => Get.find<ExtractionQueueService>();
  ExportService get _export => Get.find<ExportService>();

  @override
  void onInit() {
    super.onInit();
    _messagesBox = Hive.box<ProcessedMessage>('processed_messages');
    _correctionsBox = Hive.box<CorrectionRecord>('corrections');
    _recompute();
    _messagesSub = _messagesBox.watch().listen((_) => _recompute());
    _correctionsSub = _correctionsBox.watch().listen((_) => _recompute());
  }

  @override
  void onClose() {
    _messagesSub?.cancel();
    _correctionsSub?.cancel();
    super.onClose();
  }

  void _recompute() {
    messagesProcessed.value = _messagesBox.length;

    final byStatus = <String, int>{};
    for (final r in _messagesBox.values) {
      byStatus[r.extractionStatus] = (byStatus[r.extractionStatus] ?? 0) + 1;
    }
    messagesByStatus.assignAll(byStatus);

    final byKind = <String, int>{};
    for (final c in _correctionsBox.values) {
      byKind[c.kind] = (byKind[c.kind] ?? 0) + 1;
    }
    correctionsByKind.assignAll(byKind);
    hasCorrections.value = _correctionsBox.isNotEmpty;
  }

  void rerunPendingExtractions() {
    _queue
      ..enqueueAllPending()
      ..resume();
    Get.snackbar('Extraction', 'Queue restarted.',
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> exportCorrections() => _export.shareAll();
}
