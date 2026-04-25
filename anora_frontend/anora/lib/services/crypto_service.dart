import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

class CryptoException implements Exception {
  CryptoException(this.message);

  final String message;

  @override
  String toString() => 'CryptoException: $message';
}

class CryptoService {
  CryptoService._();

  static final CryptoService instance = CryptoService._();

  Uint8List generateAesKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  Map<String, String> encryptAes(Uint8List key, String plaintext) {
    if (key.lengthInBytes != 32) {
      throw CryptoException('AES-256-GCM requires a 32-byte key.');
    }

    final iv = _secureBytes(12);
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));

    try {
      cipher.init(true, params);
      final plainBytes = Uint8List.fromList(utf8.encode(plaintext));
      final encrypted = cipher.process(plainBytes);
      if (encrypted.length < 16) {
        throw CryptoException('Encrypted payload is invalid.');
      }

      final tagStart = encrypted.length - 16;
      final ciphertext = encrypted.sublist(0, tagStart);
      final tag = encrypted.sublist(tagStart);

      return <String, String>{
        'ciphertext': base64Encode(ciphertext),
        'iv': base64Encode(iv),
        'tag': base64Encode(tag),
      };
    } catch (error) {
      throw CryptoException('AES encryption failed: $error');
    }
  }

  String encryptRsa(String clinicianPublicKeyPem, Uint8List data) {
    try {
      final publicKey = _parseRsaPublicKeyFromPem(clinicianPublicKeyPem);
      final rsaCipher = OAEPEncoding.withSHA256(RSAEngine(), Uint8List(0));
      rsaCipher.init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
      final encrypted = rsaCipher.process(data);
      return base64Encode(encrypted);
    } catch (error) {
      throw CryptoException('RSA encryption failed: $error');
    }
  }

  String decryptAes(Uint8List key, Map<String, String> cipherBundle) {
    if (key.lengthInBytes != 32) {
      throw CryptoException('AES-256-GCM requires a 32-byte key.');
    }

    final ciphertextBase64 = cipherBundle['ciphertext'];
    final ivBase64 = cipherBundle['iv'];
    final tagBase64 = cipherBundle['tag'];

    if (ciphertextBase64 == null || ivBase64 == null || tagBase64 == null) {
      throw CryptoException('cipherBundle must include ciphertext, iv, and tag.');
    }

    try {
      final ciphertext = base64Decode(ciphertextBase64);
      final iv = base64Decode(ivBase64);
      final tag = base64Decode(tagBase64);
      final combined = Uint8List.fromList(<int>[...ciphertext, ...tag]);

      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
      cipher.init(false, params);
      final decrypted = cipher.process(combined);
      return utf8.decode(decrypted);
    } catch (error) {
      throw CryptoException('AES decryption failed: $error');
    }
  }

  Uint8List _secureBytes(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }

  RSAPublicKey _parseRsaPublicKeyFromPem(String pem) {
    final cleaned = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll(RegExp(r'\s'), '');

    if (cleaned.isEmpty) {
      throw CryptoException('Clinician public key PEM is empty.');
    }

    final derBytes = base64Decode(cleaned);
    final asn1Parser = ASN1Parser(derBytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    if (topLevelSeq.elements == null || topLevelSeq.elements!.length < 2) {
      throw CryptoException('Invalid RSA public key structure.');
    }

    final bitString = topLevelSeq.elements![1] as ASN1BitString;
    final publicKeyAsn = ASN1Parser(Uint8List.fromList(bitString.stringValue));
    final publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;

    if (publicKeySeq.elements == null || publicKeySeq.elements!.length < 2) {
      throw CryptoException('Invalid RSA public key payload.');
    }

    final modulus =
        (publicKeySeq.elements![0] as ASN1Integer).valueAsBigInteger;
    final exponent =
        (publicKeySeq.elements![1] as ASN1Integer).valueAsBigInteger;

    if (modulus == null || exponent == null) {
      throw CryptoException('RSA key modulus/exponent missing.');
    }

    return RSAPublicKey(modulus, exponent);
  }
}
