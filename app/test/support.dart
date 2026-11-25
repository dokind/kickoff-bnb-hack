// Shared fakes: nothing in the tests touches the network, a chain or the
// device's storage.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pacepact/app_state.dart';
import 'package:pacepact/services/chain_service.dart';
import 'package:pacepact/services/health_service.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:pacepact/services/wallet_store.dart';
import 'package:pacepact/theme/theme.dart';
import 'package:pacepact/util/format.dart';
import 'package:web3dart/web3dart.dart';

const launcher = '0x1000000000000000000000000000000000000001';
const vault = '0x3000000000000000000000000000000000000003';
const tokenAddress = '0x4000000000000000000000000000000000007777';

/// The well-known test key the contracts' vectors use. Never a real wallet.
const testKeyHex =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
final testKey = EthPrivateKey.fromHex(testKeyHex);
const testAddress = '0xfcad0b19bb29d4674531d6f115237e16afce377c';

BigInt usd(num whole) => parseUnits('$whole') ?? BigInt.zero;

/// 25 Nov 2026 15:00 UTC, day 20782 on chain.
final fixedNow = DateTime.utc(2026, 11, 25, 15);
const today = '2026-11-25';

/// A signature of the right shape (65 bytes); the fake chain does not check
/// it.
final attesterSignature = '0x${'ab' * 64}1c';

/// The wallet and flags stay in memory.
class MemoryStore extends WalletStore {
  MemoryStore({this.key, this.onboarded = false, this.pending});
  EthPrivateKey? key;
  bool onboarded;
  Map<String, dynamic>? pending;

  @override
  Future<EthPrivateKey?> load() async => key;
  @override
  Future<EthPrivateKey> create() async => key = testKey;
  @override
  Future<void> save(EthPrivateKey k) async => key = k;
  @override
  Future<bool> loadOnboarded() async => onboarded;
  @override
  Future<void> saveOnboarded() async => onboarded = true;
  @override
  Future<Map<String, dynamic>?> loadPending() async => pending;
  @override
  Future<void> savePending(Map<String, dynamic>? p) async => pending = p;
}

/// A round's contract and vault in memory. Each write changes the numbers
/// the way the real contract would, so the screens move on.
class FakeChain extends ChainService {
  FakeChain({
    num bnb = 0.03,
    num dollars = 0,
    this.deposit = 1000,
    this.launched = false,
    this.totalCheckIns = 0,
    this.pool = 0,
    this.isMember = false,
    this.daysOf = 0,
    this.checkedInToday = false,
    this.refundable = 0,
    this.claimableTokens = 0,
    this.claimableQuote = 0,
    this.fail,
  }) : bnb = usd(bnb),
       dollars = usd(dollars);

  BigInt bnb;
  BigInt dollars;
  num deposit;
  bool launched;
  int totalCheckIns;
  num pool;
  bool isMember;
  int daysOf;
  bool checkedInToday;
  num refundable;
  num claimableTokens;
  num claimableQuote;
  num claimedTokens = 0;
  num claimedQuote = 0;

  /// The name of a write that should fail once ("mint", "join", ...).
  String? fail;

  /// The chain cannot be read at all.
  bool down = false;

  /// Every write, in order: "mint 1000", "join", "checkIn 20782", ...
  final calls = <String>[];

  void _write(String name, [String detail = '']) {
    if (fail == name) {
      fail = null;
      throw Exception('The $name was rejected. Try again.');
    }
    calls.add(detail.isEmpty ? name : '$name $detail');
  }

  @override
  Future<BigInt> bnbBalance(String address) async => bnb;
  @override
  Future<BigInt> quoteBalance(String address) async => dollars;

  @override
  Future<RoundChain> roundState(
    String launcher,
    String member, {
    DateTime? now,
  }) async {
    if (down) throw Exception('rpc down');
    return RoundChain(
      deposit: usd(deposit),
      launched: launched,
      totalCheckIns: totalCheckIns,
      poolQuoteNow: usd(pool),
      isMember: isMember,
      daysOf: daysOf,
      checkedInToday: checkedInToday,
      refundable: usd(refundable),
    );
  }

  @override
  Future<ShareChain> shareState(String launcher, String member) async =>
      ShareChain(
        vault: vault,
        token: tokenAddress,
        claimableTokens: usd(claimableTokens),
        claimableQuote: usd(claimableQuote),
        claimedTokens: usd(claimedTokens),
        claimedQuote: usd(claimedQuote),
      );

  @override
  Future<String> mintTestDollars(EthPrivateKey key, BigInt amount) async {
    _write('mint', formatUnits(amount));
    dollars += amount;
    return '0xm1';
  }

  @override
  Future<String> join(EthPrivateKey key, String launcher, BigInt amount) async {
    _write('join', formatUnits(amount));
    dollars -= amount;
    isMember = true;
    pool += deposit * 0.3;
    return '0xj1';
  }

  @override
  Future<String> sponsor(
    EthPrivateKey key,
    String launcher,
    BigInt amount,
  ) async {
    _write('sponsor', formatUnits(amount));
    dollars -= amount;
    pool += num.parse(formatUnits(amount));
    return '0xs1';
  }

  @override
  Future<String> checkIn(
    EthPrivateKey key,
    String launcher,
    int dayIndex,
    String attesterSignature,
  ) async {
    _write('checkIn', '$dayIndex');
    checkedInToday = true;
    daysOf++;
    totalCheckIns++;
    return '0xc1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1';
  }

  @override
  Future<String> launch(EthPrivateKey key, String launcher) async {
    _write('launch');
    launched = true;
    return '0xl1';
  }

  @override
  Future<String> refund(EthPrivateKey key, String launcher) async {
    _write('refund');
    dollars += usd(refundable);
    refundable = 0;
    isMember = false;
    return '0xr1';
  }

  @override
  Future<String> claim(EthPrivateKey key, String vault) async {
    _write('claim');
    claimedTokens += claimableTokens;
    claimedQuote += claimableQuote;
    dollars += usd(claimableQuote);
    claimableTokens = 0;
    claimableQuote = 0;
    return '0xd1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1';
  }

  @override
  Future<String> createRound(
    EthPrivateKey key, {
    required String name,
    required String symbol,
    required BigInt deposit,
    required int liquidityBps,
    required int checkInGoal,
    required DateTime deadline,
  }) async {
    _write(
      'createRound',
      '$name $symbol ${formatUnits(deposit)} $liquidityBps $checkInGoal',
    );
    return '0x5000000000000000000000000000000000000005';
  }
}

class FakeHealth implements HealthService {
  FakeHealth({this.available = false, this.steps = 6214});
  @override
  final bool available;
  int steps;
  int asked = 0;

  @override
  String get source => available ? 'healthkit' : 'self';

  @override
  Future<bool> requestAccess() async {
    asked++;
    return true;
  }

  @override
  Future<int> stepsToday() async => steps;
}

Map<String, dynamic> roundJson({
  int checkInGoal = 6,
  int totalCheckIns = 2,
  int memberCount = 3,
  String prizeNow = '2100',
  String poolQuoteNow = '900',
  bool launched = false,
  int? deadline,
}) => {
  'launcher': launcher,
  'name': 'Morning Movers',
  'quoteToken': '0x190C989D5665a0e404B444b53CAE9AbCfb600157',
  'deposit': '1000',
  'liquidityBps': 3000,
  'checkInGoal': checkInGoal,
  'totalCheckIns': totalCheckIns,
  'memberCount': memberCount,
  'totalDeposits': '3000',
  'totalSponsored': '0',
  'poolQuoteNow': poolQuoteNow,
  'prizeNow': prizeNow,
  // 2 Dec 2026 00:00 UTC.
  'deadline': deadline ?? 1796169600,
  'launched': launched,
  'token': launched ? tokenAddress : null,
  'vault': launched ? vault : null,
  'minSteps': 1000,
  'flapUrl': launched ? 'https://flap.sh/bnb-testnet/$tokenAddress' : null,
};

Map<String, dynamic> meJson({
  bool member = true,
  int daysOf = 0,
  int streak = 0,
  bool checkedInToday = false,
  List<String> days = const [],
}) => {
  'member': member,
  'daysOf': daysOf,
  'checkedInToday': checkedInToday,
  'streak': streak,
  'bestStreak': streak,
  'days': days,
  'claimableTokens': '0',
  'claimableQuote': '0',
  'claimedTokens': '0',
};

/// The server, in memory. Tests change the answers and read what was asked.
class FakeServer {
  /// Null answers 404 `no_round`.
  Map<String, dynamic>? round = roundJson();
  Map<String, dynamic> me = meJson(member: false);
  List<Map<String, dynamic>> members = [
    {
      'address': '0x2000000000000000000000000000000000000002',
      'daysOf': 2,
      'streak': 2,
      'checkedInToday': true,
    },
    {
      'address': '0x6000000000000000000000000000000000000006',
      'daysOf': 0,
      'streak': 0,
      'checkedInToday': false,
    },
  ];
  Map<String, dynamic> faucet = {'funded': true, 'bnbTx': '0xf1'};

  /// What POST /checkin answers; a status of 400 or more is an error body.
  int checkInStatus = 200;
  Map<String, dynamic>? checkIn;

  /// Every call fails as if there were no connection.
  bool offline = false;

  /// "GET /round", "POST /checkin", ... in order, and the POST bodies.
  final requests = <String>[];
  final bodies = <String, Map<String, dynamic>>{};

  int count(String request) => requests.where((r) => r == request).length;

  VerifierApi get api => VerifierApi(
    baseUrl: 'http://server.test',
    client: MockClient((r) async {
      if (offline) throw http.ClientException('Failed to fetch', r.url);
      requests.add('${r.method} ${r.url.path}');
      if (r.method == 'POST') {
        bodies[r.url.path] = jsonDecode(r.body) as Map<String, dynamic>;
      }
      http.Response json(Object body, [int status = 200]) =>
          http.Response(jsonEncode(body), status);
      switch (r.url.path) {
        case '/round':
          return round == null
              ? json({'error': 'no_round'}, 404)
              : json(round!);
        case '/members':
          return json(members);
        case '/faucet':
          return json(faucet);
        case '/checkin':
          return json(
            checkIn ??
                {
                  'day': today,
                  'dayIndex': 20782,
                  'attesterSignature': attesterSignature,
                },
            checkInStatus,
          );
      }
      if (r.url.path.startsWith('/me/')) return json(me);
      return json({'error': 'not_found'}, 404);
    }),
  );
}

/// An app state over the fakes, already initialised and read once.
Future<AppState> makeState({
  FakeChain? chain,
  FakeServer? server,
  FakeHealth? health,
  MemoryStore? store,
  bool wallet = true,
  DateTime? now,
}) async {
  final state = AppState(
    store:
        store ?? MemoryStore(key: wallet ? testKey : null, onboarded: wallet),
    chain: chain ?? FakeChain(),
    api: (server ?? FakeServer()).api,
    health: health ?? FakeHealth(),
    clock: () => now ?? fixedNow,
    gasPoll: Duration.zero,
    gasPollTries: 3,
  );
  await state.init();
  await state.refresh();
  return state;
}

/// A phone-sized screen for the test, put back afterwards.
void usePhone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

final inAppTheme = buildTheme(useGoogleFonts: false);

/// A screen (or sheet body) in the app's theme, with motion reduced so no
/// animation runs for ever.
Widget inApp(Widget child) => MaterialApp(
  theme: inAppTheme,
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: c!,
  ),
  home: Scaffold(backgroundColor: Colors.black, body: child),
);

/// Lets futures finish and the frames after them be drawn, without waiting
/// for spinners to stop.
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
