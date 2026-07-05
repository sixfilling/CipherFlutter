import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final class CipherEngine {
  static const List<int> _magic = <int>[67, 74, 70, 88, 49]; // CJFX1
  static const List<int> _legacySalt = <int>[
    116, 111, 107, 101, 110, 45, 99, 114, 121, 112, 116, 58, 118, 49, 58,
    102, 105, 120, 101, 100, 45, 115, 97, 108, 116,
  ];

  static const int _saltBytes = 16;
  static const int _iterations = 300000;
  static const int _keyBits = 256;
  static const int _tagBytes = 16;
  static const int _ivBytes = 12;

  static final Random _rng = Random.secure();
  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: _keyBits,
  );
  static final AesGcm _aesGcm = AesGcm.with256bits(nonceLength: _ivBytes);

  CipherEngine._();

  static Future<String> encrypt(String token, String plaintext) async {
    final salt = _randomBytes(_saltBytes);
    final iv = _randomBytes(_ivBytes);
    final key = await _keyFromToken(token, salt);

    final box = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: iv,
    );

    final payload = <int>[
      ..._magic,
      ...salt,
      ...iv,
      ...box.cipherText,
      ...box.mac.bytes,
    ];

    return base64.encode(payload);
  }

  static Future<String> decrypt(String token, String tokenText) async {
    final trimmed = tokenText.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Ciphertext is empty');
    }

    final all = base64.decode(trimmed);
    if (_isCurrentFormat(all)) {
      return _decryptCurrent(token, all);
    }
    return _decryptLegacy(token, all);
  }

  static Future<SecretKey> _keyFromToken(String token, List<int> salt) {
    return _pbkdf2.deriveKeyFromPassword(password: token, nonce: salt);
  }

  static bool _isCurrentFormat(List<int> all) {
    if (all.length < _magic.length + _saltBytes + _ivBytes + _tagBytes) {
      return false;
    }
    for (var i = 0; i < _magic.length; i++) {
      if (all[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<String> _decryptCurrent(String token, List<int> all) {
    var offset = _magic.length;
    final salt = all.sublist(offset, offset + _saltBytes);
    offset += _saltBytes;
    final iv = all.sublist(offset, offset + _ivBytes);
    offset += _ivBytes;
    final encryptedAndTag = all.sublist(offset);

    return _decryptBytes(token, salt, iv, encryptedAndTag);
  }

  static Future<String> _decryptLegacy(String token, List<int> all) {
    if (all.length < _ivBytes + _tagBytes) {
      throw ArgumentError('Ciphertext too short');
    }

    final iv = all.sublist(0, _ivBytes);
    final encryptedAndTag = all.sublist(_ivBytes);
    return _decryptBytes(token, _legacySalt, iv, encryptedAndTag);
  }

  static Future<String> _decryptBytes(
    String token,
    List<int> salt,
    List<int> iv,
    List<int> encryptedAndTag,
  ) async {
    if (encryptedAndTag.length < _tagBytes) {
      throw ArgumentError('Ciphertext too short');
    }

    final split = encryptedAndTag.length - _tagBytes;
    final cipherText = encryptedAndTag.sublist(0, split);
    final macBytes = encryptedAndTag.sublist(split);
    final key = await _keyFromToken(token, salt);

    final clearBytes = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac(macBytes)),
      secretKey: key,
    );

    return utf8.decode(clearBytes);
  }

  static Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _rng.nextInt(256)),
    );
  }
}
