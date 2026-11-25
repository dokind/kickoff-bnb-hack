import 'package:flutter/foundation.dart' show kIsWeb;

import 'services/origin_service.dart';

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

  /// The server (see ../verifier) at a fixed address, set at build time with
  /// `--dart-define=VERIFIER_URL=https://...`. For local development and
  /// tests; a release build leaves it empty and finds the server on chain
  /// (see [originRegistry]).
  static const String verifierUrlDefine = String.fromEnvironment(
    'VERIFIER_URL',
  );

  /// OriginRegistry on BSC testnet (../contracts/src/OriginRegistry.sol).
  /// The server writes its current host here whenever it moves; the apps
  /// read it with OriginService before their first call.
  static const String originRegistry =
      '0xb9aD45Dc177C801f10670F2aac03B467f1C367d2';

  /// Base URL of every server call, without a trailing slash. Empty when the
  /// server's address is not known yet.
  static String get verifierBaseUrl => apiBaseFor(
    define: verifierUrlDefine,
    web: kIsWeb,
    pageOrigin: kIsWeb ? Uri.base.origin : '',
    originHost: OriginService.instance.host,
  );

  /// [verifierBaseUrl] for any set of values, so tests can check it. In
  /// order:
  ///
  /// 1. VERIFIER_URL, when set. One that points at this machine (localhost)
  ///    is only used when the page itself is served from this machine: a
  ///    hosted site must never send people's browsers to their own
  ///    localhost.
  /// 2. On the web, a page served through a Cloudflare quick tunnel
  ///    (`*.trycloudflare.com`, the links handed out before the site moved):
  ///    the page's own origin plus `/api`, the server behind that tunnel.
  /// 3. [originHost], the host OriginRegistry holds (read this run, else the
  ///    one kept on the device): `https://<host>/api`.
  /// 4. Empty: the app says it has no server address yet.
  static String apiBaseFor({
    required String define,
    required bool web,
    required String pageOrigin,
    String originHost = '',
  }) {
    final url = _trim(define);
    if (url.isNotEmpty && !(web && _isLocal(url) && !_isLocal(pageOrigin))) {
      return url;
    }
    if (web && _isTunnel(pageOrigin)) return '${_trim(pageOrigin)}/api';
    final host = originHost.trim().toLowerCase();
    if (OriginService.isValidHost(host)) {
      return OriginService.apiBaseForHost(host);
    }
    return '';
  }

  /// True when [verifierBaseUrl] does not depend on the chain, so there is
  /// nothing to look up.
  static bool get _fixedServer => apiBaseFor(
    define: verifierUrlDefine,
    web: kIsWeb,
    pageOrigin: kIsWeb ? Uri.base.origin : '',
  ).isNotEmpty;

  /// Finds the server before the first screen: reads the host kept on the
  /// device and OriginRegistry. Bounded by the origin lookup's timeout, so a
  /// slow RPC cannot hold the app on its splash.
  static Future<void> resolveServer() async {
    if (_fixedServer) return;
    final origin = OriginService.instance;
    try {
      await origin.resolve().timeout(
        origin.timeout + const Duration(seconds: 1),
      );
    } catch (_) {
      // Start with whatever is known; a failed call looks again.
    }
  }

  /// Looks the server up again after a call could not reach it, and returns
  /// the base URL to try next (the same one when nothing changed).
  static Future<String> refreshVerifierBaseUrl() async {
    if (!_fixedServer) {
      final origin = OriginService.instance;
      try {
        await origin.refresh().timeout(
          origin.timeout + const Duration(seconds: 1),
        );
      } catch (_) {}
    }
    return verifierBaseUrl;
  }

  static String _trim(String url) =>
      url.trim().replaceFirst(RegExp(r'/+$'), '');

  static bool _isLocal(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  static bool _isTunnel(String url) {
    final host = (Uri.tryParse(url.trim())?.host ?? '').toLowerCase();
    return host.endsWith('.trycloudflare.com');
  }

  /// The web app's permanent address (GitHub Pages), without a trailing
  /// slash.
  static const String siteUrl = 'https://dokind.github.io/kickoff-bnb-hack';

  /// Where the web build of this app is served, without a trailing slash:
  /// the start of every round's invite link. Set it at build time with
  /// `--dart-define=WEB_BASE_URL=https://...`.
  static const String webBaseUrlDefine = String.fromEnvironment('WEB_BASE_URL');

  static String get webBaseUrl => webBaseFor(
    define: webBaseUrlDefine,
    web: kIsWeb,
    pageOrigin: kIsWeb ? Uri.base.origin : '',
    pagePath: kIsWeb ? Uri.base.path : '',
  );

  /// [webBaseUrl] for any set of values, so tests can check it. WEB_BASE_URL
  /// when set; else, on the web, the address the page is served from (with
  /// its path, so a site under a path such as GitHub Pages keeps it), except
  /// a quick tunnel's, whose host changes when the tunnel restarts; else
  /// [siteUrl].
  static String webBaseFor({
    required String define,
    required bool web,
    required String pageOrigin,
    required String pagePath,
  }) {
    final set = _trim(define);
    if (set.isNotEmpty) return set;
    if (web && pageOrigin.trim().isNotEmpty && !_isTunnel(pageOrigin)) {
      final path = pagePath.replaceFirst(RegExp(r'index\.html$'), '');
      return _trim('${_trim(pageOrigin)}$path');
    }
    return siteUrl;
  }

  /// A round's link: `<webBaseUrl>/#/r/<launcher>`. Opening it selects that
  /// round, listed or not.
  static String inviteLink(String launcher) =>
      inviteLinkFor(webBaseUrl, launcher);

  /// [inviteLink] for any base, so tests can check it.
  static String inviteLinkFor(String base, String launcher) {
    final b = _trim(base);
    return b.isEmpty ? '' : '$b/#/r/${launcher.toLowerCase()}';
  }

  /// The launcher address in a round's link, a route (`/r/0x...`) or a bare
  /// address, in lower case. Null when the text holds none.
  static String? launcherFromLink(String text) {
    final t = text.trim();
    final linked = RegExp(
      r'/r/(0x[0-9a-fA-F]{40})(?![0-9a-fA-F])',
    ).firstMatch(t);
    if (linked != null) return linked.group(1)!.toLowerCase();
    return RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(t) ? t.toLowerCase() : null;
  }

  /// How often the round cards on Home move on by themselves (until the
  /// first touch on Home, never after it), and how long they wait once a
  /// sheet has closed or a mouse has left them before they start again.
  static const Duration sliderInterval = Duration(seconds: 5);
  static const Duration sliderHold = Duration(seconds: 10);

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
  static const String flapToken = 'https://abc.flap.sh/bnb-testnet/';

  /// Every transaction is a legacy one at this gas price with an explicit
  /// gas limit. Fee estimation on BSC testnet answers 1 wei, and a
  /// transaction sent at that price is never mined.
  static final BigInt gasPriceWei = BigInt.from(1000000000); // 1 gwei

  /// The share of each deposit that goes to the token pool when a round is
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
