import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';

/// A pure Dart service that loads a trained TF-IDF + Logistic Regression
/// classifier from JSON and performs on-device SMS classification.
class SmsClassifierService extends GetxService {
  Map<String, int> _vocabulary = {};
  List<double> _idf = [];
  List<double> _weights = [];
  double _intercept = 0.0;
  double _threshold = 0.80;
  bool _isInitialized = false;

  /// Per-message logging; keep off during bulk scans.
  bool verbose = false;

  bool get isInitialized => _isInitialized;
  double get threshold => _threshold;

  @override
  void onInit() {
    super.onInit();
    loadModel();
  }

  /// Loads the serialized model weights from Flutter assets
  Future<void> loadModel() async {
    try {
      final jsonString = await rootBundle.loadString('assets/models/classifier_model.json');
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Parse Vocabulary
      _vocabulary = Map<String, int>.from(data['vocabulary']);

      // Parse IDFs safely converting both int/double to double
      _idf = List<double>.from(
        (data['idf'] as List).map((x) => (x as num).toDouble()),
      );

      // Parse Weights safely
      _weights = List<double>.from(
        (data['weights'] as List).map((x) => (x as num).toDouble()),
      );

      // Parse Intercept and Threshold
      _intercept = (data['intercept'] as num).toDouble();
      _threshold = (data['threshold'] as num?)?.toDouble() ?? 0.80;

      _isInitialized = true;
      print("[SMS_CLASSIFIER] Model loaded successfully. Vocab size: ${_vocabulary.length}");
    } catch (e) {
      print("[SMS_CLASSIFIER] Error loading model: $e");
    }
  }

  /// Tokenization function matching Python preprocessing
  List<String> preprocess(String text) {
    final lowercase = text.toLowerCase();
    
    // Alphanumeric manual character scan for faster execution
    final buffer = StringBuffer();
    for (var i = 0; i < lowercase.length; i++) {
      final char = lowercase.codeUnitAt(i);
      if ((char >= 97 && char <= 122) || // a-z
          (char >= 48 && char <= 57) ||  // 0-9
          char == 32 || char == 10 || char == 13 || char == 9) { // whitespaces
        buffer.writeCharCode(char);
      }
    }
    
    final cleaned = buffer.toString();
    return cleaned.split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();
  }

  /// Classifies an SMS text. Returns true if it is a transaction, false otherwise.
  bool classify(String text) => probability(text) >= _threshold;

  /// Transaction probability in [0, 1].
  /// Returns 1.0 when the model isn't loaded (fail open to the SLM,
  /// matching the previous classify() behavior) and 0.0 for empty text.
  double probability(String text) {
    if (!_isInitialized) {
      if (verbose) {
        print("[SMS_CLASSIFIER] Warning: Service not initialized. Defaulting to transaction.");
      }
      return 1.0; // Fallback to running the SLM if the classifier is not ready
    }

    final tokens = preprocess(text);
    if (tokens.isEmpty) return 0.0;

    // 1. Calculate Term Frequencies
    final Map<String, double> tf = {};
    for (var token in tokens) {
      tf[token] = (tf[token] ?? 0.0) + 1.0;
    }

    // 2. Compute TF-IDF and vector length (sum of squares)
    double sumSquares = 0.0;
    final Map<int, double> tfidfValues = {};

    tf.forEach((token, count) {
      if (_vocabulary.containsKey(token)) {
        final int idx = _vocabulary[token]!;
        final double idfVal = _idf[idx];
        final double tfidfVal = count * idfVal;
        
        tfidfValues[idx] = tfidfVal;
        sumSquares += tfidfVal * tfidfVal;
      }
    });

    final double norm = sqrt(sumSquares);
    if (norm == 0.0) {
      // If no vocabulary words are present, use the bias intercept
      return 1.0 / (1.0 + exp(-_intercept));
    }

    // 3. Dot Product and L2 Normalization
    double score = 0.0;
    tfidfValues.forEach((idx, val) {
      final double normalizedVal = val / norm; // L2 normalization
      score += normalizedVal * _weights[idx]; // Dot product
    });
    score += _intercept;

    // 4. Sigmoid Activation with overflow protection
    double probability;
    if (score >= 0) {
      probability = 1.0 / (1.0 + exp(-score));
    } else {
      final double expScore = exp(score);
      probability = expScore / (1.0 + expScore);
    }
    
    if (verbose) {
      print("[SMS_CLASSIFIER] Text: '$text'");
      print("[SMS_CLASSIFIER] Probability: ${probability.toStringAsFixed(4)} (Threshold: $_threshold) -> IsTxn: ${probability >= _threshold}");
    }

    return probability;
  }
}
