import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:wallet/wallet.dart' show EtherAmount, EthereumAddress;
import 'package:web3dart/web3dart.dart';

import '../config.dart';
import '../util/format.dart';
import 'abi.dart';

/// What the round's contract (CheckInLauncher) says right now: the few
/// shared numbers the app acts on, and where one wallet stands.
class RoundChain {
  RoundChain({
    required this.deposit,
    required this.launched,
    required this.totalCheckIns,
    required this.poolQuoteNow,
    required this.isMember,
    required this.daysOf,
    required this.checkedInToday,
    required this.refundable,
  });

  /// The fixed deposit, in base units of the quote token.
  final BigInt deposit;
  final bool launched;
  final int totalCheckIns;

  /// What would seed the launch pool now: all sponsor money plus the launch
  /// share of the deposits.
  final BigInt poolQuoteNow;

  final bool isMember;

  /// Days this wallet has checked in.
  final int daysOf;

  /// This wallet's check-in for the current UTC day is on chain.
  final bool checkedInToday;

  /// What `refund()` would pay this wallet now (0 while the round is open).
  final BigInt refundable;
}

/// What the vault (StreakVault) says about one wallet after the launch.
class ShareChain {
  ShareChain({
    required this.vault,
    required this.token,
    required this.claimableTokens,
    required this.claimableQuote,
    required this.claimedTokens,
    required this.claimedQuote,
  });

  final String vault;
  final String token;

  /// What `claim()` would pay now.
  final BigInt claimableTokens;
  final BigInt claimableQuote;

  /// What this wallet has taken so far.
  final BigInt claimedTokens;
  final BigInt claimedQuote;

  bool get hasClaimable =>
      claimableTokens > BigInt.zero || claimableQuote > BigInt.zero;
}

/// Finds a launch salt for which the token address ends in 0x7777, as the
/// Portal requires. The token is a CREATE2 clone deployed by the Portal:
///   address = last 20 bytes of keccak256(0xff ++ portal ++ salt ++ initCodeHash)
/// About 65,000 hashes on average. [seed] is 32 random bytes.
Uint8List mineSalt(Uint8List seed) {
  for (var from = 0; ; from += saltChunk) {
    final salt = mineSaltChunk(seed, from, saltChunk);
    if (salt != null) return salt;
  }
}

/// How many hashes [mineSaltAsync] tries between two pauses on the web.
const int saltChunk = 500;

/// Tries the counters [from] .. [from] + [count] - 1 and returns the salt, or
/// null when none of them gives an address ending in 0x7777.
Uint8List? mineSaltChunk(Uint8List seed, int from, int count) {
  final input = Uint8List(85);
  input[0] = 0xff;
  input.setRange(1, 21, hexToBytes(AppConfig.portal));
  input.setRange(21, 53, seed);
  input.setRange(53, 85, hexToBytes(AppConfig.tokenInitCodeHash));
  final view = input.buffer.asByteData();
  for (var i = from; i < from + count; i++) {
    // The counter overwrites the last four bytes of the salt.
    view.setUint32(49, i);
    final hash = keccak256(input);
    if (hash[30] == 0x77 && hash[31] == 0x77) return input.sublist(21, 53);
  }
  return null;
}

/// [mineSalt] without freezing the screen. A phone runs it on a background
/// isolate. A browser has no isolates, so the search runs in short chunks and
/// hands control back to the page between them ([web] is a parameter so tests
/// can run the browser path).
Future<Uint8List> mineSaltAsync(Uint8List seed, {bool web = kIsWeb}) async {
  if (!web) return compute(mineSalt, seed);
  for (var from = 0; ; from += saltChunk) {
    final salt = mineSaltChunk(seed, from, saltChunk);
    if (salt != null) return salt;
    await Future<void>.delayed(Duration.zero);
  }
}

/// All chain access. Reads go through eth_call; writes are signed on the
/// device with the wallet key and sent to BSC testnet as legacy transactions
/// at 1 gwei with an explicit gas limit.
class ChainService {
  ChainService({Web3Client? client})
    : _client = client ?? Web3Client(AppConfig.rpcUrls.first, http.Client());

  final Web3Client _client;

  static EthereumAddress _addr(String hex) => EthereumAddress.fromHex(hex);

  static DeployedContract _contract(ContractAbi abi, String address) =>
      DeployedContract(abi, _addr(address));

  static DeployedContract get _quote =>
      _contract(erc20Abi, AppConfig.quoteToken);

  static DeployedContract _launcher(String address) =>
      _contract(checkInLauncherAbi, address);

  Future<List<dynamic>> _call(
    DeployedContract c,
    String fn, [
    List<dynamic> params = const [],
  ]) => _client.call(contract: c, function: c.function(fn), params: params);

  Future<T> _read<T>(
    DeployedContract c,
    String fn, [
    List<dynamic> params = const [],
  ]) async => (await _call(c, fn, params)).first as T;

  /// The exact bytes a call to [fn] sends. Used by [_send] and pinned by the
  /// tests against `cast calldata`.
  static Uint8List callData(
    ContractAbi abi,
    String fn, [
    List<dynamic> params = const [],
  ]) => abi.functions.singleWhere((f) => f.name == fn).encodeCall(params);

  /// Signs, sends, waits for the receipt and throws [rejected] (one sentence
  /// for a person) if the call reverted. Returns the transaction hash.
  Future<String> _send(
    Credentials key,
    DeployedContract c,
    String fn,
    List<dynamic> params, {
    required int gas,
    required String rejected,
    EtherAmount? value,
  }) async => bytesToHex(
    (await _sendForReceipt(
      key,
      c,
      fn,
      params,
      gas: gas,
      rejected: rejected,
      value: value,
    )).transactionHash,
    include0x: true,
  );

  Future<TransactionReceipt> _sendForReceipt(
    Credentials key,
    DeployedContract c,
    String fn,
    List<dynamic> params, {
    required int gas,
    required String rejected,
    EtherAmount? value,
  }) async {
    final hash = await _client.sendTransaction(
      key,
      Transaction.callContract(
        contract: c,
        function: c.function(fn),
        parameters: params,
        value: value,
        // Legacy transaction at 1 gwei with an explicit limit: estimated
        // fees are never mined on this testnet.
        gasPrice: EtherAmount.inWei(AppConfig.gasPriceWei),
        maxGas: gas,
      ),
      chainId: AppConfig.chainId,
    );
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final receipt = await _client.getTransactionReceipt(hash);
      if (receipt == null) continue;
      if (receipt.status == false) throw Exception(rejected);
      return receipt;
    }
    throw Exception('Still waiting for the network. Check again in a minute.');
  }

  // Wallet -------------------------------------------------------------------

  /// tBNB balance, needed to pay for gas.
  Future<BigInt> bnbBalance(String address) async =>
      (await _client.getBalance(_addr(address))).getInWei;

  Future<BigInt> quoteBalance(String address) =>
      _read<BigInt>(_quote, 'balanceOf', [_addr(address)]);

  /// The wallet mints [amount] of test USD to itself. Testnet token with an
  /// open mint and no real value; on mainnet this step is paying with a
  /// stablecoin the person already holds.
  Future<String> mintTestDollars(EthPrivateKey key, BigInt amount) => _send(
    key,
    _quote,
    'mint',
    [key.address, amount],
    gas: GasLimit.mint,
    rejected: 'The test dollars could not be minted. Try again.',
  );

  /// Lets [spender] take [amount] of test USD, unless it already may.
  Future<void> _approve(
    EthPrivateKey key,
    String spender,
    BigInt amount,
  ) async {
    final allowance = await _read<BigInt>(_quote, 'allowance', [
      key.address,
      _addr(spender),
    ]);
    if (allowance >= amount) return;
    await _send(
      key,
      _quote,
      'approve',
      [_addr(spender), amount],
      gas: GasLimit.approve,
      rejected: 'The payment could not be approved. Try again.',
    );
  }

  // Round --------------------------------------------------------------------

  /// Reads the round for one wallet. [now] decides which UTC day "today" is.
  Future<RoundChain> roundState(
    String launcher,
    String member, {
    DateTime? now,
  }) async {
    final c = _launcher(launcher);
    final who = _addr(member);
    final today = BigInt.from(dayIndexOf(now ?? DateTime.now()));
    final r = await Future.wait<dynamic>([
      _read<BigInt>(c, 'deposit'),
      _read<bool>(c, 'launched'),
      _read<BigInt>(c, 'totalCheckIns'),
      _read<BigInt>(c, 'poolQuoteNow'),
      _read<bool>(c, 'isMember', [who]),
      _read<BigInt>(c, 'daysOf', [who]),
      _read<bool>(c, 'checkedInOn', [who, today]),
      _read<BigInt>(c, 'refundable', [who]),
    ]);
    return RoundChain(
      deposit: r[0] as BigInt,
      launched: r[1] as bool,
      totalCheckIns: (r[2] as BigInt).toInt(),
      poolQuoteNow: r[3] as BigInt,
      isMember: r[4] as bool,
      daysOf: (r[5] as BigInt).toInt(),
      checkedInToday: r[6] as bool,
      refundable: r[7] as BigInt,
    );
  }

  /// Whether [member] has paid the deposit of the round at [launcher]. One
  /// read, for "You're in" on a round's card.
  Future<bool> isMemberOf(String launcher, String member) =>
      _read<bool>(_launcher(launcher), 'isMember', [_addr(member)]);

  /// After the launch: the vault and token addresses and this wallet's share.
  Future<ShareChain> shareState(String launcher, String member) async {
    final c = _launcher(launcher);
    final addresses = await Future.wait([
      _read<EthereumAddress>(c, 'vault'),
      _read<EthereumAddress>(c, 'token'),
    ]);
    final vault = addresses[0].with0x;
    final v = _contract(streakVaultAbi, vault);
    final who = _addr(member);
    final r = await Future.wait<dynamic>([
      _call(v, 'claimable', [who]),
      _read<BigInt>(v, 'claimedTokens', [who]),
      _read<BigInt>(v, 'claimedQuote', [who]),
    ]);
    final claimable = r[0] as List<dynamic>;
    return ShareChain(
      vault: vault,
      token: addresses[1].with0x,
      claimableTokens: claimable[0] as BigInt,
      claimableQuote: claimable[1] as BigInt,
      claimedTokens: r[1] as BigInt,
      claimedQuote: r[2] as BigInt,
    );
  }

  /// Pays the deposit: approves it if needed, then `join()`.
  Future<String> join(
    EthPrivateKey key,
    String launcher,
    BigInt deposit,
  ) async {
    await _approve(key, launcher, deposit);
    return _send(
      key,
      _launcher(launcher),
      'join',
      const [],
      gas: GasLimit.join,
      rejected:
          'The deposit was not accepted. You may already be a member, or '
          'the round has closed.',
    );
  }

  /// Adds [amount] to the launch pool. It earns no share and comes back to
  /// this wallet if the round does not launch.
  Future<String> sponsor(
    EthPrivateKey key,
    String launcher,
    BigInt amount,
  ) async {
    await _approve(key, launcher, amount);
    return _send(
      key,
      _launcher(launcher),
      'sponsor',
      [amount],
      gas: GasLimit.sponsor,
      rejected: 'The contribution was not accepted. The round may have closed.',
    );
  }

  /// Records today's check-in with the attester's signature from the server.
  Future<String> checkIn(
    EthPrivateKey key,
    String launcher,
    int dayIndex,
    String attesterSignature,
  ) => _send(
    key,
    _launcher(launcher),
    'checkIn',
    [BigInt.from(dayIndex), hexToBytes(attesterSignature)],
    gas: GasLimit.checkIn,
    rejected:
        'The check-in was not accepted on chain. You may have checked in '
        'already today.',
  );

  /// Launches the token through Flap. Anyone may call it once the bar is
  /// full. Needs about 5,000,000 gas; the limit is 7,000,000.
  Future<String> launch(EthPrivateKey key, String launcher) => _send(
    key,
    _launcher(launcher),
    'launch',
    const [],
    gas: GasLimit.launch,
    rejected:
        'The launch was rejected. The launch pool may be under the minimum '
        'Flap needs; a sponsor can add the rest.',
  );

  /// After a missed deadline: takes the deposit (and anything sponsored) back.
  Future<String> refund(EthPrivateKey key, String launcher) => _send(
    key,
    _launcher(launcher),
    'refund',
    const [],
    gas: GasLimit.refund,
    rejected: 'Nothing could be refunded to this wallet.',
  );

  /// Takes this wallet's share out of the vault.
  Future<String> claim(EthPrivateKey key, String vault) => _send(
    key,
    _contract(streakVaultAbi, vault),
    'claim',
    const [],
    gas: GasLimit.claim,
    rejected: 'There is nothing to claim for this wallet right now.',
  );

  // Starting a round ---------------------------------------------------------

  /// Starts a round: Portal.newLauncher with our CheckInLauncherFactory,
  /// paying the Portal's salt lock fee in tBNB. Returns the launcher address,
  /// read from the factory's CheckInLauncherCreated event.
  Future<String> createRound(
    EthPrivateKey key, {
    required String name,
    required String symbol,
    required BigInt deposit,
    required int liquidityBps,
    required int checkInGoal,
    required DateTime deadline,
  }) async {
    if (!AppConfig.canStartRound) {
      throw Exception('This build cannot start a round yet.');
    }
    final portal = _contract(portalAbi, AppConfig.portal);
    final fee = await _read<BigInt>(portal, 'SALT_LOCK_FEE');
    final random = Random.secure();
    final seed = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final salt = await mineSaltAsync(seed);
    final receipt = await _sendForReceipt(
      key,
      portal,
      'newLauncher',
      [
        _addr(AppConfig.checkInLauncherFactory),
        encodeRoundConfig(
          name: name,
          symbol: symbol,
          salt: salt,
          deposit: deposit,
          liquidityBps: liquidityBps,
          checkInGoal: checkInGoal,
          deadline: deadline,
          attester: AppConfig.attesterAddress,
        ),
      ],
      gas: GasLimit.newLauncher,
      rejected:
          'The round could not be started. Check the numbers and try again.',
      value: EtherAmount.inWei(fee),
    );
    final launcher = launcherFromLogs(
      receipt.logs,
      AppConfig.checkInLauncherFactory,
    );
    if (launcher == null) {
      throw Exception('The round was started but its address was not found.');
    }
    return launcher;
  }

  /// keccak256("CheckInLauncherCreated(address,address,bytes32)").
  static final String createdTopic = bytesToHex(
    keccakUtf8('CheckInLauncherCreated(address,address,bytes32)'),
    include0x: true,
  );

  /// The launcher address from the factory's
  /// `CheckInLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt)`.
  static String? launcherFromLogs(List<FilterEvent> logs, String factory) {
    for (final log in logs) {
      final topics = log.topics;
      if (topics == null || topics.length < 2) continue;
      if (log.address?.with0x.toLowerCase() != factory.toLowerCase()) continue;
      if (topics[0]?.toLowerCase() != createdTopic) continue;
      final topic = topics[1]!;
      return '0x${topic.substring(topic.length - 40)}';
    }
    return null;
  }

  /// abi.encode(RoundConfig): one tuple, in the order the factory decodes it:
  /// (name, symbol, meta, salt, deposit, liquidityBps, checkInGoal, deadline,
  /// attester). The metadata URI is left empty.
  static Uint8List encodeRoundConfig({
    required String name,
    required String symbol,
    required Uint8List salt,
    required BigInt deposit,
    required int liquidityBps,
    required int checkInGoal,
    required DateTime deadline,
    required String attester,
  }) {
    final call = roundConfigAbi.functions.single.encodeCall([
      [
        name,
        symbol,
        '',
        salt,
        deposit,
        BigInt.from(liquidityBps),
        BigInt.from(checkInGoal),
        BigInt.from(deadline.millisecondsSinceEpoch ~/ 1000),
        _addr(attester),
      ],
    ]);
    return call.sublist(4); // drop the 4-byte selector, keep the arguments
  }
}

/// A short token symbol made from a round's name: the initials of its words,
/// or its first letters when it is one word. The Portal needs one; the app
/// never shows it.
String symbolFor(String name) {
  final words = RegExp(
    r'[A-Za-z0-9]+',
  ).allMatches(name).map((m) => m.group(0)!).toList();
  if (words.isEmpty) return 'ROUND';
  final raw = words.length == 1 ? words.first : words.map((w) => w[0]).join();
  final symbol = raw.toUpperCase();
  return symbol.length > 6 ? symbol.substring(0, 6) : symbol;
}
