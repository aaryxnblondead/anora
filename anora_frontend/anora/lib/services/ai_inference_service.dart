import 'dart:async';

class AiInferenceService {
  AiInferenceService._();

  static final AiInferenceService instance = AiInferenceService._();

  // TODO: Enable this once the .tflite model and tokenizer assets are added.
  // late final Interpreter _interpreter;
  //
  // Future<void> init() async {
  //   _interpreter = await Interpreter.fromAsset(
  //     'models/mentalbert.tflite',
  //     options: InterpreterOptions()..threads = 2,
  //   );
  // }
  //
  // AiInferenceResult runInference(List<int> tokenIds, List<int> mask) {
  //   final inputIds = [tokenIds];
  //   final inputMask = [mask];
  //   final output = List.filled(1 * 1, 0.0).reshape([1, 1]);
  //
  //   _interpreter.runForMultipleInputs([inputIds, inputMask], output);
  //
  //   final sentimentScore = output[0][0] as double;
  //   return AiInferenceResult(
  //     sentimentScore: sentimentScore.clamp(0.0, 1.0),
  //     riskFlags: const [],
  //   );
  // }

  Future<AiInferenceResult> mockAnalyze(String text) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final normalized = text.toLowerCase();
    final riskFlags = <String>[];
    if (normalized.contains('worry')) {
      riskFlags.add('Anxiety');
    }

    final sentimentScore = _estimateSentiment(normalized);

    return AiInferenceResult(
      sentimentScore: sentimentScore,
      riskFlags: riskFlags,
    );
  }

  double _estimateSentiment(String text) {
    if (text.trim().isEmpty) {
      return 0.5;
    }

    const positiveHints = ['calm', 'okay', 'better', 'hopeful', 'steady'];
    const negativeHints = ['sad', 'down', 'tired', 'overwhelmed', 'anxious'];

    var score = 0.5;
    for (final hint in positiveHints) {
      if (text.contains(hint)) {
        score += 0.08;
      }
    }
    for (final hint in negativeHints) {
      if (text.contains(hint)) {
        score -= 0.08;
      }
    }

    if (text.length > 220) {
      score -= 0.03;
    }

    return score.clamp(0.0, 1.0);
  }
}

class AiInferenceResult {
  const AiInferenceResult({
    required this.sentimentScore,
    required this.riskFlags,
  });

  final double sentimentScore;
  final List<String> riskFlags;
}
