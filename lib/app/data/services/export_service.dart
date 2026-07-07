import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/correction_record.dart';
import 'generative_extractor_service.dart';

/// Serializes the correction log into JSONL files compatible with the
/// training pipeline (data/v2 format) and shares them.
class ExportService extends GetxService {
  Box<CorrectionRecord> get _corrections =>
      Hive.box<CorrectionRecord>('corrections');

  /// One line per extraction_fix/exclusion correction, in the exact
  /// {instruction, input, output} shape of data/v2/train.jsonl.
  Future<File> buildExtractionCorrectionsJsonl() async {
    final records = _corrections.values
        .where((c) => c.kind == 'extraction_fix' || c.kind == 'exclusion');
    final lines = records.map((c) => jsonEncode({
          'instruction': GenerativeExtractorService.extractionSystemPrompt,
          'input': 'SMS: ${c.smsBody}',
          'output': c.correctedJson,
        }));
    return _writeFile('extraction_corrections.jsonl', lines);
  }

  /// One line per classifier false positive/negative, for retraining the
  /// TF-IDF gatekeeper (label 1 = transaction).
  Future<File> buildClassifierFeedbackJsonl() async {
    final records = _corrections.values.where((c) =>
        c.kind == 'classifier_false_positive' ||
        c.kind == 'classifier_false_negative');
    final lines = records.map((c) => jsonEncode({
          'text': c.smsBody,
          'label': c.kind == 'classifier_false_negative' ? 1 : 0,
          'source': 'user_correction',
          'probability': c.classifierProbability,
        }));
    return _writeFile('classifier_feedback.jsonl', lines);
  }

  Future<void> shareAll() async {
    final extraction = await buildExtractionCorrectionsJsonl();
    final classifier = await buildClassifierFeedbackJsonl();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(extraction.path), XFile(classifier.path)],
      subject: 'FlashFlow correction datasets',
    ));
  }

  Future<File> _writeFile(String name, Iterable<String> lines) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(lines.isEmpty ? '' : '${lines.join('\n')}\n');
    return file;
  }
}
