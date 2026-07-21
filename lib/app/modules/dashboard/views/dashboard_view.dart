import 'dart:math' show max;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../data/services/analytics_service.dart';
import '../../root/controllers/root_controller.dart';
import '../controllers/chart_zoom_controller.dart';
import '../controllers/dashboard_controller.dart';

/// Horizontally scrollable, pinch-zoomable viewport for the spending chart.
/// Panning is a real [SingleChildScrollView] (native one-finger swipe, with
/// the usual momentum/fling) — when there are more bars than fit on screen,
/// you can always swipe to see the rest. [ChartZoomController] (reactive Rx
/// state, no setState) only handles two-finger pinch-to-zoom, growing/
/// shrinking the scrollable content's width. Height is always fixed to the
/// viewport, so the Y-axis/tallest bar can never be cropped — only
/// horizontal density (bars per screen) zooms, which is what actually
/// matters for a time-series chart. Deliberately not using InteractiveViewer
/// for the zoom: its pinch scale applies uniformly to both axes, which was
/// stretching the chart vertically past its fixed-height box with no way to
/// pan back into view.
///
/// The controller tracks raw pointers via a [Listener] rather than a
/// [GestureDetector] with onScale*: a GestureDetector's scale recognizer
/// claims the gesture arena for every touch — including a plain single-finger
/// tap — which was silently swallowing taps meant for fl_chart's own
/// bar/line touch-tooltip handling. A Listener sits outside the gesture-arena
/// system entirely, so it can track a two-finger pinch for zoom while leaving
/// single-finger taps/drags completely free for the scroll view and the
/// chart underneath.
class _HorizontalZoomChart extends GetView<ChartZoomController> {
  static const _minPxPerItem = 14.0;
  static const _height = 200.0;

  final int itemCount;
  final Widget Function() chartBuilder;

  const _HorizontalZoomChart({
    required this.itemCount,
    required this.chartBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final viewportWidth = constraints.maxWidth;
      final baseWidth = max(viewportWidth, itemCount * _minPxPerItem);

      return Obx(() {
        final contentWidth = baseWidth * controller.scale.value;

        return Listener(
          onPointerDown: controller.onPointerDown,
          onPointerMove: controller.onPointerMove,
          onPointerUp: controller.onPointerUp,
          onPointerCancel: controller.onPointerUp,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: _height,
              child: chartBuilder(),
            ),
          ),
        );
      });
    });
  }
}

class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final currency =
        NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const IconButton(
          icon: Icon(Icons.menu),
          onPressed: null,
        ),
        title: const Text(
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.security, color: context.appColors.accentPurple),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (action) {
              if (action == 'toggle_theme') {
                Get.find<RootController>().toggleTheme();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_theme',
                child: Obx(() => Text(
                  Get.find<RootController>().isDarkMode.value
                      ? 'Switch to Light Mode'
                      : 'Switch to Dark Mode',
                )),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Obx(() {
        if (!controller.hasAnyMessages.value) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No messages yet.\nAnalytics appear once messages are synced.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final net = controller.creditTotal.value - controller.debitTotal.value;
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _CustomPeriodSelector(
              selectedPeriod: controller.period.value,
              onPeriodSelected: (p) => controller.period.value = p,
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: context.appColors.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.appColors.borderColor),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: context.appColors.textGrey),
                    onPressed: controller.goBack,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_outlined,
                          color: context.appColors.textGrey, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        controller.rangeLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.chevron_right, color: context.appColors.textGrey),
                    onPressed: controller.canGoForward ? controller.goForward : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (controller.unprocessedCount.value > 0) ...[
              _UnprocessedBanner(controller: controller),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _SummaryCard(
                  label: 'Spent',
                  value: currency.format(controller.debitTotal.value),
                  color: context.appColors.spentRed,
                  icon: Icons.arrow_downward,
                ),
                const SizedBox(width: 8),
                _SummaryCard(
                  label: 'Received',
                  value: currency.format(controller.creditTotal.value),
                  color: context.appColors.receivedGreen,
                  icon: Icons.arrow_upward,
                ),
                const SizedBox(width: 8),
                _SummaryCard(
                  label: 'Net',
                  value: currency.format(net),
                  color: context.appColors.accentPurple,
                  customIconText: '≈',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: context.appColors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.appColors.borderColor),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Spending',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            controller.chartTitle,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.info_outline,
                              size: 14, color: Colors.grey),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ChartLegendDot(color: context.appColors.spentRed),
                      const SizedBox(width: 4),
                      const Text('Debited',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(width: 12),
                      _ChartLegendDot(color: context.appColors.receivedGreen),
                      const SizedBox(width: 4),
                      const Text('Credited',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: _HorizontalZoomChart(
                      itemCount: controller.chartTransactions.length,
                      chartBuilder: () => _SpendingBarChart(controller: controller),
                    ),
                  ),
                ],
              ),
            ),
            if (controller.topVendors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: context.appColors.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.appColors.borderColor),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Top Vendors',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).colorScheme.onSurface),
                        ),
                        GestureDetector(
                          onTap: () {},
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View all',
                                style: TextStyle(
                                    color: context.appColors.accentPurple,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.chevron_right,
                                  size: 16, color: context.appColors.accentPurple),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...controller.topVendors.map((e) {
                      final rows = controller.vendorTxnsByVendor[e.key] ?? const [];
                      return Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          key: PageStorageKey(e.key),
                          dense: true,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 4),
                          title: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: context.appColors.accentPurple.withValues(alpha: 0.15),
                                child: Text(
                                  e.key.isNotEmpty
                                      ? e.key[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.appColors.accentPurple,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                currency.format(e.value),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const Spacer(),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 120),
                                child: Text(
                                  e.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      color: context.appColors.textGrey, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          trailing: Icon(Icons.expand_more,
                              size: 20, color: context.appColors.textGrey),
                          children: [
                            for (final t in rows)
                              ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.only(left: 44, right: 8),
                                title: Text(
                                  DateFormat('d MMM, HH:mm')
                                      .format(t.effectiveDate),
                                  style: TextStyle(
                                      color: context.appColors.textGrey, fontSize: 12),
                                ),
                                trailing: Text(
                                  currency.format(t.effectiveAmount),
                                  style: TextStyle(
                                      color: context.appColors.textGrey, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

}

class _CustomPeriodSelector extends StatelessWidget {
  final Period selectedPeriod;
  final ValueChanged<Period> onPeriodSelected;

  const _CustomPeriodSelector({
    required this.selectedPeriod,
    required this.onPeriodSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appColors.borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: Period.values.map((p) {
          final isSelected = p == selectedPeriod;
          return Expanded(
            child: GestureDetector(
              onTap: () => onPeriodSelected(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF6333C4), Color(0xFF4F2AA6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  _labelOf(p),
                  style: TextStyle(
                    color: isSelected ? Colors.white : context.appColors.textGrey,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _labelOf(Period p) {
    switch (p) {
      case Period.daily:
        return 'Day';
      case Period.weekly:
        return 'Week';
      case Period.monthly:
        return 'Month';
    }
  }
}

/// Small colored dot for the spending chart's debit/credit legend.
class _ChartLegendDot extends StatelessWidget {
  final Color color;

  const _ChartLegendDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Banner offering to process the extraction backlog for the currently
/// viewed period, shown when the summary/chart look empty (or incomplete)
/// only because those messages haven't been run through the model yet.
class _UnprocessedBanner extends StatelessWidget {
  final DashboardController controller;

  const _UnprocessedBanner({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = controller.unprocessedCount.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count message${count == 1 ? '' : 's'} in this range '
              "haven't been processed yet",
              style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
            ),
          ),
          TextButton(
            onPressed: controller.processUnprocessed,
            child: const Text('Process now'),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final String? customIconText;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    this.icon,
    this.customIconText,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: context.appColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appColors.borderColor),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: color.withValues(alpha: 0.12),
              child: customIconText != null
                  ? Text(
                      customIconText!,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 13,
                      color: color,
                    ),
            ),
            const Spacer(),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: context.appColors.subTextGrey),
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One bar per individual debit transaction in the currently-focused range
/// (see [DashboardController.chartTransactions]) — never an aggregated
/// bucket, so the chart always matches exactly what the transaction list
/// below it shows.
class _SpendingBarChart extends StatelessWidget {
  final DashboardController controller;

  const _SpendingBarChart({required this.controller});

  @override
  Widget build(BuildContext context) {
    final entries = controller.chartTransactions;
    if (entries.isEmpty) return const SizedBox.shrink();

    final maxY = controller.barChartMaxY;
    final labelEvery = controller.chartLabelEvery;

    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: context.appColors.borderColor,
            strokeWidth: 1,
            dashArray: [5, 5],
          ),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final t = entries[group.x.toInt()];
              final vendor = t.effectiveVendor ?? 'Transaction';
              final when = DateFormat('d MMM, HH:mm').format(t.effectiveDate);
              final sign = t.effectiveType == 'credit' ? '+' : '-';
              return BarTooltipItem(
                '$vendor\n$when\n$sign₹${rod.toY.toStringAsFixed(0)}',
                const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: controller.yAxisInterval(maxY),
              getTitlesWidget: (value, meta) => value == 0
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(controller.formatCompactCurrency(value),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length || i % labelEvery != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('d MMM').format(entries[i].effectiveDate),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(
              x: i,
              groupVertically: false,
              barsSpace: 0,
              barRods: [
                BarChartRodData(
                  toY: entries[i].effectiveAmount,
                  width: 6,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  gradient: LinearGradient(
                    colors: entries[i].effectiveType == 'credit'
                        ? [
                            context.appColors.receivedGreen,
                            context.appColors.receivedGreen.withValues(alpha: 0.6),
                          ]
                        : [
                            context.appColors.spentRed,
                            context.appColors.spentRed.withValues(alpha: 0.6),
                          ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
