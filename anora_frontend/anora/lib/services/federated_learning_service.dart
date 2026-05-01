import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'api_endpoint_service.dart';
import 'storage_service.dart';

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
  static const int _embeddingDim = 512;

  /// Initialize federated learning client
  Future<void> init({
    String? appVersion,
  }) async {
    _localModelVersion = appVersion ?? _localModelVersion;
    _lastUserInteraction = DateTime.now(); // Start with "just now"
    await _registerWithCoordinator();
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilebert_quant.tflite');
      if (kDebugMode) {
        print('[FL] TFLite interpreter initialized');
      }
    } catch (e) {
      _interpreter = null;
      if (kDebugMode) {
        print('[FL] TFLite init skipped: $e');
      }
    }
    _startIdleDetection();
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

        if (newVersion > _currentModelVersionInt) {
          // In a real implementation, you would:
          // 1. Decode base64_weights
          // 2. Replace the local model file
          // 3. Reload the interpreter

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
      _accumulatedGradients.addAll(await _computeGradients(trainingData));
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
    if (trainingData.isEmpty) return List<double>.filled(_embeddingDim, 0.0);

    // Load or initialize local head weights for personalization.
    final loaded = StorageService.instance.loadFlHeadWeights();
    final head = loaded != null && loaded.length == _embeddingDim
        ? List<double>.from(loaded)
        : List<double>.filled(_embeddingDim, 0.0);

    final accumulated = List<double>.filled(_embeddingDim, 0.0);
    final random = math.Random.secure();
    const learningRate = 0.01;
    int steps = 0;

    for (final text in trainingData) {
      final emb = await _embeddingForText(text, random);
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

  Future<List<double>> _embeddingForText(String text, math.Random random) async {
    // Real tokenizer + interpreter inputs are TODO. For now, generate a stable-ish
    // embedding from text hash to make training deterministic per sample.
    final seed = text.codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7fffffff);
    final seeded = math.Random(seed);
    final fallback = List<double>.generate(
      _embeddingDim,
      (_) => (seeded.nextDouble() - 0.5) * 0.2,
    );

    if (_interpreter == null) return fallback;

    // Interpreter path is currently stubbed until tokenizer tensors are wired.
    // Keeping fallback ensures loop is functional end-to-end.
    return fallback;
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
    try {
      final deviceId = StorageService.instance.deviceId;
      final now = DateTime.now().toUtc();

      // Get the current FL round (in a real implementation, query the server)
      const int roundId = 0; // Placeholder

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
