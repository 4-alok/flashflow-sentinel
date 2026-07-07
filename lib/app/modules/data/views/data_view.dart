import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/theme.dart';
import '../controllers/data_controller.dart';

/// Stats about processing + corrections, and the JSONL export entry point.
class DataView extends GetView<DataController> {
  const DataView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () {},
        ),
        title: const Text(
          'Data',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.security, color: context.appColors.accentPurple),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Obx(() {
        final byStatus = controller.messagesByStatus;
        final byKind = controller.correctionsByKind;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _section('Extraction'),
            Container(
              decoration: BoxDecoration(
                color: context.appColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.appColors.borderColor),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _statTile(context, 'Messages processed', controller.messagesProcessed.value,
                      Icons.sms_outlined),
                  Divider(color: context.appColors.borderColor, height: 1),
                  _statTile(context, 'Extracted', byStatus['done'] ?? 0,
                      Icons.check_circle_outline),
                  Divider(color: context.appColors.borderColor, height: 1),
                  _statTile(context, 
                      'Pending', byStatus['pending'] ?? 0, Icons.hourglass_empty),
                  Divider(color: context.appColors.borderColor, height: 1),
                  _statTile(context, 
                      'Failed', byStatus['failed'] ?? 0, Icons.error_outline),
                  Divider(color: context.appColors.borderColor, height: 1),
                  _statTile(context, 'Non-transactional', byStatus['skipped'] ?? 0,
                      Icons.chat_bubble_outline),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.appColors.accentPurple,
                side: BorderSide(color: context.appColors.borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Re-run pending & failed extractions'),
              onPressed: controller.rerunPendingExtractions,
            ),
            const SizedBox(height: 24),
            _section('Your corrections'),
            Container(
              decoration: BoxDecoration(
                color: context.appColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.appColors.borderColor),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  _statTile(context, 'Field fixes', byKind['extraction_fix'] ?? 0,
                      Icons.edit_outlined),
                  Divider(color: context.appColors.borderColor, height: 1),
                  _statTile(context, 'Exclusions (self transfer etc.)',
                      byKind['exclusion'] ?? 0, Icons.visibility_off_outlined),
                  Divider(color: context.appColors.borderColor, height: 1),
                  _statTile(context, 
                      'Classifier false positives',
                      byKind['classifier_false_positive'] ?? 0,
                      Icons.thumb_down_outlined),
                  Divider(color: context.appColors.borderColor, height: 1),
                  _statTile(context, 
                      'Classifier false negatives',
                      byKind['classifier_false_negative'] ?? 0,
                      Icons.thumb_up_outlined),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.appColors.accentPurple.withValues(alpha: 0.8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Export corrections (JSONL)'),
              onPressed: controller.hasCorrections.value
                  ? controller.exportCorrections
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Exports two files: extraction corrections in the training '
              'data format (instruction/input/output) and classifier '
              'feedback (text/label) for retraining the TF-IDF gate.',
              style: TextStyle(fontSize: 12, color: context.appColors.textGrey),
            ),
          ],
        );
      }),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
      );

  Widget _statTile(BuildContext context, String label, int count, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.appColors.accentPurple),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}
