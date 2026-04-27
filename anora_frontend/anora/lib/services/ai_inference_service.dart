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
    'risk_selfharm': 0.80,
    'risk_anxiety': 0.75,
    'risk_depression': 0.75,
    'risk_mania': 0.78,
  };

  static const Set<String> _positiveWords = <String>{
    'happy', 'blessed', 'thankful', 'grateful', 'wonderful', 'great',
    'amazing', 'fantastic', 'joyful', 'love', 'peaceful', 'excited',
    'good', 'excellent', 'beautiful', 'delighted', 'cheerful', 'content',
  };

  Interpreter? _interpreter;

  Future<void> init({int threads = 2}) async {
    if (_interpreter != null) {
      return;
    }

    await TokenizerService.instance.init();
    try {
      _interpreter = await Interpreter.fromAsset(
        _modelAssetPath,
        options: InterpreterOptions()..threads = threads,
      );
      return;
    } catch (threadedError) {
      // Some devices fail interpreter construction with custom thread settings.
      try {
        _interpreter = await Interpreter.fromAsset(_modelAssetPath);
        return;
      } catch (fallbackError) {
        throw StateError(
          'Failed to initialize TFLite interpreter for $_modelAssetPath. '
          'threadedError=$threadedError; fallbackError=$fallbackError',
        );
      }
    }
  }

  Future<AiInferenceResult> analyze(String text) async {
    final normalizedText = text.trim();
    final wordCount = normalizedText.isEmpty
        ? 0
        : normalizedText.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    if (normalizedText.length < 10 || wordCount < 3) {
      return const AiInferenceResult(
        sentimentScore: 0.5,
        riskFlags: <String>[],
        emotionScores: <String, double>{},
        dominantEmotion: 'neutral',
      );
    }

    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('AiInferenceService.init() must be called before analyze().');
    }

    final encoding = TokenizerService.instance.encode(normalizedText);
    final logits = List<double>.filled(11, 0.0);
    final output = <int, Object>{
      0: <List<double>>[logits],
    };

    interpreter.runForMultipleInputs(
      [
        [encoding.attentionMask],
        [encoding.inputIds],
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

    final positiveContext = _isPositiveContext(normalizedText);
    final adjustedProbabilities = positiveContext
        ? probabilities.asMap().map((i, v) =>
            MapEntry(i, i < 7 ? v : v * 0.25)).values.toList()
        : probabilities;

    final criticalPhrase = _containsCriticalSelfHarmPhrase(normalizedText);

    final riskFlags = <String>[];
    for (var index = 0; index < _riskLabelOrder.length; index++) {
      final label = _riskLabelOrder[index];
      final threshold = _riskThresholds[label] ?? 0.5;
      if (adjustedProbabilities[_emotionLabels.length + index] >= threshold) {
        riskFlags.add(_riskLabelDisplayNames[label] ?? label);
      }
    }

    var sentimentScore = _deriveSentimentScore(probabilities);

    // Safety override: explicit self-harm language should never be interpreted as safe.
    if (criticalPhrase) {
      if (!riskFlags.contains('Self-harm')) {
        riskFlags.insert(0, 'Self-harm');
      }
      if (!riskFlags.contains('Depression')) {
        riskFlags.add('Depression');
      }
      sentimentScore = sentimentScore.clamp(0.0, 0.15);
    }

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
    final joy = probabilities[0];
    final surprise = probabilities[5];
    final neutral = probabilities[6];
    final sadness = probabilities[1];
    final anger = probabilities[2];
    final fear = probabilities[3];
    final disgust = probabilities[4];

    final positive = (joy * 0.80) + (surprise * 0.35) + (neutral * 0.45);
    final negative = (sadness * 0.85) + (anger * 0.65) + (fear * 0.70) + (disgust * 0.60);

    final score = 0.5 + ((positive - negative) * 0.65);
    return score.clamp(0.0, 1.0);
  }

  bool _isPositiveContext(String text) {
    final words = text.toLowerCase().split(RegExp(r'\W+'));
    final matchCount = words.where((w) => _positiveWords.contains(w)).length;
    return matchCount >= 1 && !_containsCriticalSelfHarmPhrase(text);
  }

  bool _containsCriticalSelfHarmPhrase(String text) {
    final lowerText = text.toLowerCase();
    return lowerText.contains('killing myself') ||
        lowerText.contains('end my life') ||
        lowerText.contains('suicide') ||
        lowerText.contains('want to die') ||
        lowerText.contains('ready to die') ||
        lowerText.contains('hurt myself');
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
