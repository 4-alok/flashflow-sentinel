import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../data/models/processed_message.dart';
import '../../controllers/home_controller.dart';

/// Bottom sheet for correcting an extracted transaction. Only fields the
/// user actually changed are recorded as overrides; original AI values stay
/// visible as helper text.
class EditTransactionSheet extends StatefulWidget {
  final ProcessedMessage record;

  const EditTransactionSheet({super.key, required this.record});

  @override
  State<EditTransactionSheet> createState() => _EditTransactionSheetState();
}

class _EditTransactionSheetState extends State<EditTransactionSheet> {
  static const _reasons = {
    'self_transfer': 'Self transfer',
    'wrong_amount': 'Wrong amount',
    'wrong_type': 'Wrong type',
    'other': 'Other',
  };

  late String _type;
  late bool _excluded;
  late DateTime _date;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _vendorCtrl;
  String _reason = 'other';

  ProcessedMessage get record => widget.record;

  @override
  void initState() {
    super.initState();
    _type = record.effectiveType;
    _excluded = record.excluded;
    _date = record.effectiveDate;
    _amountCtrl = TextEditingController(
        text: record.effectiveAmount == 0.0
            ? ''
            : record.effectiveAmount.toStringAsFixed(2));
    _vendorCtrl = TextEditingController(text: record.effectiveVendor ?? '');
    if (record.overrideReason != null &&
        _reasons.containsKey(record.overrideReason)) {
      _reason = record.overrideReason!;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _vendorCtrl.dispose();
    super.dispose();
  }

  void _save() {
    Get.find<HomeController>().applyEditFromSheet(
      record: record,
      type: _type,
      amountText: _amountCtrl.text,
      vendorText: _vendorCtrl.text,
      date: _date,
      excluded: _excluded,
      reason: _reason,
    );
    Get.back();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _date =
          DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Transaction',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(record.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'debit',
                    label: Text('Debit'),
                    icon: Icon(Icons.arrow_downward)),
                ButtonSegment(
                    value: 'credit',
                    label: Text('Credit'),
                    icon: Icon(Icons.arrow_upward)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            if (record.aiType != null && _type != record.aiType)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('AI said: ${record.aiType}',
                    style: const TextStyle(fontSize: 11, color: Colors.amber)),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (₹)',
                border: const OutlineInputBorder(),
                helperText:
                    record.aiAmount != null ? 'AI said: ${record.aiAmount}' : null,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _vendorCtrl,
              decoration: InputDecoration(
                labelText: 'Vendor / Counterparty',
                border: const OutlineInputBorder(),
                helperText:
                    record.aiVendor != null ? 'AI said: ${record.aiVendor}' : null,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('Date: ${dateFormat.format(_date)}'),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Exclude from analytics'),
              subtitle: const Text('e.g. self transfer',
                  style: TextStyle(fontSize: 12)),
              value: _excluded,
              onChanged: (v) => setState(() => _excluded = v),
            ),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(
                labelText: 'Correction reason',
                border: OutlineInputBorder(),
              ),
              items: _reasons.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _reason = v ?? 'other'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Get.back(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
