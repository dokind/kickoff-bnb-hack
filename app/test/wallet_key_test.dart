import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/services/wallet_store.dart';
import 'package:web3dart/web3dart.dart';

void main() {
  test('privateKeyHex is always 64 hex characters and round-trips', () {
    final random = Random(7);
    for (var i = 0; i < 300; i++) {
      final key = EthPrivateKey.createRandom(random);
      final hex = privateKeyHex(key);
      expect(hex.length, 64);
      expect(EthPrivateKey.fromHex(hex).address, key.address);
    }
  });
}
