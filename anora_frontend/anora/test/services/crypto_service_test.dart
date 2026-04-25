import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:anora/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('CryptoService', () {
    test('AES-GCM + RSA OAEP round-trip preserves plaintext', () {
      final crypto = CryptoService.instance;
      const plaintext = 'Known plaintext for locked-box crypto chain.';

      final aesKey = crypto.generateAesKey();
      expect(aesKey.length, 32);

      final encryptedPayload = crypto.encryptAes(aesKey, plaintext);

      final keyPair = _generateRsaKeyPair();
      final publicKey = keyPair.publicKey as RSAPublicKey;
      final privateKey = keyPair.privateKey as RSAPrivateKey;

      final publicKeyPem = _publicKeyToPemForServiceParser(publicKey);
      final encryptedAesKeyBase64 = crypto.encryptRsa(publicKeyPem, aesKey);
      final encryptedAesKey = base64Decode(encryptedAesKeyBase64);

      final rsaDecryptor = OAEPEncoding.withSHA256(RSAEngine(), Uint8List(0))
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      final decryptedAesKey = Uint8List.fromList(rsaDecryptor.process(encryptedAesKey));
      expect(decryptedAesKey, orderedEquals(aesKey));

      final decryptedPlaintext = crypto.decryptAes(decryptedAesKey, encryptedPayload);
      expect(decryptedPlaintext, plaintext);
    });
  });
}

AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPair() {
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        _fortunaRandom(),
      ),
    );

  return generator.generateKeyPair();
}

FortunaRandom _fortunaRandom() {
  final random = FortunaRandom();
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  random.seed(KeyParameter(seed));
  return random;
}

String _publicKeyToPemForServiceParser(RSAPublicKey publicKey) {
  final rsaPublicKeySequence = ASN1Sequence()
    ..add(ASN1Integer(publicKey.modulus!))
    ..add(ASN1Integer(publicKey.exponent!));

  final topLevelSequence = ASN1Sequence()
    ..add(ASN1Sequence()..add(ASN1Integer(BigInt.one)))
    ..add(ASN1BitString(Uint8List.fromList(rsaPublicKeySequence.encodedBytes)));

  final der = topLevelSequence.encodedBytes;
  final pemBody = _chunk64(base64Encode(der));
  return '-----BEGIN PUBLIC KEY-----\n$pemBody\n-----END PUBLIC KEY-----';
}

String _chunk64(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i += 64) {
    final end = (i + 64 < value.length) ? i + 64 : value.length;
    buffer.writeln(value.substring(i, end));
  }
  return buffer.toString().trimRight();
}
