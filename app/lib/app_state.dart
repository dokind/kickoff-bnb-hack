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
import 'widgets/gauges.dart' show DayState;

/// What Home's one primary action is right now.
enum HomeStage {
  /// The round is being read for the first time.
  loading,

  /// The round could not be read.
  error,

  /// The server has no round open.
  noRound,

  /// Not a member yet: "Join for 1,000 USD".
  join,

  /// A member who has not checked in today: "Check in today".
  checkIn,

  /// A member who has: "Checked in", with a hint about tomorrow.
  checkedIn,

  /// The bar is full: anyone may "Launch the token".
  launch,

  /// Launched, and this wallet showed up at least one day: "Claim your
  /// share".
  claim,

  /// Launched, and this wallet has no days: "See the result".
  result,

  /// The deadline passed without a launch and this wallet has money in the
  /// round: "Take your deposit back".
  refund,

  /// The deadline passed without a launch and nothing is owed here.
  ended,
}

/// The whole app's state: the wallet, the current round, and where this
/// wallet stands in it. Screens listen to it and call its methods; it calls
/// the services.
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

  /// The current round as the server reports it. Null until read, or when
  /// there is none ([noRound]).
  Round? round;
  bool noRound = false;

  /// One sentence when the round could not be read.
  String? roundError;
  bool loading = false;

  /// What the round's contract says for this wallet. Null when the chain
  /// could not be read; the server's numbers are used then.
  RoundChain? onChain;

  /// This wallet's share in the vault, after the launch.
  ShareChain? share;

  /// This wallet's days and streak, from the server.
  Me? me;
  List<Member> members = const [];

  /// A check-in the server signed that is not on chain yet.
  CheckInTicket? _pending;
  String? _pendingLauncher;

  String get address => key!.address.with0x;
  bool get hasWallet => key != null;

  /// The wallet key as hex, for "Back up key" only.
  String get keyHex => privateKeyHex(key!);

  // The round, chain first ----------------------------------------------------

  /// The fixed deposit of the round.
  BigInt get deposit => onChain?.deposit ?? round?.deposit ?? BigInt.zero;

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

  BigInt get poolQuoteNow =>
      onChain?.poolQuoteNow ?? round?.poolQuoteNow ?? BigInt.zero;

  /// How much the launch pool is short of what Flap needs. Zero when it has
  /// enough.
  BigInt get poolShort {
    final short = wholeUnits(AppConfig.launchPoolFloor) - poolQuoteNow;
    return short > BigInt.zero ? short : BigInt.zero;
  }

  bool get pastDeadline {
    final r = round;
    return r != null && now.isAfter(r.deadline);
  }

  bool get isMember => onChain?.isMember ?? me?.member ?? false;

  /// Days this wallet has checked in.
  int get daysOf => onChain?.daysOf ?? me?.daysOf ?? 0;

  bool get checkedInToday =>
      onChain?.checkedInToday ?? me?.checkedInToday ?? false;

  /// Consecutive days ending today or yesterday.
  int get streak => me?.streak ?? 0;

  BigInt get refundable => onChain?.refundable ?? BigInt.zero;

  /// The server signed today's check-in but it is not on chain yet.
  bool get hasPendingCheckIn => _pendingTicket != null;

  CheckInTicket? get _pendingTicket {
    final p = _pending;
    final r = round;
    if (p == null || r == null) return null;
    if (_pendingLauncher != r.launcher.toLowerCase()) return null;
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
    onChain = null;
    share = null;
    me = null;
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

  // Reading the round ---------------------------------------------------------

  Future<void>? _refreshRun;

  /// Reads the round, this wallet's place in it, the members and the
  /// balances. Calls made while one is running share it.
  Future<void> refresh() =>
      _refreshRun ??= _refresh().whenComplete(() => _refreshRun = null);

  Future<void> _refresh() async {
    if (!hasWallet) return;
    loading = true;
    roundError = null;
    notifyListeners();
    try {
      final r = await api.round();
      if (r?.launcher.toLowerCase() != round?.launcher.toLowerCase()) {
        onChain = null;
        share = null;
        me = null;
        members = const [];
      }
      round = r;
      noRound = r == null;
    } catch (e) {
      roundError = friendlyError(e);
    }
    if (round != null) {
      await Future.wait([
        _readChain(),
        _readMe(),
        _readMembers(),
        refreshBalances(),
      ]);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _readChain() async {
    final r = round!;
    try {
      final state = await chain.roundState(r.launcher, address, now: now);
      onChain = state;
      if (state.checkedInToday && _pending != null) {
        _pending = null;
        await store.savePending(null);
      }
      if (state.launched || r.launched) {
        share = await chain.shareState(r.launcher, address);
      }
    } catch (_) {
      // The server's numbers stand in until the chain answers again.
    }
  }

  Future<void> _readMe() async {
    try {
      me = await api.me(address);
    } catch (_) {}
  }

  Future<void> _readMembers() async {
    try {
      members = await api.members();
    } catch (_) {}
  }

  // Actions -------------------------------------------------------------------

  /// Join, step 1: the wallet mints the deposit in test USD to itself.
  /// Testnet only; on mainnet this step is paying with a stablecoin.
  Future<String> getTestDollars(BigInt amount) async {
    await ensureGas(AppConfig.smallGasWei);
    final tx = await chain.mintTestDollars(key!, amount);
    await refreshBalances();
    return tx;
  }

  /// Join, step 2: approves and pays the deposit into the round's contract.
  Future<String> payDeposit() async {
    final r = round!;
    await ensureGas(AppConfig.smallGasWei);
    final tx = await chain.join(key!, r.launcher, deposit);
    await refresh();
    return tx;
  }

  /// Adds [amount] to the launch pool. Mints the test USD first when the
  /// wallet does not hold it.
  Future<String> sponsor(BigInt amount) async {
    final r = round!;
    await ensureGas(AppConfig.smallGasWei);
    if (usd < amount) await chain.mintTestDollars(key!, amount - usd);
    final tx = await chain.sponsor(key!, r.launcher, amount);
    await refresh();
    return tx;
  }

  /// Today's check-in: sends the steps to the server (read from the health
  /// store on a phone, [selfReported] in a browser), then records the day on
  /// chain with the attester's signature. Returns the transaction hash.
  Future<String> checkIn({int? selfReported}) async {
    final r = round!;
    await ensureGas(AppConfig.smallGasWei);
    var ticket = _pendingTicket;
    if (ticket == null) {
      final steps = health.available
          ? await health.stepsToday()
          : selfReported ?? 0;
      if (steps < r.minSteps) {
        throw Exception(
          'A check-in needs at least ${formatCount(r.minSteps)} steps today. '
          'You have ${formatCount(steps)} so far.',
        );
      }
      ticket = await api.checkIn(
        key!,
        launcher: r.launcher,
        steps: steps,
        source: health.available ? health.source : 'self',
        now: now,
      );
      _pending = ticket;
      _pendingLauncher = r.launcher.toLowerCase();
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
    await refresh();
    return tx;
  }

  /// Launches the token through Flap. Open to anyone once the bar is full.
  Future<String> launch() async {
    final r = round!;
    await ensureGas(
      AppConfig.launchGasWei,
      shortMessage:
          'Launching needs about 0.008 test BNB for network fees and this '
          'wallet has less. Anyone else in the round can launch.',
    );
    final tx = await chain.launch(key!, r.launcher);
    await refresh();
    return tx;
  }

  /// Takes this wallet's share out of the vault.
  Future<String> claim() async {
    final vault = share?.vault ?? round?.vault;
    if (vault == null) {
      throw Exception('The vault is not ready yet. Try again in a moment.');
    }
    await ensureGas(AppConfig.smallGasWei);
    final tx = await chain.claim(key!, vault);
    await refresh();
    return tx;
  }

  /// After a missed deadline: takes the deposit back.
  Future<String> refund() async {
    final r = round!;
    await ensureGas(AppConfig.smallGasWei);
    final tx = await chain.refund(key!, r.launcher);
    await refresh();
    return tx;
  }

  /// "Start a new round" in Account. Returns the new round's contract
  /// address, to hand to whoever runs the server.
  Future<String> createRound({
    required String name,
    required BigInt deposit,
    required int liquidityBps,
    required int checkInGoal,
    required DateTime deadline,
  }) async {
    await ensureGas(
      AppConfig.startRoundGasWei,
      shortMessage:
          'Starting a round needs about 0.007 test BNB and this wallet has '
          'less.',
    );
    final launcher = await chain.createRound(
      key!,
      name: name,
      symbol: symbolFor(name),
      deposit: deposit,
      liquidityBps: liquidityBps,
      checkInGoal: checkInGoal,
      deadline: deadline,
    );
    await refreshBalances();
    return launcher;
  }
}
