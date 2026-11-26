/// What the app says about a Season, in one place: the screens and the tests
/// read the same sentences. Days are UTC days, as the contract counts them;
/// 00:00 UTC is 07:00 in Bangkok, where Season 1 is run from.
library;

import '../services/verifier_api.dart';
import 'format.dart' as f;

/// Over the join button once the app stops offering Join in a Season
/// squad. The contract has no cap and no join window of its own.
const joinStopNote =
    'The contract still takes joins; the app stops here so everyone starts '
    'fair.';

extension SeasonText on Season {
  /// Bangkok is UTC+7 all year (no summer time).
  static const _bangkok = Duration(hours: 7);

  /// Why a check-in cannot be sent today, or null when it can: before the
  /// first check-in day and after the last the server signs none, so the app
  /// asks it nothing. The sentences are the server's own refusal, word for
  /// word (`seasonRefusal` in verifier/src/season.ts), so an older app build
  /// that does ask shows the same words.
  String? checkInRefusal(DateTime now) => notStarted(now)
      ? opensLine
      : checkInsOver(now)
      ? endedLine
      : null;

  /// "Season 1 check-ins open Tue 1 Dec (07:00 in Bangkok). Everyone starts
  /// at 0." The server's `season_not_started` message.
  String get opensLine =>
      '$name check-ins open ${f.formatWeekdayDayMonth(startsAt)} '
      '(${f.formatTime(startsAt.add(_bangkok))} in Bangkok). '
      'Everyone starts at 0.';

  /// "Season 1 check-ins have ended. The last day was Wed 30 Dec." The
  /// server's `season_over` message.
  String get endedLine =>
      '$name check-ins have ended. The last day was '
      '${f.formatWeekdayDayMonth(lastDay)}.';

  /// Over Check in before the start: "Check-ins open 1 Dec · in 6 days".
  String opensHint(DateTime now) =>
      'Check-ins open ${f.formatDayMonth(startsAt)} · '
      'in ${f.days(daysToStart(now))}';

  /// The same place after the last day, short enough for one line (the
  /// streak's badge, the line over Check in, the join sheet's Season line):
  /// "Check-ins ended 30 Dec". A press on Check in then shows [endedLine].
  String get endedHint => 'Check-ins ended ${f.formatDayMonth(lastDay)}';

  /// The join sheet before the start: "Starts Tue 1 Dec. Everyone starts at
  /// 0."
  String get startsLine =>
      'Starts ${f.formatWeekdayDayMonth(startsAt)}. Everyone starts at 0.';

  /// The join sheet once it has started: "Day 7 of 30: 24 days left".
  String lateLine(DateTime now) =>
      'Day ${dayNumber(now)} of $dayCount: ${f.days(daysLeft(now))} left';

  /// Under the bar before the start: "Season 1 starts Tue 1 Dec · everyone
  /// at 0".
  String get barBefore =>
      '$name starts ${f.formatWeekdayDayMonth(startsAt)} · everyone at 0';

  /// Under the bar during: "Day 7 of 30 · average 4.2 days · you 5". The
  /// average is all check-ins over all members (0-day members count), the
  /// number the Keep-Up Guarantee compares your days with. [yourDays] is
  /// left out for someone who is not a member.
  String barDuring(
    DateTime now, {
    required int totalCheckIns,
    required int memberCount,
    int? yourDays,
  }) {
    final average = memberCount <= 0 ? 0.0 : totalCheckIns / memberCount;
    final shown = average.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return 'Day ${dayNumber(now)} of $dayCount · average $shown '
        '${shown == '1' ? 'day' : 'days'}'
        '${yourDays == null ? '' : ' · you $yourDays'}';
  }

  /// When the bar can no longer fill ([Season.cannotFill]): "This squad
  /// can't fill now. 100% back after 31 Dec." [deadline] is the round's.
  String cannotFillLine(DateTime deadline) =>
      'This squad can\'t fill now. 100% back after '
      '${f.formatDayMonth(deadline.toUtc())}.';

  /// The disabled button once the app stops offering Join: "Joining closed
  /// 7 Dec" after the last day to join, else "Squad full".
  String joinClosedLabel(DateTime now) => joinWindowOver(now)
      ? 'Joining closed ${f.formatDayMonth(joinUntil)}'
      : 'Squad full';
}

/// The banner after a paid deposit into [round]. Before a Season starts
/// there is nothing to check in yet.
String joinedNote(Round round, DateTime now) {
  final season = round.season;
  if (season != null && season.notStarted(now)) {
    return 'You\'re in. ${season.startsLine}';
  }
  return 'You\'re in. Check in today to start your share.';
}
