import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';

import 'config.dart';
import 'services/chain_service.dart';
import 'services/health_service.dart';
import 'services/verifier_api.dart';
import 'services/wallet_store.dart';
import 'util/format.dart';
import 'util/season_text.dart';
import 'widgets/gauges.dart' show DayState;

/// What Home's one primary action is right now.
enum HomeStage {
  /// The round is being read for the first time.
  loading,

  /// The round could not be read.
  error,

  /// The server has no round open.
  noRound,

  /// Not a member yet: "Join Demo Day · 1,000 USD".
  join,

  /// A member who has not checked in today: "Check in · Demo Day".
  checkIn,

  /// A member who has: "Checked in", with a hint about tomorrow.
  checkedIn,

  /// The bar is full: anyone may "Launch Demo Day".
  launch,

  /// Launched, and this wallet showed up at least one day: "Claim · Demo
  /// Day".
  claim,

  /// Launched, and this wallet has no days: "See the result · Demo Day".
  result,

  /// The deadline passed without a launch and this wallet has money in the
  /// round: "Deposit back · Demo Day".
  refund,

  /// The deadline passed without a launch and nothing is owed here.
  ended,
}

/// The actions that take several transactions or waits, each shown with
/// its steps ([RunProgress]).
enum StepAction { join, start, launch, claim, refund }

/// Where a multi-step action is right now: its steps, in the words the
/// screen shows, and the one running. [AppState] moves [current] on only
/// when that step has really begun (a transaction mined, an answer read),
/// never on a timer.
class ActionSteps {
  const ActionSteps({
    required this.action,
    required this.launcher,
    required this.steps,
    this.current = 0,
  });

  final StepAction action;

  /// The round it is for, in lower case. Null while a round is started.
  final String? launcher;
  final List<String> steps;

  /// The step running now, from 0.
  final int current;

  ActionSteps at(int i) =>
      ActionSteps(action: action, launcher: launcher, steps: steps, current: i);

  static const prepare = 'Prepare your wallet';
  static const getDollars = 'Get test dollars';
  static const approve = 'Approve test USD';
  static const pay = 'Pay the deposit';
  static const findAddress = 'Find the launch address';
  static const send = 'Start the round on chain';
  static const launchOnFlap = 'Launch on Flap';
  static const readResult = 'Read the result';
  static const claimVault = 'Claim from the piggy bank';
  static const takeBack = 'Take your deposit back';
  static const updateBalance = 'Update your balance';
}

/// A round this device knows beyond the public list: opened by its link, or
/// started here. Kept on the device so it stays on Home's slider.
class KnownRound {
  KnownRound({
    required this.launcher,
    this.creator,
    this.unlisted,
    this.registered = true,
    this.cached,
  });

  /// The round's contract, in lower case.
  final String launcher;

  /// The wallet that started the round on this device, in lower case. Null
  /// for a round opened by its link.
  String? creator;

  /// What its creator chose: not shown in the public list. Null when this
  /// device does not know.
  bool? unlisted;

  /// The server holds the creator's choice. False until POST /rounds went
  /// through; the app asks again by itself.
  bool registered;

  /// One sentence when the last try to save the choice failed.
  String? registerError;

  /// The round as last seen, in the server's JSON shape.
  Map<String, dynamic>? cached;

  Map<String, dynamic> toJson() => {
    'launcher': launcher,
    'creator': creator,
    'unlisted': unlisted,
    'registered': registered,
    'round': cached,
  };

  static KnownRound? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final launcher = '${j['launcher']}'.toLowerCase();
    if (!isAddress(launcher)) return null;
    final round = j['round'];
    return KnownRound(
      launcher: launcher,
      creator: j['creator'] is String ? j['creator'] as String : null,
      unlisted: j['unlisted'] is bool ? j['unlisted'] as bool : null,
      registered: j['registered'] != false,
      cached: round is Map<String, dynamic> ? round : null,
    );
  }
}

/// What the app has read about one round for this wallet.
class _RoundView {
  /// The round in full (GET /rounds/:launcher). Null until read; the list's
  /// entry stands in.
  Round? round;
  RoundChain? onChain;
  ShareChain? share;
  Me? me;
  List<Member> members = const [];

  /// The members list was answered at least once (it may be empty).
  bool membersRead = false;

  /// One sentence when the last try to read the members failed.
  String? membersError;
  DateTime? readAt;
}

/// The whole app's state: the wallet, every round on Home's slider, the one
/// selected, and where this wallet stands in it. Screens listen to it and
/// call its methods; it calls the services.
class AppState extends ChangeNotifier {
  AppState({
    WalletStore? store,
    ChainService? chain,
    VerifierApi? api,
    HealthService? health,
    DateTime Function()? clock,
    this.gasPoll = const Duration(seconds: 3),
    this.gasPollTries = 15,
  }) : store = store ?? WalletStore(),
       chain = chain ?? ChainService(),
       api = api ?? VerifierApi(),
       health = health ?? HealthService(),
       _clock = clock ?? DateTime.now;

  final WalletStore store;
  final ChainService chain;
  final VerifierApi api;
  final HealthService health;
  final DateTime Function() _clock;

  /// How often and how many times [ensureGas] looks for the faucet's
  /// transfer.
  final Duration gasPoll;
  final int gasPollTries;

  DateTime get now => _clock();

  bool ready = false;

  /// The onboarding steps have been seen on this device.
  bool onboarded = false;
  EthPrivateKey? key;
  BigInt bnb = BigInt.zero;
  BigInt usd = BigInt.zero;

  /// True while the wallet waits for the faucet's test BNB.
  bool funding = false;

  /// The multi-step action running now, and its step. Null when none is.
  ActionSteps? steps;

  /// [steps] when they are for [action] (and for [launcher], when given).
  ActionSteps? stepsFor(StepAction action, {String? launcher}) {
    final s = steps;
    if (s == null || s.action != action) return null;
    if (launcher != null && s.launcher != launcher.toLowerCase()) return null;
    return s;
  }

  /// The join transaction of each round this wallet joined on this device
  /// since the app opened, by launcher in lower case.
  final _joinTx = <String, String>{};

  /// The transaction that paid this wallet's deposit into [launcher], when
  /// this device sent it since the app opened.
  String? joinTxOf(String launcher) => _joinTx[launcher.toLowerCase()];

  /// "Prepare your wallet" leads the steps only when the wallet, as last
  /// read, has less than [need] for fees.
  List<String> _gasStep(BigInt need) =>
      bnb < need ? const [ActionSteps.prepare] : const [];

  /// Runs [body] with [names] as its steps, the first one running.
  Future<T> _withSteps<T>(
    StepAction action,
    String? launcher,
    List<String> names,
    Future<T> Function() body,
  ) async {
    steps = ActionSteps(action: action, launcher: launcher, steps: names);
    notifyListeners();
    try {
      return await body();
    } finally {
      steps = null;
      notifyListeners();
    }
  }

  /// The step called [name] has begun. Steps only move forward, and a step
  /// that is not in the list (not needed this time) changes nothing.
  void _reach(String name) {
    final s = steps;
    if (s == null) return;
    final i = s.steps.indexOf(name);
    if (i <= s.current) return;
    steps = s.at(i);
    notifyListeners();
  }

  /// Every round on Home's slider, in its order: the server's featured
  /// round, then the rounds this wallet has joined, then open rounds by
  /// nearest deadline, launched ones, ended ones. The public list (GET
  /// /rounds) plus the rounds this device opened by link or started, listed
  /// or not.
  List<Round> rounds = const [];

  /// The rounds (launcher, lower case) this wallet is a member of.
  final Set<String> joined = {};

  /// The round whose card is in view on Home (launcher, lower case). It is
  /// what [round] and everything read from it are about.
  String? selected;

  /// The server answered 404 to GET /rounds: it is from before it knew more
  /// than one round, and the app uses its single-round calls.
  bool legacyServer = false;
  String? _legacyCurrent;

  /// True when the server was read and has no round to show.
  bool noRound = false;

  /// One sentence when the rounds could not be read.
  String? roundError;
  bool loading = false;

  /// One sentence for the banner (a link that leads nowhere). Home shows it
  /// once and clears it.
  String? notice;

  final _known = <String, KnownRound>{};
  final _views = <String, _RoundView>{};
  List<String> _serverOrder = const [];

  /// The round a link asked for, until the rounds are read.
  String? _linked;

  /// The round a link asked for (`/r/<launcher>`), until the rounds are
  /// read. Before there is a wallet this is the round the visitor was
  /// invited to, which the first-run step names.
  String? get linkedRound => _linked;

  /// The round the person last chose, kept between launches.
  String? _remembered;

  /// Home's cards move on by themselves only until the person first touches
  /// Home, and not at all when the app was opened from a round's link. Not
  /// kept on the device: it is true again the next time the app is opened.
  bool autoAdvance = true;

  /// From now until the app is opened again the cards stay where they are
  /// unless the person moves them.
  void stopAutoAdvance() {
    if (!autoAdvance) return;
    autoAdvance = false;
    notifyListeners();
  }

  _RoundView? get _view => selected == null ? null : _views[selected];

  Round? _listed(String? id) {
    for (final r in rounds) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// The selected round as the server reports it. Null until read, or when
  /// there is none ([noRound]).
  Round? get round => roundOf(selected);

  /// The round at [launcher] as the server reports it, whichever card is in
  /// view. Null when it is not on the slider. A sheet opened for a round
  /// reads that round through this and the other "of" readers below, so it
  /// stays about that round when the selection changes behind it.
  Round? roundOf(String? launcher) {
    final id = launcher?.toLowerCase();
    return _views[id]?.round ?? _listed(id);
  }

  /// What the selected round's contract says for this wallet. Null when the
  /// chain could not be read; the server's numbers are used then.
  RoundChain? get onChain => _view?.onChain;

  /// This wallet's share in the vault, after the launch.
  ShareChain? get share => _view?.share;

  /// This wallet's days and streak in the selected round, from the server.
  Me? get me => _view?.me;
  List<Member> get members => _view?.members ?? const [];

  /// The selected round's members list has been answered (it may be
  /// empty). False while it is read for the first time.
  bool get membersRead => _view?.membersRead ?? false;

  /// One sentence when the members list could not be read.
  String? get membersError => _view?.membersError;

  /// Totals across every round, and this wallet's own. Null until read, and
  /// with a server that does not keep them.
  Stats? stats;

  /// Where [selected] sits in [rounds]; 0 when there is none.
  int get selectedIndex {
    final i = rounds.indexWhere((r) => r.id == selected);
    return i < 0 ? 0 : i;
  }

  /// What this device knows about a round it opened by link or started.
  KnownRound? knownRound(String launcher) => _known[launcher.toLowerCase()];

  /// This wallet has paid the deposit of the round at [launcher].
  bool isMemberOf(String launcher) {
    final id = launcher.toLowerCase();
    return id == selected ? isMember : joined.contains(id);
  }

  /// A check-in the server signed that is not on chain yet.
  CheckInTicket? _pending;
  String? _pendingLauncher;

  String get address => key!.address.with0x;
  bool get hasWallet => key != null;

  /// The wallet key as hex, for "Back up your key" only.
  String get keyHex => privateKeyHex(key!);

  // The round, chain first ----------------------------------------------------

  /// The fixed deposit of the round.
  BigInt get deposit => depositOf(selected);

  /// The fixed deposit of the round at [launcher], chain first.
  BigInt depositOf(String? launcher) {
    final id = launcher?.toLowerCase();
    return _views[id]?.onChain?.deposit ?? roundOf(id)?.deposit ?? BigInt.zero;
  }

  bool get launched =>
      (onChain?.launched ?? false) || (round?.launched ?? false);

  int get totalCheckIns =>
      math.max(onChain?.totalCheckIns ?? 0, round?.totalCheckIns ?? 0);

  /// Everyone's check-ins have filled the bar.
  bool get goalReached {
    final goal = round?.checkInGoal ?? 0;
    return goal > 0 && totalCheckIns >= goal;
  }

  /// 0 to 1: how full the bar is.
  double get barProgress {
    final goal = round?.checkInGoal ?? 0;
    return goal <= 0 ? 0 : (totalCheckIns / goal).clamp(0.0, 1.0);
  }

  BigInt get poolQuoteNow => poolQuoteNowOf(selected);

  /// What is in the token pool of the round at [launcher], chain first.
  BigInt poolQuoteNowOf(String? launcher) {
    final id = launcher?.toLowerCase();
    return _views[id]?.onChain?.poolQuoteNow ??
        roundOf(id)?.poolQuoteNow ??
        BigInt.zero;
  }

  /// How much the token pool is short of what Flap needs. Zero when it has
  /// enough.
  BigInt get poolShort => poolShortOf(selected);

  /// The same for the round at [launcher].
  BigInt poolShortOf(String? launcher) {
    final short =
        wholeUnits(AppConfig.launchPoolFloor) - poolQuoteNowOf(launcher);
    return short > BigInt.zero ? short : BigInt.zero;
  }

  bool get pastDeadline {
    final r = round;
    return r != null && now.isAfter(r.deadline);
  }

  bool get isMember =>
      onChain?.isMember ?? me?.member ?? joined.contains(selected);

  /// This wallet's days and today's check-in in the selected round have
  /// been read, from the chain or from the server. Until then [daysOf] and
  /// [checkedInToday] say 0 and false only because nothing is known yet,
  /// and [isMember] may come from what was known before.
  bool get yourDaysKnown => onChain != null || me != null;

  /// The selected round has been read at least once, whatever came back.
  /// With [yourDaysKnown] still false after it, neither the chain nor the
  /// server answered for this wallet.
  bool get selectedReadOnce => _view?.readAt != null;

  /// Days this wallet has checked in.
  int get daysOf => daysIn(selected);

  /// Days this wallet has checked in to the round at [launcher].
  int daysIn(String? launcher) {
    final view = _views[launcher?.toLowerCase()];
    return view?.onChain?.daysOf ?? view?.me?.daysOf ?? 0;
  }

  bool get checkedInToday =>
      onChain?.checkedInToday ?? me?.checkedInToday ?? false;

  /// Consecutive days ending today or yesterday.
  int get streak => streakIn(selected);

  /// This wallet's streak in the round at [launcher].
  int streakIn(String? launcher) =>
      _views[launcher?.toLowerCase()]?.me?.streak ?? 0;

  BigInt get refundable => onChain?.refundable ?? BigInt.zero;

  /// The server signed today's check-in but it is not on chain yet.
  bool get hasPendingCheckIn => hasPendingCheckInFor(selected);

  /// The same for the round at [launcher].
  bool hasPendingCheckInFor(String? launcher) =>
      _pendingTicketFor(roundOf(launcher)) != null;

  CheckInTicket? _pendingTicketFor(Round? r) {
    final p = _pending;
    if (p == null || r == null) return null;
    if (_pendingLauncher != r.id) return null;
    return p.dayIndex == dayIndexOf(now) ? p : null;
  }

  /// The token's address, once launched.
  String? get token => share?.token ?? round?.token;

  /// What this wallet can take from the vault now.
  BigInt get claimableTokens =>
      share?.claimableTokens ?? me?.claimableTokens ?? BigInt.zero;
  BigInt get claimableQuote =>
      share?.claimableQuote ?? me?.claimableQuote ?? BigInt.zero;
  BigInt get claimedTokens =>
      share?.claimedTokens ?? me?.claimedTokens ?? BigInt.zero;
  BigInt get claimedQuote => share?.claimedQuote ?? BigInt.zero;
  bool get hasClaimable =>
      claimableTokens > BigInt.zero || claimableQuote > BigInt.zero;

  /// Home's one primary action.
  HomeStage get stage {
    if (round == null) {
      if (noRound) return HomeStage.noRound;
      return roundError != null ? HomeStage.error : HomeStage.loading;
    }
    if (launched) return daysOf > 0 ? HomeStage.claim : HomeStage.result;
    if (pastDeadline) {
      return refundable > BigInt.zero || (onChain == null && isMember)
          ? HomeStage.refund
          : HomeStage.ended;
    }
    if (goalReached) return HomeStage.launch;
    if (!isMember) return HomeStage.join;
    return checkedInToday ? HomeStage.checkedIn : HomeStage.checkIn;
  }

  /// The last seven UTC days, oldest first, for the strip on Home. A day is
  /// "missed" only after this wallet's first check-in.
  List<(DateTime, DayState)> get week {
    final today = now.toUtc();
    final done = {...?me?.days};
    if (checkedInToday) done.add(utcDayKey(today));
    final first = done.isEmpty
        ? null
        : done.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    return [
      for (var back = 6; back >= 0; back--)
        () {
          final day = DateTime.utc(today.year, today.month, today.day - back);
          final key = utcDayKey(day);
          final state = done.contains(key)
              ? DayState.done
              : back == 0
              ? DayState.today
              : first != null && key.compareTo(first) > 0
              ? DayState.missed
              : DayState.upcoming;
          return (day, state);
        }(),
    ];
  }

  // Start-up and onboarding ---------------------------------------------------

  /// Loads the wallet from secure storage, then refreshes everything in the
  /// background.
  Future<void> init() async {
    key = await store.load();
    onboarded = hasWallet && await store.loadOnboarded();
    final pending = await store.loadPending();
    if (pending != null) {
      try {
        _pending = CheckInTicket.fromJson(pending);
        _pendingLauncher = '${pending['launcher']}'.toLowerCase();
      } catch (_) {}
    }
    _restoreRounds(await store.loadRounds());
    ready = true;
    notifyListeners();
    if (hasWallet) {
      unawaited(_fundIfEmpty());
      unawaited(refresh());
    }
  }

  /// Makes the device wallet if there is none yet, silently, and asks the
  /// faucet for gas in the background. Nothing waits for the faucet.
  Future<void> createWallet() async {
    if (hasWallet) return;
    key = await store.create();
    notifyListeners();
    unawaited(_fundIfEmpty());
    unawaited(refresh());
  }

  Future<void> completeOnboarding() async {
    await createWallet();
    onboarded = true;
    await store.saveOnboarded();
    notifyListeners();
  }

  /// "Import a key": this device uses [text]'s wallet from now on. Throws
  /// one sentence when the text is not a private key.
  Future<void> importKey(String text) async {
    final imported = parsePrivateKey(text);
    if (imported == null) {
      throw Exception(
        'That is not a private key. It is 64 characters, 0 to 9 and a to f.',
      );
    }
    await store.save(imported);
    key = imported;
    bnb = BigInt.zero;
    usd = BigInt.zero;
    _views.clear();
    joined.clear();
    stats = null;
    _pending = null;
    await store.savePending(null);
    notifyListeners();
    unawaited(_fundIfEmpty());
    await refresh();
  }

  // Gas -----------------------------------------------------------------------

  /// Background top-up for a wallet with no gas. Never throws.
  Future<void> _fundIfEmpty() async {
    if (!hasWallet) return;
    if (!await refreshBalances() || bnb >= AppConfig.smallGasWei) return;
    try {
      await requestFaucet();
      await refreshBalances();
    } catch (_) {
      // ensureGas asks again before the first transaction.
    }
  }

  Future<FaucetResult>? _faucetRun;

  /// Asks the server's faucet for a little test BNB (gas only). Calls made
  /// while one is running share its answer, so the faucet is asked once.
  Future<FaucetResult> requestFaucet() =>
      _faucetRun ??= api.faucet(key!).whenComplete(() => _faucetRun = null);

  /// Called before every transaction: makes sure the wallet holds [need] of
  /// test BNB, asking the faucet and waiting for its transfer when it does
  /// not. [funding] is true meanwhile ("Preparing your wallet"). Throws one
  /// sentence when the gas does not arrive.
  Future<void> ensureGas(BigInt need, {String? shortMessage}) async {
    await refreshBalances();
    if (bnb >= need) return;
    funding = true;
    notifyListeners();
    try {
      try {
        await requestFaucet();
      } catch (_) {
        // The faucet serves an address once; the balance check decides.
      }
      for (var i = 0; i < gasPollTries; i++) {
        await refreshBalances();
        if (bnb >= need) return;
        await Future<void>.delayed(gasPoll);
      }
    } finally {
      funding = false;
      notifyListeners();
    }
    throw Exception(
      shortMessage ??
          'Your wallet has no test BNB for network fees yet. Try again in a '
              'minute.',
    );
  }

  /// Returns false when the balances could not be read.
  Future<bool> refreshBalances() async {
    if (!hasWallet) return false;
    try {
      final results = await Future.wait([
        chain.bnbBalance(address),
        chain.quoteBalance(address),
      ]);
      bnb = results[0];
      usd = results[1];
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // The rounds this device knows ---------------------------------------------

  void _restoreRounds(Map<String, dynamic>? saved) {
    if (saved == null) return;
    final picked = saved['selected'];
    if (picked is String && isAddress(picked)) {
      _remembered = picked.toLowerCase();
    }
    for (final j in (saved['known'] as List? ?? const [])) {
      final k = KnownRound.fromJson(j);
      if (k != null) _known[k.launcher] = k;
    }
  }

  Future<void> _saveRounds() async {
    try {
      await store.saveRounds({
        'selected': _remembered,
        'known': [for (final k in _known.values) k.toJson()],
      });
    } catch (_) {
      // Storage is a convenience here: the rounds are read again anyway.
    }
  }

  /// A round's link was opened (`/r/<launcher>`): that round is selected as
  /// soon as it is read, listed or not, and stays on this device's slider.
  /// Before there is a wallet it is only remembered, so it survives the
  /// first-run steps.
  Future<void> openLink(String launcher) async {
    final id = launcher.toLowerCase();
    if (!isAddress(id)) return;
    // The person came for this round: the cards do not leave it by
    // themselves.
    stopAutoAdvance();
    _known.putIfAbsent(id, () => KnownRound(launcher: id));
    _linked = id;
    _remembered = id;
    await _saveRounds();
    if (!hasWallet) return;
    if (_listed(id) != null) {
      _linked = null;
      select(id);
      return;
    }
    await refresh();
    // A read that was already running may not have looked for this round.
    if (_linked == id) await refresh();
  }

  /// The card in view on Home is now [launcher]: everything under the cards
  /// is about that round. [remember] is false when the cards moved by
  /// themselves, so only a round the person chose is kept between launches.
  void select(String launcher, {bool remember = true}) {
    final id = launcher.toLowerCase();
    if (_listed(id) == null) return;
    if (remember && _remembered != id) {
      _remembered = id;
      unawaited(_saveRounds());
    }
    if (selected == id) return;
    selected = id;
    notifyListeners();
    // Read it again unless it was read a moment ago.
    final readAt = _views[id]?.readAt;
    final fresh = Duration(seconds: remember ? 5 : 30);
    if (readAt == null || now.difference(readAt) > fresh) {
      unawaited(_readSelected(id).then((_) => notifyListeners()));
    }
  }

  // Reading the rounds --------------------------------------------------------

  Future<void>? _refreshRun;

  /// Reads the rounds, the selected one for this wallet (its contract, the
  /// days, the members) and the balances. Calls made while one is running
  /// share it.
  Future<void> refresh() =>
      _refreshRun ??= _refresh().whenComplete(() => _refreshRun = null);

  Future<void> _refresh() async {
    if (!hasWallet) return;
    loading = true;
    roundError = null;
    notifyListeners();
    try {
      await _readRounds();
    } catch (e) {
      roundError = friendlyError(e);
    }
    final id = selected;
    await Future.wait([if (id != null) _readSelected(id), refreshBalances()]);
    loading = false;
    notifyListeners();
    // The totals last: after a join or a check-in the server has then
    // already seen this wallet in the round (its GET /me), so the totals do
    // not lag behind what the round itself says. The server adds up every
    // round for them, so they are waited for only [statsGrace]: a slow
    // answer must not hold up an action's "Confirming…" or pull-to-refresh.
    // It still lands on its own when it comes.
    var waiting = true;
    final stats = _readStats().then((_) {
      if (!waiting) notifyListeners();
    });
    try {
      await stats.timeout(statsGrace);
    } on TimeoutException {
      // Shown when it comes.
    }
    waiting = false;
    notifyListeners();
  }

  /// How long [refresh] waits for the totals before it returns without
  /// them.
  static const statsGrace = Duration(seconds: 2);

  Future<void> _readRounds() async {
    final wanted = _linked;
    var listed = await api.rounds();
    if (listed == null) {
      // A server from before /rounds: the one round it calls current.
      legacyServer = true;
      final current = await api.round();
      _legacyCurrent = current?.id;
      listed = [if (current != null) current.copyWith(featured: true)];
    } else {
      legacyServer = false;
      _legacyCurrent = null;
      await _registerPending();
    }
    final byId = {for (final r in listed) r.id: r};
    // Rounds this device knows that the public list does not show.
    var missing = false;
    final extras = await Future.wait([
      for (final k in _known.values.toList())
        if (!byId.containsKey(k.launcher)) _readKnown(k),
    ]);
    for (final (k, r) in extras) {
      if (r != null) {
        byId[r.id] = r;
      } else if (k.launcher == wanted) {
        missing = _known[k.launcher] == null;
      }
    }
    final all = byId.values.toList();
    await _readJoined(all);
    _serverOrder = [for (final r in listed) r.id];
    rounds = _ordered(all);
    noRound = rounds.isEmpty;

    if (wanted != null && _linked == wanted) {
      _linked = null;
      if (_listed(wanted) != null) {
        selected = wanted;
      } else {
        // Dropped from this device's rounds: the server said our factory
        // never made it (404), in this read or in one that was already
        // running when the link was opened.
        missing = missing || !_known.containsKey(wanted);
        notice = missing
            ? 'That link does not lead to a round.'
            : 'That round could not be opened yet. Try the link again in a '
                  'moment.';
      }
    }
    if (_listed(selected) == null) {
      selected = _listed(_remembered)?.id ?? rounds.firstOrNull?.id;
    }
    _views.removeWhere((id, _) => !byId.containsKey(id));
  }

  /// A round the public list does not show: asked for by its address, or,
  /// when the server cannot be asked, as this device last saw it.
  Future<(KnownRound, Round?)> _readKnown(KnownRound k) async {
    Round? kept() {
      final j = k.cached;
      if (j == null) return null;
      try {
        return Round.fromJson(j);
      } catch (_) {
        return null;
      }
    }

    if (legacyServer) return (k, kept());
    try {
      final r = await api.roundAt(k.launcher);
      if (r != null) {
        // Until the creator's choice is saved, the card shows the choice.
        final shown = k.registered
            ? r
            : r.copyWith(unlisted: k.unlisted ?? r.unlisted);
        k.cached = shown.toJson();
        if (k.registered) k.unlisted = r.unlisted;
        return (k, shown);
      }
      // Started here a moment ago: the server finds it on chain shortly.
      if (k.creator != null) return (k, kept());
      // Our factory never made it. Not a round.
      _known.remove(k.launcher);
      unawaited(_saveRounds());
      return (k, null);
    } catch (_) {
      return (k, kept());
    }
  }

  /// Which of [all] this wallet has joined, from each round's contract. A
  /// round that cannot be read keeps what was known.
  Future<void> _readJoined(List<Round> all) async {
    final who = address;
    await Future.wait([
      for (final r in all)
        () async {
          try {
            if (await chain.isMemberOf(r.launcher, who)) {
              joined.add(r.id);
            } else {
              joined.remove(r.id);
            }
          } catch (_) {}
        }(),
    ]);
  }

  /// Home's order: the featured round, the rounds this wallet has joined,
  /// then open rounds by nearest deadline, launched ones in the server's
  /// order (newest first), ended ones.
  List<Round> _ordered(List<Round> all) {
    final at = {for (final (i, id) in _serverOrder.indexed) id: i};
    int group(Round r) => r.featured
        ? 0
        : joined.contains(r.id)
        ? 1
        : 2;
    final t = now;
    return [...all]..sort((a, b) {
      var c = group(a).compareTo(group(b));
      if (c != 0) return c;
      final phase = a.phaseAt(t);
      c = phase.index.compareTo(b.phaseAt(t).index);
      if (c != 0) return c;
      if (phase == RoundPhase.open) {
        c = a.deadline.compareTo(b.deadline);
        if (c != 0) return c;
      }
      c = (at[a.id] ?? 1 << 30).compareTo(at[b.id] ?? 1 << 30);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  Future<void> _readSelected(String id) async {
    final listed = _listed(id);
    if (listed == null) return;
    final view = _views.putIfAbsent(id, _RoundView.new);
    await Future.wait([
      if (!legacyServer) _readDetail(listed, view),
      _readChain(listed, view),
      _readMe(listed, view),
      _readMembers(listed, view),
    ]);
    view.readAt = now;
  }

  /// The round in full: the list's entry leaves out the fewest steps for a
  /// check-in and whether the round is unlisted.
  Future<void> _readDetail(Round listed, _RoundView view) async {
    try {
      final r = await api.roundAt(listed.launcher);
      if (r == null) return;
      final k = _known[listed.id];
      view.round = r.copyWith(
        featured: listed.featured,
        unlisted: k != null && !k.registered ? listed.unlisted : r.unlisted,
      );
    } catch (_) {
      // The list's entry stands in.
    }
  }

  Future<void> _readChain(Round r, _RoundView view) async {
    try {
      final state = await chain.roundState(r.launcher, address, now: now);
      view.onChain = state;
      if (state.isMember) {
        joined.add(r.id);
      } else {
        joined.remove(r.id);
      }
      if (state.checkedInToday &&
          _pending != null &&
          _pendingLauncher == r.id) {
        _pending = null;
        await store.savePending(null);
      }
      if (state.launched || r.launched) {
        view.share = await chain.shareState(r.launcher, address);
      }
    } catch (_) {
      // The server's numbers stand in until the chain answers again.
    }
  }

  /// A server from before /rounds answers for its current round only.
  bool _serverKnows(Round r) => !legacyServer || r.id == _legacyCurrent;

  Future<void> _readMe(Round r, _RoundView view) async {
    if (!_serverKnows(r)) return;
    try {
      final me = await api.me(
        address,
        launcher: legacyServer ? null : r.launcher,
      );
      view.me = me;
      // The chain says who is a member; the server stands in when the
      // chain could not be read.
      if (view.onChain == null && me.member) joined.add(r.id);
    } catch (_) {}
  }

  Future<void> _readMembers(Round r, _RoundView view) async {
    if (!_serverKnows(r)) {
      // No list to ask for: an empty one, not one that is still loading.
      view.membersRead = true;
      return;
    }
    try {
      view.members = await api.members(
        launcher: legacyServer ? null : r.launcher,
      );
      view
        ..membersRead = true
        ..membersError = null;
    } catch (e) {
      // The list read before, if any, stays.
      view.membersError = friendlyError(e);
    }
  }

  /// The totals across every round. Never throws: what was read before
  /// stays, and totals the server could only read in part are not shown in
  /// place of whole ones.
  Future<void> _readStats() async {
    if (legacyServer) return;
    final who = address;
    try {
      final read = await api.stats(who);
      if (read == null || !read.complete || !hasWallet || address != who) {
        return;
      }
      // The wallet's own numbers are kept when this answer left them out.
      stats = read.you == null && stats?.you != null
          ? Stats(
              people: read.people,
              checkIns: read.checkIns,
              deposited: read.deposited,
              launched: read.launched,
              complete: read.complete,
              you: stats!.you,
            )
          : read;
    } catch (_) {}
  }

  // Listing a round -----------------------------------------------------------

  /// Tells the server whether the round at [launcher] is shown in the
  /// public list, signed by this wallet (only the round's creator can say).
  /// [unlisted] null repeats the last choice. Throws one sentence when the
  /// server did not save it; the app asks again by itself.
  Future<void> registerRound(String launcher, {bool? unlisted}) async {
    final id = launcher.toLowerCase();
    final k = _known.putIfAbsent(
      id,
      () => KnownRound(launcher: id, creator: address.toLowerCase()),
    );
    final want = unlisted ?? k.unlisted ?? false;
    k
      ..creator ??= address.toLowerCase()
      ..unlisted = want
      ..registered = false;
    try {
      final saved = await api.registerRound(key!, launcher: id, unlisted: want);
      k
        ..unlisted = saved
        ..registered = true
        ..registerError = null;
      rounds = [
        for (final r in rounds) r.id == id ? r.copyWith(unlisted: saved) : r,
      ];
      final view = _views[id];
      view?.round = view.round?.copyWith(unlisted: saved);
    } on VerifierException catch (e) {
      k.registerError = e.status == 404 && e.code == null
          ? '${AppConfig.productName}\'s server does not keep a list of '
                'rounds yet. The choice is kept on this device and saved as '
                'soon as it does.'
          : e.code == 'no_round'
          ? 'The server has not found this round on chain yet. It is asked '
                'again in a moment.'
          : e.message;
      await _saveRounds();
      notifyListeners();
      throw Exception(k.registerError);
    }
    await _saveRounds();
    notifyListeners();
  }

  /// Asks again for every round started with this wallet whose choice the
  /// server does not hold yet. Never throws.
  Future<void> _registerPending() async {
    final me = address.toLowerCase();
    for (final k in _known.values.toList()) {
      if (k.registered || k.creator != me) continue;
      try {
        await registerRound(k.launcher);
      } catch (_) {}
    }
  }

  // Actions -------------------------------------------------------------------

  /// The round an action is for. Every action that sends something takes
  /// the round's address from the button that was pressed (a sheet keeps the
  /// one it was opened for), so it acts on the round the person read on that
  /// button even if another card has come into view since. With no address
  /// it is the selected round.
  Round _acting(String? launcher) {
    final r = roundOf(launcher ?? selected);
    if (r == null) {
      throw Exception(
        'That round is not on Home any more. Close this and look again.',
      );
    }
    return r;
  }

  /// Reads everything again after something was sent for the round [id],
  /// which may not be the selected one any more.
  Future<void> _refreshAfter(String id) async {
    await refresh();
    if (selected != id && _listed(id) != null) {
      await _readSelected(id);
      notifyListeners();
    }
  }

  /// Join, step 1: the wallet mints the deposit in test USD to itself.
  /// Testnet only; on mainnet this step is paying with a stablecoin.
  Future<String> getTestDollars(BigInt amount) async {
    await ensureGas(AppConfig.smallGasWei);
    final tx = await chain.mintTestDollars(key!, amount);
    await refreshBalances();
    return tx;
  }

  /// Join, step 2: approves and pays the deposit into the round's contract.
  Future<String> payDeposit({String? launcher}) async {
    final r = _acting(launcher);
    final amount = depositOf(r.id);
    await ensureGas(AppConfig.smallGasWei);
    final tx = await chain.join(key!, r.launcher, amount);
    _joinTx[r.id] = tx;
    await _refreshAfter(r.id);
    return tx;
  }

  /// Joining in one press: gets the test dollars the wallet is short of the
  /// deposit (testnet only), approves them and pays the deposit, with
  /// [steps] following along: "Get test dollars" (only when the wallet does
  /// not hold the deposit), "Approve test USD", "Pay the deposit", led by
  /// "Prepare your wallet" when it has no fees yet.
  Future<String> joinRound({String? launcher}) {
    final r = _acting(launcher);
    final amount = depositOf(r.id);
    return _withSteps(
      StepAction.join,
      r.id,
      [
        ..._gasStep(AppConfig.smallGasWei),
        if (usd < amount) ActionSteps.getDollars,
        ActionSteps.approve,
        ActionSteps.pay,
      ],
      () async {
        await ensureGas(AppConfig.smallGasWei);
        if (usd < amount) {
          _reach(ActionSteps.getDollars);
          await chain.mintTestDollars(key!, amount - usd);
          await refreshBalances();
        }
        _reach(ActionSteps.approve);
        final tx = await chain.join(
          key!,
          r.launcher,
          amount,
          onApproved: () => _reach(ActionSteps.pay),
        );
        _joinTx[r.id] = tx;
        await _refreshAfter(r.id);
        return tx;
      },
    );
  }

  /// Adds [amount] to the token pool. Mints the test USD first when the
  /// wallet does not hold it.
  Future<String> sponsor(BigInt amount, {String? launcher}) async {
    final r = _acting(launcher);
    await ensureGas(AppConfig.smallGasWei);
    if (usd < amount) await chain.mintTestDollars(key!, amount - usd);
    final tx = await chain.sponsor(key!, r.launcher, amount);
    await _refreshAfter(r.id);
    return tx;
  }

  /// Today's check-in: sends the steps to the server (read from the health
  /// store on a phone, [selfReported] in a browser or when typed on a phone
  /// as source "self"), then records the day on chain with the attester's
  /// signature. Returns the transaction hash.
  ///
  /// A Season round before its first check-in day or after its last: the
  /// server signs nothing then, so nothing is asked of it (nor of the
  /// faucet, nor of the chain) and the one sentence says when.
  Future<String> checkIn({int? selfReported, String? launcher}) async {
    final r = _acting(launcher);
    final refusal = r.season?.checkInRefusal(now);
    if (refusal != null) throw Exception(refusal);
    await ensureGas(AppConfig.smallGasWei);
    var ticket = _pendingTicketFor(r);
    if (ticket == null) {
      final typed = selfReported != null || !health.available;
      final steps = typed ? selfReported ?? 0 : await health.stepsToday();
      if (steps < r.minSteps) {
        throw Exception(
          'A check-in needs at least ${formatCount(r.minSteps)} steps today. '
          'You have ${formatCount(steps)} so far.',
        );
      }
      // A server from before /rounds signs for its current round only.
      if (!_serverKnows(r)) {
        throw Exception(
          '${AppConfig.productName}\'s server cannot sign check-ins for this '
          'round yet. Try again later.',
        );
      }
      ticket = await api.checkIn(
        key!,
        launcher: r.launcher,
        steps: steps,
        source: typed ? 'self' : health.source,
        now: now,
        perRound: !legacyServer,
      );
      _pending = ticket;
      _pendingLauncher = r.id;
      await store.savePending({...ticket.toJson(), 'launcher': r.launcher});
      notifyListeners();
    }
    final tx = await chain.checkIn(
      key!,
      r.launcher,
      ticket.dayIndex,
      ticket.attesterSignature,
    );
    _pending = null;
    await store.savePending(null);
    await _refreshAfter(r.id);
    return tx;
  }

  /// Launches the token through Flap. Open to anyone once the bar is full.
  Future<String> launch({String? launcher}) {
    final r = _acting(launcher);
    return _withSteps(
      StepAction.launch,
      r.id,
      [
        ..._gasStep(AppConfig.launchGasWei),
        ActionSteps.launchOnFlap,
        ActionSteps.readResult,
      ],
      () async {
        await ensureGas(
          AppConfig.launchGasWei,
          shortMessage:
              'Launching needs about 0.008 test BNB for network fees and this '
              'wallet has less. Anyone else in the round can launch.',
        );
        _reach(ActionSteps.launchOnFlap);
        final tx = await chain.launch(key!, r.launcher);
        _reach(ActionSteps.readResult);
        await _refreshAfter(r.id);
        return tx;
      },
    );
  }

  /// Takes this wallet's share out of the vault.
  Future<String> claim({String? launcher}) async {
    final r = _acting(launcher);
    final vault = _views[r.id]?.share?.vault ?? r.vault;
    if (vault == null) {
      throw Exception(
        'The piggy bank is not ready yet. Try again in a moment.',
      );
    }
    return _withSteps(
      StepAction.claim,
      r.id,
      [
        ..._gasStep(AppConfig.smallGasWei),
        ActionSteps.claimVault,
        ActionSteps.updateBalance,
      ],
      () async {
        await ensureGas(AppConfig.smallGasWei);
        _reach(ActionSteps.claimVault);
        final tx = await chain.claim(key!, vault);
        _reach(ActionSteps.updateBalance);
        await _refreshAfter(r.id);
        return tx;
      },
    );
  }

  /// After a missed deadline: takes the deposit back.
  Future<String> refund({String? launcher}) {
    final r = _acting(launcher);
    return _withSteps(
      StepAction.refund,
      r.id,
      [
        ..._gasStep(AppConfig.smallGasWei),
        ActionSteps.takeBack,
        ActionSteps.updateBalance,
      ],
      () async {
        await ensureGas(AppConfig.smallGasWei);
        _reach(ActionSteps.takeBack);
        final tx = await chain.refund(key!, r.launcher);
        _refunded.add(r.id);
        _reach(ActionSteps.updateBalance);
        await _refreshAfter(r.id);
        return tx;
      },
    );
  }

  /// Rounds whose deposit this wallet took back on this device since the
  /// app opened.
  final _refunded = <String>{};

  /// This wallet took its deposit back from [launcher] on this device.
  bool refundedFrom(String launcher) =>
      _refunded.contains(launcher.toLowerCase());

  /// "Start round" on the new-round screen. The new round goes on this
  /// device's slider at once and is selected; then the server is told whether it is
  /// shown in the public list ([unlisted] means it is not; anyone with the
  /// link can still join, and the chain is public). Returns the new round's
  /// contract address. If the server did not save the choice, the round's
  /// [knownRound] says so and the app asks again by itself.
  Future<String> createRound({
    required String name,
    required BigInt deposit,
    required int liquidityBps,
    required int checkInGoal,
    required DateTime deadline,
    bool unlisted = false,
  }) => _withSteps(
    StepAction.start,
    null,
    [
      ..._gasStep(AppConfig.startRoundGasWei),
      ActionSteps.findAddress,
      ActionSteps.send,
    ],
    () async {
      await ensureGas(
        AppConfig.startRoundGasWei,
        // The faucet fills a wallet once, so waiting does not help here: the
        // sentence says where more comes from.
        shortMessage:
            'Starting a round needs about 0.007 test BNB in fees and this '
            'wallet has less. Send test BNB to your address (Wallet, then '
            'Address), then try again.',
      );
      _reach(ActionSteps.findAddress);
      final launcher = await chain.createRound(
        key!,
        name: name,
        symbol: symbolFor(name),
        deposit: deposit,
        liquidityBps: liquidityBps,
        checkInGoal: checkInGoal,
        deadline: deadline,
        onMined: () => _reach(ActionSteps.send),
      );
      // On the slider at once, from what was just sent to the chain.
      final created = Round(
        launcher: launcher,
        name: name,
        deposit: deposit,
        liquidityBps: liquidityBps,
        checkInGoal: checkInGoal,
        totalCheckIns: 0,
        memberCount: 0,
        totalDeposits: BigInt.zero,
        totalSponsored: BigInt.zero,
        poolQuoteNow: BigInt.zero,
        prizeNow: BigInt.zero,
        deadline: deadline,
        launched: false,
        minSteps: round?.minSteps ?? 1000,
        unlisted: unlisted,
      );
      final id = created.id;
      _known[id] = KnownRound(
        launcher: id,
        creator: address.toLowerCase(),
        unlisted: unlisted,
        registered: false,
        cached: created.toJson(),
      );
      rounds = _ordered([...rounds.where((r) => r.id != id), created]);
      noRound = false;
      selected = id;
      _remembered = id;
      await _saveRounds();
      notifyListeners();
      try {
        await registerRound(id, unlisted: unlisted);
      } catch (_) {
        // Kept on the device; [refresh] asks again.
      }
      await refreshBalances();
      unawaited(refresh());
      return launcher;
    },
  );
}
