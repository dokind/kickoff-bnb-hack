# HackQuest submission kit

Copy-paste text for the BNB Hack Bangkok form, in the final positioning: **the pot is safe, the
launch is the bonus.** Every link below was opened on 26 November 2026 (10:40 UTC; the web app, APK,
TestFlight, GitHub and Flap links again at 10:54 UTC, all answering 200), and the links of this
version again on 26 November at 12:28 UTC, all answering 200. Every address was read on BSC testnet
(chain 97) with `cast` the same day. BscScan pages refuse scripted requests, so those links were
checked by reading the same address or transaction on chain (again at about 12:30 UTC: every
transaction succeeded and every address holds code or has been used).

Fill in before submitting: **[Your name]**, **[demo video link]**, **[deck link]**. See "Before you
press submit" at the end.

---

## Project name

Cypher Run

## Tagline (under 100 characters)

Show up together, launch together: the pot is safe, the Flap launch is the bonus.

## One-liner

Cypher Run turns showing up into a community, and a community into a launch.

## Tracks

- Flap: "Build on Pool Launch"
- BNB Chain

## Short description

Cypher Run is a group step challenge with a deposit on it, built on Flap Pool Launch. A group puts
in equal deposits and checks in each day they walk 1,000 steps or more; everyone's check-ins fill
one bar. Two endings: if the round has not launched by its deadline, everyone gets 100% back. If the
bar fills, anyone can launch the group's own coin through Flap: a shop (trading pool) locked
forever, half the coins and 80% of 30 days of trading tax to the group's piggy bank, which is split
by days shown up, not by dollars. In a sponsored Season the sponsor fills the shop, so every deposit
is prize and a member who keeps up with the average gets the whole deposit back, or more. BSC
testnet only, with test USD that has no value.

## Long description

Cypher Run turns "let's all move every day" into a round with a deposit on it, and turns a group
that keeps showing up into a coin launch.

**The pot is safe, the launch is the bonus.**

- **The pot** is the core: the deposits, held by the round's own contract in test USD (standing in
  for a stablecoin), split by days shown up. If the group falls short, everyone gets 100% back. The
  only thing that can go wrong is not showing up.
- **The launch** is the bonus: a full bar unlocks a Flap Pool Launch, with a new coin, a shop locked
  forever, half the coins and 80% of 30 days of trading tax to the group. The only thing that can go
  wrong there is the coin's price, and in a sponsored round it can never eat a deposit: the sponsor
  fills the shop, so your deposit never touches the coin.

**How a round works.**

1. A round is one contract (a vending machine made of code), our Launcher, created through the Flap
   Portal by our own Launcher Factory. Everyone who joins pays the same deposit in test USD.
2. Each day you walk 1,000 steps or more, you check in. The phone app reads steps from Apple Health
   or Health Connect; on the web you type them (a testnet-only switch). Our server checks the
   1,000-step minimum and signs the day, and your own wallet records it on chain. The contract
   allows one check-in per wallet per UTC day.
3. Everyone's check-ins fill one bar. When it is full, at or before the deadline, anyone can send
   the launch transaction, once. No admin, no operator, not our server.
4. The launch makes 1,000,000 new coins. Half go into a PancakeSwap pool (the shop) with the shop
   money: all sponsor money plus a set share of the deposits (30% by default, 0% in a sponsored
   Season). Flap burns the LP tokens, so the shop is locked forever: nobody can withdraw that
   liquidity, and trading still works. The other half go to the round's vault (the group's piggy
   bank), with the prize: the rest of the deposits.
5. For 30 days trades pay a 3% buy and 5% sell tax: 80% goes to the piggy bank, 20% is burned.
6. The piggy bank pays by days, not by dollars: a member with d days gets d / (all check-ins) of the
   prize, the coins and the tax. A member with 0 days gets nothing.
7. If the round has not launched by the deadline (the bar never filled, nobody launched, or the shop
   stayed under Flap's floor), each wallet presses Refund and gets back exactly what it paid:
   members their whole deposit, sponsors everything they sponsored, whatever their days.

**Season 1: Show Up 30.** Our first sponsored Season: squads of 10, deposit 100 test USD, 0% of the
deposits to the shop, goal 240 check-ins (10 × 30 days × 0.8). Join now; check-ins run Tue 1 Dec to
Wed 30 Dec 2026, and everyone starts at 0. The bar can fill on 24 Dec at the earliest, with all 10
checking in every day, and the deadline is 31 Dec: launch earliest 24 Dec, latest 31 Dec. Two named
promises: the **Keep-Up Guarantee** (keep up with the average member: your whole deposit back, or
more) and the **Fall-Short Refund** (the group falls short: 100% back). The guarantee holds in
sponsored rounds only, in test USD, when the round launches, against the average frozen at launch;
coins and tax come on top and are never promised. A fuzz test plays it on the real contracts in
every test run (`contracts/test/KeepUpGuarantee.t.sol`: 3 properties × 1,024 random whole rounds).
On testnet we are the sponsor (1,500 test USD per squad) and charge no fee. The first squad,
"Season 1 Squad A", was created and sponsored on BSC testnet on 26 November 2026, before check-ins
start on Tue 1 December 2026: https://dokind.github.io/kickoff-bnb-hack/#/r/0xa60e2f022d891dd394415a594c9e33614c019153 (not featured before judging).

**Proof.** A full round ran on BSC testnet on 25 November 2026. Three member wallets each paid a 500
test USD deposit. After a member launched the coin, the piggy bank split the 1,050 prize plus 183.48
test USD of trading tax by days: 822.32 test USD to the member with 2 days, 411.16 to the member
with 1 day, nothing to the member with 0 days. That is the deposits split by days, not a return:
the tax came from our own 17 test swaps, and it was a scripted test round with typed-in steps.
Every transaction is in PROOF.md.

Judges: join "Bangkok Demo Run" in the web app (deposit 100 test USD, goal 12 check-ins, deadline
30 November 2026 00:34 UTC). Its shop money is already above Flap's 1,500 test USD floor, so only
check-ins decide the launch. It is a default round (30% of each deposit to the shop), so the
Keep-Up Guarantee does not apply to it.

## How it uses Flap Pool Launch

**One new rule for Pool Launch: no community, no coin.** Pool Launch lets a Launcher decide what
unlocks a launch. Flap's own example Launcher opens on money raised. We forked it, set the raise
target to 0, and open on days shown up.

**Why Flap's Pool Launch is good for everyone in it:**

1. **For members:** a free bonus on top of a safe pot: coins and a 30-day tax stream, paid for by
   the sponsor, not by them.
2. **For sponsors:** a race or brand doesn't just pay a prize. It launches its community's coin,
   with a crowd that has already proven it shows up, and a shop nobody can drain.
3. **For Flap:** on any launchpad, most new coins fade because there's no real community behind
   them. Ours can't launch until a community exists: N days of people showing up is the launch
   condition. That's a quality filter no money target can give.

**Community first, coin second.** On most launches the coin comes first and the community, if it
ever comes, comes after, and the earliest buyers get the best price. Flap's classic launch climbs a
price ladder, which is a fair way to price a coin that has no group yet. Here the community comes
first. You can't buy into the group's coins; you earn them by showing up. And for 30 days, every
buy and sell pays the people who showed up: 80% of the 3% buy tax and 5% sell tax goes to the group's piggy bank. Pool
Launch is what makes this possible: instead of a price ladder (a bonding curve), one transaction
makes the coin, fills a PancakeSwap shop and burns the LP. A fair launch: no presale, no team or
creator coins, no sponsor coins; 50% of the coins to the group by days, 50% in the locked shop.

**What we built on it:**

- **Our own Launcher Factory**, `CheckInLauncherFactory`, enabled on Flap's BSC testnet Portal at
  1x (`launcherFactoryMultiplier(factory)` reads `true, 10000`). Every round is created with
  `Portal.newLauncher(factory, config)`.
- **The launch is one Flap call.** `CheckInLauncher.launch()` calls `Portal.launchTaxTokenV2`. In
  that one transaction Flap creates the coin (1,000,000 supply, 3% buy and 5% sell tax for 30 days),
  seeds the PancakeSwap pool with half the supply and the shop money, burns the LP, creates our vault
  through our `StreakVaultFactory` and hands it the other half; our Launcher then sends the prize.
- **The tax goes through Flap's fee slots**: 80% to our vault, 20% burned.
- **What we changed**: the launch condition is a check-in counter, not a raise target
  (`targetRaise` 0). We wrote the deposit escrow, sponsor money, refunds and the vault that pays by
  days. Flap's base contracts in `contracts/src/flap/` are used unmodified (a fork of Flap's
  FlapPoolLaunchVaultExample).
- **Full flow on BSC testnet, own UI**: open, join, sponsor, check in, launch by a member, trade,
  claim. All of it is done from our Flutter app or our script, with the transactions in PROOF.md.

## How it uses BNB Chain

- All contracts are on BNB Smart Chain testnet (chain 97). Deposits, check-ins, the launch, the
  vault and the refunds are on chain. There is no withdraw function on a round or a vault: not for
  the server, a sponsor, the creator or the deployer. We never hold the money.
- A PancakeSwap pool on BSC for each launched coin, created by Flap, with the LP burned.
- `OriginRegistry`, a small contract on BSC testnet, holds the server's current address. The apps
  read it before their first call, so no build has a server address baked in.
- New wallets get a little test BNB for fees from our faucet, so a judge needs nothing to start.
- On the BNB roadmap: gas paid by a BSC paymaster, check-ins (and later gym, Strava or GitHub
  stamps) as BNB Attestation Service attestations, a real stablecoin, and Flap mainnet after an
  audit.

## With a sponsor or without

- **A. Sponsored Season** (the flagship), in squads of 10: a race, brand, employer or charity walk
  fills each squad's shop (at least Flap's floor, 1,500 test USD at our factory's 1x). Every
  deposit is prize, and the Keep-Up Guarantee holds. The sponsor's money is spent only if the squad
  launches; otherwise the sponsor gets it all back.
- **B. A club round without a sponsor:** the club builds its own shop from 30% of each deposit. It
  launches only if deposits × 30% reach the floor: 5,000 test USD of deposits (50 × 100, or
  20 × 250). A member at the average gets at least 70% back in test USD, plus coins and tax.
- **C. Small clubs, pooled:** five 10-person clubs × 100 test USD = 5,000, and 30% of that is the
  1,500 floor, with no sponsor at all: one round, one bar, many clubs. It works today, with no change
  from Flap.
- **D. Our ask to Flap:** set our factory's floor multiplier to 0.1x on testnet
  (`setLauncherFactoryMultiplier`, Flap's admin setting per factory; ours reads 1x). The floor drops
  to 150, and a 10-person club × 50 test USD × 30% = 150 launches on its own, with no sponsor. Days
  shown up are the filter, not money: every one of our launches already has a community behind it.
- **The honest catch: no launch, no stake.** A round that does not launch refunds everyone in full,
  including members with 0 days. The split by days only happens through the launch.

**Any club, not just running.** It sounds like a running club. It works for any club where showing
up can be stamped. Today the only stamp is steps; gym check-ins, Strava runs, GitHub commits for a
coding club or a teacher's sign-off for a study group are v2, through more attesters.

## Tech stack

- **Contracts:** Solidity 0.8.26, Foundry. Fork of Flap's FlapPoolLaunchVaultExample (commit
  `29334f6`); `contracts/src/flap/` unmodified.
- **Server:** TypeScript on Node 22, Hono, viem, vitest. It signs daily check-ins, lists rounds from
  the factory's on-chain events, and runs the gas faucet. It sends no transaction to any round or
  vault.
- **App:** Flutter 3.41, one codebase for web, iOS (Apple Health) and Android (Health Connect). The
  wallet is made on the device and its key stays there.
- **Hosting:** web app on GitHub Pages; Android APK built by GitHub Actions; server behind a
  Cloudflare tunnel, found through `OriginRegistry` on chain.
- **Open source:** MIT licence, public repo, 732 tests passing: 80 for the contracts (5 of them on a
  fork of Flap's live testnet), 203 for the server and 449 for the app (details in the README's
  "Status" section).

## Contracts on BSC testnet

| What | Address or transaction |
|---|---|
| `CheckInLauncherFactory` (our Launcher Factory) | https://testnet.bscscan.com/address/0x2A872200B83dD025977d785cDE05356d23eA4153 |
| `StreakVaultFactory` (our vault factory) | https://testnet.bscscan.com/address/0x0652AAD1d659344f6EdB9572723479aaece144Be |
| `OriginRegistry` | https://testnet.bscscan.com/address/0xb9aD45Dc177C801f10670F2aac03B467f1C367d2 |
| Flap Portal (testnet) | https://testnet.bscscan.com/address/0x000042108465206185A077Edc3F3fd2b49060000 |
| Test USD (Flap's free-mint quote token) | https://testnet.bscscan.com/address/0x190C989D5665a0e404B444b53CAE9AbCfb600157 |
| Our factory enabled on Flap's testnet Portal | https://testnet.bscscan.com/tx/0x2a7d71063496b439a12248f90b133ce5230d7c9581a25b6af84ede2ec3d9ad45 |
| First launch, sent by an ordinary member | https://testnet.bscscan.com/tx/0xe9d53da5e8ce1bc49e859a42a1f55879a6f056fb3a09b5dca8a9aa55e3adb896 |
| Its coin, "Bangkok Showup" | https://testnet.bscscan.com/address/0x79F03A11234CFF1Bca37860B29ddb6a7947B7777 |
| The same coin on Flap's testnet site | https://abc.flap.sh/bnb-testnet/0x79F03A11234CFF1Bca37860B29ddb6a7947B7777 |
| Its vault (paid out by days) | https://testnet.bscscan.com/address/0x93873812C48C9f5fCD3594fD651Ce9Ce96c75728 |
| Judges' round, "Bangkok Demo Run" | https://testnet.bscscan.com/address/0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876 |
| Attester (our server's key) | https://testnet.bscscan.com/address/0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7 |
| Season 1 Squad A, and the refund round | PROOF.md, "Season 1 Squad A" and "Refund on testnet" |

## Try it

| | |
|---|---|
| Web app (no install, wallet made in the browser) | https://dokind.github.io/kickoff-bnb-hack/ |
| Judges' round, straight to it | https://dokind.github.io/kickoff-bnb-hack/#/r/0xcf7957dc48e5c16732331d27e2c2a1b2a9fa5876 |
| Join Squad A · starts Tue 1 Dec (Season 1) | https://dokind.github.io/kickoff-bnb-hack/#/r/0xa60e2f022d891dd394415a594c9e33614c019153 |
| Android 8.0 and later (APK) | https://github.com/dokind/kickoff-bnb-hack/releases/download/android-latest/cypher-run.apk |
| iPhone (TestFlight) | https://testflight.apple.com/join/bp4WaEu5 (opens once Apple approves the build; build 202611261356 is in Apple's beta review) |

In the app: "Get started", then on the round "Join", "Get test dollars" (mints the deposit), "Pay
deposit", then "Check in" and type today's steps.

## Links

| | |
|---|---|
| Demo video | [demo video link] |
| Pitch deck | [deck link] |
| GitHub | https://github.com/dokind/kickoff-bnb-hack |
| Proof (every address and transaction) | https://github.com/dokind/kickoff-bnb-hack/blob/main/PROOF.md |
| Whitepaper | https://github.com/dokind/kickoff-bnb-hack/blob/main/docs/WHITEPAPER.md |
| Demo steps | https://github.com/dokind/kickoff-bnb-hack/blob/main/DEMO.md |

## Team

[Your name], solo.

## Business model

Members pay a deposit, never a fee. Sponsors (a race, a brand, an employer, a charity walk) pay two
things: the shop money on chain, spent only if the group shows up and launches and refunded
otherwise, and our flat fee per sponsored Season, off-chain. What they buy is people showing up
under their name, counted on chain, and a coin launched by a crowd that has proven it shows up.
Clubs without a sponsor pay nothing extra: their shop comes from their own deposits. Nothing in the
contracts takes a fee, and no sponsor has paid one yet. Version 2: a treasury slot that takes the
20% of the tax that is burned today.

## Roadmap

- Season rules on chain: a start day, a join cutoff and a launch that opens only after the last
  check-in day; a goal that scales with the head count.
- Club mode: when the bar fills but the shop can't reach Flap's floor, split the pot by days with no
  coin. Club tags and leaderboards inside a Season.
- More stamps than steps (gym, Strava, GitHub and more) through the BNB Attestation Service; proof
  of personhood; a key held in a KMS.
- Passkey wallets with recovery, and gas paid by a BSC paymaster, so a new member needs no test BNB.
- An audit, then Flap mainnet with a real stablecoin.

## Limits, said plainly

- **Testnet only.** Test BNB and test USD have no value. Nothing here is an investment. Not
  audited.
- **Check-ins are attested by our server, not proven.** Our server's key signs each day. It could
  sign for someone who did not move, or refuse someone who did. It cannot move funds, launch early
  or block a launch, and if it stops signing, everyone is refunded after the deadline. One person
  can make many wallets (v2: proof of personhood).
- **Typed check-ins on the web** are a testnet-only switch and prove nothing. The phone apps read
  health data, but the server cannot verify where a step count came from.
- **Coins and tax are worth only what trading makes them.** Round 1's tax came from our own test
  trades.
- **The Keep-Up Guarantee has conditions:** a sponsored round with 0% of the deposits in the shop,
  equal deposits, a launch, and test USD only. If someone presses Launch before your check-in that
  day, that day doesn't count, so check in early in your UTC day. Default rounds give at least 70%
  back at the average, with no guarantee badge.
- **Season 1's start day is a server rule** and its squad size and join window are app rules; the
  contract has no start date (v2 puts them on chain).
- **Flap's Guardian can upgrade the contracts**, and the 1,500 floor is Flap's and can change.
- **Not yet tried on a real phone:** reading steps from Apple Health or Health Connect. The iPhone
  build is in Apple's beta review. The Android APK is built by CI but was not installed on a phone.
- **The proof round was scripted**, with typed-in steps from throwaway wallets.
- **The refund ending ran on testnet** on 26 November 2026 (13:22 UTC): a full bar that never
  launched (its shop was under Flap's floor) paid 150 test USD back after the deadline, the 100
  deposit and the 50 sponsored; 9 of 9 checks passed (PROOF.md, "Refund on testnet"). That round is
  unlisted: its attester is the deployer.
- **A member who joins just before a launch can get 0 days** and so nothing; the app warns before
  that deposit.
- **Legal:** a commitment device, not a game of chance, but pooled forfeits and a launched coin need
  a lawyer in each market.

---

## Before you press submit

- [ ] Recheck https://testflight.apple.com/join/bp4WaEu5. The link opens only after Apple approves
      the beta of build 202611261356; on 26 November 2026 at 12:28 UTC it still said the beta is not
      accepting any new testers. If it still does, keep "(opens once Apple approves the build)" or
      remove the iPhone line.
- [ ] Replace [demo video link] with the unlisted YouTube link, and check it plays in a private
      window. The video is in the owner's own voice clone. Upload only the cut rendered again with
      lines 1, 7, 10 and 11 re-voiced and the new card text: the 85.1 s cut of 26 Nov still says
      and shows the old lines ([docs/pitch/DEMO_VIDEO.md](docs/pitch/DEMO_VIDEO.md), the status
      at the top).
- [ ] Replace [deck link] with the shared deck link.
- [ ] Replace [Your name].
- [ ] Read the factory back on the Portal (expect `true` and `10000`):
      `cast call 0x000042108465206185A077Edc3F3fd2b49060000 "launcherFactoryMultiplier(address)(bool,uint256)" 0x2A872200B83dD025977d785cDE05356d23eA4153 --rpc-url https://bsc-testnet-rpc.publicnode.com`
- [ ] Open the web app on a phone on mobile data, through "Get started" to Home.
