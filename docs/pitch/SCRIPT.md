# Cypher Run: the pitch

Three minutes on stage at BNB Hack Bangkok, Friday 27 November 2026. The spoken words below are the
speaker notes in the deck, word for word, in the same order and with the same times. Everything is
BSC testnet with test USD; nothing has value. Never say a ticker, never talk about returns or profit,
never say "real money", and never say "can't lose" without its conditions.

The kid-level cheat sheet for every term and number is [EXPLAINED.md](EXPLAINED.md). Read it once
before you rehearse.

**The story in one breath.** Cypher Run turns showing up into a community, and a community into a
launch. A group puts in equal deposits and checks in each day they move. Everyone's check-ins fill
one bar. If the group falls short, everyone gets 100% back. If the bar fills, the group launches its
own coin on Flap, and the piggy bank is split by days shown up.

**Two endings. Say both, always.** The group misses: everyone gets 100% back. The group launches:
you're paid by your days, not by your deposit. (The game slide says the first, the proof slide the
second.)

**Why Flap's Pool Launch is good for us: the owner's three points.** All three are in the talk.

1. **For members** (Season slide): a free bonus on top of a safe pot: coins and a 30-day tax stream,
   paid for by the sponsor, not by them.
2. **For sponsors** (Season slide): a race or brand doesn't just pay a prize. It launches its
   community's coin, with a crowd that has already proven it shows up, and a shop nobody can drain.
3. **For Flap** (Flap slide, the line for the Flap judge): on any launchpad, most new coins fade
   because there's no real community behind them. Ours can't launch until a community exists: days
   of people showing up are the launch condition. That's a quality filter no money target can give.
   On screen: "One new rule for Pool Launch: no community, no coin."

**The ladder contrast** (Flap slide, right after the Flap line; say it with respect, the Flap
founder is in the room, and the price ladder is Flap's own fair way to price a coin that has no
group yet): on a price ladder, the earliest buyers get the best price, and the community comes
later. Here the community comes first, and for 30 days every trade pays the people who showed up.
(The tax is on every buy and every sell for 30 days, not only on the first buyers: never say "the
first buyers pay".) The long version is in the Q&A below.

**No sponsor, and small real clubs** (the owner's point, said on the close and shown on the Season
slide): a club's own deposits build the shop, and five clubs of ten can pool into one round and
launch today, with no sponsor and no change from Flap. Our ask to Flap, a floor multiplier of 0.1x
for our factory, lets one club of ten launch alone.

**The words we use on stage** (and the real term, if a judge asks):

| Say | Real term |
|---|---|
| a vending machine made of code | smart contract |
| a sticker | one check-in (one per wallet per UTC day) |
| the bar | totalCheckIns against checkInGoal |
| a new coin | the token Flap's Portal mints at launch (exactly 1,000,000) |
| the shop | the PancakeSwap liquidity pool |
| the shop's key thrown away, "shop open", "a shop nobody can drain" | LP tokens burned (sent to the dead address); trading still moves the price |
| the group's piggy bank | the StreakVault |
| the tax | 3% on buys, 5% on sells, for 30 days; 80% to the piggy bank, 20% burned |
| the minimum shop money, the floor | Flap's floor: 1,500 test USD at our 1x floor multiplier |
| a lower floor multiplier | Flap's admin setting for our factory; 10,000 bps = 1x |
| the ladder | a bonding curve: the price climbs with each buy |
| a squad | one round of 10 people in a Season: one bar, one piggy bank, one coin |
| keep up with the average | your days ≥ all check-ins ÷ all members, frozen at launch |
| a fork | a local copy of the live testnet, used by 5 of our tests |

Three splits, three things: **50 / 50 is the coins** (shop / piggy bank), **30 / 70 is the deposits**
(shop / prize, the default round; a sponsored Season is 0 / 100), **80 / 20 is the tax** (piggy
bank / burned).

**How to say it.** Short sentences, one idea per slide, look at the judges and not the screen, a beat
after every number. Words in (brackets) are what you do, not what you say. The talk is 446 spoken
words plus the one number you read on the close (the bar line on the close is 6 of them). At about
160 a minute that is about 2:47, which leaves about 13 seconds for the one on-stage check-in, the
beats and the pauses: you finish at 3:00. Three lines are already cut to make room for the
positioning line, the sponsor reason and the no-sponsor line: "Look after it." on the hook, the
shop-money line on the live slide and "Next: an audit, then Flap mainnet." on the team slide. The
prepared line on the live slide (21 words) is extra: say it only when the round is close to full,
and then let the loader run in silence.

**Running long?** Cut, in this order: the bar line on the close ("While I talked, you added ...
stickers.", 6 words) if nobody checked in or time is short; "then it's over" on the ladder slide.
Never cut: the heart line on the hook (it is what makes "so does your body" true), the one-breath
line on the game slide, the Flap line, the ladder contrast, "A sponsor fills the shop, so every
deposit is prize.", the members and sponsors lines, either ending, the any-club line and the
no-sponsor line on the close, the ask.

**Order, and why.** Problem, then the game in one picture, then the ladder (why crypto, and what
Pool Launch adds on top), then the Flap slide (why it is a quality filter for Flap and what one press
does), so the room knows what "12 stickers and anyone can press Launch" means before they try it. The
demo proves it, the proof shows the payout split by days, and Season 1 is the offer and the business.

Never frame the proof as a return. Round 1 is a split by days: 2/3, 1/3, 0. Never put 822 against
the 500 deposit. Its tax came from our own deployer's 17 test swaps, and we topped up its shop: say
both if asked. Health numbers: say only the ones on the slides; each has its source line. Say
"risk", never "you will live longer". The step figure is observational.

## The 3-minute script

| Time | Slide | On screen | Say |
|---|---|---|---|
| 0:00-0:13 | Hook (`hook`) | YOUR AGENTS RUN 24/7. SO DOES YOUR BODY. "Agents get a new version every month. Your body never does." Card: v12, your agents, upgraded every month; v1, your body, version 1, for life | (Walk out. Wait for quiet. Look at the judges, not the screen.) Your AI agents run 24/7. So does your body: your heart never takes a day off. But agents get upgraded every month. Your body is version one, for life. (Two beats. Click.) |
| 0:13-0:18 | Problem (`inactive`) | 1.8 BILLION adults don't move enough. 1 in 3, and rising (WHO, 2024) | (Let the number land. One beat.) 1.8 billion adults don't move enough. One in three. |
| 0:18-0:24 | The fix (`steps`) | 47% lower risk of death at 7,000 steps a day than at 2,000. Not a marathon. A walk. (Ding, Lancet Public Health 2025, observational) | 7,000 steps a day: 47% lower risk of dying. Not a marathon. A walk. |
| 0:24-0:31 | Stakes (`stakes`) | WILLPOWER FAILS. STAKES WORK. 4x as many people hit their goal with money they could lose; bars 10.5% and 47.4% (Volpp, JAMA 2008) | Willpower fails. Stakes work. With money they could lose, four times as many people hit their goal. |
| 0:31-0:50 | The game (`solve`) | CYPHER RUN · SHOWING UP BECOMES A COMMUNITY, THEN A LAUNCH. STAKE IT. SHOW UP. LAUNCH IT. 1 deposit (a contract holds it, not us), 2 check in (one sticker a day fills one bar), 3 bar full: anyone can press Launch; no launch by the deadline: every deposit comes back | (Point left to right.) Cypher Run turns showing up into a community, and a community into a launch. Friends put in a deposit; a contract holds it, not us. Walk, tap Check in: one sticker a day on a shared bar. Full bar: anyone can press Launch. No launch by the deadline? Everyone gets 100% back. |
| 0:50-1:04 | The ladder (`versus`) | STAKES AREN'T NEW. A LAUNCH ON TOP IS. Three steps rising left to right, rows marked by a lock, a trophy and a clock: NO CRYPTO (company; quitters' deposits; over), SMART CONTRACT (code; same; over), FLAP POOL LAUNCH, tallest, in volt (code; + coins + tax; shop open). Footer: Trading sets value. | Stakes aren't new. A company or a smart contract can hold the pot, but you only win what quitters lost, then it's over. (Point at the volt column.) Flap Pool Launch adds a launch on top: coins, tax, and a shop that stays open. |
| 1:04-1:31 | Launch on Flap (`onflap`) | FULL BAR. ONE PRESS. A NEW COIN. "One new rule for Pool Launch: no community, no coin. Days shown up open the launch, not money raised." "Our factory is enabled on Flap's BSC testnet Portal." The diagram: a new coin (1,000,000, made by Flap at launch, none to us), 50% of the coins to the shop and 50% to the piggy bank; the money (deposits plus sponsor money; default 30/70, a sponsored Season puts 0% in the shop): 30% of deposits + all sponsor money to the shop (Season: 0%; a PancakeSwap pool; key thrown away: LP burned) and 70% of deposits, the prize, to the piggy bank (Season: 100%); 80% of the tax from the shop to the piggy bank (for 30 days: buy 3%, sell 5%; 20% is burned) | (Look at the Flap judge.) On any launchpad, most new coins fade because there's no real community behind them. Ours can't launch until a community exists: days of people showing up are the launch condition. That's a quality filter no money target can give. (Point at the piggy bank.) On a price ladder, the earliest buyers get the best price, and the community comes later. Here the community comes first, and for 30 days every trade pays the people who showed up. |
| 1:31-1:34 | Product (`product`) | ONE TAP A DAY. iPhone, Android, web. Phones read your steps. The 46-second app loop plays | (The 46-second loop plays by itself, muted. Talk over it; do not wait for it.) One tap a day. |
| 1:34-1:49 | Live demo (`live`) | LIVE · BSC TESTNET · TEST MONEY ONLY. YOUR TURN. CHECK IN. "Scan, join with free test dollars, tap Check in. At 12 stickers, anyone can press Launch." QR to Bangkok Demo Run | Try it. Scan this and join with test dollars. (Prepared line, only when the round is close to full, see the red warning in the demo steps: "If it warns the bar can fill today, that's the app being honest: tap Join anyway, then check in right away.") (Tap Check in, type today's steps, send. Let the loader run; the shop-money line is cut by default.) (Point at the bar.) Twelve stickers, and anyone can press Launch. |
| 1:49-1:58 | Proof (`paid`) | ROUND 1 · 3 WALLETS, SAME DEPOSIT. SPLIT BY DAYS, NOT BY DOLLARS. The piggy bank (1,050 prize + 183.48 tax = 1,233.48 test dollars + 500,000 coins) splits into stickers A, A, B; C has none: A 2 days 2/3, B 1 day 1/3, C 0 days 0 | (Point at the piggy bank, then the stickers, then the rows.) It already ran on testnet. Three wallets, same deposit. Split by days, not dollars: two days, two thirds. One day, one third. Zero days, nothing. |
| 1:58-2:29 | Season 1 (`earn`) | SEASON 1: SHOW UP 30 · SQUADS OF 10 · LAUNCH EARLIEST 24 DEC, LATEST 31 DEC · BSC TESTNET. EVERYONE STARTS DEC 1. Volt card, KEEP-UP GUARANTEE: "Keep up with the average: deposit back, or more." Dark card, FALL-SHORT REFUND: "Group falls short: 100% back." Lines: "A sponsor fills the shop, so every deposit is prize." "No sponsor? A club's own deposits build the shop." | Season one: everyone starts December first. A sponsor fills the shop, so every deposit is prize. Keep up with the average: deposit back, or more. Group falls short: 100% back. (Look at the room.) For members, the launch is a free bonus on top of a safe pot, paid for by the sponsor, not by them. A sponsor doesn't just pay a prize: it launches its community's coin, with a crowd that has proven it shows up, and a shop nobody can drain. Sponsors pay us per Season. |
| 2:29-2:34 | Team (`team`) | [Your name] · SOLO FOUNDER. ONE BUILDER. SHIPPED END TO END. 732 tests passing / 5 of them on a fork of Flap's live testnet / 47 testnet transactions; NEXT: gas paid for you, BNB attestations, audit, Flap mainnet | I built this solo: contracts, server, iPhone, Android, web. 732 tests, open source. |
| 2:34-3:00 | Close (`finale`) | Pill: "Running first. Any club where showing up can be stamped." ONE BODY. NO UPGRADES. SHOW UP. The ask: Flap, "Set our factory's floor multiplier to 0.1x on testnet: the floor drops to 150, so a club of 10 launches with no sponsor. Days shown up are the filter."; BNB Chain, a grant for an audit, before mainnet | (Glance at the stage phone.) While I talked, you added [read the bar] stickers. (Read only the number the app shows. If nobody checked in, skip this line.) (Step forward.) It sounds like a running club. It works for any club where showing up can be stamped. No sponsor? Five clubs of ten pool into one round and launch today. My ask. Flap: set our factory's floor multiplier to 0.1x, so one club of ten launches alone. Days shown up are the filter, not money. BNB Chain: an audit grant. (Pause.) One body. No upgrades. Show up. (Stop. Click to the try-it slide for questions.) |

Optional joke on the hook, only if the room is warm (adds 4 seconds): "My agents shipped three
features last night. My body shipped a back pain."

After the close, in this order, for questions: Try it in 60 seconds (leave it up; it also shows
Season 1 and a link to Squad A, starting Tue 1 Dec), the four paths with or without a sponsor, the
full product video (85 seconds, with sound, click to play), the refund and what you still trust,
the keep-up proof, the evidence behind the design, the flow end to end, and the architecture. The
full video is for questions only, never part of the talk (see "The demo video" at the end).

Before the talk: put your real name where the deck says [Your name] (the team slide and the close).
The test counts were re-run on 26 November between 13:20 and 13:30 UTC, after the last app change:
forge test 75 offline plus 5 on a fork of Flap's live testnet Portal (fork suite last run 26 Nov);
server 203 in 11 files; flutter test 449 pass, 1 skipped; 732 in all. The team card, its notes and
the script row say 732; say that total on stage. If the app changes again, run `cd app && flutter
test` and set the total to 80 + 203 + the flutter pass count in all four places.
Run the published deck in present mode on the stage laptop and confirm the 46-second loop plays;
keep a local MP4 of the loop on the desktop.

### The demo, step by step

- **Never demo Season 1.** Its check-ins are refused until Tue 1 Dec (07:00 in Bangkok), and it is
  not the featured round. The stage demo is Bangkok Demo Run. Show Season 1 only as the upcoming
  flagship, and never use it as the backup round.
- **Before you walk on:** have a second open round ready. If the room fills the bar during
  questions, Bangkok Demo Run launches and takes no more joins. Run the checklist in
  [DEMO.md](../../DEMO.md). Open the web app on the stage phone on mobile data, tap Get started,
  and join Bangkok Demo Run now ("Join with test dollars · 100 test USD"), so the stage demo is the
  check-in only. Do not check in yet: one check-in per wallet per UTC day, and a new UTC day starts
  at 07:00 in Bangkok. Wait on Your round. Mirror the phone.
- **Check the server the apps will find** (read-only): read
  `cast call 0xb9aD45Dc177C801f10670F2aac03B467f1C367d2 "origin()(string)" --rpc-url https://bsc-testnet-rpc.publicnode.com`
  and open `https://<that host>/api/round` on the stage phone: it must answer 200 with Bangkok Demo
  Run. The host is a Cloudflare quick tunnel, so it changes if the server restarts, and the apps
  follow OriginRegistry only after it is rewritten. After any server redeploy tonight, check the same
  two things again, and check that `/api/rounds/0xcf7957dc48e5c16732331d27e2c2a1b2a9fa5876` shows
  `"season":null` (the demo round is not a Season round) and that
  `/api/rounds/0xa60e2f022d891dd394415a594c9e33614c019153` (Season 1 Squad A) shows a `season`
  object named "Season 1". Never feature Squad A before judging.
- **Check the round right before the talk** (read-only):
  `cast call 0xcF7957Dc48E5c16732331d27E2C2a1b2A9FA5876 "totalCheckIns()(uint256)" --rpc-url https://bsc-testnet-rpc.publicnode.com`
  and the same with `"launched()(bool)"` and `"memberCount()(uint256)"`. If it has launched, or
  has 11 or more of its 12 check-ins, switch to the second open round: it must be featured so it is
  the first card on Home.
  On the live slide, tell the room to type the address under the code (it opens Home) instead of
  scanning, and do the stage check-in on that round. Bangkok Demo Run's deadline is Mon 30 November,
  00:34 UTC.
- **The product slide comes first** (right after the Flap slide): its 46-second loop plays by
  itself, muted. Talk over it and click on; do not wait for it to end.
- **The one tap on stage:** on Your round, "Check in", type today's steps, send. Let the loader run
  in silence: the shop-money line ("The shop money is already in: only check-ins stand between this
  room and a launch.") is cut by default, and its time now carries the no-sponsor line on the close.
  Say it only if the check-in is slow and you did not say the prepared line. It is true because our
  sponsor top-up plus 30% of the deposits already meets Flap's floor: before the talk, read
  `"poolQuoteNow()(uint256)"` with the same `cast call`; it must be at least
  1500000000000000000000, which is 1,500 test USD. The bar moves by one. The room joins on their own
  phones.
- **The red warning, and the prepared line.** Once a round's members are at least the check-ins it
  still needs (12 minus the check-ins on Bangkok Demo Run), the join sheet shows a red card: "This
  round can launch before your first check-in. If it does, you get nothing back.", with the count
  (for example "5 of 12 check-ins. The bar can fill today."), and the deposit takes a second press,
  Join anyway. It is true: a member with no check-in gets nothing at launch. If `memberCount()` plus
  `totalCheckIns()` is 8 or more before the talk, most joiners will see it: say the prepared line
  right after "join with test dollars". Otherwise keep it for anyone
  who hesitates: "If it warns the bar can fill today, that's the app being honest: tap Join anyway,
  then check in right away."
- **Point:** THE PRIZE line on Home, "If it launched now, each day shown up would be worth about ...".
  Read the number on the screen; do not say one from this page.
- **Days:** the app names members with friendly names made from their addresses (such as "Gentle
  Giraffe"), never Ana, Ben or Chai, so point at the rows and say "this member". Say what the screen
  shows.
- **If the wifi or the server fails** (no loader progress after 8 seconds), say: "The wifi lost, so
  here is the same flow, recorded on testnet." Press back one slide: the product loop plays. Say
  the demo lines over it, then click forward twice to the proof. Never debug on stage.
- **If the room fills the bar during questions:** hand the phone (or a judge's own phone) to a
  judge to press Launch, then open the coin on abc.flap.sh and read its name and the piggy bank
  numbers aloud, never its symbol (that would be a ticker). Members who joined but never checked in
  get nothing at launch; the app warns them before they pay.

## What the judges must see, and where

| Judges look for | Where in the deck |
|---|---|
| The hook and the problem, with numbers | Hook (agents run 24/7 and so does your body; v12 against v1); 1.8 billion; 47%; 4x |
| The solution in one picture | STAKE IT. SHOW UP. LAUNCH IT.: deposit, stickers fill one bar, at a full bar anyone can press Launch, no launch means 100% back |
| Why crypto, and what Pool Launch adds | STAKES AREN'T NEW. A LAUNCH ON TOP IS.: the three-step ladder, no crypto, a smart contract, Flap Pool Launch; only the last adds coins, tax and a shop that stays open |
| How Flap Pool Launch is used, and why it matters to Flap | FULL BAR. ONE PRESS. A NEW COIN.: "One new rule for Pool Launch: no community, no coin. Days shown up open the launch, not money raised."; the quality-filter line for the Flap judge; the ladder contrast (community first, and for 30 days every trade pays the people who showed up); the default 30/70 split and the sponsored Season's 0/100 on the diagram; our factory is enabled on Flap's BSC testnet Portal; the one launch transaction drawn |
| The live product | Product loop, then the live demo the judges join (QR also on the try-it slide) |
| Proof it works | SPLIT BY DAYS, NOT BY DOLLARS.: 3 wallets, same deposit, 2/3 / 1/3 / 0; wallet A pressed Launch; PROOF.md has all 47 transactions; the close reads the room's stickers |
| The offer, the business model and the market | EVERYONE STARTS DEC 1.: Season 1: Show Up 30, squads of 10, launch earliest 24 Dec and latest 31 Dec; the Keep-Up Guarantee and the Fall-Short Refund; "A sponsor fills the shop, so every deposit is prize."; sponsors pay us per Season (spoken); the members and sponsors lines say why Pool Launch helps each of them |
| Sponsor or not, any club | The Season slide: "No sponsor? A club's own deposits build the shop."; the close, spoken: "It sounds like a running club. It works for any club where showing up can be stamped. No sponsor? Five clubs of ten pool into one round and launch today.", and the pill "Running first. Any club where showing up can be stamped."; backup: FOUR PATHS TO A LAUNCH. (sponsored squad, a club round needing 5,000 of deposits, five small clubs pooled, our ask) |
| Trust and limits | "A contract holds it, not us" on the game slide; the proof's source line; backups: the refund and what you still trust, and the keep-up proof |
| Why now | Inactivity rising to 35% by 2030 (problem notes); Pool Launch lets a Launcher set its own launch condition, so the condition can be days of showing up |
| Team, scalability and roadmap | ONE BUILDER. SHIPPED END TO END.: 732 tests, 5 on a fork of Flap's live testnet, 47 testnet transactions, NEXT |
| Open source and integration | Team slide ("All open source", MIT license) and the try-it slide (source, whitepaper, PROOF.md) |
| The ask | The close: "Set our factory's floor multiplier to 0.1x on testnet: the floor drops to 150, so a club of 10 launches with no sponsor. Days shown up are the filter." (Flap; the lever is `setLauncherFactoryMultiplier`, ours reads 1x today); an audit grant (BNB Chain) |

## Sources for the numbers on the slides

- 1.8 billion adults (31%) not active enough, 35% by 2030 if trends continue: WHO news release,
  26 June 2024 (Lancet Global Health data).
- 47% lower all-cause mortality at 7,000 against 2,000 steps a day: Ding et al., The Lancet Public
  Health, 2025, doi 10.1016/S2468-2667(25)00164-1.
- 47.4% against 10.5% hit a 16-lb weight-loss goal in 16 weeks with a deposit contract: Volpp et al.,
  JAMA, 2008, doi 10.1001/jama.2008.804 (randomized, 57 adults).
- US$300 billion by 2030 (cumulative, about US$27 billion a year), in the problem notes only, not on
  screen: WHO, Global status report on physical activity, 19 October 2022. It is a cost to health
  systems, not a market size.
- 27% lower all-cause mortality with any running, even once a week (on the evidence backup slide and
  in the notes): Pedisic et al., BJSM, 2020, doi 10.1136/bjsports-2018-100493 (14 studies, 232,149
  people).
- Backup slide only: about 3 years longer for runners (Lee et al., Prog Cardiovasc Dis 2017); 15% per
  1,000 steps (Banach et al., Eur J Prev Cardiol 2023); loss framing 45% against 30% of days (Patel
  et al., Ann Intern Med 2016); competition +920 steps a day (Patel et al., JAMA Intern Med 2019);
  habits median 59-66 days (Singh et al., Healthcare 2024); 18 to 254 days, one missed day did not
  matter (Lally et al., Eur J Soc Psychol 2010); 13.7% accept deposit programs (Halpern et al., NEJM
  2015).
- Contract, Season and round-1 numbers: contracts/src (CheckInLauncher, CheckInLauncherFactory,
  StreakVault), [PROOF.md](../../PROOF.md) and [WHITEPAPER.md](../WHITEPAPER.md).
- Do not use: "80% of resolutions fail by February", "50% of gym members quit in 6 months",
  "21 days to form a habit". None has a primary source.

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

(The code: `refund()`, CheckInLauncher.sol:430-449. It opens strictly after the deadline and only if
the coin never launched, which covers a bar that never filled, a full bar nobody launched, and a shop
below Flap's floor. Sponsors get back everything they sponsored. 7 contract tests cover it.)

## Q&A: the hardest questions, 20 seconds each

### Why Flap, and the coin

**1. "Why Flap?"**
Three reasons, one for each side. Members get a free bonus on top of a safe pot: coins and a 30-day
tax stream, paid for by the sponsor, not by them. A sponsor doesn't just pay a prize: it launches its
community's coin, with a crowd that has already proven it shows up, and a shop nobody can drain. And
for Flap: on any launchpad, most new coins fade because there's no real community behind them. Ours
can't launch until a community exists: days of people showing up are the launch condition. That's a quality filter
no money target can give.

**2. "Why Pool Launch and not a plain escrow contract?"**
Escrow can only hand back what quitters lost. One Pool Launch call adds a coin, a shop nobody can
empty and 30 days of tax for the group. Pool Launch lets a Launcher decide what unlocks a launch:
Flap's own example opens on money raised; we forked it and open on days shown up (our Launcher
reports `targetRaise = 0`). We forked Flap's launcher and vault example and
wrote only what is new: the check-in counter as the launch condition and a piggy bank that pays by
days. We enabled our factory on Flap's testnet Portal ourselves, through Flap's testnet helper; on
mainnet, Flap's admins decide.

**3. "Isn't the coin just a memecoin?"**
It's a community coin with a launch condition: it can't exist until the group has shown up, 240
attested check-ins for a Season squad. On most launches the coin comes first and the community, if
it ever comes, comes after, and the earliest buyers get the best price. Flap's classic launch climbs
a price ladder, which is a fair way to price a coin that has no group yet. Here the community comes
first. You can't buy into the group's coins; you earn them by showing up. And for 30 days, every buy
and sell pays the people who showed up: 80% of the 3% buy tax and 5% sell tax goes to the group's piggy bank. Fair launch: no
presale, no team, creator or sponsor coins; half to the group by days, half locked in the shop. Its
price is whatever trading makes it: count on the pot, not the coin.

**4. "Don't squads just make junk coins?"**
Each launch needs 240 attested check-ins first, the creator and we get zero coins, the LP is burned,
and the tax goes to the squad.

### Season 1 and the keep-up promise

**5. "Is 'deposit back or more' a return?"**
No. It is test USD on testnet, split by days from the members' own deposits: the extra is the
skippers' deposits. Coins are worth only what trading makes them, and we never promise them.

**6. "Why is the deposit-back promise true?"**
In a sponsored Season the prize is every deposit and your share is your days over all days, so days
at or above the average mean a share at or above your deposit (CheckInLauncher.sol:247, :380;
StreakVault.sol:128). We checked 300,000 random cases, with rounding, 0-day members and late
joiners: 0 violations, and six forge tests check it on our real contracts
(contracts/test/KeepUpGuarantee.t.sol). The keep-up backup slide has the proof. Conditions: a
sponsored round with 0% of deposits to the shop, equal deposits, and the round launches; the
promise is in test USD only.
Kid version: "If nobody showed up more than you, you can't get back less than you put in."

**7. "Is the start day in the contract?"**
No. Our server signs no Season check-in before 1 Dec or after 30 Dec, a server rule like the
1,000-step minimum, and we disclose it. v2 moves the start date on chain.

**8. "What if the bar fills on day 24?"**
Anyone can launch, shares freeze, and the promise holds on the frozen numbers. If someone presses
Launch before your check-in that day, that day doesn't count, so check in early in your UTC day.
Earliest 24 Dec with a full squad of 10, latest 31 Dec. If the bar is full and nobody has launched
by 31 Dec 12:00 UTC, we press Launch.

**9. "What if only 5 people join a squad?"**
The bar can't fill (5 × 30 = 150 is short of 240), the app says so, and everyone, the sponsor
included, gets 100% back after 31 Dec.

**10. "Who sponsors Season 1?"**
We do, on testnet, with 1,500 test USD per squad, Flap's floor at our 1x multiplier. No fee has been
charged yet.

**11. "Why would a sponsor pay?"**
They pay for people showing up under their name, counted on chain, and their shop money is spent
only if the squad launches; otherwise they get it all back. And they don't just pay a prize: they
launch their community's coin, with a crowd that has already proven it shows up.

**12. "How do you make money?"**
Members pay a deposit, never a fee. Sponsors pay the shop money on chain, spent only if the group
shows up, and our flat fee per sponsored Season, off chain. Honest status: no fee is in the
contracts, no sponsor has paid yet, and on testnet we are the sponsor. v2 idea: a treasury slot from
the 20% of the tax that is burned today.

**13. "Why squads of 10?"**
The goal is fixed when a round is created, so the head count must be known. Ten makes the goal
fillable (10 × 30 × 0.8 = 240) and the limit real: the app stops offering Join at 10, and we open
the next squad. A direct contract join still works, so we say so: the contract has no member cap,
and an 11th member who joined directly could fill the bar by 22 Dec instead of 24 Dec.

### No sponsor, and any club

**14. "What if there's no sponsor?"**
Four paths, on the backup slide. A: a sponsored squad, the flagship. B: one club, no sponsor: 30% of
each deposit builds the shop, so it needs 5,000 test USD of deposits to reach Flap's 1,500 floor, for
example 50 × 100. C: small clubs pool: five clubs of 10 × 100 in one round is 5,000, and 30% is
1,500, no sponsor at all. D: our ask: a lower floor multiplier; at 0.1x the floor is 150, so a club
of 10 × 50 with 30% to the shop launches alone. Today a lone club of 10 at 100 test USD
each can't reach Flap's 1,500 floor without a sponsor (it would need 500 each at 30%, or a lower floor multiplier). Every path: no launch by the deadline, 100% back. Without a sponsor, 30% of each deposit
becomes locked shop money, so keeping up with the average gives at least 70% back in test USD, plus
coins and tax; no guarantee badge there.

**15. "Isn't this just a running club?"**
It sounds like a running club. It works for any club where showing up can be stamped. Running and
walking come first because phones already count steps, and today steps are the only stamp. Next
stamps, through more attesters such as the BNB Attestation Service: a gym door QR, Strava or Garmin
runs, GitHub commits for a coding club, Duolingo for a language club, a teacher's sign-off for a
study group. None of these works today.

**16. "Flap wants 1,500 in the shop. Who pays that for a group of ten?"**
A sponsor, or the clubs themselves. The 1,500 floor is Flap's Portal rule, measured at our 1x
multiplier, not our code. If the shop is short, the whole launch fails and nothing changes; a sponsor
tops up with `sponsor()` and anyone presses again. With no sponsor, five clubs of ten at 100 test USD
pool into one round: 5,000 of deposits, 30% of it is 1,500, and it launches today with no change from
Flap. That is our ask for one club alone: Flap's admins set a floor multiplier per factory
(`setLauncherFactoryMultiplier`; 10,000 = 1x = the full floor, and ours reads 1x). Set ours to 0.1x on
testnet and the floor is 150, so a club of 10 × 50 test USD with 30% to the shop launches alone. Why
Flap might: every one of our launches already has a community behind it, because days shown up open
the launch, not money; the days are the filter. The honest
catch: no launch, no stake. Everyone gets 100% back, so the split by days only happens through a
launch; that is why the floor matters so much for small clubs.

### The refund and trust

**17. "How does the 100% refund work?"**
If the round hasn't launched by the deadline, from one second after it each wallet presses Refund
once and gets exactly its deposit plus any sponsor money, whatever its days
(CheckInLauncher.sol:430-449).

**18. "Has a refund happened on chain?"**
Yes. `scripts/refund-proof.ts` ran one on BSC testnet on 26 November (13:22 UTC): a full bar, a
launch refused because the shop would hold 80 test USD, under Flap's 1,500 floor, a refund refused
before the deadline, then after it 150 test USD back to the wallet that paid (the 100 deposit and
the 50 sponsored), and a second refund refused. All 9 checks passed; the transaction is in
PROOF.md, "Refund on testnet". 7 contract tests cover it too, including a full bar that nobody
launched, and two whole rounds on a fork of the live Portal end in a refund.

**19. "What can your server do to a Season? Why should I trust it?"**
You trust it for one thing: whether a day counts. It can stamp or refuse a day, but it cannot move
money, launch, block a launch or stop a refund (CheckInLauncher.sol:67-77). A stamp is good for one
wallet, one round, one UTC day. Honest limit: it can stamp someone who did not walk, or refuse
someone who did; if it stops stamping, the bar never fills and everyone is refunded after the
deadline. In round 1 we hand-signed one check-in with it, and PROOF.md says so. Next: the BNB
Attestation Service and a KMS-held key.

**20. "Who can upgrade the contracts?"**
Only Flap's Guardian, as in Flap's own example: both factories deploy beacon proxies, and the
upgrade function is Guardian-only. We hold no owner key and there is no withdraw function: we never
hold the money. Our only key stamps check-ins.

**21. "Isn't this gambling?"**
The outcome depends on what you do, not on chance: it is the commitment-contract model. We take no
fee from members and no cut of lost deposits. It is testnet only, and stays there until counsel signs
off, market by market: pooled forfeits and a launched coin need a lawyer per market.

### The proof and the product

**22. "Wallet C paid 500 and got 0. Isn't that just a loser's bet?"**
Yes, that is the stake. Of the 500, 350 went into the prize, shared by days, and 150 went into the
shop, locked for good. Three differences from a bet: a contract holds the money, not a company;
showing up together also creates a coin and its tax that did not exist before; and if the round never
launches, everyone gets their deposit back.

**23. "Wallet B showed up and got 411 for 500. Why less than it paid?"**
B had 1 of the 3 stickers, so a third: 350 of the 1,050 prize plus 61.16 of tax is 411.16 test USD,
plus 166,667 coins B can sell in the shop. B was at the average (1 of 3 days, 3 members), and the 150
gap is the 30% of B's deposit that went into the shop. In a sponsored round the sponsor fills the
shop and 100% of deposits are prize: the same round would have paid 1,000 / 500 / 0 before tax, the
average member exactly the deposit back. That is why Season 1 is sponsored.

**24. "I join late, the bar fills before my first check-in. Do I lose my deposit?"**
Yes, and we say so before you pay. Shares are frozen at launch, so zero stickers gets nothing. When
the bar can fill today (the check-ins still needed are no more than the members), the join sheet
warns you in red and the deposit needs a second press, Join anyway; then check in right away. In
Season 1 the app closes joining after Mon 7 Dec, the last day a newcomer can still reach 24 of 30.
Version 2 adds a join cutoff in the Launcher itself.

**25. "What breaks at 10,000 users?"**
It is all written in the README, with the fix for each: one JSON store becomes Postgres, a log scan
becomes an indexer, one public RPC becomes a paid one with a fallback, one key moves to KMS, the gas
faucet becomes a BSC paymaster. The apps find the server through OriginRegistry on chain, so moving
it needs no new build. One Launcher per round, so rounds do not share state.

**26. "Are your health numbers real?"**
Every one on a slide has its source line, and the backup slide "Why stakes, groups and days" has the
rest. 1.8 billion inactive adults: WHO, June 2024. 47% lower risk of death at 7,000 steps against
2,000: The Lancet Public Health, 2025. 4x with a deposit: Volpp, JAMA 2008, a 57-adult weight-loss
trial, 47.4% against 10.5%. The step figure is observational: linked, not proven to cause.

**27. "Only a few people ever accept a deposit. Why would anyone join?"**
True: in Halpern's NEJM 2015 trial only 13.7% accepted a deposit program, and those who did quit
smoking more. That is why onboarding is the battle, and why we start with free test dollars and
grow through sponsored Seasons, where 100% of each deposit is prize and keeping up gets it back. A
group bar also helps: competition kept people moving after the trial ended (Patel, JAMA Internal
Medicine 2019).

**Spare, if there is time:**

- *"Can people fake steps?"* On the web, yes: typed steps are a testnet-only switch and prove
  nothing; round 1's steps were made up by a test script. One person can also make many wallets (v2:
  proof of personhood). The 1,000-step minimum is our server's rule, not the contract's. Phones read
  Apple Health or Health Connect.
- *"Can the shop be emptied?"* Nobody can withdraw the liquidity: 27,386.13 LP tokens went to the
  dead address. People can still trade, and selling coins takes test USD out of the shop; that is
  trading, not withdrawing.
- *"What stops the first member dumping the coins?"* Nothing yet: coins are claimable and liquid
  right after launch. Count on the pot, not the coin. Version 2 releases them over the 30-day tax
  window.
- *"Does Flap take a cut of the tax?"* We never measured it. Say "80% of the tax that reaches the
  split goes to the piggy bank; 20% is burned".
- *"Is it audited?"* No. Mainnet needs Flap to enable our factory there, and we want an audit first:
  that is our ask to BNB Chain.

## Honest limits: say them before you're asked

- Testnet only, test money. Not audited.
- Check-ins are attested by our server, not proven. Typed steps on the web prove nothing, and one
  person can make many wallets (v2: proof of personhood).
- Coins and tax are worth only what trading makes them; round 1's tax was our own test trades.
- The refund ending: 7 contract tests, and one real refund on testnet on 26 Nov (PROOF.md).
- Flap's Guardian can upgrade the contracts. We never hold the money, but say "not us", never
  "nobody can touch it".
- The 1,500 floor is Flap's and can change; today a lone club of 10 at 100 test USD each
  can't reach it without a sponsor (it would need 500 each at 30%, or a lower floor multiplier).
- Season 1's same start day and squad size are our server's and app's rules, not the contract's; a
  direct contract join still works.
- The keep-up promise holds only in a sponsored round that launches, in test USD, with "average"
  frozen at launch; a launch before your check-in that day means that day doesn't count.
- Legal: a commitment device, not a game of chance, but pooled forfeits and a launched coin need a
  lawyer per market.

## The 60-second version (hallway)

> Your AI agents run 24/7. So does your body. But agents get upgraded every month; your body is
> version one, for life.
>
> Willpower fails; stakes work. Cypher Run turns showing up into a community, and a community into a
> launch. Friends put in equal deposits, and each day they walk they add a sticker to a shared bar.
> Group falls short: everyone gets 100% back. Bar fills: anyone presses Launch on Flap, the group's
> coin is born with a shop nobody can drain, and the piggy bank is split by days shown up, not by
> dollars. For 30 days, every trade pays the people who showed up.
>
> On any launchpad, most new coins fade because there's no real community behind them; ours can't
> launch until one exists. Season 1 starts 1 December: keep up with the average and you get your deposit back, or
> more, because a sponsor fills the shop. It works for any club where showing up can be stamped, and
> with no sponsor, a club's own deposits build the shop: five clubs of ten can pool into one round
> today, and a floor multiplier of 0.1x from Flap would let one club of 10 launch alone.
>
> Scan this, join Bangkok Demo Run with test dollars, and check in. One body. No upgrades. Show up.

## The demo video

The demo video brief is [DEMO_VIDEO.md](DEMO_VIDEO.md) (2:00, hard cap 2:30). Use only that file.
The deck carries one cut: the 46-second silent loop on the product slide (app screens with
captions, no voice). The full product video, 85 seconds in the owner's voice (an AI clone of it),
is on the backup slide after the four paths (`film`): click it to play with sound, for questions
only. Its opening and closing title cards still carry the old "get paid" line; if it plays, say it
the final way: the piggy bank is split by days shown up, not by dollars, and we never hold the
money.
