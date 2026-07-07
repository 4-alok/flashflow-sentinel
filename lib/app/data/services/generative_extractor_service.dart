import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

class GenerativeExtractorService extends GetxService {
  /// Must stay byte-identical to the `instruction` field of the training
  /// dataset (data/v2/*.jsonl) — also reused by ExportService so exported
  /// corrections match the training format.
  static const String extractionSystemPrompt =
      "You are a financial data extractor. Parse the bank SMS and return a JSON object with these fields: transaction_type, amount, currency, date (ISO 8601), time, sender_bank, sender_acc, receiver_bank, receiver_acc, counterparty_name, reference_id, balance_after, is_actionable. Use null for absent fields.";

  LlamaController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  
  final isLoaded = false.obs;
  final isLoading = false.obs;

  Future<void> loadModel() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    isLoading.value = true;

    try {
      _controller = LlamaController();

      // Check if the model is already loaded on the native side (e.g. surviving hot restarts)
      final loaded = await _controller!.isModelLoaded();
      if (loaded) {
        print("[FLASHFLOW] SmolLM is already loaded natively.");
        _isInitialized = true;
        isLoaded.value = true;
        return;
      }

      // Load model from assets to local storage
      final byteData = await rootBundle.load('assets/models/smollm-q4_k_m.gguf');
      final directory = await getApplicationSupportDirectory();
      // Using v3 to force the app to overwrite the old base model with the new fine-tuned GGUF
      final file = File('${directory.path}/smollm_v3.gguf');
      
      if (!await file.exists() || (await file.length()) != byteData.lengthInBytes) {
        await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      }

      // GPU Detection for hardware acceleration (Vulkan)
      final gpu = await _controller!.detectGpu();
      print("[FLASHFLOW] GPU: ${gpu.gpuName}, Vulkan: ${gpu.vulkanSupported}, Recommended Layers: ${gpu.recommendedGpuLayers}");

      await _controller!.loadModel(
        modelPath: file.path,
        threads: 4,
        contextSize: 512,
        gpuLayers: gpu.recommendedGpuLayers,
      );
      
      _isInitialized = true;
      isLoaded.value = true;
    } catch (e) {
      print("[FLASHFLOW] Failed to initialize SmolLM: $e");
      isLoaded.value = false;
      _controller = null;
    } finally {
      _isInitializing = false;
      isLoading.value = false;
    }
  }

  Future<void> unloadModel() async {
    if (_controller != null) {
      isLoading.value = true;
      try {
        await _controller!.dispose();
      } catch (e) {
        print("[FLASHFLOW] Failed to dispose SmolLM: $e");
      } finally {
        _controller = null;
        _isInitialized = false;
        isLoaded.value = false;
        isLoading.value = false;
      }
    }
  }

  Future<Map<String, dynamic>> extractFromSms(String smsText) async {
    try {
      if (!_isInitialized) {
        await loadModel();
      }

      if (_controller == null || !isLoaded.value) {
        return {'error': 'Model failed to load/initialize'};
      }

      // Prevent concurrent generation on the same controller and clear context to avoid KV cache bleed/overflow
      if (_controller!.isGenerating) {
        await _controller!.stop();
      }
      await _controller!.clearContext();

      const systemPrompt = extractionSystemPrompt;

      // Match training template EXACTLY
      final prompt = "<|im_start|>system\n$systemPrompt<|im_end|>\n"
                    "<|im_start|>user\n$systemPrompt\n\nSMS: $smsText<|im_end|>\n"
                    "<|im_start|>assistant\n";

      print("[FLASHFLOW] Sending Prompt:\n$prompt");

      String fullResponse = "";
      final responseCompleter = Completer<String>();
      
      final subscription = _controller!.generate(
        prompt: prompt,
        maxTokens: 160,
        temperature: 0.1, // Fine-tuned model should be stable at 0.1
        topK: 40,
        topP: 0.9,
      ).listen((token) {
        fullResponse += token;
      }, onDone: () {
        if (!responseCompleter.isCompleted) responseCompleter.complete(fullResponse);
      }, onError: (e) {
        if (!responseCompleter.isCompleted) responseCompleter.completeError(e);
      });

      final resultText = await responseCompleter.future.timeout(const Duration(seconds: 15), onTimeout: () {
        subscription.cancel();
        return fullResponse;
      });

      // Clean the JSON output
      String cleanedJson = resultText.trim();
      
      // Remove ChatML suffix if generated
      if (cleanedJson.contains("<|im_end|>")) {
        cleanedJson = cleanedJson.split("<|im_end|>")[0].trim();
      }

      if (cleanedJson.contains('```json')) {
        cleanedJson = cleanedJson.split('```json')[1].split('```')[0].trim();
      } else if (cleanedJson.contains('```')) {
        cleanedJson = cleanedJson.split('```')[1].split('```')[0].trim();
      }
      
      if (cleanedJson.contains('}')) {
        cleanedJson = cleanedJson.substring(0, cleanedJson.lastIndexOf('}') + 1);
      }

      if (cleanedJson.isEmpty) return {'error': 'Empty response from model'};

      // Try to parse, if it fails, return the raw text for debugging
      try {
        final parsed = jsonDecode(cleanedJson);
        if (parsed is Map<String, dynamic>) {
          parsed['raw_output'] = cleanedJson;
          return parsed;
        }
        return {'raw_output': cleanedJson, 'error': 'Parsed JSON is not a map'};
      } catch (e) {
        print("[FLASHFLOW] JSON Parse Error: $e for string: $cleanedJson");
        return {'error': 'JSON Parse Error', 'raw': cleanedJson, 'raw_output': cleanedJson};
      }
    } catch (e) {
      return {'error': 'Inference Error: $e'};
    }
  }
  
  @override
  void onClose() {
    unloadModel();
    super.onClose();
  }
}
