/// Small pure helpers: amounts, dates, days, addresses and safe error text.
library;

/// 0x1234…abcd: first 6 and last 4 characters.
String shortAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}

/// 1234567 -> "1,234,567".
String groupDigits(String digits) {
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A whole number with thousands separators: "6,214".
String formatCount(num n) => groupDigits(n.round().toString());

/// Token base units to a decimal string, trailing zeros trimmed:
/// 5000000000000000000 -> "5", 10000000000000000 -> "0.01".
String formatUnits(BigInt value, {int decimals = 18, int maxFraction = 4}) {
  final base = BigInt.from(10).pow(decimals);
  final whole = value ~/ base;
  var fraction = (value % base).toString().padLeft(decimals, '0');
  if (fraction.length > maxFraction) {
    fraction = fraction.substring(0, maxFraction);
  }
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

/// An amount for people: thousands separators and at most [maxFraction]
/// decimals, rounded down. 1000e18 -> "1,000", 356.2049e18 -> "356.2".
String formatAmount(BigInt value, {int decimals = 18, int maxFraction = 2}) {
  final text = formatUnits(value, decimals: decimals, maxFraction: maxFraction);
  final parts = text.split('.');
  final whole = groupDigits(parts[0]);
  return parts.length == 1 ? whole : '$whole.${parts[1]}';
}

/// Every amount carries its unit: "1,000 USD", "0.03 tBNB".
String formatMoney(
  BigInt value,
  String symbol, {
  int decimals = 18,
  int maxFraction = 2,
}) =>
    '${formatAmount(value, decimals: decimals, maxFraction: maxFraction)} '
    '$symbol';

/// "5.5" -> 5500000000000000000. Returns null when the text is not a
/// positive decimal number.
BigInt? parseUnits(String text, {int decimals = 18}) {
  final t = text.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(t)) return null;
  final parts = t.split('.');
  var fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  fraction = fraction.padRight(decimals, '0');
  final value = BigInt.parse(parts[0] + fraction);
  return value > BigInt.zero ? value : null;
}

/// [whole] units as base units: 1000 -> 1000e18.
BigInt wholeUnits(int whole, {int decimals = 18}) =>
    BigInt.from(whole) * BigInt.from(10).pow(decimals);

/// A share written as a percentage: 3000 basis points -> "30%",
/// 3333 -> "33.33%".
String formatBps(int bps) {
  final whole = bps ~/ 100;
  final rest = bps % 100;
  if (rest == 0) return '$whole%';
  return '$whole.${rest.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}%';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A full date: "26 Nov 2026".
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Time of day, 24 hours: "23:59".
String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// How long until something: "5 h 12 min", "12 min", "under a minute".
String formatWait(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "1 day", "7 days".
String days(int n) => n == 1 ? '1 day' : '$n days';

// Days are counted in UTC on the chain and on the server ----------------------

/// The contract's day number: unix seconds / 86400.
int dayIndexOf(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 86400000;

/// The day key the server expects: "YYYY-MM-DD" in UTC.
String utcDayKey(DateTime t) {
  final d = t.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// When the current UTC day ends, as a moment in time.
DateTime nextUtcDay(DateTime t) {
  final d = t.toUtc();
  return DateTime.utc(d.year, d.month, d.day + 1);
}

final _addressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');

bool isAddress(String s) => _addressPattern.hasMatch(s);

bool _isVerifierMessage(Object e) =>
    e.runtimeType.toString() == 'VerifierException';

/// One plain sentence for anything that went wrong, safe to show a person:
/// never a raw exception, a URL or the word "localhost". Sentences written
/// by this app or by the server pass through.
String friendlyError(Object e) {
  const generic = 'Something went wrong. Check your connection and try again.';
  var text = e.toString();
  if (RegExp('insufficient funds', caseSensitive: false).hasMatch(text)) {
    return 'This wallet has no test BNB for network fees yet. Try again in '
        'a minute.';
  }
  // Only three things are sentences meant for a person: what the server
  // said (VerifierException), an `Exception('...')` thrown by this app, and
  // plain text. Any other error type is a raw failure from a library.
  final ours = text.startsWith('Exception: ');
  if (ours) text = text.substring('Exception: '.length);
  if (!ours && e is! String && !_isVerifierMessage(e)) return generic;
  final raw = RegExp(
    r'localhost|127\.0\.0\.1|https?://|Exception|XMLHttpRequest|errno|'
    r'Failed to fetch|RPCError|TypeError|Null check|is not a subtype|'
    r'SocketException|ClientException',
    caseSensitive: false,
  );
  if (text.trim().isEmpty || raw.hasMatch(text)) return generic;
  return text;
}
