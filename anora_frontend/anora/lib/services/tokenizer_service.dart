import 'dart:typed_data';

import 'package:flutter/services.dart';

class TokenizerService {
  TokenizerService._();

  static final TokenizerService instance = TokenizerService._();

  static const String _vocabAssetPath = 'assets/models/vocab.txt';
  static const String _unkToken = '[UNK]';
  static const String _clsToken = '[CLS]';
  static const String _sepToken = '[SEP]';
  static const String _padToken = '[PAD]';

  final Map<String, int> _vocab = <String, int>{};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final vocabText = await rootBundle.loadString(_vocabAssetPath);
    final lines = vocabText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    for (var index = 0; index < lines.length; index++) {
      _vocab[lines[index]] = index;
    }

    for (final specialToken in const <String>[
      _unkToken,
      _clsToken,
      _sepToken,
      _padToken,
    ]) {
      if (!_vocab.containsKey(specialToken)) {
        throw StateError(
          'Tokenizer vocab is missing required token: $specialToken',
        );
      }
    }

    _initialized = true;
  }

  TokenizerEncoding encode(String text, {int maxLength = 128}) {
    if (!_initialized) {
      throw StateError('TokenizerService.init() must be called before encode().');
    }

    final tokens = <String>[_clsToken];
    for (final token in _basicTokenize(text)) {
      tokens.addAll(_wordPieceTokenize(token));
    }
    tokens.add(_sepToken);

    final inputIds = Int32List(maxLength);
    final attentionMask = Int32List(maxLength);
    final padId = _vocab[_padToken]!;

    for (var index = 0; index < maxLength; index++) {
      inputIds[index] = padId;
    }

    final usableTokenCount = tokens.length > maxLength ? maxLength : tokens.length;
    for (var index = 0; index < usableTokenCount; index++) {
      inputIds[index] = _idFor(tokens[index]);
      attentionMask[index] = 1;
    }

    return TokenizerEncoding(
      inputIds: inputIds,
      attentionMask: attentionMask,
    );
  }

  List<String> _basicTokenize(String text) {
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final matches = RegExp(r"[a-z0-9']+|[^\s]").allMatches(normalized);
    return matches.map((match) => match.group(0)!).toList(growable: false);
  }

  List<String> _wordPieceTokenize(String token) {
    if (_vocab.containsKey(token)) {
      return <String>[token];
    }

    final pieces = <String>[];
    var start = 0;

    while (start < token.length) {
      var end = token.length;
      String? currentPiece;

      while (start < end) {
        final prefix = start == 0 ? '' : '##';
        final candidate = '$prefix${token.substring(start, end)}';
        if (_vocab.containsKey(candidate)) {
          currentPiece = candidate;
          break;
        }
        end--;
      }

      if (currentPiece == null) {
        return <String>[_unkToken];
      }

      pieces.add(currentPiece);
      start = end;
    }

    return pieces;
  }

  int _idFor(String token) {
    return _vocab[token] ?? _vocab[_unkToken]!;
  }
}

class TokenizerEncoding {
  const TokenizerEncoding({
    required this.inputIds,
    required this.attentionMask,
  });

  final Int32List inputIds;
  final Int32List attentionMask;
}