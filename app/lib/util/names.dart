/// A friendly name for a wallet, made from its address: an adjective and an
/// animal, "Quiet Otter". The same address always gets the same name, on
/// every device, with nothing stored or sent. It is a nickname to tell rows
/// apart, not an identity: two wallets can share one (64 x 64 = 4,096
/// names), so the short address stays next to it.
library;

/// 64 plain, kind adjectives.
const nameAdjectives = <String>[
  'Quiet', 'Brave', 'Calm', 'Bright', 'Gentle', 'Happy', 'Kind', 'Lucky', //
  'Merry', 'Noble', 'Swift', 'Sunny', 'Steady', 'Clever', 'Cheerful', 'Bold',
  'Eager', 'Fair', 'Glad', 'Golden', 'Honest', 'Jolly', 'Keen', 'Lively',
  'Mellow', 'Neat', 'Polite', 'Proud', 'Quick', 'Silver', 'Smart', 'Spry',
  'Tidy', 'Warm', 'Wise', 'Witty', 'Breezy', 'Snug', 'Daring', 'Dapper',
  'Friendly', 'Graceful', 'Hearty', 'Humble', 'Jovial', 'Loyal', 'Mighty',
  'Nimble', 'Patient', 'Peppy', 'Plucky', 'Radiant', 'Sincere', 'Sturdy',
  'Sparkly', 'Trusty', 'Upbeat', 'Vivid', 'Willing', 'Zippy', 'Chipper',
  'Curious', 'Bouncy', 'Hopeful',
];

/// 64 animals.
const nameAnimals = <String>[
  'Otter', 'Badger', 'Falcon', 'Heron', 'Panda', 'Koala', 'Lynx', 'Fox', //
  'Hare', 'Owl', 'Robin', 'Wren', 'Finch', 'Sparrow', 'Swan', 'Crane',
  'Dolphin', 'Seal', 'Walrus', 'Penguin', 'Puffin', 'Beaver', 'Moose', 'Elk',
  'Deer', 'Bison', 'Yak', 'Llama', 'Alpaca', 'Camel', 'Zebra', 'Giraffe',
  'Hippo', 'Rhino', 'Tiger', 'Lion', 'Leopard', 'Cheetah', 'Jaguar', 'Wolf',
  'Bear', 'Rabbit', 'Squirrel', 'Hedgehog', 'Gecko', 'Turtle', 'Tortoise',
  'Frog', 'Newt', 'Salmon', 'Marlin', 'Whale', 'Orca', 'Pelican', 'Toucan',
  'Parrot', 'Magpie', 'Kestrel', 'Ibis', 'Meerkat', 'Lemur', 'Tapir',
  'Ferret', 'Mongoose',
];

/// "Quiet Otter" for [address], whatever its case. The address's 20 bytes
/// are folded together (FNV-1a), so addresses that differ in one byte
/// still get different names; the low six bits pick the adjective and the
/// next six the animal. Text that is not an address is folded by its
/// characters instead, so the name is never empty.
String friendlyName(String address) {
  final text = address.trim().toLowerCase();
  final hex = text.startsWith('0x') ? text.substring(2) : text;
  final bytes = <int>[];
  if (hex.length == 40 && RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
    for (var i = 0; i < 40; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
  } else {
    bytes.addAll(text.codeUnits);
  }
  var hash = 0x811c9dc5;
  for (final b in bytes) {
    hash ^= b & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final adjective = nameAdjectives[hash & 63];
  final animal = nameAnimals[(hash >> 6) & 63];
  return '$adjective $animal';
}
