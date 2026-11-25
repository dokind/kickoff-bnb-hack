import 'package:flutter/foundation.dart' show kIsWeb;

/// Every name, address, chain id, gas limit and URL the app uses lives here.
class AppConfig {
  /// The product's name. The one place the app spells it: screens,
  /// the page title and the texts the device signs for the server all read
  /// this constant. The server builds the same signed texts, so change the
  /// name there in the same step (see ../verifier).
  static const String productName = 'Cypher Run';

  /// The line on the first screen, chosen by the owner with the name. The
  /// one place the app spells it (test/design_test.dart pins that).
  static const String heroLine = 'RUN THE\nSTAKES.';

  /// BSC testnet.
  static const int chainId = 97;

  /// Public BSC testnet RPC endpoints. The first one is used; the others are
  /// here so it is a one-line change when an endpoint is down.
  static const List<String> rpcUrls = [
    'https://bsc-testnet-rpc.publicnode.com',
    'https://data-seed-prebsc-1-s1.bnbchain.org:8545',
  ];

  /// The server (see ../verifier), set at build time with
  /// `--dart-define=VERIFIER_URL=https://...`. Phone builds need it. The web
  /// build does not: it calls the API on the address it is served from, under
  /// `/api`.
  static const String verifierUrlDefine = String.fromEnvironment(
    'VERIFIER_URL',
  );

  /// Base URL of every server call, without a trailing slash. Empty when a
  /// phone build was made without VERIFIER_URL.
  static String get verifierBaseUrl => apiBaseFor(
    define: verifierUrlDefine,
    web: kIsWeb,
    pageOrigin: kIsWeb ? Uri.base.origin : '',
  );

  /// [verifierBaseUrl] for any set of values, so tests can check it.
  ///
  /// On the web the default is the page's own origin plus `/api`. A
  /// VERIFIER_URL that points at this machine (localhost) is only used when
  /// the page itself is served from this machine: a hosted site must never
  /// send people's browsers to their own localhost.
  static String apiBaseFor({
    required String define,
    required bool web,
    required String pageOrigin,
  }) {
    final url = define.trim().replaceFirst(RegExp(r'/+$'), '');
    if (!web) return url;
    final sameOrigin = '${pageOrigin.replaceFirst(RegExp(r'/+$'), '')}/api';
    if (url.isEmpty) return sameOrigin;
    if (_isLocal(url) && !_isLocal(pageOrigin)) return sameOrigin;
    return url;
  }

  static bool _isLocal(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  /// Where the web build of this app is served, without a trailing slash:
  /// the link "Copy invite link" hands out. Set it at build time with
  /// `--dart-define=WEB_BASE_URL=https://...`. When it is not set, the web
  /// build uses the address it is served from and a phone build has no link
  /// to hand out.
  static const String webBaseUrlDefine = String.fromEnvironment('WEB_BASE_URL');

  static String get webBaseUrl {
    var url = webBaseUrlDefine;
    if (url.isEmpty && kIsWeb) url = Uri.base.origin + Uri.base.path;
    return url.replaceFirst(RegExp(r'/+$'), '');
  }

  /// Flap's free-mint test "USD" on BSC testnet (18 decimals). Anyone can
  /// call `mint(address,uint256)`. It stands in for a stablecoin.
  static const String quoteToken = '0x190C989D5665a0e404B444b53CAE9AbCfb600157';
  static const String quoteSymbol = 'USD';
  static const int quoteDecimals = 18;

  /// The Flap Portal will not open a pool with less quote token than this
  /// (its testnet floor today, in whole test USD). Flap can change it; the
  /// contract's `launch()` simply reverts below the real floor.
  static const int launchPoolFloor = 1500;

  /// Flap Portal on BSC testnet.
  static const String portal = '0x000042108465206185A077Edc3F3fd2b49060000';

  /// keccak256 of the creation code of the token clone the Portal deploys.
  /// Used to mine the launch salt (../contracts/test/Salt.t.sol).
  static const String tokenInitCodeHash =
      '0xc7e15deb24b23c120ed65985516639441790ec6e89090f4aa0a87169aa9c2730';

  /// Address of the server's signing key (the attester). A round started
  /// from this app names it as the address whose signature a check-in must
  /// carry. Set with `--dart-define=ATTESTER_ADDRESS=0x...`.
  static const String attesterAddress = String.fromEnvironment(
    'ATTESTER_ADDRESS',
    defaultValue: zeroAddress,
  );

  /// Deployed CheckInLauncherFactory (our Flap Launcher Factory).
  /// Set with `--dart-define=CHECKIN_LAUNCHER_FACTORY=0x...`.
  static const String checkInLauncherFactory = String.fromEnvironment(
    'CHECKIN_LAUNCHER_FACTORY',
    defaultValue: zeroAddress,
  );

  /// Deployed StreakVaultFactory. The app does not call it directly; it is
  /// kept here so all addresses sit in one place.
  /// Set with `--dart-define=STREAK_VAULT_FACTORY=0x...`.
  static const String streakVaultFactory = String.fromEnvironment(
    'STREAK_VAULT_FACTORY',
    defaultValue: zeroAddress,
  );

  static const String zeroAddress =
      '0x0000000000000000000000000000000000000000';

  /// The build values still at their placeholder, by `--dart-define` name.
  /// Empty when the build can start a round.
  static List<String> get missingValues => missingFrom(
    checkInLauncherFactory: checkInLauncherFactory,
    streakVaultFactory: streakVaultFactory,
    attesterAddress: attesterAddress,
  );

  /// [missingValues] for any set of values (a parameter list so tests can
  /// check it without rebuilding).
  static List<String> missingFrom({
    required String checkInLauncherFactory,
    required String streakVaultFactory,
    required String attesterAddress,
  }) {
    bool unset(String a) =>
        !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(a) ||
        a.toLowerCase() == zeroAddress;
    return [
      if (unset(checkInLauncherFactory)) 'CHECKIN_LAUNCHER_FACTORY',
      if (unset(streakVaultFactory)) 'STREAK_VAULT_FACTORY',
      if (unset(attesterAddress)) 'ATTESTER_ADDRESS',
    ];
  }

  static bool get canStartRound => missingValues.isEmpty;

  static const String explorerTx = 'https://testnet.bscscan.com/tx/';
  static const String explorerAddress = 'https://testnet.bscscan.com/address/';
  static const String explorerToken = 'https://testnet.bscscan.com/token/';

  /// A token's page on Flap (testnet): this plus the token address.
  static const String flapToken = 'https://flap.sh/bnb-testnet/';

  /// Every transaction is a legacy one at this gas price with an explicit
  /// gas limit. Fee estimation on BSC testnet answers 1 wei, and a
  /// transaction sent at that price is never mined.
  static final BigInt gasPriceWei = BigInt.from(1000000000); // 1 gwei

  /// The share of each deposit that goes to the launch pool when a round is
  /// started from this app, in basis points (the factory's
  /// DEFAULT_LIQUIDITY_BPS).
  static const int defaultLiquidityBps = 3000;

  /// The longest a round may run (the factory's MAX_ROUND_DURATION).
  static const int maxRoundDays = 90;

  static BigInt _gwei(int n) => BigInt.from(n) * gasPriceWei;

  /// Test BNB a wallet must hold before the app sends a small transaction
  /// (mint, approve, join, check in, claim, refund). Below it the app asks
  /// the faucet and waits.
  static final BigInt smallGasWei = _gwei(1000000); // 0.001 tBNB

  /// Test BNB needed before `launch()`: its gas limit at 1 gwei, plus room.
  static final BigInt launchGasWei = _gwei(GasLimit.launch + 500000);

  /// Test BNB needed before starting a round: the Portal's 0.005 tBNB salt
  /// lock fee plus the gas.
  static final BigInt startRoundGasWei =
      _gwei(5000000) + _gwei(GasLimit.newLauncher + 500000);
}

/// Explicit gas limits, measured on a fork of BSC testnet (see
/// ../contracts/README.md) with room on top.
class GasLimit {
  static const int mint = 150000;
  static const int approve = 100000;
  static const int join = 250000;
  static const int sponsor = 200000;
  static const int checkIn = 200000;
  static const int launch = 7000000;
  static const int refund = 200000;
  static const int claim = 500000;
  static const int newLauncher = 1000000;
}
