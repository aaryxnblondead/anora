import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

import 'crypto_service.dart';
import 'storage_service.dart';

class ClinicianCryptoException implements Exception {
  ClinicianCryptoException(this.message);

  final String message;

  @override
  String toString() => 'ClinicianCryptoException: $message';
}

class ClinicianCryptoService {
  ClinicianCryptoService._();

  static final ClinicianCryptoService instance = ClinicianCryptoService._();

  static const _privateKeyStorageKey = 'clinician_private_key_pem';
  static const _publicKeyStorageKey = 'clinician_public_key_pem';

  Future<void> generateAndStoreKeypair() async {
    try {
      final keyPair = _generateRsaKeyPair();
      final publicKey = keyPair.publicKey as RSAPublicKey;
      final privateKey = keyPair.privateKey as RSAPrivateKey;

      final privatePem = _encodePrivateKeyToPkcs8Pem(privateKey, publicKey.exponent!);
      final publicPem = _encodePublicKeyToSpkiPem(publicKey);

      await StorageService.instance.settingsBox.put(_privateKeyStorageKey, privatePem);
      await StorageService.instance.settingsBox.put(_publicKeyStorageKey, publicPem);
    } catch (error) {
      throw ClinicianCryptoException('Failed to generate keypair: $error');
    }
  }

  Future<void> validateAndStorePrivateKey(String privatePem) async {
    try {
      final parsed = _parsePrivateKeyPem(privatePem);
      final privateKey = parsed.privateKey;
      final publicKey = RSAPublicKey(privateKey.modulus!, parsed.publicExponent);

      final normalizedPrivatePem = _encodePrivateKeyToPkcs8Pem(privateKey, parsed.publicExponent);
      final publicPem = _encodePublicKeyToSpkiPem(publicKey);

      await StorageService.instance.settingsBox.put(_privateKeyStorageKey, normalizedPrivatePem);
      await StorageService.instance.settingsBox.put(_publicKeyStorageKey, publicPem);
    } catch (error) {
      throw ClinicianCryptoException('Invalid private key PEM: $error');
    }
  }

  String? getPublicKeyPem() {
    final value = StorageService.instance.settingsBox.get(_publicKeyStorageKey);
    return value is String && value.isNotEmpty ? value : null;
  }

  String? getPrivateKeyPem() {
    final value = StorageService.instance.settingsBox.get(_privateKeyStorageKey);
    return value is String && value.isNotEmpty ? value : null;
  }

  bool get hasKeypair {
    final privateKey = getPrivateKeyPem();
    final publicKey = getPublicKeyPem();
    return privateKey != null && publicKey != null;
  }

  String decryptReportPayload({
    required String encryptedKeyB64,
    required Map<String, String> encryptedPayload,
  }) {
    try {
      final privatePem = getPrivateKeyPem();
      if (privatePem == null) {
        throw ClinicianCryptoException('No private key is stored on this device.');
      }

      final privateKey = _parsePrivateKeyPem(privatePem).privateKey;
      final encryptedKey = base64Decode(encryptedKeyB64);

      final rsaDecryptor = OAEPEncoding.withSHA256(RSAEngine(), Uint8List(0))
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      final aesKey = Uint8List.fromList(rsaDecryptor.process(encryptedKey));
      final plaintext = CryptoService.instance.decryptAes(aesKey, encryptedPayload);
      return plaintext;
    } catch (error) {
      throw ClinicianCryptoException('Failed to decrypt report payload: $error');
    }
  }

  AsymmetricKeyPair<PublicKey, PrivateKey> _generateRsaKeyPair() {
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          _secureRandom(),
        ),
      );
    return generator.generateKeyPair();
  }

  SecureRandom _secureRandom() {
    final random = FortunaRandom();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
    random.seed(KeyParameter(seed));
    return random;
  }

  _ParsedPrivateKey _parsePrivateKeyPem(String pem) {
    final normalized = pem.trim();
    if (normalized.isEmpty) {
      throw ClinicianCryptoException('Private key PEM is empty.');
    }

    final isPkcs8 = normalized.contains('BEGIN PRIVATE KEY');
    final isPkcs1 = normalized.contains('BEGIN RSA PRIVATE KEY');
    if (!isPkcs8 && !isPkcs1) {
      throw ClinicianCryptoException('Unsupported PEM header.');
    }

    final derBytes = _decodePem(normalized);
    final parser = ASN1Parser(derBytes);
    final topLevel = parser.nextObject() as ASN1Sequence;

    ASN1Sequence privateSeq;
    if (isPkcs8) {
      if (topLevel.elements.length < 3) {
        throw ClinicianCryptoException('Invalid PKCS#8 private key structure.');
      }
      final privateOctets = topLevel.elements[2] as ASN1OctetString;
      privateSeq = ASN1Parser(privateOctets.valueBytes()).nextObject() as ASN1Sequence;
    } else {
      privateSeq = topLevel;
    }

    final elements = privateSeq.elements;
    if (elements.length < 9) {
      throw ClinicianCryptoException('Invalid RSA private key fields.');
    }

    final modulus = (elements[1] as ASN1Integer).valueAsBigInteger;
    final publicExponent = (elements[2] as ASN1Integer).valueAsBigInteger;
    final privateExponent = (elements[3] as ASN1Integer).valueAsBigInteger;
    final p = (elements[4] as ASN1Integer).valueAsBigInteger;
    final q = (elements[5] as ASN1Integer).valueAsBigInteger;

    return _ParsedPrivateKey(
      privateKey: RSAPrivateKey(modulus, privateExponent, p, q),
      publicExponent: publicExponent,
    );
  }

  Uint8List _decodePem(String pem) {
    final cleaned = pem
        .replaceAll('-----BEGIN PRIVATE KEY-----', '')
        .replaceAll('-----END PRIVATE KEY-----', '')
        .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
        .replaceAll('-----END RSA PRIVATE KEY-----', '')
        .replaceAll(RegExp(r'\s'), '');
    return base64Decode(cleaned);
  }

  String _encodePrivateKeyToPkcs8Pem(RSAPrivateKey privateKey, BigInt publicExponent) {
    final modulus = privateKey.modulus;
    final privateExponent = privateKey.privateExponent;
    final p = privateKey.p;
    final q = privateKey.q;
    if (modulus == null || privateExponent == null || p == null || q == null) {
      throw ClinicianCryptoException('RSA private key parameters are incomplete.');
    }

    final dP = privateExponent % (p - BigInt.one);
    final dQ = privateExponent % (q - BigInt.one);
    final qInv = q.modInverse(p);

    final pkcs1 = ASN1Sequence()
      ..add(ASN1Integer(BigInt.zero))
      ..add(ASN1Integer(modulus))
      ..add(ASN1Integer(publicExponent))
      ..add(ASN1Integer(privateExponent))
      ..add(ASN1Integer(p))
      ..add(ASN1Integer(q))
      ..add(ASN1Integer(dP))
      ..add(ASN1Integer(dQ))
      ..add(ASN1Integer(qInv));

    final algorithmIdentifier = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromName('rsaEncryption'))
      ..add(ASN1Null());

    final pkcs8 = ASN1Sequence()
      ..add(ASN1Integer(BigInt.zero))
      ..add(algorithmIdentifier)
      ..add(ASN1OctetString(Uint8List.fromList(pkcs1.encodedBytes)));

    return _toPem(
      type: 'PRIVATE KEY',
      derBytes: Uint8List.fromList(pkcs8.encodedBytes),
    );
  }

  String _encodePublicKeyToSpkiPem(RSAPublicKey publicKey) {
    final modulus = publicKey.modulus;
    final exponent = publicKey.exponent;
    if (modulus == null || exponent == null) {
      throw ClinicianCryptoException('RSA public key parameters are incomplete.');
    }

    final publicKeySequence = ASN1Sequence()
      ..add(ASN1Integer(modulus))
      ..add(ASN1Integer(exponent));

    final algorithmIdentifier = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromName('rsaEncryption'))
      ..add(ASN1Null());

    final spki = ASN1Sequence()
      ..add(algorithmIdentifier)
      ..add(ASN1BitString(Uint8List.fromList(publicKeySequence.encodedBytes)));

    return _toPem(
      type: 'PUBLIC KEY',
      derBytes: Uint8List.fromList(spki.encodedBytes),
    );
  }

  String _toPem({required String type, required Uint8List derBytes}) {
    final b64 = base64Encode(derBytes);
    final chunks = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      final end = (i + 64 < b64.length) ? i + 64 : b64.length;
      chunks.add(b64.substring(i, end));
    }

    return '-----BEGIN $type-----\n${chunks.join('\n')}\n-----END $type-----';
  }
}

class _ParsedPrivateKey {
  const _ParsedPrivateKey({
    required this.privateKey,
    required this.publicExponent,
  });

  final RSAPrivateKey privateKey;
  final BigInt publicExponent;
}
