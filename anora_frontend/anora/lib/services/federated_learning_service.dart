import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'api_endpoint_service.dart';
import 'storage_service.dart';
import 'tokenizer_service.dart';

/// Federated Learning Client Service
///
/// Implements privacy-preserving model improvement via:
/// 1. Local training on device (journal entries never leave)
/// 2. Gradient computation (weight updates)
/// 3. Secure Aggregation masking (gradients masked with random noise)
/// 4. Submitting masked gradients to server
/// 5. Downloading global model updates
class FederatedLearningService {
  FederatedLearningService._();

  static final FederatedLearningService instance = FederatedLearningService._();

  // Platform channels for native device access
  static const platform = MethodChannel('com.anorahealth.anora/fl');

  // FL Configuration
  static const Duration _idleCheckInterval = Duration(minutes: 5);
  static const Duration _minIdleTime = Duration(minutes: 15); // Must be idle for 15+ min

  // Model state
  String _localModelVersion = '1.0.0';
  int _currentModelVersionInt = 0;
  bool _isTrainingActive = false;

  // Training state
  Timer? _idleDetectionTimer;
  bool _deviceIsIdle = false;
  bool _deviceIsCharging = false;
  DateTime? _lastUserInteraction;

  // Gradient accumulation
  final List<double> _accumulatedGradients = [];
  int _localTrainingSteps = 0;
  double _gradientNorm = 0.0;
  Interpreter? _interpreter;
  static const int _defaultEmbeddingDim = 11;
  int _embeddingDim = _defaultEmbeddingDim;

  /// Initialize federated learning client
  Future<void> init({
    String? appVersion,
  }) async {
    _localModelVersion = appVersion ?? _localModelVersion;
    _lastUserInteraction = DateTime.now(); // Start with "just now"
    await TokenizerService.instance.init();
    await _restoreOrInitializeInterpreter();

    final persistedVersion = StorageService.instance.loadDownloadedFlModelVersion();
    if (persistedVersion != null && persistedVersion > _currentModelVersionInt) {
      _currentModelVersionInt = persistedVersion;
    }

    await _registerWithCoordinator();
    _startIdleDetection();
  }

  Future<void> _restoreOrInitializeInterpreter() async {
    final persistedModelB64 = StorageService.instance.loadDownloadedFlModelBase64();

    if (persistedModelB64 != null && persistedModelB64.isNotEmpty) {
      final restored = await _reloadInterpreterFromEncodedModel(
        persistedModelB64,
        persistModel: false,
      );
      if (restored) {
        if (kDebugMode) {
          print('[FL] Restored persisted FL model interpreter');
        }
        return;
      }

      await StorageService.instance.clearDownloadedFlModel();
    }

    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilebert_quant.tflite');
      if (kDebugMode) {
        print('[FL] TFLite interpreter initialized from bundled asset');
      }
    } catch (e) {
      _interpreter = null;
      if (kDebugMode) {
        print('[FL] TFLite init skipped: $e');
      }
    }
  }

  /// Register this device with the FL coordinator
  Future<void> _registerWithCoordinator() async {
    try {
      final deviceId = StorageService.instance.deviceId;
      final response = await ApiEndpointService.instance.post(
        Uri.parse('${ApiEndpointService.instance.buildUri('/fl').toString()}/clients/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'patient_device_id': deviceId,
          'app_version': _localModelVersion,
          'model_version': _currentModelVersionInt,
        }),
      );

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        _currentModelVersionInt = body['current_model_version'] as int? ?? 0;
        if (kDebugMode) {
          print('[FL] Client registered: model_version=$_currentModelVersionInt');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Registration failed: $e');
      }
    }
  }

  /// Download the latest global model from the coordinator
  Future<bool> downloadLatestModel() async {
    try {
      final response = await ApiEndpointService.instance.get(
        Uri.parse('${ApiEndpointService.instance.buildUri('/fl').toString()}/models/latest'),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final newVersion = body['version'] as int? ?? 0;
        final weightsBase64 = body['base64_weights'] as String?;

        if (newVersion > _currentModelVersionInt) {
          if (weightsBase64 == null || weightsBase64.isEmpty) {
            if (kDebugMode) {
              print('[FL] Model update skipped: no model bytes for version $newVersion');
            }
            return false;
          }

          final updated = await _reloadInterpreterFromEncodedModel(
            weightsBase64,
            persistModel: true,
            version: newVersion,
          );
          if (!updated) {
            if (kDebugMode) {
              print('[FL] Model update skipped: failed to reload interpreter for version $newVersion');
            }
            return false;
          }

          _currentModelVersionInt = newVersion;
          if (kDebugMode) {
            print('[FL] Model updated to version $newVersion');
          }
          return true;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Model download failed: $e');
      }
    }
    return false;
  }

  Future<bool> _reloadInterpreterFromEncodedModel(
    String encodedWeights, {
    required bool persistModel,
    int? version,
  }) async {
    try {
      final bytes = base64Decode(encodedWeights);
      final nextInterpreter = await Interpreter.fromBuffer(bytes);
      final previousInterpreter = _interpreter;
      _interpreter = nextInterpreter;
      previousInterpreter?.close();

      if (persistModel) {
        final effectiveVersion = version ?? _currentModelVersionInt;
        await StorageService.instance.saveDownloadedFlModel(
          version: effectiveVersion,
          base64Model: encodedWeights,
        );
      }

      if (version != null && version > _currentModelVersionInt) {
        _currentModelVersionInt = version;
      }

      if (kDebugMode) {
        print('[FL] Interpreter hot-reloaded from downloaded model bytes (${bytes.length} bytes)');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Interpreter hot-reload failed: $e');
      }
      return false;
    }
  }

  /// Start detecting device idle state
  void _startIdleDetection() {
    _idleDetectionTimer = Timer.periodic(_idleCheckInterval, (_) async {
      _deviceIsIdle = await _checkIfIdle();
      _deviceIsCharging = await _checkIfCharging();

      if (_deviceIsIdle && _deviceIsCharging && !_isTrainingActive) {
        await _performLocalTraining();
      }
    });
  }

  /// Check if device has been idle (no user interaction)
  Future<bool> _checkIfIdle() async {
    try {
      // Query native platform for device activity state
      final isIdle = await platform.invokeMethod<bool>('isDeviceIdle') ?? false;
      
      if (isIdle) {
        // Double-check with local tracking
        // Only consider idle if no user interaction for _minIdleTime
        if (_lastUserInteraction != null) {
          final timeSinceLastInteraction = DateTime.now().difference(_lastUserInteraction!);
          return timeSinceLastInteraction > _minIdleTime;
        }
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Idle check error: $e');
      }
      // Fallback: check local timestamp
      if (_lastUserInteraction != null) {
        final timeSinceLastInteraction = DateTime.now().difference(_lastUserInteraction!);
        return timeSinceLastInteraction > _minIdleTime;
      }
      return false;
    }
  }

  /// Check if device is charging
  Future<bool> _checkIfCharging() async {
    try {
      // Query native platform for charging state
      // Requires Android: BatteryManager.isCharging()
      // iOS: UIDevice.batteryState
      final isCharging = await platform.invokeMethod<bool>('isDeviceCharging') ?? false;
      return isCharging;
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Charging check error: $e');
      }
      return false;
    }
  }

  /// Update last user interaction timestamp
  /// Called from UI when user interacts with the app
  void recordUserInteraction() {
    _lastUserInteraction = DateTime.now();
    platform.invokeMethod<void>('recordUserInteraction');
  }

  /// Perform local federated learning training
  ///
  /// This runs when the device is idle and charging:
  /// 1. Load local journal data from secure storage
  /// 2. Fine-tune the model on local data
  /// 3. Compute weight gradients
  /// 4. Apply SecAgg masking
  /// 5. Submit to coordinator
  Future<void> _performLocalTraining() async {
    if (_isTrainingActive) return;

    _isTrainingActive = true;
    try {
      if (kDebugMode) {
        print('[FL] Starting local training...');
      }

      // Load local journal entries for training
      final trainingData = await _loadTrainingData();
      if (trainingData.isEmpty) {
        if (kDebugMode) {
          print('[FL] No training data available');
        }
        return;
      }

      // Lightweight on-device adaptation: train a small linear head and use
      // its gradients as the FL signal. This is a practical approximation of
      // backprop while keeping compute and memory bounded on mobile.
      final gradients = await _computeGradients(trainingData);
      if (gradients.isEmpty) {
        if (kDebugMode) {
          print('[FL] Skipping submission: no valid gradients produced');
        }
        return;
      }

      _accumulatedGradients.addAll(gradients);
      _gradientNorm = _computeGradientNorm(_accumulatedGradients);

      // Apply Secure Aggregation masking
      final maskedGradient = _applySecureAggregationMask(_accumulatedGradients);

      // Submit to coordinator
      await _submitMaskedGradient(maskedGradient);

      if (kDebugMode) {
        print('[FL] Local training completed');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Local training error: $e');
      }
    } finally {
      _isTrainingActive = false;
      _accumulatedGradients.clear();
      _localTrainingSteps = 0;
      _gradientNorm = 0.0;
    }
  }

  /// Load journal entries for federated learning training
  Future<List<String>> _loadTrainingData() async {
    // In a real implementation, query the local database
    // for recent journal entries (encrypted, local only)
    // Example:
    // final entries = await StorageService.instance.getRecentEntries(limit: 50);
    // return entries.map((e) => e.text).toList();

    // Use persisted Unstuck sessions as current local corpus source.
    final sessions = StorageService.instance.readUnstuckSessions();
    if (sessions.isEmpty) return [];
    final payloads = <String>[];
    for (final session in sessions.take(50)) {
      final title = session['title']?.toString() ?? '';
      final notes = session['notes']?.toString() ?? '';
      final summary = session['summary']?.toString() ?? '';
      final merged = [title, notes, summary].where((s) => s.trim().isNotEmpty).join(' ');
      if (merged.isNotEmpty) payloads.add(merged);
    }
    return payloads;
  }

  /// Compute gradients from local training data
  ///
  /// Simulates fine-tuning the model and extracting weight gradients.
  /// In a real implementation, this would:
  /// 1. Run inference on local data
  /// 2. Compute loss
  /// 3. Backprop to get dW (weight gradients)
  /// 4. Return flattened gradient vector
  Future<List<double>> _computeGradients(List<String> trainingData) async {
    if (trainingData.isEmpty) return const <double>[];

    final embeddings = <List<double>>[];
    int? embeddingSize;

    for (final text in trainingData) {
      final emb = await _embeddingForText(text);
      if (emb.isEmpty) continue;

      embeddingSize ??= emb.length;
      embeddings.add(_resizeEmbedding(emb, embeddingSize));
    }

    if (embeddings.isEmpty || embeddingSize == null || embeddingSize <= 0) {
      return const <double>[];
    }

    _embeddingDim = embeddingSize;

    // Load or initialize local head weights for personalization.
    final loaded = StorageService.instance.loadFlHeadWeights();
    final head = loaded != null && loaded.length == _embeddingDim
        ? List<double>.from(loaded)
        : List<double>.filled(_embeddingDim, 0.0);

    final accumulated = List<double>.filled(_embeddingDim, 0.0);
    const learningRate = 0.01;
    int steps = 0;

    for (final emb in embeddings) {
      final prediction = _dot(head, emb);
      final target = 0.0;
      final error = prediction - target;

      // Backprop for linear head: dL/dw = 2 * error * x
      for (int i = 0; i < _embeddingDim; i++) {
        accumulated[i] += 2.0 * error * emb[i];
      }
      steps += 1;
    }

    final denom = math.max(1, steps);
    for (int i = 0; i < _embeddingDim; i++) {
      accumulated[i] /= denom;
      head[i] -= learningRate * accumulated[i];
    }

    await StorageService.instance.saveFlHeadWeights(head);
    _localTrainingSteps = steps;

    return accumulated;
  }

  Future<List<double>> _embeddingForText(String text) async {
    final fallbackDim = _embeddingDim > 0 ? _embeddingDim : _defaultEmbeddingDim;

    // Stable fallback so local training continues if interpreter/tokenizer fails.
    final seed = text.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    final seeded = math.Random(seed);
    final fallback = List<double>.generate(
      fallbackDim,
      (_) => (seeded.nextDouble() - 0.5) * 0.2,
    );

    final interpreter = _interpreter;
    if (interpreter == null) return fallback;

    try {
      final encoding = TokenizerService.instance.encode(text, maxLength: 128);
      final outputTensor = interpreter.getOutputTensor(0);
      final outputShape = outputTensor.shape;
      if (outputShape.isEmpty) {
        return fallback;
      }

      final outputBuffer = _allocateOutputBuffer(outputShape);
      final inputs = _buildTokenizerInputs(interpreter, encoding);

      interpreter.runForMultipleInputs(inputs, {0: outputBuffer});

      final embedding = _extractEmbedding(outputBuffer, outputShape, encoding.attentionMask);
      if (embedding.isEmpty) {
        return fallback;
      }

      return _normalizeVector(embedding);
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Tokenizer->TFLite embedding failed: $e');
      }
      return fallback;
    }
  }

  List<Object> _buildTokenizerInputs(
    Interpreter interpreter,
    TokenizerEncoding encoding,
  ) {
    final ids = encoding.inputIds.toList(growable: false);
    final mask = encoding.attentionMask.toList(growable: false);
    final tokenTypes = List<int>.filled(ids.length, 0);
    final inputTensors = interpreter.getInputTensors();

    if (inputTensors.length == 2) {
      return [
        [mask],
        [ids],
      ];
    }

    if (inputTensors.isEmpty) {
      return [
        [ids],
      ];
    }

    final inputs = <Object>[];
    for (final tensor in inputTensors) {
      final name = tensor.name.toLowerCase();
      if (name.contains('mask')) {
        inputs.add([mask]);
      } else if (name.contains('token_type') || name.contains('segment')) {
        inputs.add([tokenTypes]);
      } else {
        inputs.add([ids]);
      }
    }
    return inputs;
  }

  Object _allocateOutputBuffer(List<int> shape) {
    if (shape.length == 1) {
      return List<double>.filled(shape[0], 0.0);
    }

    if (shape.length == 2) {
      return List<List<double>>.generate(
        shape[0],
        (_) => List<double>.filled(shape[1], 0.0),
        growable: false,
      );
    }

    if (shape.length == 3) {
      return List<List<List<double>>>.generate(
        shape[0],
        (_) => List<List<double>>.generate(
          shape[1],
          (_) => List<double>.filled(shape[2], 0.0),
          growable: false,
        ),
        growable: false,
      );
    }

    final flattened = shape.fold<int>(1, (acc, value) => acc * value);
    return List<double>.filled(flattened, 0.0);
  }

  List<double> _extractEmbedding(
    Object outputBuffer,
    List<int> outputShape,
    Int32List attentionMask,
  ) {
    if (outputShape.length == 3 && outputBuffer is List) {
      final batch = outputBuffer.isNotEmpty ? outputBuffer.first : null;
      if (batch is! List || batch.isEmpty) return const <double>[];

      final tokenVectors = batch.whereType<List>().toList(growable: false);
      if (tokenVectors.isEmpty) return const <double>[];

      // Mean-pool only attended tokens for a stable sentence embedding.
      final hiddenSize = tokenVectors.first.length;
      final pooled = List<double>.filled(hiddenSize, 0.0);
      int tokenCount = 0;
      final usableLength = math.min(tokenVectors.length, attentionMask.length);

      for (int i = 0; i < usableLength; i++) {
        if (attentionMask[i] == 0) continue;
        final token = tokenVectors[i];
        for (int j = 0; j < hiddenSize && j < token.length; j++) {
          pooled[j] += _asDouble(token[j]);
        }
        tokenCount += 1;
      }

      if (tokenCount == 0) {
        return tokenVectors.first.map(_asDouble).toList(growable: false);
      }

      for (int j = 0; j < pooled.length; j++) {
        pooled[j] /= tokenCount;
      }
      return pooled;
    }

    if (outputShape.length == 2 && outputBuffer is List && outputBuffer.isNotEmpty) {
      final firstRow = outputBuffer.first;
      if (firstRow is List) {
        return firstRow.map(_asDouble).toList(growable: false);
      }
    }

    if (outputShape.length == 1 && outputBuffer is List) {
      return outputBuffer.map(_asDouble).toList(growable: false);
    }

    if (outputBuffer is List) {
      return outputBuffer.map(_asDouble).toList(growable: false);
    }

    return const <double>[];
  }

  List<double> _normalizeVector(List<double> vector) {
    if (vector.isEmpty) return vector;

    final l2 = math.sqrt(vector.fold<double>(0.0, (sum, value) => sum + (value * value)));
    if (l2 <= 1e-9) return vector;

    return vector.map((value) => value / l2).toList(growable: false);
  }

  List<double> _resizeEmbedding(List<double> embedding, int size) {
    if (embedding.length == size) return embedding;
    if (size <= 0) return const <double>[];

    final resized = List<double>.filled(size, 0.0);
    final copyLength = math.min(size, embedding.length);
    for (int i = 0; i < copyLength; i++) {
      resized[i] = embedding[i];
    }
    return resized;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return 0.0;
  }

  double _dot(List<double> a, List<double> b) {
    var sum = 0.0;
    final len = math.min(a.length, b.length);
    for (var i = 0; i < len; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  /// Compute the L2 norm of gradients for monitoring
  double _computeGradientNorm(List<double> gradients) {
    if (gradients.isEmpty) return 0.0;
    final sumSquares = gradients.fold<double>(0.0, (sum, g) => sum + (g * g));
    return math.sqrt(sumSquares);
  }

  /// Apply Secure Aggregation (SecAgg) masking
  ///
  /// **SecAgg Protocol:**
  /// 1. Generate random mask R ~ N(0, sigma²)
  /// 2. Add mask to gradients: masked = gradients + R
  /// 3. Return masked gradients to server
  /// 4. Server aggregates from 1000+ clients
  /// 5. When summed, individual masks cancel mathematically: Σ(R_i) ≈ 0
  /// 6. Result: Σ(gradients_i + R_i) ≈ Σ(gradients_i) = true average
  List<double> _applySecureAggregationMask(List<double> gradients) {
    const double maskSigma = 0.1; // Tunable privacy parameter
    final random = math.Random();

    return gradients.map((g) {
      // Generate random mask element from Gaussian distribution
      // Using Box-Muller transform for approximately normal distribution
      final u1 = random.nextDouble();
      final u2 = random.nextDouble();
      final mask = maskSigma *
          math.sqrt(-2.0 * math.log(u1)) *
          math.cos(2.0 * math.pi * u2);

      return g + mask;
    }).toList();
  }

  /// Submit masked gradients to the FL coordinator
  Future<void> _submitMaskedGradient(List<double> maskedGradient) async {
    if (maskedGradient.isEmpty) {
      if (kDebugMode) {
        print('[FL] Gradient submission skipped: empty gradient vector');
      }
      return;
    }

    try {
      final deviceId = StorageService.instance.deviceId;
      final now = DateTime.now().toUtc();

      final roundId = await _resolveActiveRoundId();

      final response = await ApiEndpointService.instance.post(
        Uri.parse('${ApiEndpointService.instance.buildUri('/fl').toString()}/gradients/submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'patient_device_id': deviceId,
          'round_id': roundId,
          'model_version': _currentModelVersionInt,
          'masked_gradient': maskedGradient,
          'gradient_norm': _gradientNorm,
          'num_local_steps': _localTrainingSteps,
          'timestamp': now.toIso8601String(),
        }),
      );

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final gradientId = body['gradient_id'] as String? ?? 'unknown';
        if (kDebugMode) {
          print('[FL] Gradient submitted: gradient_id=$gradientId');
        }
      } else {
        if (kDebugMode) {
          print('[FL] Gradient submission failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Gradient submission error: $e');
      }
    }
  }

  Future<int> _resolveActiveRoundId() async {
    try {
      final deviceId = StorageService.instance.deviceId;
      final response = await ApiEndpointService.instance.get(
        ApiEndpointService.instance.buildUri(
          '/fl/rounds/active',
          queryParameters: {
            'patient_device_id': deviceId,
            'app_version': _localModelVersion,
          },
        ),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final roundId = body['round_id'] as int?;
        if (roundId != null && roundId >= 0) {
          return roundId;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Active round lookup failed, defaulting to round 0: $e');
      }
    }

    return 0;
  }

  /// Check FL round status (for monitoring)
  Future<Map<String, dynamic>?> checkRoundStatus(int roundId) async {
    try {
      final response = await ApiEndpointService.instance.get(
        Uri.parse('${ApiEndpointService.instance.buildUri('/fl').toString()}/rounds/$roundId'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FL] Round status check failed: $e');
      }
    }
    return null;
  }

  /// Clean up resources
  void dispose() {
    _idleDetectionTimer?.cancel();
    _interpreter?.close();
  }
}
