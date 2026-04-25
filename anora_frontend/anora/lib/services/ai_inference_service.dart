import 'dart:math' as math;

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tokenizer_service.dart';

class AiInferenceService {
  AiInferenceService._();

  static final AiInferenceService instance = AiInferenceService._();

  static const String _modelAssetPath = 'assets/models/mentalbert_quant.tflite';

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
      if (probabilities[_emotionLabels.length + index] >= 0.5) {
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
