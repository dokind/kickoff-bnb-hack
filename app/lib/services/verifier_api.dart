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

/// An amount the server sends both ways: `raw.<name>` in exact base units
/// and `<name>` as a decimal string in whole units. The exact one is read
/// first; the decimal string is taken as whole units, never as base units,
/// so a large whole number is not misread.
BigInt exactAmountFromJson(
  Map<String, dynamic> j,
  String name, {
  int decimals = 18,
}) {
  final raw = j['raw'];
  if (raw is Map) {
    final exact = '${raw[name] ?? ''}'.trim();
    if (RegExp(r'^\d+$').hasMatch(exact)) return BigInt.parse(exact);
  }
  final value = j[name];
  if (value == null) return BigInt.zero;
  return parseUnits('$value', decimals: decimals) ?? BigInt.zero;
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

/// A Season: one event with one set of dates ("Season 1"), made of squads.
/// Each squad is its own round: one bar, one piggy bank, one coin. The
/// server sends it as `season` with a round that is part of one, and null or
/// nothing with any other round; a server from before Seasons sends nothing.
///
/// The contract has no start date. The server signs no check-in for a
/// Season round before [startDay] or after [endDay] (a server rule, like the
/// fewest steps), so everyone starts at 0 on the same day. The app stops
/// offering Join after [joinUntilDay] or at [squadSize] members; a join sent
/// to the contract directly still goes through.
class Season {
  const Season({
    required this.name,
    required this.startDay,
    required this.endDay,
    required this.joinUntilDay,
    this.squadSize = 0,
  });

  /// "Season 1".
  final String name;

  /// The first and the last check-in day, numbered as the contract numbers
  /// days: unix seconds / 86400 (UTC).
  final int startDay;
  final int endDay;

  /// The last day the app offers Join.
  final int joinUntilDay;

  /// The app stops offering Join at this many members. 0: no limit.
  final int squadSize;

  /// How many check-in days the Season has: 30.
  int get dayCount => endDay - startDay + 1;

  /// When check-ins open: 00:00 UTC on [startDay] (07:00 in Bangkok).
  DateTime get startsAt => utcDayStart(startDay);

  /// The last check-in day, at 00:00 UTC.
  DateTime get lastDay => utcDayStart(endDay);

  /// The last day the app offers Join, at 00:00 UTC.
  DateTime get joinUntil => utcDayStart(joinUntilDay);

  /// The Season's day [now] falls on: 0 before the first check-in day, 1 to
  /// [dayCount] during, [dayCount] + 1 after the last.
  int dayNumber(DateTime now) {
    final today = dayIndexOf(now);
    if (today < startDay) return 0;
    if (today > endDay) return dayCount + 1;
    return today - startDay + 1;
  }

  /// Check-ins have not opened yet: the server signs none.
  bool notStarted(DateTime now) => dayIndexOf(now) < startDay;

  /// The last check-in day is over: the server signs none.
  bool checkInsOver(DateTime now) => dayIndexOf(now) > endDay;

  /// Check-in days still to come, today included: all of them before the
  /// start, none after the end.
  int daysLeft(DateTime now) {
    final today = dayIndexOf(now);
    if (today < startDay) return dayCount;
    if (today > endDay) return 0;
    return endDay - today + 1;
  }

  /// Whole UTC days until check-ins open; 0 once they have.
  int daysToStart(DateTime now) {
    final n = startDay - dayIndexOf(now);
    return n > 0 ? n : 0;
  }

  /// The last day to join in the app is over.
  bool joinWindowOver(DateTime now) => dayIndexOf(now) > joinUntilDay;

  /// The squad has as many members as the app lets in.
  bool squadFull(int memberCount) => squadSize > 0 && memberCount >= squadSize;

  /// The app stops offering Join: the window is over or the squad is full.
  bool joinClosed(DateTime now, int memberCount) =>
      joinWindowOver(now) || squadFull(memberCount);

  /// The bar can no longer fill in this Season: even if every member, and
  /// while the app still lets people in a full squad, checked in on every
  /// day left (today included), it would stay short of [goal]. The round is
  /// then refunded after its deadline.
  bool cannotFill(
    DateTime now, {
    required int totalCheckIns,
    required int memberCount,
    required int goal,
  }) {
    if (goal <= 0 || totalCheckIns >= goal) return false;
    var people = memberCount;
    if (!joinClosed(now, memberCount)) {
      // Anyone may still come: nothing to say yet.
      if (squadSize <= 0) return false;
      if (squadSize > people) people = squadSize;
    }
    return totalCheckIns + people * daysLeft(now) < goal;
  }

  /// The `season` of a round's JSON. Null when there is none, or when it
  /// makes no sense (no dates, the end before the start). The day numbers
  /// are read first (unix seconds are taken as the day they fall on); the
  /// "YYYY-MM-DD" dates stand in for them, or a full date and time, read as
  /// its UTC day.
  static Season? fromJson(Object? j) {
    if (j is! Map) return null;
    int? day(Object? index, Object? date) {
      final n = index is num
          ? index.toInt()
          : index is String
          ? int.tryParse(index.trim())
          : null;
      if (n != null && n > 0) return n > 100000000 ? n ~/ 86400 : n;
      if (date is! String) return null;
      final text = date.trim();
      if (!text.contains('T')) return dayIndexOfKey(text);
      final at = DateTime.tryParse(text);
      return at == null ? null : dayIndexOf(at);
    }

    final start = day(j['startDay'], j['start']);
    final end = day(j['endDay'], j['end']);
    if (start == null || end == null || end < start) return null;
    final until = day(j['joinUntilDay'], j['joinUntil']) ?? end;
    final name = '${j['name'] ?? ''}'.trim();
    final size = _int(j['squadSize']);
    return Season(
      name: name.isEmpty ? 'Season' : name,
      startDay: start,
      endDay: end,
      joinUntilDay: until,
      squadSize: size > 0 ? size : 0,
    );
  }

  /// The server's shape, so a round kept on the device reads back the same.
  Map<String, dynamic> toJson() => {
    'name': name,
    'start': utcDayKey(startsAt),
    'end': utcDayKey(lastDay),
    'joinUntil': utcDayKey(joinUntil),
    'startDay': startDay,
    'endDay': endDay,
    'joinUntilDay': joinUntilDay,
    'days': dayCount,
    'squadSize': squadSize,
  };
}

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
    this.season,
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

  /// The Season this round is a squad of. Null for any other round, and
  /// with a server that does not send it.
  final Season? season;

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
    season: season,
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
    'season': season?.toJson(),
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
    season: Season.fromJson(j['season']),
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

/// Totals across every round our factory created, listed or not (GET
/// /stats/:address). Numbers only: no round is named.
class Stats {
  Stats({
    required this.people,
    required this.checkIns,
    required this.deposited,
    required this.launched,
    required this.complete,
    this.you,
  });

  /// Unique wallets the server has seen as members.
  final int people;

  /// Check-ins on chain, all rounds together.
  final int checkIns;

  /// Deposits the rounds hold or launched with, in base units.
  final BigInt deposited;

  /// Rounds whose token launched.
  final int launched;

  /// False when the server could not read one of the rounds: the totals
  /// are then lower than the truth.
  final bool complete;

  /// This wallet across the rounds it joined. Null when the server could
  /// not read one of them.
  final WalletStats? you;

  factory Stats.fromJson(Map<String, dynamic> j) {
    final you = j['you'];
    return Stats(
      people: _int(j['people']),
      checkIns: _int(j['checkIns']),
      deposited: exactAmountFromJson(j, 'deposited'),
      launched: _int(j['launched']),
      complete: j['complete'] != false,
      you: you is Map<String, dynamic> ? WalletStats.fromJson(you) : null,
    );
  }
}

/// One wallet across every round it joined.
class WalletStats {
  WalletStats({
    required this.rounds,
    required this.days,
    required this.claimed,
  });

  /// Rounds joined.
  final int rounds;

  /// Days shown up, all rounds together.
  final int days;

  /// Test USD claimed from the vaults of launched rounds, in base units.
  final BigInt claimed;

  factory WalletStats.fromJson(Map<String, dynamic> j) => WalletStats(
    rounds: _int(j['rounds']),
    days: _int(j['days']),
    claimed: exactAmountFromJson(j, 'claimed'),
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
///
/// The server's address can change (see OriginService). When a call cannot
/// connect, or the answer is 530 (Cloudflare's code for a tunnel that is
/// gone) or a 502 or 503 without the server's own error body, the address is
/// looked up once more and, if it changed, that one call is sent once more
/// to the new address. Never more.
class VerifierApi {
  /// With no [baseUrl] every call uses [AppConfig.verifierBaseUrl] as it is
  /// at that moment, and [relocate] defaults to
  /// [AppConfig.refreshVerifierBaseUrl]. With a [baseUrl] the address is
  /// fixed unless a [relocate] is given.
  VerifierApi({
    http.Client? client,
    String? baseUrl,
    Future<String> Function()? relocate,
  }) : _http = client ?? http.Client(),
       _pinned = baseUrl,
       _relocate =
           relocate ??
           (baseUrl == null ? AppConfig.refreshVerifierBaseUrl : null);

  final http.Client _http;

  /// The fixed address, when one was given (and the one moved to since).
  String? _pinned;

  /// Looks the server's address up again; returns the base URL to use.
  final Future<String> Function()? _relocate;

  String get _base => _pinned ?? AppConfig.verifierBaseUrl;

  /// Answers that mean the server is not where the app thought: the tunnel
  /// in front of it is gone (530) or nothing is behind it (502, 503 from the
  /// tunnel). A 503 from the server itself carries a JSON body and is not
  /// one of these.
  static bool _gone(http.Response r) {
    if (r.statusCode == 530) return true;
    if (r.statusCode != 502 && r.statusCode != 503) return false;
    try {
      final body = jsonDecode(r.body);
      return body is! Map || body['error'] is! String;
    } catch (_) {
      return true;
    }
  }

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

  static const _noAddress = 'This build has no server address yet.';

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

  /// One try: the answer, or null when it could not connect. The cause of a
  /// failure (which may name a host) is dropped.
  Future<http.Response?> _try(
    String base,
    Future<http.Response> Function(Uri url) send,
    String path,
  ) async {
    try {
      return await send(Uri.parse('$base$path'));
    } catch (_) {
      return null;
    }
  }

  /// Sends one call. When it cannot connect or the server is gone, looks the
  /// address up again and, if it changed, sends it once more there. A
  /// network failure becomes one plain sentence.
  Future<dynamic> _send(
    String path,
    Future<http.Response> Function(Uri url) send,
  ) async {
    var base = _base;
    http.Response? r = base.isEmpty ? null : await _try(base, send, path);
    final relocate = _relocate;
    if ((r == null || _gone(r)) && relocate != null) {
      String next;
      try {
        next = await relocate();
      } catch (_) {
        next = base;
      }
      if (next.isNotEmpty && next != base) {
        base = next;
        if (_pinned != null) _pinned = next;
        r = await _try(next, send, path);
      }
    }
    if (r == null) {
      throw VerifierException(base.isEmpty ? _noAddress : unreachable);
    }
    // Still nothing behind the address: say so plainly.
    if (_gone(r)) throw VerifierException(unreachable, status: r.statusCode);
    return _decode(r);
  }

  Future<dynamic> _get(String path) => _send(path, _http.get);

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await _send(
      path,
      (url) => _http.post(
        url,
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

  /// The totals across every round, with [address]'s own. Null when the
  /// server is from before it kept them (404).
  Future<Stats?> stats(String address) async {
    try {
      return Stats.fromJson(
        _map(await _get('/stats/${address.toLowerCase()}')),
      );
    } on VerifierException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
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
