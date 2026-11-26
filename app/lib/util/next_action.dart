/// The one next step on Your round, and the money a member has in it, as
/// pure functions so every rule and number can be tested against the
/// contracts (CheckInLauncher, StreakVault) without a screen.
library;

import 'pot.dart';

/// What the button pinned to the bottom of Your round does.
enum RoundNext {
  /// Not a member and the round is open: join.
  join,

  /// A member who has not checked in today.
  checkIn,

  /// The bar is full and the token pool meets Flap's floor: anyone can
  /// launch.
  launch,

  /// Launched, with days shown up and something in the vault to take.
  claim,

  /// Launched: nothing to claim right now (no days, or claimed already).
  result,

  /// The deadline passed without a launch and this wallet has a deposit in
  /// the round: take it back.
  refund,

  /// Checked in today; the next check-in opens at the next UTC midnight.
  doneToday,

  /// The deadline passed without a launch and nothing is owed here.
  ended,
}

/// The rule, top to bottom: launched rounds are about the vault, closed
/// ones about the refund, open ones about the bar and today.
///
/// [refundable] is what `CheckInLauncher.refundable` says for this wallet.
/// [chainRead] is false when the contract could not be read: a member is
/// then offered Refund after the deadline, as the contract would pay them.
RoundNext nextStep({
  required bool member,
  required bool launched,
  required bool pastDeadline,
  required int days,
  required bool checkedInToday,
  required bool barFull,
  required bool poolShort,
  required bool hasClaimable,
  required BigInt refundable,
  bool chainRead = true,
}) {
  if (launched) {
    return days > 0 && hasClaimable ? RoundNext.claim : RoundNext.result;
  }
  if (pastDeadline) {
    return refundable > BigInt.zero || (!chainRead && member)
        ? RoundNext.refund
        : RoundNext.ended;
  }
  // Anyone can launch a full bar, member or not, as on Home.
  if (barFull && !poolShort) return RoundNext.launch;
  if (!member) return RoundNext.join;
  return checkedInToday ? RoundNext.doneToday : RoundNext.checkIn;
}

/// Which of the three endings on Your round applies now.
enum RoundEnding {
  /// It launches (or launched) and you have days: a share comes to you.
  withDays,

  /// It launches (or launched) and you have 0 days: nothing comes back.
  noDays,

  /// Not launched by the deadline: every deposit comes back.
  refund,
}

/// The ending that applies to a member with [days] right now. While the
/// round is open it is the one heading their way if it launched now.
RoundEnding endingNow({
  required bool launched,
  required bool pastDeadline,
  required int days,
}) {
  if (!launched && pastDeadline) return RoundEnding.refund;
  return days > 0 ? RoundEnding.withDays : RoundEnding.noDays;
}

/// One member's money in a round, the receipt on Your round.
///
/// The split of one deposit is `CheckInLauncher`'s: `liquidityBps` of it
/// goes to the token pool at launch (`deposit * liquidityBps / 10000`,
/// rounded down), the rest stays as the prize. The projection is
/// `StreakVault`'s rule over today's numbers: [days] of [total] check-ins
/// of the [prize], rounded down ([shareOf]).
class YourMoney {
  YourMoney({
    required this.deposit,
    required int liquidityBps,
    required BigInt prize,
    required this.days,
    required this.total,
  }) : toPool = deposit * BigInt.from(liquidityBps) ~/ BigInt.from(10000),
       projected = shareOf(prize, days, total);

  /// The deposit this wallet paid.
  final BigInt deposit;

  /// The part of it that seeds the token pool at launch.
  final BigInt toPool;

  /// The part of it that stays in the prize.
  BigInt get toPrize => deposit - toPool;

  /// Days this wallet showed up, and all check-ins of the round.
  final int days;
  final int total;

  /// What this wallet would get from the prize if the round launched now.
  final BigInt projected;

  /// "40%": this wallet's share of the prize and of the members' half of
  /// the token.
  String get share => formatShare(days, total);
}
