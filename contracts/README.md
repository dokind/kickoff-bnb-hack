# Cypher Run contracts

Cypher Run is a discipline app with money on it (the contracts keep the working name "Showup", set in
`src/Product.sol`, in their on-chain description; they were not redeployed). You pay a deposit
to join and check in every day you move. Everyone's check-ins fill one bar. When it is full, a token
launches on [Flap](https://flap.sh) Pool Launch, and the deposits and the token are shared by how many
days each person showed up. A sponsor is optional.

These are the Solidity contracts for that, on BNB Testnet (chain 97). One Launcher is one round.

**Status: deployed on BNB Testnet (chain 97), 25 November 2026.** The record is
`deployments/bsc-testnet.json`.

| Contract | Address | Deployment transaction |
|---|---|---|
| `CheckInLauncherFactory` | [`0x2A872200B83dD025977d785cDE05356d23eA4153`](https://testnet.bscscan.com/address/0x2A872200B83dD025977d785cDE05356d23eA4153) | [`0x827f9b4e…079c094c`](https://testnet.bscscan.com/tx/0x827f9b4e404217a35e75fbef0f9ea0012f1c3e0d490ac87a88e31c44079c094c) |
| `StreakVaultFactory` | [`0x0652AAD1d659344f6EdB9572723479aaece144Be`](https://testnet.bscscan.com/address/0x0652AAD1d659344f6EdB9572723479aaece144Be) | [`0x19a6d3aa…a1deb2a6`](https://testnet.bscscan.com/tx/0x19a6d3aa23f2d6e5458965070462f1411a62256d67403f8127232b4fa1deb2a6) |
| `OriginRegistry` (26 November 2026) | [`0xb9aD45Dc177C801f10670F2aac03B467f1C367d2`](https://testnet.bscscan.com/address/0xb9aD45Dc177C801f10670F2aac03B467f1C367d2) | [`0x0387d2b0…4498596098`](https://testnet.bscscan.com/tx/0x0387d2b0e7a84d0a6b72f26d2fdd8ebc4fadd0bfb7620aa7cd231f4498596098) |

`CheckInLauncherFactory` is enabled on the Flap Portal at 1x: `launcherFactoryMultiplier(address)` on
the Portal reads `true, 10000` for it (enabled on 26 November 2026 in
[`0x2a7d7106…d9ad45`](https://testnet.bscscan.com/tx/0x2a7d71063496b439a12248f90b133ce5230d7c9581a25b6af84ede2ec3d9ad45)).

The addresses of the earlier contracts (running club seasons, see
[`../docs/archive/PROOF-club-season.md`](../docs/archive/PROOF-club-season.md)) are kept in
`deployments/bsc-testnet.club-season.json`.

## The rules of a round

1. **Join.** `join()`: a wallet pays the round's fixed `deposit` in the quote token, once, and becomes
   a member. The quote token is Flap's free-mint test USD
   (`0x190C989D5665a0e404B444b53CAE9AbCfb600157`, 18 decimals).
2. **Sponsor (optional).** `sponsor(amount)`: anyone may add quote. Sponsor money only ever goes to the
   token pool. It earns no share of anything. If the round does not launch, the sponsor takes it back.
3. **Check in.** `checkIn(day, signature)`: members only, once per wallet per UTC day
   (`day = block.timestamp / 86400`), for today or yesterday only. It must carry the attester's
   signature for that wallet and day. Each check-in adds 1 to `daysOf[wallet]` and to `totalCheckIns`,
   the bar. Check-ins close at the launch.
4. **Launch.** `launch()`: **anyone** may call it, once, when `totalCheckIns >= checkInGoal` and the
   deadline has not passed. In that one transaction:
   - the pool gets all sponsor money plus `liquidityBps` of the deposits (3000 = 30%) and half the
     token supply, through `Portal.launchTaxTokenV2`; Flap burns the LP;
   - the other half of the supply goes to the round's **StreakVault**;
   - the rest of the deposits, the **prize**, is sent to the StreakVault;
   - the token has a 3% buy and 5% sell tax; 80% of the tax flows to the StreakVault, 20% is burned.
5. **Refund.** `refund()`: strictly after the deadline, if the token did not launch, each member takes
   the full deposit back and each sponsor their contribution.
6. **Claim.** `StreakVault.claim()`: a member with `d = daysOf(member) > 0` receives
   `reservedTokens * d / totalCheckIns` tokens once, and
   `quoteReceived() * d / totalCheckIns` of the quote the vault has received (prize plus tax), minus
   what that wallet already took. It can be called again as tax arrives. Members with zero days get
   nothing. There is no settle step, no list and no privileged role.

Nobody can withdraw from the Launcher or the vault: not the attester, a sponsor, the creator or the
deployer. Quote leaves the Launcher only to the Flap pool and the vault at launch, or back to the wallet
that paid it in a refund. Tokens and quote leave the vault only through a member's `claim()`.

### The attester, plainly

The attester is one address chosen when the round is created: our server.

- **What it does.** It signs that a wallet moved enough on a given day, from phone health data, or
  self-reported on the web.
- **Check-ins are attested, not proven.** The contract cannot see anyone's activity and takes the
  signature as given. The attester can sign for a member who did not move, or refuse to sign for one
  who did. Members rely on the operator of that server for this, and for nothing else.
- **What it cannot do.** It cannot launch early: the bar needs `checkInGoal` check-ins, each from a
  wallet that paid a deposit, at most one per wallet per day, for today or yesterday only. It cannot
  block or delay a launch once the bar is full: `launch()` is open to anyone. It cannot choose who is
  paid in any way other than by signing daily check-ins. It cannot move funds: it has no function on
  either contract, and it receives nothing.
- **If it stops signing**, the bar never fills, and after the deadline everyone takes their money back.

### The pool floor

Flap's Portal enforces a minimum pool size at launch. For half the supply it is **1,500 test USD** today
(Flap can change it). `poolQuoteNow()` returns what the pool would get right now; show it next to the
floor. Below the floor the Portal reverts the whole `launch()` with the custom error `0xa32ef056` and
two words, `(poolQuote offered, floor required)`; nothing changes and the round stays open, so a
sponsor can top the pool up and anyone can call `launch()` again. With three members at a 1,000 test USD
deposit and 30%, the pool is 900 test USD and needs 600 test USD of sponsor money. If nobody adds it before the
deadline, everyone is refunded.

## Credit

These contracts are a fork of the `CrowdLauncher` / `CrowdLauncherFactory` / `CrowdVault` /
`CrowdVaultFactory` example in
[flap-sh/FlapPoolLaunchVaultExample](https://github.com/flap-sh/FlapPoolLaunchVaultExample)
(commit `29334f689774f6b3a39720b3fc802ab0d6a61718`). Everything in `src/flap/` is copied from that
repository unmodified, as it requires. The fork test is adapted from its `test/ForkBase.sol` and
`test/launcher-vault/Crowd.fork.t.sol`. The upstream repository has no licence file; its sources carry
`SPDX-License-Identifier: MIT` headers, which are kept, and the files here use the same identifier.

The Portal call, the salt handling, the fee slots and the pairing of the two factories are the ones
that already launched a token on testnet in the earlier contracts
([`../docs/archive/PROOF-club-season.md`](../docs/archive/PROOF-club-season.md)).

## Layout

```
src/
├── flap/                       Flap's interfaces and base contracts, unmodified
├── Product.sol                 the working product name, one constant
├── CheckInLauncherFactory.sol  called by the Portal to create a CheckInLauncher
├── CheckInLauncher.sol         join, sponsor, checkIn, launch (anyone), refund
├── StreakVaultFactory.sol      called by the Portal during the launch to create the StreakVault
├── StreakVault.sol             holds the reserve, the prize and the tax; claim by days checked in
└── OriginRegistry.sol          the server's current host, set by the attester key, read by the apps
test/
├── RoundBase.sol               shared setup: a mock Portal at the Portal's real address, helpers
├── CheckInLauncher.t.sol       every rule and revert of a round, the config vector, the signature vector
├── StreakVault.t.sol           claim maths, rounding, the vault factory's checks
├── Salt.t.sol                  pins the salt formula below
├── OriginRegistry.t.sol        who may set the origin, empty values, the event
└── ShowupRound.fork.t.sol      whole rounds against the live testnet Portal
script/Deploy.s.sol             deploys the two factories, writes deployments/bsc-testnet.json
deployments/                    written by a real deploy: the addresses the app and the verifier use
abi/                            ABIs as JSON for the app and the verifier
```

## Setup

Needs [Foundry](https://getfoundry.sh) (`forge`) and `git`.

```sh
cd contracts
./install-deps.sh        # fetches forge-std, OpenZeppelin 4.9.6 (+ upgradeable) and solady into lib/
cp .env.example .env     # then set BSC_TESTNET_RPC_URL (and PRIVATE_KEY only when deploying)
forge build
```

## Test

```sh
forge test               # 69 pass; the fork suite is skipped when BSC_TESTNET_RPC_URL is not set

export BSC_TESTNET_RPC_URL=https://bsc-testnet-rpc.publicnode.com
forge test -vv           # 74 tests, including the 5 fork tests (about 30 seconds)
```

Last run, 26 November 2026: 74 passed, 0 failed, 0 skipped with the RPC (44 in
`CheckInLauncher.t.sol`, 17 in `StreakVault.t.sol`, 6 in `OriginRegistry.t.sol`, 2 in `Salt.t.sol`,
5 fork tests); 69 passed and the fork suite skipped without it.

The unit tests (`test/CheckInLauncher.t.sol`, `test/StreakVault.t.sol`) need no RPC. They run our
contracts unchanged against a mock Portal placed at the Portal's real address, which creates the vault
through `StreakVaultFactory` the way the real one does. They cover: the wrong signer, a signature for
another wallet, day, round or chain, a malformed signature, a replayed day, a future day, a day older
than yesterday, a non-member, a double join, launching below the goal (by the attester, the creator, a
member, a sponsor, anyone), launching after the deadline, launching at the deadline, a launch below
the floor followed by a sponsor top-up, refunds for members, sponsors and a wallet that is both, refund
only once and never after a launch, claims with unequal days, repeat claims as tax arrives in any
order, a member with zero days, and rounding (fuzzed: at most 2 wei of each asset is left for three
members).

The fork tests (`test/ShowupRound.fork.t.sol`) run against the live Portal with nothing mocked and
without touching the Portal's settings and without relying on the factory being enabled. The journey:

1. the creator opens a round with `Portal.newLauncher`; the Portal's creation event carries our
   `description()` (2,522 bytes);
2. three members mint test USD and join with 1,000 test USD each; a second join reverts;
3. day one: a forged signature and a non-member are rejected; four check-ins (one for yesterday);
   a replay reverts; `launch()` reverts below the goal, also for the attester;
4. day two (time moved forward one day): two more check-ins fill the bar of six;
5. `launch()` reverts at the Portal because 900 test USD is below the floor; a sponsor adds 600 test USD;
6. a wallet with no role and no deposit calls `launch()`: 1,500 test USD and half the supply are in the
   pool, the other half and the 2,100 test USD prize are in the vault, the Launcher holds nothing;
7. the member with 3 of 6 days claims straight away: half the tokens and half the prize;
8. real swaps on the PancakeSwap testnet pool produce tax; about 37 test USD reaches the vault;
9. she claims again for the tax, the others claim everything at once: 3/6, 2/6 and 1/6 of the tokens
   and of prize plus tax (about 1,068.59, 712.39 and 356.20 test USD for a 1,000 test USD deposit each);
10. the sponsor, the creator, the attester and the launch's caller cannot claim, and nobody can refund.

Plus: the refund path when the bar never fills (members and the sponsor), the refund path when the bar
is full but the pool never reaches the floor, a launch at the deadline itself, and the factory's
config checks through the real Portal.

## Deploy (BNB Testnet)

```sh
# .env: BSC_TESTNET_RPC_URL and PRIVATE_KEY (a throwaway testnet wallet with a little tBNB)
forge script script/Deploy.s.sol --rpc-url bsc_testnet               # dry run, sends nothing
forge script script/Deploy.s.sol --rpc-url bsc_testnet --broadcast --slow --legacy --with-gas-price 1000000000
```

`--legacy --with-gas-price 1000000000` (1 gwei) is required: fee estimation on this testnet answers
1 wei, and such transactions are never mined. The same holds for every transaction the app and the
verifier send: legacy type, gas price 1 gwei, an explicit gas limit (see "Gas" below).

With `--broadcast` the script writes `deployments/bsc-testnet.json`; a dry run does not:

```json
{
  "chainId": 97,
  "checkInLauncherFactory": "0x…",
  "deployedAt": 144810149,
  "portal": "0x…",
  "quoteToken": "0x…",
  "streakVaultFactory": "0x…"
}
```

`deployedAt` is the chain's block number when the script ran, just before the two transactions are
mined, so it is a safe block to read the factories' events from. The file is written before forge sends
the transactions: if the broadcast fails, delete it. Keys come out in alphabetical order.

The script deploys `StreakVaultFactory` first, then `CheckInLauncherFactory`. The two name each other,
so the Launcher factory's address is predicted from the deployer's next nonce; do not send another
transaction from the deployer wallet while the script runs. A dry run estimates about 13.9M gas for
the two transactions (about 0.014 tBNB at 1 gwei).

Fixed addresses on BNB Testnet:

| What | Address |
|---|---|
| Flap Portal | `0x000042108465206185A077Edc3F3fd2b49060000` |
| Flap Guardian | `0x00004d58290854c5E9880F4b5B1993c6Ad8b0000` |
| Test USD (quote token, 18 decimals, anyone can mint) | `0x190C989D5665a0e404B444b53CAE9AbCfb600157` |
| PancakeSwap V2 router (testnet) | `0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3` |

## Using the contracts

### Open a round

```solidity
struct RoundConfig {
    string name;           // token name
    string symbol;         // token symbol
    string meta;           // metadata URI, may be empty
    bytes32 salt;          // mined, see below; not zero
    uint256 deposit;       // quote token every member pays once; > 0
    uint256 liquidityBps;  // part of the deposits that seeds the pool, 0..10000; the app uses 3000
    uint256 checkInGoal;   // check-ins by all members together that open the launch; > 0
    uint256 deadline;      // unix time, in the future, at most 90 days ahead
    address attester;      // whose signature every check-in needs; not zero
}

address launcher = Portal.newLauncher{value: Portal.SALT_LOCK_FEE()}(checkInLauncherFactory, abi.encode(config));
```

`abi.encode(config)` is the encoding of **one tuple**, in exactly this order and with these types:

```
(string name, string symbol, string meta, bytes32 salt, uint256 deposit, uint256 liquidityBps,
 uint256 checkInGoal, uint256 deadline, address attester)

(string,string,string,bytes32,uint256,uint256,uint256,uint256,address)
```

In viem: `encodeAbiParameters([{ type: "tuple", components: [...] }], [config])`. The factory rejects
any other encoding, trailing bytes included (`InvalidData`). A 480-byte vector is pinned in
`test/CheckInLauncher.t.sol` (`ROUND_CONFIG_VECTOR`, the same bytes `cast abi-encode` gives):
`("Morning Movers","MOVE","",0x00…ab,1000e18,3000,6,1796342400,0xFCAd0B19bB29D4674531d6f115237E16AfCE377c)`.

The Launcher address is the return value, and is also in the factory's
`CheckInLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt)` event.
`SALT_LOCK_FEE` is 0.005 tBNB today. Factory reverts: `EmptyField()` (name, symbol or salt),
`ZeroAddress()` (attester), `InvalidDeposit()`, `InvalidLiquidityBps(uint256)`, `InvalidCheckInGoal()`,
`InvalidDeadline(uint256)`, `InvalidData()`. Factory views: `quoteToken()`, `pairedVaultFactory()`,
`hub()`, `DEFAULT_LIQUIDITY_BPS()` (3000), `MAX_ROUND_DURATION()` (90 days), `launcherDataSchema()`.

**Salt.** The Portal requires the token's address to end in `0x7777`. The token is an EIP-1167 clone
the Portal deploys with CREATE2, so a salt can be mined off-chain with one hash per attempt (about
65,000 attempts on average):

```
token = last 20 bytes of keccak256(0xff ++ PORTAL ++ salt ++ TOKEN_INIT_CODE_HASH)
TOKEN_INIT_CODE_HASH = 0xc7e15deb24b23c120ed65985516639441790ec6e89090f4aa0a87169aa9c2730
```

`test/Salt.t.sol` checks this formula against OpenZeppelin's clone prediction. A salt can be used once.

### Launcher: functions

```solidity
// approve the Launcher for the amount first, on the quote token
function join() external;                                       // pays deposit(); once per wallet
function sponsor(uint256 amount) external;                      // optional, anyone, any number of times
function checkIn(uint256 day, bytes calldata signature) external; // member; day = today or yesterday (UTC)
function launch() external;                                     // anyone; bar full, not after the deadline
function refund() external;                                     // after the deadline, if not launched
```

All of `join`, `sponsor`, `checkIn` and `launch` work up to and including `deadline()`
(`block.timestamp <= deadline`). `refund` works strictly after it (`block.timestamp > deadline`), and
pays a wallet its deposit (if it is a member) plus everything it sponsored, in one call.

Views:

| View | Returns |
|---|---|
| `deposit()` | `uint256`, quote per member |
| `liquidityBps()` | `uint256`, 0..10000 |
| `checkInGoal()` | `uint256`, the size of the bar |
| `deadline()` | `uint256`, unix time |
| `attester()` | `address` |
| `isMember(address)` | `bool` (false again after that wallet refunds) |
| `memberCount()` | `uint256` (goes down as members refund) |
| `daysOf(address)` | `uint256`, days that member checked in |
| `totalCheckIns()` | `uint256`, the bar |
| `checkedInOn(address, uint256 day)` | `bool` |
| `sponsoredBy(address)` | `uint256` |
| `totalDeposits()` | `uint256`, `memberCount * deposit` |
| `totalSponsored()` | `uint256` |
| `poolQuoteNow()` | `uint256`, `totalSponsored + totalDeposits * liquidityBps / 10000`; unchanged after launch |
| `prizeQuoteNow()` | `uint256`, what would go to the vault now; after launch, what did |
| `prizeQuote()` | `uint256`, the prize sent at launch; 0 before |
| `canLaunch()` | `bool`: bar full, not launched, deadline not passed, pool not empty (the Portal's floor is not checked) |
| `refundable(address)` | `uint256`, what `refund()` would pay that wallet now; 0 while refunds are closed |
| `currentDay()` | `uint256`, `block.timestamp / 86400` |
| `checkInDigest(address wallet, uint256 day)` | `bytes32`, the hash the attester signs |
| `launched()` | `bool` |
| `token()`, `pool()`, `vault()` | `address`, zero before the launch |
| `quoteToken()`, `creator()`, `hub()`, `vaultFactory()` | `address` |
| `name()`, `symbol()`, `meta()` | `string` |
| `description()` | `string`, Flap's v1 JSON, English and Chinese |

Events:

```solidity
event Joined(address indexed member, uint256 amount);
event Sponsored(address indexed sponsor, uint256 amount);
event CheckedIn(address indexed member, uint256 indexed day, uint256 daysOfMember, uint256 totalCheckIns);
event Launched(address indexed token, address indexed pool, address indexed vault, uint256 poolQuote, uint256 prizeQuote);
event Refunded(address indexed account, uint256 amount);
```

Errors: `RoundClosed()` (join or sponsor after the launch or the deadline), `AlreadyMember()`,
`ZeroAmount()`, `NotMember()`, `CheckInsClosed()` (after the launch or the deadline),
`InvalidDay(uint256 day, uint256 today)`, `AlreadyCheckedIn(uint256 day)`, `InvalidSignature()`,
`AlreadyLaunched()`, `GoalNotReached(uint256 totalCheckIns, uint256 checkInGoal)`, `LaunchClosed()`
(after the deadline), `NoPoolQuote()`, `RefundUnavailable()`, `NothingToRefund()`,
`LaunchInProgress()`. `checkIn` checks in this order: closed, member, day, replay, signature.

### The check-in signature

The attester signs, with `personal_sign` (EIP-191), the 32 raw bytes of

```
inner  = keccak256(abi.encode(uint256 chainId, address launcher, address wallet, uint256 day))
digest = keccak256("\x19Ethereum Signed Message:\n32" ++ inner)
```

- `abi.encode`, not packed: four 32-byte words, 128 bytes. `chainId` is 97. `launcher` is the round's
  Launcher address. `wallet` is the member who will send the `checkIn` transaction (`msg.sender`).
  `day` is `floor(unix time / 86400)`.
- The signature is 65 bytes, `r ++ s ++ v` with `v` 27 or 28, low `s` (OpenZeppelin `ECDSA`). A 64-byte
  compact signature is rejected.
- In viem:
  `account.signMessage({ message: { raw: keccak256(encodeAbiParameters(parseAbiParameters("uint256, address, address, uint256"), [97n, launcher, wallet, day])) } })`.
- `checkInDigest(wallet, day)` on the Launcher returns `digest` for comparison.
- A signature is good for one wallet, one day, one round and one chain, and only while that day is
  today or yesterday on chain.

Worked vector, pinned in `test/CheckInLauncher.t.sol` (`test_checkInSignatureVector`). The key is a
well-known test value, not a key anyone uses:

| | |
|---|---|
| private key | `0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef` |
| attester address | `0xFCAd0B19bB29D4674531d6f115237E16AfCE377c` |
| chainId | `97` |
| launcher | `0x1000000000000000000000000000000000000001` |
| wallet | `0x2000000000000000000000000000000000000002` |
| day | `20782` (2026-11-25 UTC) |
| `abi.encode(...)` | `0x0000000000000000000000000000000000000000000000000000000000000061` `0000000000000000000000001000000000000000000000000000000000000001` `0000000000000000000000002000000000000000000000000000000000000002` `000000000000000000000000000000000000000000000000000000000000512e` |
| inner | `0xcbafcc6a3bedc56b8321a9d1f392336f2ecb2f6f507c449622b3597fab79ab07` |
| digest | `0xc1d54e2ae2bba8b6827381f84e8b5fa7ec86048f467fd60570575dec445aba41` |
| signature | `0xea91a378e84c0366ee93151c23b319e4ace635db74a3175e585737d4cd9cd5256dc9ee53d41e88ce0ac5b09c04f13e85612648bf490fad7c1e32814fc11b7cdc1c` |

(`r = 0xea91…d525`, `s = 0x6dc9…7cdc`, `v = 28`.) `cast wallet sign --private-key <key> <inner>` gives
the same signature.

### StreakVault: claim

```solidity
function claim() external;                                              // no arguments
function claimable(address member) external view returns (uint256 tokenAmount, uint256 quoteAmount);
function claimedTokens(address member) external view returns (uint256); // 0 until the first claim
function claimedQuote(address member) external view returns (uint256);
function daysOf(address member) external view returns (uint256);        // read from the Launcher
function totalCheckIns() external view returns (uint256);               // fixed at launch
function quoteReceived() external view returns (uint256);               // prize + tax so far
function reservedTokens() external view returns (uint256);              // 500,000 tokens
function totalQuotePaid() external view returns (uint256);
function totalTokensPaid() external view returns (uint256);
function launcher() external view returns (address);
function taxToken() external view returns (address);
function quoteToken() external view returns (address);
function description() external view returns (string memory);

event Claimed(address indexed member, uint256 tokenAmount, uint256 quoteAmount);
error NothingToClaim();
```

- The vault exists from the launch transaction on, and `claim()` is open from the next transaction.
- The first `claim` pays the tokens and the caller's share of the quote received so far. Later calls
  pay the share of the tax that arrived since. `claim` reverts with `NothingToClaim()` when both
  amounts are zero, which is always the case for a wallet with no check-in.
- The order and number of claims do not change what anyone ends up with.
- Shares are integer divisions, so a few wei of each asset can stay in the vault for good: fewer wei
  than there are members with a check-in.

### Getting tax to the vault

Tax is collected in the token on each swap (3% on buys, 5% on sells), sold into the quote token by the
token's tax processor once enough has built up, and paid out when anyone calls `dispatch()` on
`ITaxToken(token).taxProcessor()`. In the fork test a 1,000 test USD buy followed by one sell-and-rebuy
round sent about 37 test USD to the vault.

### Gas

Measured in the fork test against the live contracts (the call itself, without the 21,000 base cost):

| Call | Gas used | Suggested explicit limit |
|---|---|---|
| `Portal.newLauncher` | 610,545 | 1,000,000 |
| `approve` on the quote token | about 46,000 | 100,000 |
| `join()` | up to 118,188 | 250,000 |
| `sponsor(amount)` | 76,580 | 200,000 |
| `checkIn(day, signature)` | up to 82,809 | 200,000 |
| `launch()` | 4,928,635 | 7,000,000 |
| `refund()` | up to 61,442 | 200,000 |
| `claim()` | up to 269,196 | 500,000 |

## Who can do what

| Who | Can | Cannot |
|---|---|---|
| **Creator** (anyone) | Open a round and choose its name, symbol, deposit, liquidity part, goal, deadline and attester. | Change any of it afterwards. Take deposits, sponsor money, reserved tokens, prize or tax. The creator has no rights after opening the round. |
| **Member** (anyone who paid the deposit) | Check in once a day with the attester's signature. Launch. Claim a share by days checked in. Take the full deposit back if the deadline passes without a launch. | Check in without the attester's signature, twice for one day, for a future day or one older than yesterday. Take the deposit back before the deadline or after a launch. |
| **Sponsor** (anyone) | Add quote to the token pool. Take it back if the deadline passes without a launch. | Claim anything from the vault. Take the money back after a launch: it is pool liquidity then. |
| **Attester** (one address, set at creation; our server) | Sign, or not sign, that a wallet moved enough on a day. | Launch early. Block a launch once the bar is full. Choose who is paid beyond signing daily check-ins. Move or receive funds. Change a check-in once it is on chain. |
| **Anyone** | Call `launch()` once the bar is full and the deadline has not passed. | Launch before that, after the deadline, or twice. |
| **Flap Portal** | Create Launchers and vaults through the factories, hand the reserved tokens to the vault. | Call anything else. |
| **Flap Guardian** | Upgrade the Launcher and StreakVault implementations behind their beacons. This follows Flap's convention for its factories. | — |
| **Deployer of the factories** | Nothing after deployment. The factories have no owner. | — |

What this means in plain terms:

- **Who receives tokens or revenue.** Members with at least one check-in, in proportion to their days:
  the reserved half of the supply, the prize and 80% of the tax. The pool: half the supply, sponsor
  money and the liquidity part of the deposits, with the LP burned by Flap. Burned: 20% of the tax.
  Nobody else: no fee, no creator share, nothing for sponsors or the attester.
- **A deposit is not safe money once the token launches.** `liquidityBps` of it becomes pool liquidity.
  The rest is shared by days, so a member who showed up less than the others gets back less than they
  paid, and one who never checked in gets nothing.
- **The reserved tokens are liquid at once.** The vault exists from the launch transaction and
  `claim()` works from the next one; the tokens are ordinary ERC-20 tokens, so a member can sell
  them straight away. Members sell into the same pool, so whoever sells first gets the best price
  and later sellers get less for the same share. Nothing in these contracts releases them over time.
- **The tax share is fixed at launch.** `totalCheckIns` and every `daysOf` are frozen when the
  token launches, and the vault pays the tax by them. Days after the launch do not count: a member
  who keeps showing up earns no more tax, and one who stops loses none. The tax is the token's 3% buy
  and 5% sell tax under the launch's 30-day `taxDuration`; 80% of it reaches the vault only when
  someone calls `dispatch()` on the token's tax processor (in round 1 an outside account did, and
  183.48 test USD arrived; `../PROOF.md`).
- **The attester is the one party members rely on**, for the honesty of check-ins and only for that.
  See "The attester, plainly".
- **Flap's Guardian is relied on too**, because it can upgrade the Launcher and vault code.
- **Late joiners.** A wallet can join until the launch. It can check in for today and yesterday at
  once, so two check-ins on its first day, if the attester signs both.
- **Quote sent to the Launcher by a plain transfer**, not through `sponsor()`, is not recorded for
  anyone: it joins the prize at launch, and is stuck if the round does not launch.
- **Testnet only.** On mainnet, Flap requires factories to be audited and enabled. On testnet
  `CheckInLauncherFactory` is enabled at 1x (`launcherFactoryMultiplier` reads `true, 10000`, set
  through Flap's testnet helper, which anyone can call for any factory, so read it back before a
  demo). If Flap pauses testnet creation (`Portal.featureFlags() & 1 != 0`), the deploy script prints
  a warning and the fork test fails with a clear message.
- These contracts have not been audited.

## OriginRegistry

`src/OriginRegistry.sol`, deployed at
[`0xb9aD45Dc177C801f10670F2aac03B467f1C367d2`](https://testnet.bscscan.com/address/0xb9aD45Dc177C801f10670F2aac03B467f1C367d2).
It tells the apps where the server can be reached right now. The server sits behind a Cloudflare
quick tunnel whose host changes when the tunnel restarts; instead of building that host into the
apps, the server writes it here and the apps read it before their first call.

```solidity
address public immutable announcer;   // the only address that may call setOrigin: the attester
string public origin;                 // the server's host, no scheme or path ("" until first set)
uint256 public updatedAt;             // block time of the last change
function setOrigin(string calldata origin_) external;  // announcer only; reverts on ""
event OriginChanged(string origin);
error NotAnnouncer(); error EmptyOrigin(); error ZeroAnnouncer();
```

- `announcer` is fixed in the constructor. On testnet it reads
  `0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7`, the same key that attests check-ins.
- It holds no funds and gates nothing on chain. A wrong value can only send the apps to a server
  that cannot sign check-ins, because each Launcher checks every check-in against its own
  `attester`.
- The server sends `setOrigin(host)` when `ORIGIN_REGISTRY` is set and the host it finds differs
  from `origin()` (see `../verifier/README.md`).
- `test/OriginRegistry.t.sol` covers: it starts empty, the announcer sets and moves the origin with
  the event, and anyone else, an empty origin and a zero announcer are refused.

## ABIs

`abi/CheckInLauncherFactory.json`, `abi/CheckInLauncher.json`, `abi/StreakVaultFactory.json`,
`abi/StreakVault.json` and `abi/IPortal.json` (for `newLauncher`, `SALT_LOCK_FEE`, `getLaunchVault`,
`featureFlags`). Regenerate after changing a contract:

```sh
./export-abi.sh
```
