// Friendly names made from addresses: stable, never empty, and different
// enough to tell the rows of a round apart.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pacepact/util/names.dart';

import 'support.dart';

String randomAddress(Random random) =>
    '0x${[for (var i = 0; i < 40; i++) random.nextInt(16).toRadixString(16)].join()}';

void main() {
  test('two lists of 64 plain words, no repeats, each one capitalised', () {
    for (final words in [nameAdjectives, nameAnimals]) {
      expect(words, hasLength(64));
      expect(words.toSet(), hasLength(64));
      for (final w in words) {
        expect(w, matches(RegExp(r'^[A-Z][a-z]+$')));
      }
    }
  });

  test('the same address gets the same name, whatever its case', () {
    final name = friendlyName(testAddress);
    expect(friendlyName(testAddress), name);
    expect(friendlyName(testAddress.toUpperCase()), name);
    expect(friendlyName('0x${testAddress.substring(2).toUpperCase()}'), name);
    // Fixed for good: a name must not change between versions of the app.
    expect(name, 'Glad Panda');
    expect(
      friendlyName('0x2000000000000000000000000000000000000002'),
      'Bold Turtle',
    );
    final parts = name.split(' ');
    expect(parts, hasLength(2));
    expect(nameAdjectives, contains(parts[0]));
    expect(nameAnimals, contains(parts[1]));
  });

  test('never empty, even for text that is not an address', () {
    for (final text in ['', '0x', 'hello', '0x1234', ' ']) {
      final name = friendlyName(text);
      expect(name.trim(), isNotEmpty);
      expect(name.split(' '), hasLength(2));
    }
  });

  test('200 random addresses give at least 150 different names', () {
    final random = Random(97);
    final names = {
      for (var i = 0; i < 200; i++) friendlyName(randomAddress(random)),
    };
    expect(names.length, greaterThanOrEqualTo(150));
  });

  test('addresses one byte apart still get different names', () {
    final names = {
      for (var i = 0; i < 40; i++)
        friendlyName('0x${(0xa000 + i).toRadixString(16).padLeft(40, '0')}'),
    };
    expect(names.length, greaterThanOrEqualTo(30));
  });
}
