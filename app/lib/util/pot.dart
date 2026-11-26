/// The pot's arithmetic: who gets how much of a round's prize, by days shown
/// up. Pure, so every number Home shows can be tested against the contract.
///
/// The rule is StreakVault's: a member with `d` of the `totalCheckIns`
/// counted at launch can claim `amount * d / totalCheckIns` of the quote the
/// vault received and the same fraction of the reserved tokens, both rounded
/// down. A member with no check-in gets nothing. Before the launch the same
/// rule over today's numbers is a projection ("if it launched now"), not a
/// promise: every later check-in changes the shares.
library;

import 'format.dart';

/// What `days` of `total` check-ins are paid out of [amount], rounded down
/// the way `StreakVault.claimable` does it. Zero with no days.
BigInt shareOf(BigInt amount, int days, int total) {
  if (days <= 0 || total <= 0) return BigInt.zero;
  final d = days > total ? total : days;
  return amount * BigInt.from(d) ~/ BigInt.from(total);
}

/// `days` of `total` as a percentage, rounded down to one decimal so the
/// shares on screen never add up to more than 100%: "50%", "33.3%", "0%".
/// A share that is not zero but below 0.1% reads "under 0.1%".
String formatShare(int days, int total) {
  if (days <= 0 || total <= 0) return '0%';
  if (days >= total) return '100%';
  final tenths = days * 1000 ~/ total;
  if (tenths == 0) return 'under 0.1%';
  return tenths % 10 == 0
      ? '${tenths ~/ 10}%'
      : '${tenths ~/ 10}.${tenths % 10}%';
}

/// The share after one more check-in by the same member, when nobody else
/// checks in meanwhile: (days + 1) of (total + 1).
String formatShareAfterCheckIn(int days, int total) =>
    formatShare(days + 1, total + 1);

/// What checking in today does to a share of [days] in [total], said only
/// as far as it is true: when the share as written would not move (a
/// member who holds every check-in stays at 100%), it does not promise a
/// new number.
String shareNudge(int days, int total) {
  final after = formatShareAfterCheckIn(days, total);
  if (after != formatShare(days, total)) {
    return 'Check in today and your share goes to $after.';
  }
  return total > 0 && days >= total
      ? 'You hold every check-in so far. Check in today to stay ahead when '
            'others show up.'
      : 'Check in today to grow your share.';
}

/// What a check-in did to a share, said once it is on chain: "Your share
/// went from 25% to 40%." Before is [beforeDays] of [beforeTotal], after is
/// [afterDays] of [afterTotal] (others may have checked in meanwhile, so the
/// share can also stay or fall, and the sentence says so).
String shareChangeSentence(
  int beforeDays,
  int beforeTotal,
  int afterDays,
  int afterTotal,
) {
  final before = formatShare(beforeDays, beforeTotal);
  final after = formatShare(afterDays, afterTotal);
  return before == after
      ? 'Your share stays at $after.'
      : 'Your share went from $before to $after.';
}

/// The quiet line under a member's share while the bar is not full: the
/// round cannot launch yet, and every check-in until it does moves the
/// shares. Null once [total] reaches [goal].
String? barNeedsSentence(int goal, int total) {
  final n = goal - total;
  if (n <= 0) return null;
  return n == 1
      ? 'The bar needs 1 more check-in before it can launch, and that one '
            'changes these shares.'
      : 'The bar needs ${formatCount(n)} more check-ins before it can '
            'launch, and each one changes these shares.';
}

/// How many more members, each paying [deposit], would bring the token pool
/// up by [short]: every join adds `deposit * liquidityBps / 10000` to it
/// (`CheckInLauncher.poolQuoteNow`), so this is [short] over that, rounded
/// up. Null when a join adds nothing to the pool (a round started with no
/// part of the deposit for it): then only a sponsor can. Zero when nothing
/// is short.
int? membersToFillPool({
  required BigInt short,
  required BigInt deposit,
  required int liquidityBps,
}) {
  if (short <= BigInt.zero) return 0;
  final each = deposit * BigInt.from(liquidityBps) ~/ BigInt.from(10000);
  if (each <= BigInt.zero) return null;
  return ((short + each - BigInt.one) ~/ each).toInt();
}

/// One member's place in the pot.
class PotRow {
  const PotRow({
    required this.address,
    required this.days,
    required this.isYou,
    required this.fraction,
    required this.amount,
  });

  /// Lower case.
  final String address;

  /// Days shown up.
  final int days;
  final bool isYou;

  /// This member's share of all check-ins, 0 to 1: the length of the bar.
  final double fraction;

  /// This member's part of the prize, in base units, rounded down.
  final BigInt amount;
}

/// A round's prize split by days shown up, as of the numbers it was built
/// from.
class Pot {
  const Pot._({
    required this.prize,
    required this.total,
    required this.rows,
    required this.you,
    required this.memberCount,
  });

  /// What is shared, in base units of the quote token: the prize before the
  /// launch, everything the vault has received (prize plus trading tax so
  /// far) after it.
  final BigInt prize;

  /// All check-ins of the round: what every share is out of.
  final int total;

  /// The members the app knows, most days first. Yourself first among
  /// equals.
  final List<PotRow> rows;

  /// This wallet's row, when it is a member.
  final PotRow? you;

  /// Members of the round, counted by the contract. Never less than
  /// [rows].
  final int memberCount;

  /// Builds the split.
  ///
  /// [members] is the server's list as (address, days); it can leave out a
  /// wallet that joined and never opened the app. [you] is this wallet in
  /// lower case; when [isMember] it gets a row even if the list has not
  /// caught up, and [yourDays], the chain's count, replaces the list's.
  ///
  /// Every share is out of [totalCheckIns], or out of the days in the list
  /// when those add up to more (one of the two numbers is a moment older
  /// than the other): the amounts can then never add up to more than
  /// [prize].
  factory Pot.build({
    required BigInt prize,
    required int totalCheckIns,
    required int memberCount,
    required Iterable<(String address, int days)> members,
    String? you,
    bool isMember = false,
    int yourDays = 0,
  }) {
    final me = you?.toLowerCase();
    final days = <String, int>{};
    for (final (address, d) in members) {
      days[address.toLowerCase()] = d < 0 ? 0 : d;
    }
    if (me != null && isMember) days[me] = yourDays < 0 ? 0 : yourDays;

    var listed = 0;
    for (final d in days.values) {
      listed += d;
    }
    final total = listed > totalCheckIns ? listed : totalCheckIns;

    final order = days.keys.toList();
    final at = {for (final (i, a) in order.indexed) a: i};
    order.sort((a, b) {
      final c = days[b]!.compareTo(days[a]!);
      if (c != 0) return c;
      if (a == me) return -1;
      if (b == me) return 1;
      return at[a]!.compareTo(at[b]!);
    });
    final rows = [
      for (final a in order)
        PotRow(
          address: a,
          days: days[a]!,
          isYou: a == me,
          fraction: total == 0 ? 0 : days[a]! / total,
          amount: shareOf(prize, days[a]!, total),
        ),
    ];
    PotRow? mine;
    for (final r in rows) {
      if (r.isYou) mine = r;
    }
    return Pot._(
      prize: prize,
      total: total,
      rows: rows,
      you: mine,
      memberCount: memberCount > rows.length ? memberCount : rows.length,
    );
  }

  /// Members the contract counts that the list does not show.
  int get unlisted => memberCount - rows.length;

  /// The days in the list account for every check-in, so each member the
  /// list leaves out has none.
  bool get unlistedHaveNoDays {
    var listed = 0;
    for (final r in rows) {
      listed += r.days;
    }
    return listed >= total;
  }

  /// A member with no check-in is in sight or left out of the list.
  bool get someoneHasNoDays =>
      rows.any((r) => r.days == 0) || (unlisted > 0 && unlistedHaveNoDays);

  /// What one day shown up is worth right now: the prize over all
  /// check-ins, rounded down. Zero with no check-ins.
  BigInt get perDay => shareOf(prize, 1, total);

  /// The rows on screen. Collapsed: the first [top], then yourself when you
  /// are further down. With [everyone]: all of them, up to [most] (yourself
  /// included even past that).
  List<PotRow> shown({required bool everyone, int top = 5, int most = 50}) {
    final head = rows.take(everyone ? most : top).toList();
    final mine = you;
    if (mine != null && !head.contains(mine)) head.add(mine);
    return head;
  }

  /// Yourself is on screen below a gap: not one of the first rows.
  bool youBelow(List<PotRow> shown) {
    final mine = you;
    if (mine == null || shown.isEmpty || shown.last != mine) return false;
    return rows.indexOf(mine) >= shown.length;
  }
}
