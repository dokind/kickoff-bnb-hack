// The app's own state and services against the real server code and the real
// contracts, on a local fork of BSC testnet. Skipped unless both addresses
// are given, so `flutter test` alone never touches a network:
//
//   anvil --fork-url https://bsc-testnet-rpc.publicnode.com --chain-id 97 --port 8546
//   (cd ../verifier && RPC_URL=http://127.0.0.1:8546 PORT=8799 ALLOW_SELF_REPORTED=true \
//       FAUCET_ENABLED=true DATA_FILE=/tmp/cypher-run-fork.json npm start)
//   (cd ../verifier && RPC_URL=http://127.0.0.1:8546 VERIFIER_URL=http://127.0.0.1:8799/api \
//       STATE_FILE=/tmp/cypher-run-fork-run.json CHECKIN_GOAL=3 npx tsx ../scripts/run-round.ts)
//   FORK_RPC_URL=http://127.0.0.1:8546 FORK_VERIFIER_URL=http://127.0.0.1:8799/api \
//       flutter test test/fork_e2e_test.dart
//
// The script leaves a round with the bar one check-in short. This test is the
// last member: a new wallet gets gas from the faucet, mints the deposit,
// joins, checks in (self-reported, as the browser does), launches and claims.
// Every number is read back through the same code the screens use.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pacepact/app_state.dart';
import 'package:pacepact/services/chain_service.dart';
import 'package:pacepact/services/verifier_api.dart';
import 'package:web3dart/web3dart.dart';

import 'support.dart';

/// A fresh random wallet, kept in memory.
class _FreshStore extends MemoryStore {
  @override
  Future<EthPrivateKey> create() async =>
      key = EthPrivateKey.createRandom(Random.secure());
}

void main() {
  final rpc = Platform.environment['FORK_RPC_URL'] ?? '';
  final server = Platform.environment['FORK_VERIFIER_URL'] ?? '';
  final skip = rpc.isEmpty || server.isEmpty
      ? 'set FORK_RPC_URL and FORK_VERIFIER_URL (see the top of this file)'
      : false;

  test(
    'a new wallet joins, checks in, launches and claims on the fork',
    () async {
      final state = AppState(
        store: _FreshStore(),
        chain: ChainService(client: Web3Client(rpc, http.Client())),
        api: VerifierApi(baseUrl: server),
        health: FakeHealth(), // no health store: the browser's path
        gasPoll: const Duration(seconds: 1),
      );
      await state.init();
      await state.completeOnboarding();
      await state.refresh();

      final round = state.round;
      expect(round, isNotNull, reason: 'the server has no round open');
      expect(state.onChain, isNotNull, reason: 'the chain could not be read');
      // The server's numbers and the chain's agree.
      expect(round!.deposit, state.onChain!.deposit);
      expect(round.totalCheckIns, state.onChain!.totalCheckIns);
      expect(round.poolQuoteNow, state.onChain!.poolQuoteNow);
      expect(
        round.totalCheckIns,
        round.checkInGoal - 1,
        reason: 'the round must be one check-in short of its goal',
      );
      expect(state.stage, HomeStage.join);

      // Join: gas from the faucet, test dollars, then the deposit.
      await state.getTestDollars(state.deposit);
      expect(state.usd, state.deposit);
      expect(state.bnb > BigInt.zero, isTrue, reason: 'the faucet sent gas');
      await state.payDeposit();
      expect(state.isMember, isTrue);
      expect(state.me?.member, isTrue, reason: 'the server sees the member');
      expect(state.stage, HomeStage.checkIn);

      // Check in: the server signs, the wallet sends the transaction.
      await state.checkIn(selfReported: round.minSteps + 234);
      expect(state.onChain!.checkedInToday, isTrue);
      expect(state.daysOf, 1);
      expect(state.me?.daysOf, 1);
      expect(state.me?.streak, 1);
      expect(state.hasPendingCheckIn, isFalse);
      expect(state.goalReached, isTrue);
      expect(state.stage, HomeStage.launch);
      expect(state.poolShort, BigInt.zero);
      expect(
        state.members.any(
          (m) => m.address == state.address.toLowerCase() && m.daysOf == 1,
        ),
        isTrue,
        reason: 'GET /members lists this wallet with its day',
      );

      // Launch: this wallet has no special role.
      await state.launch();
      expect(state.launched, isTrue);
      expect(state.round!.launched, isTrue);
      expect(state.token, isNotNull);
      expect(state.token!.toLowerCase().endsWith('7777'), isTrue);
      expect(state.stage, HomeStage.claim);

      // Claim: one day out of the goal's check-ins.
      final goal = BigInt.from(round.checkInGoal);
      final share = state.share!;
      expect(share.claimableTokens, usd(500000) ~/ goal);
      expect(share.claimableQuote > BigInt.zero, isTrue);
      // The server reports the same share the vault does.
      expect(state.me?.claimableTokens, share.claimableTokens);
      expect(state.me?.claimableQuote, share.claimableQuote);
      final quote = share.claimableQuote;
      await state.claim();
      expect(state.claimedTokens, usd(500000) ~/ goal);
      expect(state.claimedQuote, quote);
      expect(state.hasClaimable, isFalse);
      // The deposit was spent on joining; the wallet now holds its share.
      expect(state.usd, quote);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
