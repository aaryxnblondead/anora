import 'dart:math' as math;

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tokenizer_service.dart';

class AiInferenceService {
  AiInferenceService._();

  static final AiInferenceService instance = AiInferenceService._();

  static const String _modelAssetPath = 'assets/models/mobilebert_quant.tflite';

  static const List<String> _emotionLabels = <String>[
    'joy',
    'sadness',
    'anger',
    'fear',
    'disgust',
    'surprise',
    'neutral',
  ];

  static const Map<String, String> _riskLabelDisplayNames = <String, String>{
    'risk_selfharm': 'Self-harm',
    'risk_anxiety': 'Anxiety',
    'risk_depression': 'Depression',
    'risk_mania': 'Mania',
  };

  static const List<String> _riskLabelOrder = <String>[
    'risk_selfharm',
    'risk_anxiety',
    'risk_depression',
    'risk_mania',
  ];

  static const Map<String, double> _riskThresholds = <String, double>{
    'risk_selfharm': 0.35,
    'risk_anxiety': 0.50,
    'risk_depression': 0.55,
    'risk_mania': 0.60,
  };

  Interpreter? _interpreter;

  Future<void> init({int threads = 2}) async {
    if (_interpreter != null) {
      return;
    }

    await TokenizerService.instance.init();
    _interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: InterpreterOptions()..threads = threads,
    );
  }

  Future<AiInferenceResult> analyze(String text) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('AiInferenceService.init() must be called before analyze().');
    }

    final encoding = TokenizerService.instance.encode(text);
    final logits = List<double>.filled(11, 0.0);
    final output = <int, Object>{
      0: <List<double>>[logits],
    };

    interpreter.runForMultipleInputs(
      [
        [encoding.inputIds],
        [encoding.attentionMask],
      ],
      output,
    );

    final probabilities = logits
        .map((logit) => 1.0 / (1.0 + math.exp(-logit)))
        .toList(growable: false);

    final emotionScores = <String, double>{
      for (var index = 0; index < _emotionLabels.length; index++)
        _emotionLabels[index]: probabilities[index],
    };

    final dominantEmotion = emotionScores.entries
        .reduce((left, right) => left.value >= right.value ? left : right)
        .key;

    final riskFlags = <String>[];
    for (var index = 0; index < _riskLabelOrder.length; index++) {
      final label = _riskLabelOrder[index];
      final threshold = _riskThresholds[label] ?? 0.5;
      if (probabilities[_emotionLabels.length + index] >= threshold) {
        riskFlags.add(_riskLabelDisplayNames[label] ?? label);
      }
    }

    final sentimentScore = _deriveSentimentScore(probabilities);

    return AiInferenceResult(
      sentimentScore: sentimentScore,
      riskFlags: List.unmodifiable(riskFlags),
      emotionScores: Map.unmodifiable(emotionScores),
      dominantEmotion: dominantEmotion,
    );
  }

  Future<InferenceBenchmark> benchmarkLatency(
    String text, {
    int warmupRuns = 5,
    int measuredRuns = 30,
  }) async {
    if (warmupRuns < 0 || measuredRuns <= 0) {
      throw ArgumentError('warmupRuns must be >= 0 and measuredRuns must be > 0.');
    }

    for (var index = 0; index < warmupRuns; index++) {
      await analyze(text);
    }

    var totalMicros = 0;
    var minMicros = 1 << 62;
    var maxMicros = 0;

    for (var index = 0; index < measuredRuns; index++) {
      final stopwatch = Stopwatch()..start();
      await analyze(text);
      stopwatch.stop();
      final elapsed = stopwatch.elapsedMicroseconds;
      totalMicros += elapsed;
      if (elapsed < minMicros) {
        minMicros = elapsed;
      }
      if (elapsed > maxMicros) {
        maxMicros = elapsed;
      }
    }

    return InferenceBenchmark(
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
      averageMs: (totalMicros / measuredRuns) / 1000.0,
      minMs: minMicros / 1000.0,
      maxMs: maxMicros / 1000.0,
    );
  }

  double _deriveSentimentScore(List<double> probabilities) {
    final positive = probabilities[0] + (probabilities[5] * 0.5) + (probabilities[6] * 0.35);
    final negative = probabilities[1] + probabilities[2] + probabilities[3] + probabilities[4];
    final score = 0.5 + ((positive - negative) * 0.5);
    return score.clamp(0.0, 1.0);
  }
}

class AiInferenceResult {
  const AiInferenceResult({
    required this.sentimentScore,
    required this.riskFlags,
    required this.emotionScores,
    required this.dominantEmotion,
  });

  final double sentimentScore;
  final List<String> riskFlags;
  final Map<String, double> emotionScores;
  final String? dominantEmotion;
}

class InferenceBenchmark {
  const InferenceBenchmark({
    required this.warmupRuns,
    required this.measuredRuns,
    required this.averageMs,
    required this.minMs,
    required this.maxMs,
  });

  final int warmupRuns;
  final int measuredRuns;
  final double averageMs;
  final double minMs;
  final double maxMs;
}
