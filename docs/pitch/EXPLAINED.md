# Cypher Run, explained like you're 10

Your cheat sheet for the pitch. Every number here comes from the contracts
(`contracts/src`), [PROOF.md](../../PROOF.md) or the [whitepaper](../WHITEPAPER.md). Everything runs
on BSC testnet with pretend money. Never say a ticker. Never call a payout a return or a profit.
The spoken words are in [SCRIPT.md](SCRIPT.md).

## The whole idea in one breath

**Cypher Run turns showing up into a community, and a community into a launch.**

Kid version: friends put money in a locked jar and walk every day. Each walk is a sticker on one
shared chart. Fill the chart and the group gets its own coin, plus the jar, split by stickers. Miss
the goal and everyone gets their money back.

## The opening, in plain words

Your agents run 24/7. So does your body: your heart never takes a day off. The difference is on the
first slide's card: an agent gets upgraded every month (v12), and your body is version 1, for life.
That is why the close says "One body. No upgrades. Show up."

## Glossary: kid word → real term

| Kid word | Real term | What it means |
|---|---|---|
| a notebook thousands of computers copy | blockchain | nobody can secretly change it |
| the practice copy | testnet (BSC testnet) | same notebook, pretend money |
| a vending machine made of code | smart contract | it does exactly what its code says; we have no key to reach inside |
| what you put in the jar | deposit | everyone in a round pays the same amount |
| a sticker | a check-in | one per wallet per day (a new day starts at 07:00 Bangkok time) |
| the bar | totalCheckIns against checkInGoal | everyone's stickers, added up |
| the jar that decides when the coin is born | the Launcher (CheckInLauncher) | holds the deposits and opens Launch at a full bar |
| a new coin | token | made at launch; people can buy and sell it |
| the shop | liquidity pool (PancakeSwap) | where people trade the coin for test USD |
| the shop's key thrown away, a shop nobody can drain | LP burned | nobody can close the shop and take its money; people can still trade, and selling coins takes test USD out |
| the floor, the minimum shop money | Flap Portal's minimum pool money | the shop needs at least 1,500 test USD to open |
| floor multiplier | Flap's per-factory discount knob | ours is 1x: the full 1,500; at 0.1x it would be 150 |
| the group's piggy bank | StreakVault (the vault) | holds the prize, half the coins and 80% of the tax |
| the tax jar | the coin's buy and sell tax | 3% on buys, 5% on sells, for 30 days |
| a ladder | a bonding curve | the price climbs with each buy, so the earliest buyers get the best price |
| a sponsor | sponsor money (`sponsor()`) | a race or brand that fills the shop |
| a Season, a squad | one event; each squad of 10 is its own round | one bar, one piggy bank, one coin per squad |
| the average | all check-ins ÷ all members, frozen at launch | 0-day members and late joiners count |
| our stamp | the attester's signature | our server says "this wallet walked today" |
| the button anyone can press | `launch()` | not only us: any wallet |
| a fork | a local copy of the live testnet | 5 of our tests run Flap's real deployed contracts this way, sending nothing |

## The game

1. **Deposit.** Friends each put the same deposit into the vending machine. A contract holds it, not
   us: we never hold the money.
2. **Stickers.** Each day you walk 1,000+ steps, you tap Check in: one sticker on a shared chart. Max
   one per wallet per day. (The 1,000-step rule is our server's; the one-a-day rule is the
   contract's.)
3. **The bar.** The group needs N stickers together. The bar counts stickers, not people: one person
   who shows up twice adds 2.
4. **Full bar → Launch.** Anyone can press Launch, before the deadline. The shop must also hold Flap's
   minimum money, or the press fails harmlessly and nothing changes.
5. **No launch by the deadline → refund.** Everyone presses Refund and gets back exactly what they
   paid. This also covers a full bar that nobody launched, or a shop that never reached Flap's floor.

## Two endings (say both, always)

- **The group misses:** everyone gets 100% back.
- **The group launches:** you're paid by your days, not by your deposit.

There is no third ending. "100% back" is one of the two endings, not a promise for every ending.

## Why Flap: the owner's three lines

Say these on stage. They are in the script.

1. **For members:** a free bonus on top of a safe pot: coins and a 30-day tax stream, paid for by
   the sponsor, not by them.
2. **For sponsors:** a race or brand doesn't just pay a prize. It launches its community's coin, with
   a crowd that has already proven it shows up, and a shop nobody can drain.
3. **For Flap** (the line for the Flap judge): on any launchpad, most new coins fade because
   there's no real community behind them. Ours can't launch until a community exists: days of people
   showing up are the launch condition. That's a quality filter no money target can give.

**Our one new rule for Flap: no community, no coin.** Pool Launch lets a Launcher decide what
unlocks a launch. Flap's own example Launcher opens on money raised. We forked it, set the raise
target to 0, and open on days shown up. Money is still needed, because the shop must reach Flap's
floor; what changed is that no money target opens the launch. (Never say "everyone else uses money
raised": we only know Flap's own example.)

## The ladder, and our launch

Say this with respect: the Flap founder is in the room, and Pool Launch is the part of Flap that
makes our idea possible.

- **A ladder launch** (Flap's classic launch, a bonding curve): the coin comes first. The first coin
  is cheap and every buy makes the next one cost more, so the earliest buyers get the best price. It
  is a fair way to price a coin that has no group yet, and Flap built it. A community may come later,
  or never.
- **Pool Launch** skips the ladder. One press makes the coin, opens its shop with money already in
  it, and throws away the shop's key.
- **Our launch** adds one rule on top: it can't happen until a group has shown up. So the community
  comes first. You can't buy into the group's coins; you earn them by showing up. And for 30 days,
  every buy and sell pays the people who showed up: 80% of the 3% buy tax and 5% sell tax goes to the
  group's piggy bank.
- **Fair launch:** no presale, no team or creator coins, no sponsor coins. 50% of the coins go to
  the group by days, 50% sit in the locked shop.

The short stage line: "On a price ladder, the earliest buyers get the best price, and the
community comes later. Here the community comes first, and for 30 days every trade pays the people
who showed up." (The tax is on every buy and every sell for 30 days, not only on the first buyers:
never say "the first buyers pay".)

## The ladder slide: no crypto, a smart contract, Flap Pool Launch

| | No crypto | A smart contract | Flap Pool Launch |
|---|---|---|---|
| Who holds the money (lock) | a company | code | code |
| What you can win (trophy) | what quitters lost | the same | the same + coins + tax |
| After the challenge (clock) | over | over | the shop stays open |

"The same" assumes a sponsored Season. In a default round, 30% of deposits go to the shop, so the
prize is 70% of deposits. Trading sets the value of coins and tax: never promise one.

## The launch, step by step (one press, one transaction)

Kid order, for speaking. On chain it is all one transaction.

1. **A new coin is born.** Flap makes exactly **1,000,000** coins. Nobody else gets any: not us, not
   the creator, not sponsors.
2. **The coins split 50 / 50.** **500,000 (50%)** go into the shop. **500,000 (50%)** go into the
   group's piggy bank.
3. **The shop gets money.** All sponsor money, plus **30%** of the deposits in a default round (each
   round can pick 0% to 100%; a sponsored Season picks 0%). Flap requires at least **1,500 test USD**
   in the shop. Below that, the whole press fails and nothing changes; a sponsor tops up and anyone
   presses again.
4. **The shop's key is thrown away.** The LP tokens go to a dead address, so nobody can close the
   shop and take its money, not even us. People can still trade, and selling coins takes test USD
   out: that is trading, not withdrawing.
5. **The prize goes to the piggy bank.** Everything left: 70% of the deposits in a default round,
   100% in a sponsored Season.

**After the launch: the tax jar.** For **30 days**, every buy pays **3%** and every sell pays **5%**.
**80%** of that tax goes to the piggy bank. The other **20% is burned**: nobody gets it, not Flap, not
us. Tax only arrives when people trade. (We never measured whether Flap takes a cut before that
split, so say "80% of the tax that reaches the split".)

## Split by days, not dollars

Your share = your stickers ÷ everyone's stickers, frozen at launch.

**Round 1, real testnet round** (three script wallets, 500 test USD each, default 30% to the shop):

| | Stickers | Share | Test USD | Coins |
|---|---|---|---|---|
| Member A | 2 | 2/3 | 822.32 (700 prize + 122.32 tax) | 333,333 |
| Member B | 1 | 1/3 | 411.16 (350 prize + 61.16 tax) | 166,667 |
| Member C | 0 | 0 | 0 | 0 |

- Deposits: 3 × 500 = 1,500. 30% = 450 to the shop, plus a 1,050 sponsor top-up from our deployer =
  1,500, exactly Flap's floor. 70% = 1,050 was the prize.
- Tax: 183.48 test USD, all from our own test trades (17 swaps). No outside trading.
- Why did B get 411 for 500? 30% of B's deposit (150) went into the shop. B also got 166,667 coins
  that can be sold in the shop. It is a split by days, never a gain or a loss.
- **The same round, sponsored** (0% to the shop): 1,000 / 500 / 0 before tax. B was exactly at the
  average (1 day, average 1) and would get exactly the deposit back. That is why Season 1 is
  sponsored.

## Season 1, in kid words

**Season 1: Show Up 30.** One event, one set of dates, for everyone. It comes with two named
promises: the **Keep-Up Guarantee** and the **Fall-Short Refund**. The first squad is "Season 1
Squad A", already open on testnet:
[Join Squad A · starts Tue 1 Dec](https://dokind.github.io/kickoff-bnb-hack/#/r/0xa60e2f022d891dd394415a594c9e33614c019153).

- **Join now.** Check-ins run **Tue 1 Dec to Wed 30 Dec** (UTC days; a day starts at 07:00 in
  Bangkok). Everyone starts at 0 on 1 Dec: our server signs no Season check-in before then. That is
  a server rule, like the 1,000-step minimum, not a contract rule.
- **Squads of 10.** Each squad is its own round: one bar, one piggy bank, one coin. Deposit 100 test
  USD. Goal: 10 × 30 days × 0.8 = **240 check-ins**. The app stops offering Join at 10, and we
  open the next squad (a direct contract join still works, so say so). A squad needs at least 8
  members to be able to fill.
- **The bar is the finish line.** With a full squad of 10 checking in every day, the bar fills on
  day 24, so the launch can happen **24 Dec at the earliest**, and the deadline is **31 Dec,
  23:59:59 UTC at the latest**. Never say "Launch Day is a fixed date". (The contract has no member
  cap: an 11th member who joined the contract directly could fill it by 22 Dec.)
- **Late joiners:** the app closes joining after Mon 7 Dec, the last day a newcomer can still reach
  24 of 30.
- **The sponsor:** on testnet, **we are the sponsor**: 1,500 test USD per squad, Flap's floor. So 0%
  of deposits go to the shop and every deposit is prize. If a squad doesn't launch, the sponsor money
  comes back too. No fee has been charged.
- **Season 1 is not the stage demo.** Its check-ins are refused until 1 Dec. The judges check in on
  Bangkok Demo Run.

## The Keep-Up Guarantee, in kid words

**Stage line:** "Keep up with the average member: your whole deposit back, or more. Group falls
short: 100% back."

**Kid version:** "If nobody showed up more than you, you can't get back less than you put in."

**Why it is true:** in a sponsored Season, the prize is every deposit (10 × 100 = 1,000). Your share
is your days ÷ all days. If your days are at least the average, your share is at least one tenth of
1,000, which is your 100. Checked two ways: 300,000 random cases, and six forge tests on our real
contracts (`contracts/test/KeepUpGuarantee.t.sol`).

**Worked example:** a squad of 10, 100 test USD each, the bar fills at 240.

| Members | Days each | Share each | Test USD each | Coins each |
|---|---|---|---|---|
| 6 | 30 | 30 / 240 | 125 | 62,500 |
| 3 | 20 | 20 / 240 | 83.33 | 41,666.67 |
| 1 | 0 | 0 | 0 | 0 |

The average is 240 ÷ 10 = 24 days. The six above the average get more than their 100; the three below
it get less; the one who never showed up gets nothing. It all adds up: 6 × 125 + 3 × 83.33 = 1,000,
and 6 × 62,500 + 3 × 41,666.67 = 500,000 coins. The extra 25 is the skippers' deposits, split by
days: a split, never a return. Tax comes on top as people trade, and is never promised.

**If everyone shows up every day:** the bar fills on day 24, everyone has 24 days, which is the
average, and everyone gets exactly 100 back, plus 50,000 coins and a tenth of the tax.

**The fine print (all of it):**
- Only in a sponsored round (0% of deposits to the shop) that launches, with equal deposits.
- "Average" is frozen at launch, and 0-day members and late joiners count.
- It is in test USD only. Coins and tax come on top and are never promised.
- If someone presses Launch before your check-in that day, that day doesn't count. Say "check in
  early in your UTC day", never "check in every day and you can't lose".
- Default rounds (30% to the shop): keeping up with the average gives at least 70% back in test USD,
  plus coins and tax. No guarantee badge there.

## The refund, explained like you're 10

1. Each squad's money sits in a glass jar made of code. Nobody owns the jar, not even us.
2. The jar has two endings. Either the squad fills its bar and someone presses Launch, or nobody
   launches before the last second of 31 Dec.
3. If nobody launched, the jar opens for refunds one second after midnight (07:00 on 1 Jan in
   Bangkok).
4. You press Refund yourself. It doesn't happen by magic, and it costs a tiny bit of test BNB for gas.
5. You get back exactly what you put in: your 100, plus anything you sponsored. It is the same
   whether you walked 30 days or 0.
6. Refunds go only to the wallet that paid. Nobody can take yours, and you can't take theirs.
7. You can press it once, and there is no time limit. Lose your wallet key, though, and nobody can
   press it for you.
8. If the squad **did** launch, there is no refund. Instead the piggy bank pays by days: keep up with
   the average and you get at least your 100 back.

No early exit before the deadline. 7 contract tests cover the refund, and it has happened on BSC
testnet: on 26 November (13:22 UTC) a round with a full bar that never launched (its shop would have
held 80 test USD, under Flap's 1,500 floor) paid exactly 150 test USD back after its deadline, the
100 deposit and the 50 sponsored, to the wallet that paid it (PROOF.md, "Refund on testnet").

## No sponsor? The four paths

| Path | Who fills the shop | The numbers |
|---|---|---|
| **A. Sponsored squad** (the flagship) | a race, brand, employer or charity walk | 1,500 test USD per squad of 10 × 100; 0% of deposits to the shop, so every deposit is prize; the Keep-Up Guarantee holds |
| **B. One club, no sponsor** | the club itself: 30% of each deposit | it launches only if deposits × 30% reach 1,500, so it needs **5,000** of deposits: 50 × 100, or 20 × 250 |
| **C. Small clubs pool** | five clubs together | five clubs of 10 × 100 = 5,000 in one round; 30% = 1,500 = the floor; one round, one bar, many clubs |
| **D. Our ask to Flap** | a club of 10, alone | a lower floor multiplier: at 0.1x the floor is **150**, and 10 × 50 × 30% = 150 launches on its own |

- **The honest trade-off for B and C:** that 30% becomes locked shop money, so a member at the
  average gets at least 70% back in test USD from the prize, plus coins and tax. No guarantee badge.
- **Today a lone club of 10 at 100 test USD each can't reach Flap's 1,500 floor without a sponsor**
  (it would need 500 each at 30%, or a lower floor multiplier). That is why the ask is real.
- **What you say on stage** (the close): "No sponsor? Five clubs of ten pool into one round and
  launch today." The Season slide also shows "No sponsor? A club's own deposits build the shop."
- **The honest catch for every path: no launch, no stake.** If a round doesn't launch by the
  deadline, every member gets 100% back, including members with 0 days. The split by days only
  happens through the launch, which is why the floor matters so much for small clubs.
- Club tags and leaderboards inside one round, and "club mode" (split the pot by days with no coin
  when the shop can't reach the floor), are v2.

## Any club, not just running

It sounds like a running club. It works for any club where showing up can be stamped. Running and
walking come first because phones already count steps, and today steps are the only stamp (Apple
Health or Health Connect; typed on the web as a testnet switch). Later stamps, through more
attesters such as the BNB Attestation Service: a gym door QR, Strava or Garmin runs, GitHub commits
for a coding club, Duolingo for a language club, a teacher's sign-off for a study group. **None of
these works today: never say one does.** The first two sentences are the stage line on the close,
word for word: the owner's own point, never cut. The close's pill says it on screen: "Running
first. Any club where showing up can be stamped."

## Who pays us

Members pay a deposit, never a fee. Sponsors pay two things: the shop money on chain (spent only if
the group shows up, refunded otherwise) and our flat fee per sponsored Season, off chain. Clubs
without a sponsor pay nothing extra: their shop comes from their own deposits. Honest status: no fee
is in the contracts and no sponsor has paid yet; on testnet we are Season 1's sponsor. v2 idea: a
treasury slot from the 20% of the tax that is burned today.

## Trust: what we can and cannot do

- **We cannot:** move the money, launch early, block a launch once the bar is full, or take coins. We
  hold no owner key and there is no withdraw function. Say "we never hold the money".
- **Flap's Guardian can** upgrade the contract code (beacon proxies, as in Flap's own example). So
  say "not us", not "nobody can touch it".
- **Our server stamps** "this wallet walked today", one stamp per wallet per day. It can stamp
  someone who did not walk, or refuse someone who did. If it stops stamping, the bar never fills and
  everyone gets a refund after the deadline. In round 1 we hand-signed one check-in with the server
  key; PROOF.md says so.
- **On the web, steps are typed in** (a testnet-only switch). Phones read Apple Health or Health
  Connect. One person can make many wallets (v2: proof of personhood).

## The ask

- **Flap:** "Set our factory's floor multiplier to 0.1x on testnet: the floor drops to 150, so a
  club of 10 launches with no sponsor. Days shown up are the filter." The floor multiplier is the
  minimum shop money for our rounds, one setting Flap's admins control per factory
  (`setLauncherFactoryMultiplier`). Today ours is 1x, the full 1,500 test USD. Why Flap might say
  yes: every one of our launches already has a community behind it, because days shown up open the
  launch, not money.
- **Spoken:** "My ask. Flap: set our factory's floor multiplier to 0.1x, so one club of ten launches
  alone. Days shown up are the filter, not money."
- **BNB Chain:** a grant for an audit, before mainnet.

## Words: always and never

- **Always:** "split by days, not by dollars" · "test USD", "BSC testnet" · "attested, not proven" ·
  "two endings" · "we never hold the money" · "enabled on the testnet Portal".
- **Never:** a ticker · "returns", "profit", "get paid by the people who also showed up", "822 for
  500" as a gain · "can't lose" without the conditions · "audited", "mainnet", "approved by Flap" ·
  jokes about real people · invented names ("[Your name]" stays until you fill it in).

## Likely judge questions, one-line answers

1. **Why Flap?** Members get a free bonus on a safe pot, sponsors launch their community's coin, and
   Flap gets launches that can't happen until a real community shows up: a quality filter no money
   target can give.
2. **Isn't the coin just a memecoin?** It can't exist until the group has shown up; nobody can buy in
   early; for 30 days every buy and sell pays the people who showed up; its price is whatever trading
   makes it.
3. **No sponsor?** Four paths: a sponsored squad, a club round with 5,000 of deposits, five small
   clubs pooled (they can launch today), or our ask, a 0.1x floor multiplier, so a club of 10
   launches alone.
4. **Any club?** Anywhere showing up can be stamped; today the only stamp is steps.
5. **Is "deposit back or more" a return?** No: test USD, split by days from the members' own
   deposits.
6. **Who presses Launch?** Anyone, once the bar is full, at or before the deadline, with Flap's floor
   in the shop: in round 1 a member pressed it, not us.
7. **Where do the coins go?** Half into the shop, half into the group's piggy bank; nobody else gets
   any, not us.
8. **What is the 80%?** 80% of the 30-day trading tax (3% buys, 5% sells) goes to the piggy bank; the
   other 20% is burned.
9. **What is the 30%?** In a default round, 30% of each deposit goes into the shop with any sponsor
   money; in a sponsored Season it is 0%, so every deposit is prize.
10. **Why 1,500?** It is Flap's minimum shop money at our 1x setting; below it the launch fails
    harmlessly until a sponsor tops up.
11. **What if the group fails?** No launch by the deadline: each wallet presses Refund and gets back
    exactly what it paid.
12. **Can you run off with the money?** No: we have no key and no withdraw function; only Flap's
    Guardian can upgrade the code.
13. **Can people cheat on steps?** On the web, yes, steps are typed on testnet; our server stamps the
    day, and phones read Apple Health or Health Connect.
14. **How do you make money?** Sponsors fill the shop and pay us a flat fee per Season; it is not in
    the contracts and nobody has paid yet.
15. **I join late. Can I lose my deposit?** Yes, if the bar fills before your first check-in: 0 days
    gets nothing at launch. When the bar can fill today, the app warns you in red and the deposit
    takes a second press, Join anyway; then check in right away. That warning is the app being
    honest, and it may show for judges joining the live demo.
