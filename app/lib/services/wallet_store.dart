import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';

/// Keeps the device wallet key in the platform keystore (Keychain / Keystore;
/// the site's storage in a browser), the onboarding flag, a check-in the
/// server has signed but the chain has not recorded yet, and the rounds this
/// device knows beyond the public list (opened by link or started here) with
/// the one last selected.
///
/// The storage names keep the prefix of the app's first build, so a wallet
/// made by an earlier build is still found.
class WalletStore {
  static const _keyName = 'pacepact.wallet.key';
  static const _onboardedName = 'pacepact.onboarded';
  static const _pendingName = 'showup.checkin.pending';
  static const _roundsName = 'showup.rounds';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<EthPrivateKey?> load() async {
    final hex = await _storage.read(key: _keyName);
    return hex == null ? null : EthPrivateKey.fromHex(hex);
  }

  /// Generates a new key on this device. It never leaves the device.
  Future<EthPrivateKey> create() async {
    final key = EthPrivateKey.createRandom(Random.secure());
    await _storage.write(key: _keyName, value: privateKeyHex(key));
    return key;
  }

  /// Replaces the device key with [key] ("Import a key").
  Future<void> save(EthPrivateKey key) =>
      _storage.write(key: _keyName, value: privateKeyHex(key));

  /// True once the onboarding steps have been seen on this device.
  Future<bool> loadOnboarded() async =>
      await _storage.read(key: _onboardedName) == 'true';

  Future<void> saveOnboarded() =>
      _storage.write(key: _onboardedName, value: 'true');

  /// A signed check-in that still has to be sent to the chain, as JSON, or
  /// null. Kept so a closed tab between the two steps does not lose the day.
  Future<Map<String, dynamic>?> loadPending() async {
    final text = await _storage.read(key: _pendingName);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePending(Map<String, dynamic>? pending) => pending == null
      ? _storage.delete(key: _pendingName)
      : _storage.write(key: _pendingName, value: jsonEncode(pending));

  /// The rounds this device knows and the selected one, as JSON
  /// (`{selected, known: [...]}`), or null.
  Future<Map<String, dynamic>?> loadRounds() async {
    final text = await _storage.read(key: _roundsName);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRounds(Map<String, dynamic> rounds) =>
      _storage.write(key: _roundsName, value: jsonEncode(rounds));
}

/// The private key as exactly 64 hex characters.
///
/// web3dart can return 33 bytes for a fresh key (a leading zero sign byte), which is 66 hex
/// characters and trips its own padding assertion. Keep the last 32 bytes and left-pad short keys.
String privateKeyHex(EthPrivateKey key) {
  final bytes = key.privateKey;
  final last32 = bytes.length > 32 ? bytes.sublist(bytes.length - 32) : bytes;
  return bytesToHex(last32, forcePadLength: 64);
}

/// Reads a pasted private key: 64 hex characters, with or without `0x`.
/// Null when the text is not one.
EthPrivateKey? parsePrivateKey(String text) {
  var t = text.trim();
  if (t.startsWith('0x') || t.startsWith('0X')) t = t.substring(2);
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(t)) return null;
  if (BigInt.parse(t, radix: 16) == BigInt.zero) return null;
  try {
    return EthPrivateKey.fromHex(t);
  } catch (_) {
    return null;
  }
}
