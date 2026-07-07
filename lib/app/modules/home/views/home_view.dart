import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../data/models/processed_message.dart';
import '../controllers/home_controller.dart';

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: CircleAvatar(
            backgroundColor: context.appColors.accentPurple.withValues(alpha: 0.15),
            child: Icon(Icons.security, color: context.appColors.accentPurple, size: 20),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FlashFlow Sentinel',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
            ),
            Obx(() {
              final loaded = controller.isModelLoaded.value;
              final loading = controller.isModelLoading.value;
              final dotColor = loaded
                  ? Colors.greenAccent
                  : (loading ? Colors.amberAccent : context.appColors.textGrey);
              final text = loaded
                  ? 'AI Model: Loaded'
                  : (loading ? 'AI Model: Loading...' : 'AI Model: Unloaded');
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appColors.textGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Re-sync inbox',
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.syncInbox(),
          ),
          Obx(() => PopupMenuButton<String>(
                icon: controller.isModelLoading.value
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(scheme.primary)),
                      )
                    : const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case 'toggle_hide':
                      controller.toggleHideNonTransactions();
                    case 'toggle_model':
                      controller.toggleModelLoad();
                  }
                },
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: 'toggle_hide',
                    checked: controller.hideNonTransactions.value,
                    child: const Text('Hide non-transaction messages'),
                  ),
                  PopupMenuItem(
                    value: 'toggle_model',
                    child: Text(controller.isModelLoaded.value
                        ? 'Unload AI model (free RAM)'
                        : 'Load AI model'),
                  ),
                ],
              )),
        ],
      ),
      body: Column(
        children: [
          _OlderMessagesBanner(controller: controller),
          _ExtractionProgressBar(controller: controller),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: context.appColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.appColors.borderColor),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: context.appColors.textGrey, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (val) => controller.searchQuery.value = val,
                            decoration: InputDecoration(
                              hintText: 'Search messages...',
                              hintStyle: TextStyle(color: context.appColors.textGrey, fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    controller.toggleHideNonTransactions();
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: context.appColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.appColors.borderColor),
                    ),
                    child: Obx(() => Icon(
                          controller.hideNonTransactions.value
                              ? Icons.filter_alt
                              : Icons.filter_alt_outlined,
                          color: controller.hideNonTransactions.value
                              ? context.appColors.accentPurple
                              : Colors.white70,
                          size: 20,
                        )),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.isScanning.value && controller.messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              final visible = controller.visibleMessages;
              if (visible.isEmpty) {
                return Center(
                  child: Text(controller.hideNonTransactions.value
                      ? 'No transactions found.'
                      : 'No messages found.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final record = visible[index];
                  return _MessageTile(record: record, controller: controller);
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Banner offering to process the extraction backlog older than the
/// auto-extract window (see [ExtractionQueueService.autoExtractWindow]).
/// Hides itself once the backlog is cleared (recomputed on every box change
/// via [HomeController.refreshFromBox]).
class _OlderMessagesBanner extends StatelessWidget {
  final HomeController controller;

  const _OlderMessagesBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final count = controller.olderPendingCount.value;
      if (count == 0) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count older message${count == 1 ? '' : 's'} not yet processed',
                style: TextStyle(
                    fontSize: 12, color: scheme.onTertiaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => controller.processOlderMessages(),
              child: const Text('Process now'),
            ),
          ],
        ),
      );
    });
  }
}

/// Slim persistent progress header shown while the extraction queue runs.
class _ExtractionProgressBar extends StatelessWidget {
  final HomeController controller;

  const _ExtractionProgressBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final queue = controller.queue;
      final total = queue.totalQueued.value;
      final done = queue.completedCount.value;
      final active = total > 0 && (queue.isRunning.value || queue.isPaused.value);
      if (!active) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    queue.isPaused.value
                        ? 'Extraction paused ($done/$total)'
                        : 'Extracting $done/$total',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0 ? done / total : 0,
                      minHeight: 6,
                      backgroundColor:
                          scheme.onPrimaryContainer.withValues(alpha: 0.15),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              iconSize: 20,
              tooltip: queue.isPaused.value ? 'Resume' : 'Pause',
              icon: Icon(
                  queue.isPaused.value ? Icons.play_arrow : Icons.pause,
                  color: scheme.onPrimaryContainer),
              onPressed: () =>
                  queue.isPaused.value ? queue.resume() : queue.pause(),
            ),
          ],
        ),
      );
    });
  }
}

class _MessageTile extends StatelessWidget {
  final ProcessedMessage record;
  final HomeController controller;

  const _MessageTile({required this.record, required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
    final isTxn = record.isTransaction;
    final isDone = record.extractionStatus == 'done';
    final dimmed = !isTxn || record.excluded;

    return Opacity(
      opacity: dimmed ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: context.appColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appColors.borderColor),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _leadingIcon(context, scheme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    record.address,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (record.hasOverride)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(Icons.edit,
                                        size: 13, color: context.appColors.accentPurple),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isTxn && isDone)
                            Text(
                              '${record.amountSign} ${currencyFormat.format(record.effectiveAmount)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                decoration: record.excluded
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: record.effectiveType == 'debit'
                                    ? context.appColors.spentRed
                                    : context.appColors.receivedGreen,
                              ),
                            )
                          else
                            Text(
                              DateFormat('dd MMM').format(record.smsDate),
                              style: TextStyle(
                                  fontSize: 11, color: context.appColors.textGrey),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        record.body,
                        maxLines: isTxn && isDone ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: context.appColors.subTextGrey),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (isTxn && isDone && record.effectiveVendor != null && record.effectiveVendor!.isNotEmpty)
                            _vendorChip(context, record.effectiveVendor!)
                          else if (!isTxn)
                            _notTxnChip(context)
                          else
                            const SizedBox.shrink(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isTxn && isDone) ...[
                                Text(
                                  DateFormat('dd MMM').format(record.smsDate),
                                  style: TextStyle(
                                      fontSize: 11, color: context.appColors.textGrey),
                                ),
                                const SizedBox(width: 4),
                              ],
                              _actionsMenu(context),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _vendorChip(BuildContext context, String vendor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.appColors.accentPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 12, color: context.appColors.accentPurple),
          const SizedBox(width: 4),
          Text(
            vendor.toUpperCase(),
            style: TextStyle(
              color: context.appColors.accentPurple,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notTxnChip(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.appColors.borderColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Not a transaction',
        style: TextStyle(
          color: context.appColors.textGrey,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _leadingIcon(BuildContext context, ColorScheme scheme) {
    if (!record.isTransaction) {
      return CircleAvatar(
        backgroundColor: context.appColors.borderColor.withValues(alpha: 0.6),
        child: Icon(Icons.chat_bubble_outline, color: context.appColors.textGrey, size: 20),
      );
    }
    switch (record.extractionStatus) {
      case 'done':
        final debit = record.effectiveType == 'debit';
        final circleBg = debit
            ? context.appColors.accentPurple.withValues(alpha: 0.15)
            : context.appColors.receivedGreen.withValues(alpha: 0.15);
        final iconColor = debit ? context.appColors.accentPurple : context.appColors.receivedGreen;
        return CircleAvatar(
          backgroundColor: circleBg,
          child: Icon(
            debit ? Icons.arrow_downward : Icons.arrow_upward,
            color: iconColor,
            size: 20,
          ),
        );
      case 'failed':
        return CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.12),
          child: const Icon(Icons.error_outline, color: Colors.orange, size: 20),
        );
      default: // pending
        return CircleAvatar(
          backgroundColor: context.appColors.cardBackground,
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary)),
          ),
        );
    }
  }

  Widget _actionsMenu(BuildContext context) {
    return PopupMenuButton<String>(
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Icon(Icons.more_vert, size: 18),
      ),
      onSelected: (action) {
        switch (action) {
          case 'edit':
            controller.openEditor(record);
          case 'exclude':
            controller.toggleExcluded(record);
          case 'not_txn':
            controller.markNotTransaction(record);
          case 'is_txn':
            controller.markMissedTransaction(record);
          case 'retry':
            controller.retryExtraction(record);
          case 'clear':
            controller.clearOverride(record);
        }
      },
      itemBuilder: (context) {
        final isTxn = record.isTransaction;
        return [
          if (isTxn && record.extractionStatus == 'done') ...[
            const PopupMenuItem(value: 'edit', child: Text('Edit fields')),
            PopupMenuItem(
              value: 'exclude',
              child: Text(record.excluded
                  ? 'Include in analytics'
                  : 'Exclude (self transfer)'),
            ),
            const PopupMenuItem(
                value: 'not_txn', child: Text('Not a transaction')),
          ],
          if (isTxn && record.extractionStatus == 'failed')
            const PopupMenuItem(
                value: 'retry', child: Text('Retry extraction')),
          if (!isTxn)
            const PopupMenuItem(
                value: 'is_txn', child: Text('This IS a transaction')),
          if (record.hasOverride)
            const PopupMenuItem(
                value: 'clear', child: Text('Clear my corrections')),
        ];
      },
    );
  }

  void _showDetails(BuildContext context) {
    String prettyJson = 'No extraction yet.';
    final raw = record.rawLlmOutput;
    if (raw != null && raw.isNotEmpty) {
      try {
        prettyJson =
            const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
      } catch (_) {
        prettyJson = raw;
      }
    }

    Get.defaultDialog(
      title: record.address,
      content: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.body, style: const TextStyle(height: 1.5)),
                const Divider(height: 24),
                Text(
                  'Classifier: ${record.classifiedAsTransaction ? 'transaction' : 'other'} '
                  '(p=${record.classifierProbability.toStringAsFixed(3)})',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (record.hasOverride) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Corrected by you (${record.overrideReason ?? 'manual'})',
                    style: const TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Raw AI Output:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade700),
                  ),
                  child: Text(
                    prettyJson,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      confirm: TextButton(
        onPressed: () => Get.back(),
        child: const Text('Close'),
      ),
    );
  }
}
