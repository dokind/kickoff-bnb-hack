# Cypher Run: the pitch

Three minutes on stage at BNB Hack Bangkok, Friday 27 November 2026. The same words are the
speaker notes of the deck. Everything here is BSC testnet with test USD; nothing has value. Never say
a ticker, never talk about returns, never say "real money".

How to say it: short sentences, one idea per slide, look at the judges and not the screen, a beat
after every number. Words in (brackets) are what you do, not what you say. About 394 spoken words at
150 a minute is 2:38, plus about 10 seconds of taps and loading in the demo and a few beats of
pause: about 2:55, so you finish before the 3:00 cut. Running long at the Flap slide? Point at the
Built numbers instead of reading them.

The one claim to get exactly right: a no-show's deposit does go to the people who showed up. That is
the stake, and it is how the stake apps work too. What only Cypher Run adds: showing up together
launches a token on top (half the supply and 80% of its tax), a group that falls short gets every
deposit back, and a contract holds the money, not us. Never say the reward is "not taken from people
who failed".

## The 3-minute script

| Time | Slide | Say |
|---|---|---|
| 0:00-0:13 | Cover | (Walk out. Wait for quiet. Raise your own hand.) Hands up if you have paid for a gym you stopped going to. (Pause two beats.) Your gym gets paid when you quit. Cypher Run pays the people who show up. |
| 0:13-0:24 | Problem | Two things fizzle. Running plans: nothing at stake, so they die the first busy week. Token launches: money alone fills the bar. One fix for both. |
| 0:24-0:39 | Idea | (Let the bar fill.) Pay a deposit. Tap once each day you move. Everyone's check-ins fill one bar. Full bar: anyone launches the token on Flap. Prize, token and tax, split by days shown up. A beginner's day counts like a marathoner's. |
| 0:39-1:10 | Demo, live | Don't trust me. Watch. (Phone mirrored, web app already past Get started, on Home. First card, Bangkok Demo Run: tap "Join with test dollars · 100 test USD".) One tap: test dollars in, deposit paid. (While the loader runs:) The token pool is already at Flap's floor, so only check-ins stand between this room and a launch. (Your round: tap Check in, type today's steps, send.) The bar moves. (Point at the three member rows on Home.) This member has two days, this one one, this one zero. This line: one day's worth if it launched now. |
| 1:10-1:21 | Proof | (Point at the three numbers. A beat after each.) And it already paid out. Round one, three test wallets. Two days: 822. One day: 411. Zero days: zero. 47 transactions, all public. |
| 1:21-1:39 | Compare | (Point at the volt row only.) Paying to show up is not new. StickK, Beeminder, DietBet: a company holds the money, and the best you win is what others lost. Here a contract holds it, and showing up together launches a token on top. Fall short together? Every deposit back. |
| 1:39-1:55 | Guarantee | (Point at 100% and 0.) No withdraw function, not even for me. (Point at the bottom row.) What you do trust: one server key decides if a day counts. It can't move money, launch, or block a launch. Join late with zero days: nothing, and the app warns you first. |
| 1:55-2:11 | Flap | (Look at the Flap founder.) Most launches fill with money. This one fills with people. Our Launcher Factory, enabled on your Portal. One launch call: token, pool, LP burned, 80% of the tax wired into our vault. Full flow on testnet, our own app. |
| 2:11-2:16 | Built | Solo build. 69 contract tests, 171 server, 416 app. All open source. |
| 2:16-2:33 | Model | Who pays? Sponsors. A race or a brand buys people showing up under its name: it funds the token pool, so every deposit is prize, and pays us a flat fee. No sponsor yet. Next: paymaster gas, BNB attestations, audit, mainnet. |
| 2:33-2:55 | Close | (Step forward.) My ask. Flap: a lower floor multiplier for our factory, so small clubs launch without a sponsor. BNB Chain: a grant for the audit. (Pause.) Fill the bar before questions end, and one of you presses Launch. (Pause.) Your gym gets paid when you quit. Cypher Run pays the people who show up. (Stop. Click to the links slide for questions.) |

The links slide stays up for questions. Flow and architecture come after it, as backup for "how does
it work underneath".

### The demo, step by step

- **Before you walk on:** have a second open round ready. If the room fills the bar during
  questions, Bangkok Demo Run launches and takes no more joins. Run the checklist in
  [DEMO.md](../../DEMO.md). Open the web app on the stage phone on mobile data, tap Get started, and wait on Home with Bangkok Demo Run as the first
  card. Mirror the phone. Have the recorded video open in a second tab, muted, at 0:00.
- **Tap 1:** "Join with test dollars · 100 test USD". Talk over the loader (the bar line above).
- **Tap 2:** on Your round, "Check in", type today's steps, send. The bar moves by one.
- **Point:** THE PRIZE line on Home, "If it launched now, each day shown up would be worth about ...".
  Read the number on the screen; do not say one from this page.
- **Days:** the app names members with friendly names made from their addresses (such as "Gentle
  Giraffe"), never Ana, Ben or Chai, so point at the rows and say "this member". From 07:00 Bangkok
  on Friday the script wallets show 2, 1 and 0 days; before then the first shows 1. Say what the
  screen shows.
- **If the wifi or the server fails** (no loader progress after 8 seconds), say: "The wifi lost, so
  here is the same flow, recorded on testnet." Switch to the video and say the same lines over it.
  Never debug on stage.
- **If the room fills the bar during questions:** hand the phone (or a judge's own phone) to a
  judge to press Launch, then open the token on abc.flap.sh and read it aloud. Members who joined
  but never checked in get nothing at launch; the app warns them before they pay.

## Q&A: the 12 hardest questions, 20 seconds each

**1. "I join late, the bar fills before my first check-in. Do I lose my deposit?"**
Yes, and we say so before you pay. Days are counted at launch, so zero days gets nothing. When the
bar is one check-in from full, the join sheet warns you and the deposit needs a second tap, "Join
anyway". Version 2 adds a join cutoff and a minimum round length in the Launcher itself.

**2. "Your server signs every check-in. Why should I trust it?"**
You trust it for one thing: whether a day counts. A signature is good for one wallet, one round,
one UTC day, today or yesterday, and only when that member sends it. The key has no function on the
Launcher or the vault: it cannot move money, launch early, block a launch or pay anyone who did not
deposit. If it stops signing, the bar never fills and everyone is refunded after the deadline. Next:
the BNB Attestation Service and a KMS-held key. And in PROOF.md we wrote down the one time we signed
a check-in by hand.

**3. "Why a token at all?"**
Because it is the reward the group creates by showing up. Half the supply goes to members by days,
and 80% of the trading tax, 3% on buys and 5% on sells for 30 days, keeps flowing to the people who
checked in. For Flap it is a launch with a reason: it only happens when real people do something. No
token sale, nothing to us.

**4. "Isn't this gambling?"**
The outcome depends on what you do, not on chance: it is the commitment-contract model. We take no
fee from members and no cut of lost deposits. It is testnet only, and stays there until counsel signs
off, market by market. Members pay in and can lose their deposit, so legal review comes before any
launch anywhere.

**5. "Flap wants 1,500 in the pool. Who pays that for a group of ten?"**
Today: 30% of the deposits plus any sponsor money. A club, race or brand can top up the pool with
`sponsor()`; if the pool is short, Launch simply reverts and nothing changes until someone tops up.
That is exactly our ask: the Portal sets a floor multiplier per factory (10,000 is no discount), so a
lower one for our factory would let small clubs launch alone. Later, round N's tax can seed round
N+1's pool.

**6. "How do you make money?"**
A flat fee per sponsored round, paid by the sponsor, off-chain. The sponsor funds the token pool, the
round sets the pool share to 0%, and 100% of members' deposits become prize. Honest status: no fee is
in the contracts and no sponsor has paid yet. Version 2: a treasury slot from the 20% of the tax that
is burned today.

**7. "Why Flap and not your own launch contract?"**
Pool Launch does the token, the PancakeSwap pool, the LP burn and the tax routing to our vault in one
transaction. We used Flap's Launcher and Vault bases and wrote only what is new: a check-in counter as
the launch condition and a vault that pays by days. Our Launcher Factory is enabled on the Flap
Portal and a full round ran on BSC testnet.

**8. "What breaks at 10,000 users?"**
It is all written in the README, with the fix for each: one JSON store becomes Postgres, a log scan
becomes an indexer, one public RPC becomes a paid one with a fallback, one key moves to KMS, the gas
faucet becomes a BSC paymaster, the quick tunnel becomes a named host. The apps find the server
through OriginRegistry on chain, so moving it needs no new build. The contracts are one Launcher per
round, so rounds do not share state.

**9. "Chai paid 500 and got 0. Isn't that just a loser's bet?"**
Yes, a no-show's deposit goes to the people who showed up: that is the stake. Three differences: a
contract holds it, not a company; showing up together also creates a token and 80% of its tax that
did not exist before; and if the whole group falls short, nobody loses anything.

**10. "If everyone shows up, do I get my deposit back? Ben showed up and got 411 for 500."**
You get your share of the prize, which is 70% of deposits by default, plus your share of half the
token supply and 80% of the tax. The other 30% becomes the token's pool, and its LP is burned, so it
stays there for good. Ben had 1 of the 3 days, so he got a third: 411 test USD and 166,666 tokens;
Ana had 2 and got two thirds. In a sponsored round the sponsor funds the pool and the round sets the
pool share to 0%, so 100% of deposits are prize. That is why sponsors are the model.

**11. "Has a refund ever happened?"**
Not on testnet yet: it needs a round whose deadline has passed. The contract tests cover it,
including a full bar that nobody launched, and two whole rounds on a fork of the live Portal end in a
refund. Bangkok Demo Run's deadline is 30 November (00:34 UTC); if it does not launch, that is the
first live refund, and anyone can check it.

**12. "Who can upgrade the contracts?"**
Only Flap's Guardian, as in Flap's own example: both factories hold a beacon, and the upgrade
function is Guardian-only. There is no owner. Our only key signs check-ins, and it has no function
that moves money.

**Spare, if there is time:**

- *"Can people fake steps?"* On the web, yes: typed steps are a testnet-only switch and prove
  nothing. Phones read Apple Health or Health Connect. Next: one identity per wallet, source, pace
  and route checks.
- *"What stops the first member dumping the tokens?"* Nothing yet: reserved tokens are claimable and
  liquid right after launch. Version 2 releases them over the 30-day tax window.
- *"Is it audited?"* No. Flap mainnet requires audited factories, and the audit is our ask.

## The 60-second version (hallway)

> Hands up if you have paid for a gym you stopped going to. Your gym gets paid when you quit.
> Cypher Run pays the people who show up.
>
> You put in a deposit and tap once each day you move. Everyone's check-ins fill one bar. When it is
> full, anyone launches the round's token on Flap, and the prize, half the supply and 80% of the
> trading tax go out by days shown up. A beginner's day counts the same as a marathoner's. If the
> group falls short, every deposit comes back, and a contract holds the money, not us.
>
> It already ran on BSC testnet: 2 days got 822 test USD, 1 day got 411, 0 days got nothing. 47
> transactions, all public.
>
> Scan this, join Bangkok Demo Run with test dollars, and check in. Twelve check-ins and the room can
> launch it.

## The demo video

The demo video brief is [DEMO_VIDEO.md](DEMO_VIDEO.md) (2:00, hard cap 2:30). Use only that file.
