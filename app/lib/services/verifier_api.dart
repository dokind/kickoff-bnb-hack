import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../config.dart';
import '../util/format.dart';

/// An amount from the server as base units. The server sends amounts as
/// decimal strings in whole units ("700", "356.2", "1500.000000000000000000").
/// A long whole number with no decimal point (16 digits or more) can only be
/// base units already, so it is taken as such.
BigInt amountFromJson(Object? value, {int decimals = 18}) {
  if (value == null) return BigInt.zero;
  final text = '$value'.trim();
  if (RegExp(r'^\d{16,}$').hasMatch(text)) return BigInt.parse(text);
  return parseUnits(text, decimals: decimals) ?? BigInt.zero;
}

int _int(Object? value) => switch (value) {
  final num n => n.round(),
  final String s => int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0,
  _ => 0,
};

/// Unix seconds (a number or digits), or an ISO date.
DateTime _time(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
  }
  final text = '$value';
  final seconds = int.tryParse(text);
  if (seconds != null) {
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
  return DateTime.tryParse(text) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

String? _address(Object? value) {
  if (value is! String || !isAddress(value)) return null;
  return value.toLowerCase() == AppConfig.zeroAddress ? null : value;
}

/// Where a round is: joining and checking in, launched, or past its
/// deadline with no launch.
enum RoundPhase { open, launched, expired }

/// One round, as the server read it from the chain: an entry of GET /rounds,
/// or the fuller answer of GET /rounds/:launcher and GET /round.
class Round {
  Round({
    required this.launcher,
    required this.name,
    required this.deposit,
    required this.liquidityBps,
    required this.checkInGoal,
    required this.totalCheckIns,
    required this.memberCount,
    required this.totalDeposits,
    required this.totalSponsored,
    required this.poolQuoteNow,
    required this.prizeNow,
    required this.deadline,
    required this.launched,
    required this.minSteps,
    this.token,
    this.vault,
    this.flapUrl,
    this.featured = false,
    this.unlisted = false,
  });

  /// The round's contract (CheckInLauncher).
  final String launcher;
  final String name;

  /// The fixed deposit, in base units of the quote token.
  final BigInt deposit;

  /// The share of each deposit that goes to the token pool, in basis
  /// points. The rest is the prize.
  final int liquidityBps;

  /// How many check-ins by everyone fill the bar.
  final int checkInGoal;
  final int totalCheckIns;
  final int memberCount;
  final BigInt totalDeposits;
  final BigInt totalSponsored;

  /// What would seed the token pool now.
  final BigInt poolQuoteNow;

  /// The prize so far: the deposits that do not go to the pool.
  final BigInt prizeNow;

  /// Joining, checking in and launching stop here; refunds open after it.
  final DateTime deadline;
  final bool launched;

  /// The fewest steps in a day the server accepts for a check-in.
  final int minSteps;

  /// Set once the token is launched.
  final String? token;
  final String? vault;

  /// The token's page on Flap, when the server knows it.
  final String? flapUrl;

  /// The round the server puts first (its current round).
  final bool featured;

  /// Not shown in the app's public list. Anyone with the link can still open
  /// and join it, and the chain is public.
  final bool unlisted;

  /// The launcher address in lower case: how the app tells rounds apart.
  String get id => launcher.toLowerCase();

  RoundPhase phaseAt(DateTime now) => launched
      ? RoundPhase.launched
      : now.isAfter(deadline)
      ? RoundPhase.expired
      : RoundPhase.open;

  Round copyWith({bool? featured, bool? unlisted}) => Round(
    launcher: launcher,
    name: name,
    deposit: deposit,
    liquidityBps: liquidityBps,
    checkInGoal: checkInGoal,
    totalCheckIns: totalCheckIns,
    memberCount: memberCount,
    totalDeposits: totalDeposits,
    totalSponsored: totalSponsored,
    poolQuoteNow: poolQuoteNow,
    prizeNow: prizeNow,
    deadline: deadline,
    launched: launched,
    minSteps: minSteps,
    token: token,
    vault: vault,
    flapUrl: flapUrl,
    featured: featured ?? this.featured,
    unlisted: unlisted ?? this.unlisted,
  );

  /// The same shape the server sends, so a round can be kept on the device
  /// and read back with [Round.fromJson].
  Map<String, dynamic> toJson() => {
    'launcher': launcher,
    'name': name,
    'deposit': formatUnits(deposit, maxFraction: 18),
    'liquidityBps': liquidityBps,
    'checkInGoal': checkInGoal,
    'totalCheckIns': totalCheckIns,
    'memberCount': memberCount,
    'totalDeposits': formatUnits(totalDeposits, maxFraction: 18),
    'totalSponsored': formatUnits(totalSponsored, maxFraction: 18),
    'poolQuoteNow': formatUnits(poolQuoteNow, maxFraction: 18),
    'prizeNow': formatUnits(prizeNow, maxFraction: 18),
    'deadline': deadline.millisecondsSinceEpoch ~/ 1000,
    'launched': launched,
    'minSteps': minSteps,
    'token': token,
    'vault': vault,
    'flapUrl': flapUrl,
    'featured': featured,
    'unlisted': unlisted,
  };

  /// The part of one deposit that goes to the token pool, and the rest.
  BigInt get depositToPool =>
      deposit * BigInt.from(liquidityBps) ~/ BigInt.from(10000);
  BigInt get depositToPrize => deposit - depositToPool;

  factory Round.fromJson(Map<String, dynamic> j) => Round(
    launcher: '${j['launcher']}',
    name: '${j['name'] ?? AppConfig.productName}',
    deposit: amountFromJson(j['deposit']),
    liquidityBps: _int(j['liquidityBps']),
    checkInGoal: _int(j['checkInGoal']),
    totalCheckIns: _int(j['totalCheckIns']),
    memberCount: _int(j['memberCount']),
    totalDeposits: amountFromJson(j['totalDeposits']),
    totalSponsored: amountFromJson(j['totalSponsored']),
    poolQuoteNow: amountFromJson(j['poolQuoteNow']),
    prizeNow: amountFromJson(j['prizeNow']),
    deadline: _time(j['deadline']),
    launched: j['launched'] == true,
    minSteps: j['minSteps'] == null ? 1000 : _int(j['minSteps']),
    token: _address(j['token']),
    vault: _address(j['vault']),
    flapUrl: j['flapUrl'] is String && (j['flapUrl'] as String).isNotEmpty
        ? j['flapUrl'] as String
        : null,
    featured: j['featured'] == true,
    unlisted: j['unlisted'] == true,
  );
}

/// One wallet in a round (GET /rounds/:launcher/me/:address).
class Me {
  Me({
    required this.member,
    required this.daysOf,
    required this.checkedInToday,
    required this.streak,
    required this.bestStreak,
    required this.days,
    required this.claimableTokens,
    required this.claimableQuote,
    required this.claimedTokens,
  });

  final bool member;
  final int daysOf;

  /// The server accepted a check-in for today (UTC).
  final bool checkedInToday;

  /// Consecutive UTC days ending today or yesterday, from the check-ins the
  /// server accepted.
  final int streak;
  final int bestStreak;

  /// "YYYY-MM-DD" (UTC) of each accepted check-in.
  final List<String> days;

  final BigInt claimableTokens;
  final BigInt claimableQuote;
  final BigInt claimedTokens;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    member: j['member'] == true,
    daysOf: _int(j['daysOf']),
    checkedInToday: j['checkedInToday'] == true,
    streak: _int(j['streak']),
    bestStreak: _int(j['bestStreak']),
    days: [for (final d in (j['days'] as List? ?? const [])) '$d'],
    claimableTokens: amountFromJson(j['claimableTokens']),
    claimableQuote: amountFromJson(j['claimableQuote']),
    claimedTokens: amountFromJson(j['claimedTokens']),
  );
}

/// One row of the members list (GET /rounds/:launcher/members).
class Member {
  Member({
    required this.address,
    required this.daysOf,
    required this.streak,
    required this.checkedInToday,
  });

  final String address;
  final int daysOf;
  final int streak;
  final bool checkedInToday;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
    address: '${j['address']}'.toLowerCase(),
    daysOf: _int(j['daysOf']),
    streak: _int(j['streak']),
    checkedInToday: j['checkedInToday'] == true,
  );
}

/// The server accepted today's check-in (POST /rounds/:launcher/checkin). The
/// app sends
/// `CheckInLauncher.checkIn(dayIndex, attesterSignature)` itself.
class CheckInTicket {
  CheckInTicket({
    required this.day,
    required this.dayIndex,
    required this.attesterSignature,
  });

  /// "YYYY-MM-DD" (UTC).
  final String day;

  /// The contract's day number: unix seconds / 86400.
  final int dayIndex;

  /// 65 bytes, hex: the attester's signature the contract checks.
  final String attesterSignature;

  factory CheckInTicket.fromJson(Map<String, dynamic> j) {
    final signature = '${j['attesterSignature'] ?? ''}';
    if (!RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(signature)) {
      throw VerifierException(
        '${AppConfig.productName}\'s server did not sign the check-in. Try '
        'again.',
      );
    }
    return CheckInTicket(
      day: '${j['day']}',
      dayIndex: _int(j['dayIndex']),
      attesterSignature: signature,
    );
  }

  Map<String, dynamic> toJson() => {
    'day': day,
    'dayIndex': dayIndex,
    'attesterSignature': attesterSignature,
  };
}

/// What the faucet did (POST /faucet).
class FaucetResult {
  FaucetResult({required this.funded, this.tx, this.reason});

  /// Test BNB for network fees is on its way to the wallet.
  final bool funded;
  final String? tx;

  /// Why nothing was sent, when [funded] is false.
  final String? reason;

  factory FaucetResult.fromJson(Map<String, dynamic> j) {
    final tx = j['bnbTx'] ?? j['tx'];
    return FaucetResult(
      funded: j['funded'] == true,
      tx: tx is String ? tx : null,
      reason: j['reason'] is String ? j['reason'] as String : null,
    );
  }
}

class VerifierException implements Exception {
  VerifierException(this.message, {this.code, this.status});

  /// One sentence for a person.
  final String message;

  /// The server's error code ("no_round"), when it sent one.
  final String? code;
  final int? status;

  @override
  String toString() => message;
}

/// All access to our server (../verifier). It finds every round our factory
/// created, keeps the streaks and the members lists, runs the gas faucet and
/// is the attester: it signs that a wallet moved enough on a day. Check-ins
/// are attested, not proven. The server cannot launch early, block a launch,
/// choose who is paid beyond signing daily check-ins, or move funds.
///
/// Every round has its own calls under `/rounds/<launcher>`. A server from
/// before that knows one round only (`/round`, `/me`, `/members`,
/// `/checkin`); [rounds] answers null there and the app falls back to those.
class VerifierApi {
  VerifierApi({http.Client? client, String? baseUrl})
    : _http = client ?? http.Client(),
      _base = baseUrl ?? AppConfig.verifierBaseUrl;

  final http.Client _http;
  final String _base;

  // Texts signed with personal_sign. Addresses are always lower case so both
  // sides build the same text; the server rebuilds each one the same way.

  /// `Cypher Run checkin <launcher> <YYYY-MM-DD> <steps>`
  static String checkInMessage(String launcher, String day, int steps) =>
      '${AppConfig.productName} checkin ${launcher.toLowerCase()} $day $steps';

  /// `Cypher Run faucet <address>`
  static String faucetMessage(String address) =>
      '${AppConfig.productName} faucet ${address.toLowerCase()}';

  /// `Cypher Run round <launcher> <listed|unlisted>`, signed by the wallet
  /// that created the round.
  static String roundMessage(String launcher, {required bool unlisted}) =>
      '${AppConfig.productName} round ${launcher.toLowerCase()} '
      '${unlisted ? 'unlisted' : 'listed'}';

  /// personal_sign (EIP-191) with the device key, hex encoded.
  static String sign(EthPrivateKey key, String message) => bytesToHex(
    key.signPersonalMessageToUint8List(
      Uint8List.fromList(utf8.encode(message)),
    ),
    include0x: true,
  );

  /// Shown whenever the server cannot be reached. Never names a host.
  static const unreachable =
      'Could not reach ${AppConfig.productName}\'s server. Check your '
      'connection and try again.';

  static const _busy =
      '${AppConfig.productName}\'s server could not do that right now. Try '
      'again in a moment.';

  Uri _url(String path) {
    if (_base.isEmpty) {
      throw VerifierException('This build has no server address yet.');
    }
    return Uri.parse('$_base$path');
  }

  dynamic _decode(http.Response r) {
    dynamic body;
    try {
      body = jsonDecode(r.body);
    } catch (_) {}
    if (r.statusCode >= 400) {
      // The server answers {error: <code>, message: <sentence>}.
      final map = body is Map<String, dynamic> ? body : null;
      final code = map?['error'];
      final said = map?['message'];
      throw VerifierException(
        // A code alone ("no_round") is not a sentence for a person.
        said is String && said.trim().contains(' ') ? said : _busy,
        code: code is String ? code : null,
        status: r.statusCode,
      );
    }
    // Not JSON at all: something other than the server answered.
    if (body is! Map && body is! List) throw VerifierException(unreachable);
    return body;
  }

  /// A network failure becomes one plain sentence; the cause (which may name
  /// a host) is dropped.
  Future<dynamic> _send(Future<http.Response> Function() send) async {
    final http.Response r;
    try {
      r = await send();
    } on VerifierException {
      rethrow;
    } catch (_) {
      throw VerifierException(unreachable);
    }
    return _decode(r);
  }

  Future<dynamic> _get(String path) => _send(() => _http.get(_url(path)));

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await _send(
      () => _http.post(
        _url(path),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    if (r is! Map<String, dynamic>) throw VerifierException(unreachable);
    return r;
  }

  static Map<String, dynamic> _map(dynamic body) {
    if (body is! Map<String, dynamic>) throw VerifierException(unreachable);
    return body;
  }

  /// The listed rounds, in the server's order: its featured round, then
  /// open rounds by nearest deadline, launched ones, ended ones. Null when
  /// the server is from before it knew more than one round (404).
  Future<List<Round>?> rounds() async {
    final dynamic body;
    try {
      body = await _get('/rounds');
    } on VerifierException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
    final list = body is List
        ? body
        : (body is Map ? body['rounds'] as List? : null) ?? const [];
    return [
      for (final r in list)
        if (r is Map<String, dynamic> && isAddress('${r['launcher']}'))
          Round.fromJson(r),
    ];
  }

  /// One round by its address, listed or not. Null when our factory did not
  /// create it (404 `no_round`).
  Future<Round?> roundAt(String launcher) async {
    try {
      return Round.fromJson(
        _map(await _get('/rounds/${launcher.toLowerCase()}')),
      );
    } on VerifierException catch (e) {
      if (e.code == 'no_round' || e.status == 404) return null;
      rethrow;
    }
  }

  /// The server's current round, or null when none is open (404
  /// `no_round`). The one round a server from before `/rounds` knows.
  Future<Round?> round() async {
    try {
      return Round.fromJson(_map(await _get('/round')));
    } on VerifierException catch (e) {
      if (e.code == 'no_round' || e.status == 404) return null;
      rethrow;
    }
  }

  /// `/rounds/<launcher>` before a per-round call; nothing for the calls of
  /// a server that knows one round only.
  static String _in(String? launcher) =>
      launcher == null ? '' : '/rounds/${launcher.toLowerCase()}';

  /// One wallet's place in a round: days, streak, share. With no [launcher]
  /// it asks about the server's current round.
  Future<Me> me(String address, {String? launcher}) async => Me.fromJson(
    _map(await _get('${_in(launcher)}/me/${address.toLowerCase()}')),
  );

  /// The members of a round, most days first. With no [launcher] it asks
  /// about the server's current round.
  Future<List<Member>> members({String? launcher}) async {
    final body = await _get('${_in(launcher)}/members');
    final list = body is List
        ? body
        : (body is Map ? body['members'] as List? : null) ?? const [];
    return [
      for (final m in list)
        if (m is Map<String, dynamic>) Member.fromJson(m),
    ];
  }

  /// Sends today's steps, signed by the member's key. [source] is
  /// "healthkit", "healthconnect" or "self" (typed in the browser; the
  /// server takes it on a testnet demo only and stores it flagged). The
  /// answer carries the attester's signature for the contract.
  ///
  /// The signed text names the round. [perRound] false posts to the one
  /// `/checkin` of a server that knows its current round only.
  Future<CheckInTicket> checkIn(
    EthPrivateKey key, {
    required String launcher,
    required int steps,
    required String source,
    DateTime? now,
    bool perRound = true,
  }) async {
    final day = utcDayKey(now ?? DateTime.now());
    return CheckInTicket.fromJson(
      await _post('${_in(perRound ? launcher : null)}/checkin', {
        'address': key.address.with0x.toLowerCase(),
        'steps': steps,
        'source': source,
        'signature': sign(key, checkInMessage(launcher, day, steps)),
      }),
    );
  }

  /// Tells the server whether a round is shown in the public list. Only the
  /// wallet that created the round can say; it may call this again to change
  /// it. Returns what the server now holds.
  ///
  /// Unlisted is not hidden: anyone with the link can open and join the
  /// round, and anyone reading the chain can find it.
  Future<bool> registerRound(
    EthPrivateKey key, {
    required String launcher,
    required bool unlisted,
  }) async {
    final answer = await _post('/rounds', {
      'launcher': launcher.toLowerCase(),
      'unlisted': unlisted,
      'signature': sign(key, roundMessage(launcher, unlisted: unlisted)),
    });
    return answer['unlisted'] == true;
  }

  /// Asks for a little test BNB for network fees. The server sends it once
  /// per address. It does not send test USD: getting test dollars is a step
  /// the person takes in the app.
  Future<FaucetResult> faucet(EthPrivateKey key) async {
    final address = key.address.with0x.toLowerCase();
    return FaucetResult.fromJson(
      await _post('/faucet', {
        'address': address,
        'signature': sign(key, faucetMessage(address)),
      }),
    );
  }
}
