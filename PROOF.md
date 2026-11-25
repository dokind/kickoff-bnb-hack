# Proof: Cypher Run rounds on BSC testnet

> The product is now called Cypher Run. These rounds were run under its working name, "Showup",
> which is why the first round and its token carry that name.

Two rounds were opened on 25 November 2026 with the deployed `CheckInLauncherFactory`, against the
hosted server, reached then at the Cloudflare quick tunnel host
`columbus-authentication-spine-cuts.trycloudflare.com` (API under `/api/`). A quick tunnel's host
changes whenever it restarts; from 26 November the server writes its current host to OriginRegistry.
When this page was read, `origin()` was still empty (see "Read on 26 Nov 2026"). BSC testnet only (chain 97): test BNB and Flap's free-mint test
USD. Nothing here has any value.

- **Round 1, "Bangkok Showup": complete.** Three members joined, the bar filled, a member launched
  the token through the Flap Portal, trading tax reached the vault, and the two members who showed
  up claimed in proportion to their days.
- **Round 2, "Demo Day": open.** It was left with the bar at 2 of 5 on 25 November and set as the
  featured round on the hosted server, for the live demo. On 26 November it stood at 4 of 5 with
  6 members (below).

## Read on 26 Nov 2026

Read by hand with `cast` against `https://bsc-testnet-rpc.publicnode.com` at block 144849738,
03:12 in Bangkok on 26 November 2026 (20:12 UTC on 25 November). Every line can be read again with
the call named.

**"Demo Day"** (`0x378d729aE7122e5Cf7d6f4ed8797710d2503EDb5`):

| | Read | Call |
|---|---|---|
| Bar | 4 of 5 | `totalCheckIns()`, `checkInGoal()` |
| Members | 6 | `memberCount()` |
| Deposits | 3,000 test USD (6 × 500) | `totalDeposits()`, `deposit()` |
| Sponsor money | 1,500 test USD (the deployer, 25 Nov) | `totalSponsored()` |
| Token pool if launched now | 2,400 test USD (1,500 + 30% of 3,000), above Flap's 1,500 | `poolQuoteNow()` |
| Prize if launched now | 2,100 test USD (70% of 3,000) | `prizeQuoteNow()` |
| Launched | no | `launched()` |
| Deadline | 2026-11-28 16:34:21 UTC (`1795883661`) | `deadline()` |
| Attester | `0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7` | `attester()` |

Its `Joined` and `CheckedIn` events (times UTC, 25 November):

| Member | Joined | Check-ins | Days |
|---|---|---|---|
| `0x7a38081096343B6A41109EF75ccE97863C21EB04` (script, "Ana") | 16:34:43 [`0xf6321160…524f77`](https://testnet.bscscan.com/tx/0xf632116030d8037ad373f213bed1a1cb240dec46a9272226e448fa36c9524f77) | day 20782 [`0x8dd90b97…945c2e`](https://testnet.bscscan.com/tx/0x8dd90b97132f536974cd6270601167ddb3963fac08b3b04abbe0bac658945c2e) | 1 |
| `0x71a60c1e46d74b08ba12197D8f568D1AEB664E58` (script, "Ben") | 16:34:51 [`0x1fba7a2b…efe4fd`](https://testnet.bscscan.com/tx/0x1fba7a2bc0e2c9f08ea7f942fd97dcae718c346580ae1e1dc82fb9fda7efe4fd) | day 20782 [`0xb11356ce…16618d`](https://testnet.bscscan.com/tx/0xb11356cef0d10ee82e89fdd8a488d7ecd8552649511a6fee2a72fd0a8a16618d) | 1 |
| `0x95Ced7B6D811509F8741c1C5B352353f3Ff8F4C2` | 17:02:19 [`0xe4f26955…814a6d`](https://testnet.bscscan.com/tx/0xe4f26955fab0bf185f0dbe36fe5502e2f7b8ad225531468186d871b294814a6d) | none | 0 |
| `0x2c35a93666a4a3703469f2c359a1c98d7996ee85` | 17:03:54 [`0x22a59a25…8465cf`](https://testnet.bscscan.com/tx/0x22a59a25afddfcf90e113049b9dc393647c8292c55ce9ed78d5e47dbc88465cf) | day 20782 [`0xd9b6e794…d654ca`](https://testnet.bscscan.com/tx/0xd9b6e7946e54eca33235ec729439b07ce8500efb6d59e20707d9d48d5ed654ca) | 1 |
| `0x580d21E31B49D8D21AD1d4E79F676142577e2997` | 17:29:46 [`0xd2d8d16c…d5d9ed`](https://testnet.bscscan.com/tx/0xd2d8d16c289359a7b1acccc58cc77912dd2d71642c0a4ed19933e418d2d5d9ed) | day 20782 [`0xa8b90b05…722ca6`](https://testnet.bscscan.com/tx/0xa8b90b05c5b937e53fb8e2b807deb5222ce19e04098cf30a7e99472179722ca6) | 1 |
| `0x77313b6ef7773eefccd7831a0633e7410bb72f9e` | 17:32:30 [`0x0ac7d429…6acc59`](https://testnet.bscscan.com/tx/0x0ac7d42940a4152365649e66349044bd5db743fd3f3510058524e090386acc59) | none | 0 |

All four check-ins are for 25 November (day 20782). One more check-in fills the bar: on 25 November
UTC only from one of the two members with 0 days, from 26 November UTC (07:00 in Bangkok) from any
member. Which of the four later wallets belong to people and which to tests was not recorded.

**The factory on the Flap Portal.**
`launcherFactoryMultiplier(0x2A872200B83dD025977d785cDE05356d23eA4153)` on the Portal
(`0x000042108465206185A077Edc3F3fd2b49060000`) reads `true, 10000`: enabled at 1x. It was enabled
in [`0x2a7d7106…d9ad45`](https://testnet.bscscan.com/tx/0x2a7d71063496b439a12248f90b133ce5230d7c9581a25b6af84ede2ec3d9ad45)
(block 144839701, 2026-11-25 18:56:25 UTC), sent by the deployer to Flap's testnet helper
`0x77779969a11eff7582f3bCf48135A846A3457777`; the Portal's event in that transaction carries the
factory and `10000`.

**OriginRegistry.** Deployed at [`0xb9aD45Dc177C801f10670F2aac03B467f1C367d2`](https://testnet.bscscan.com/address/0xb9aD45Dc177C801f10670F2aac03B467f1C367d2)
in [`0x0387d2b0…596098`](https://testnet.bscscan.com/tx/0x0387d2b0e7a84d0a6b72f26d2fdd8ebc4fadd0bfb7620aa7cd231f4498596098)
(block 144846127, 2026-11-25 19:44:43 UTC, 02:44 on 26 November in Bangkok) by the deployer, status
success. `announcer()` reads `0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7`, the attester.
`origin()` reads `""` and `updatedAt()` `0`: the server had not announced a host yet.

**"Night Owls", created from the app.** The factory's `CheckInLauncherCreated` events name four
rounds; the fourth is "Night Owls", Launcher `0x45ae23e5e28b4c90ce10f43266a7aa52d05ec608`, created
in [`0xa5c23316…85baf74`](https://testnet.bscscan.com/tx/0xa5c233163ba5a8c49860c0061aceaf5a9f74f06426d6da3f94e0e657f85baf74)
(block 144844114, 2026-11-25 19:29:37 UTC, 02:29 on 26 November in Bangkok). The transaction is
`Portal.newLauncher` from `0x95Ced7B6D811509F8741c1C5B352353f3Ff8F4C2`, a wallet made by the app,
with the 0.005 test BNB salt lock fee; status success. The round: 1,000 test USD deposit, 30% to the
token pool, a bar of 6, deadline 2026-12-02 19:29:34 UTC, no members yet. The app's Invite sheet
for it shows the Unlisted switch on ([docs/img/invite.png](docs/img/invite.png)): the app's public
list leaves it out. That choice is kept by the server, not on chain, and was not read from the server
here.

**The other rounds.** "Bangkok Showup" is launched; its vault has received 1,233.480561266277444141
test USD (`quoteReceived()`), paid all of it out (`totalQuotePaid()`) and holds 0 test USD, as in the
table under round 1. "morning movers" (`0x74B9218cC901fa4b295C3B021c246E6f1022915B`, created from
the app on 25 November at 17:27:37 UTC) has 1 member and 0 of 6 check-ins.

**The attester wallet.** Its nonce reads 9, against 4 when this page was first written. The same
wallet pays the faucet's gas transfers, so its nonce no longer shows by itself that it touched no
round. No function of the Launcher or the vault needs the attester as the sender in any case.

**Read this first.**

- Everything on chain below is real and can be checked on testnet.bscscan.com.
- **The check-ins were self-reported test entries from throwaway wallets.** The step counts were
  made up by `scripts/run-round.ts` and sent with source `self`; nobody walked them. The wallets
  named Ana, Ben and Chai are keys the script derives in memory.
- **One check-in in round 1 did not go through the server at all.** The contract accepts a check-in
  for today or yesterday, and the server signs for today only. To show unequal days in one sitting,
  the script signed Ana's check-in for 24 November itself, with the attester key (the same key the
  server holds). That is the operator signing by hand. It is exactly what "check-ins are attested,
  not proven" means: whoever holds the attester key decides which check-ins count.
- What the attester key cannot do was also seen here: the launch was sent by a member wallet, and
  no transaction from the attester address touches either round (its nonce stayed at 4 through
  both runs; see "Read on 26 Nov 2026" for later).

## Round 1: Bangkok Showup

| | |
|---|---|
| Deposit | 500 test USD, paid once per member |
| Part of the deposits that seeds the pool (`liquidityBps`) | 3000 (30%) |
| Bar (`checkInGoal`) | 3 check-ins |
| Opened | 2026-11-25 16:29:16 UTC |
| Deadline | 2026-11-26 22:29:16 UTC |
| Members | 3 (Ana, Ben, Chai) |
| Sponsor | the deployer wallet, 1,050 test USD |

### Addresses

| What | Address |
|---|---|
| CheckInLauncherFactory (ours) | [`0x2A872200B83dD025977d785cDE05356d23eA4153`](https://testnet.bscscan.com/address/0x2A872200B83dD025977d785cDE05356d23eA4153) |
| StreakVaultFactory (ours) | [`0x0652AAD1d659344f6EdB9572723479aaece144Be`](https://testnet.bscscan.com/address/0x0652AAD1d659344f6EdB9572723479aaece144Be) |
| Flap Portal | [`0x000042108465206185A077Edc3F3fd2b49060000`](https://testnet.bscscan.com/address/0x000042108465206185A077Edc3F3fd2b49060000) |
| **Launcher (this round)** | [`0xe1c165C295ED8bC0abA2a81c2a524564689BCeAB`](https://testnet.bscscan.com/address/0xe1c165C295ED8bC0abA2a81c2a524564689BCeAB) |
| **Token** "Bangkok Showup" | [`0x79F03A11234CFF1Bca37860B29ddb6a7947B7777`](https://testnet.bscscan.com/address/0x79F03A11234CFF1Bca37860B29ddb6a7947B7777) |
| Token page on Flap (testnet site) | https://abc.flap.sh/bnb-testnet/0x79F03A11234CFF1Bca37860B29ddb6a7947B7777 |
| PancakeSwap V2 pool (token / test USD) | [`0x86287A5dCC7D0495AEfB9e24D53a06c16cBaa737`](https://testnet.bscscan.com/address/0x86287A5dCC7D0495AEfB9e24D53a06c16cBaa737) |
| **StreakVault** | [`0x93873812C48C9f5fCD3594fD651Ce9Ce96c75728`](https://testnet.bscscan.com/address/0x93873812C48C9f5fCD3594fD651Ce9Ce96c75728) |
| Tax processor of the token (Flap's) | [`0x372C1d2779FfFa6da5Aa94fFEc5Bc4446594a20B`](https://testnet.bscscan.com/address/0x372C1d2779FfFa6da5Aa94fFEc5Bc4446594a20B) |
| Test USD (deposit and pool quote) | [`0x190C989D5665a0e404B444b53CAE9AbCfb600157`](https://testnet.bscscan.com/address/0x190C989D5665a0e404B444b53CAE9AbCfb600157) |
| PancakeSwap V2 router | [`0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3`](https://testnet.bscscan.com/address/0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3) |
| Deployer: opened the round, sponsor, trader | [`0xc1bD6aC9311b9345ae8023201875518429c8BF58`](https://testnet.bscscan.com/address/0xc1bD6aC9311b9345ae8023201875518429c8BF58) |
| Attester (our server's key) | [`0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7`](https://testnet.bscscan.com/address/0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7) |
| Member Ana | [`0x9b8ADE01c3Ccb55A7bE2b45900eF43c1F7Ea8D71`](https://testnet.bscscan.com/address/0x9b8ADE01c3Ccb55A7bE2b45900eF43c1F7Ea8D71) |
| Member Ben | [`0x4BE85b60cA4A566B64c16f8749506800D04E9f68`](https://testnet.bscscan.com/address/0x4BE85b60cA4A566B64c16f8749506800D04E9f68) |
| Member Chai | [`0x730074BbbF3C55616dB2ba174FBEAa1a708B4E92`](https://testnet.bscscan.com/address/0x730074BbbF3C55616dB2ba174FBEAa1a708B4E92) |

### What happened

1. **Open.** The deployer opened the round with `Portal.newLauncher` and our factory:
   [`0xfe0ee10e28b81bd8ac788656209a623b1da3bbc567e046fe640834b59db2c33e`](https://testnet.bscscan.com/tx/0xfe0ee10e28b81bd8ac788656209a623b1da3bbc567e046fe640834b59db2c33e). The server was then pointed at it (`POST /api/admin/round`).
2. **Join.** Ana, Ben and Chai each paid the 500 test USD deposit (`CheckInLauncher.join`):
   [`0xea83ffad…4e0e44`](https://testnet.bscscan.com/tx/0xea83ffad1768468df81fe57b11ac388171dfc6c76c4942af221e97a1514e0e44), [`0x4fd7c833…490e28`](https://testnet.bscscan.com/tx/0x4fd7c833059350ea9f95c33ad12214ba81e468e6307e50c03f5227aca2490e28), [`0x9606a21e…e9f6d2`](https://testnet.bscscan.com/tx/0x9606a21ec238059ae236345f733476b1aac48e74d8ad76e09695d7e2fce9f6d2).
   Deposits: 1,500 test USD. The pool would have received 30% of that, 450, under the 1,500 test USD
   Flap's Portal asks for.
3. **Sponsor.** The deployer added 1,050 test USD with `sponsor(amount)`: [`0xc080cf7f414006afeb2c110e2cab3025c4dcdb69df3a476829d2055d2c98df22`](https://testnet.bscscan.com/tx/0xc080cf7f414006afeb2c110e2cab3025c4dcdb69df3a476829d2055d2c98df22).
   Sponsor money goes to the token pool only and earns no share. Token pool: 450 + 1,050 = 1,500.
4. **Check-ins.** One per wallet per UTC day, each with the attester's signature:
   - Ana, for 24 November (day 20781), signed by the script with the attester key, not through
     the server: [`0x7ce64219440253fcef1a08dcd96605dab933601c85d6f982fd698743fb28279b`](https://testnet.bscscan.com/tx/0x7ce64219440253fcef1a08dcd96605dab933601c85d6f982fd698743fb28279b)
   - Ana, for 25 November (day 20782), reported to the server as 6,200 self-reported steps, signed
     by the server: [`0x200be59551d0b69421d0ed1cbfbb41f0a61d02f3c06483e63cdff13395dd6e85`](https://testnet.bscscan.com/tx/0x200be59551d0b69421d0ed1cbfbb41f0a61d02f3c06483e63cdff13395dd6e85)
   - With the bar at 2 of 3, a dry run of `launch()` reverted with `GoalNotReached`. Nothing was sent.
   - Ben, for 25 November, 5,400 self-reported steps, signed by the server:
     [`0xeaf494e7dfdee5bc72de846eca5300ea81d2ec0415911239e8649b718f125635`](https://testnet.bscscan.com/tx/0xeaf494e7dfdee5bc72de846eca5300ea81d2ec0415911239e8649b718f125635)
   - Chai never checked in. Bar: 3 of 3. Days: Ana 2, Ben 1, Chai 0.
5. **Launch.** Ana, an ordinary member wallet, sent `CheckInLauncher.launch()`:
   [`0xe9d53da5e8ce1bc49e859a42a1f55879a6f056fb3a09b5dca8a9aa55e3adb896`](https://testnet.bscscan.com/tx/0xe9d53da5e8ce1bc49e859a42a1f55879a6f056fb3a09b5dca8a9aa55e3adb896) (4,642,852 gas). In that one transaction the Flap Portal created
   the token (1,000,000 supply), seeded the pool with the 1,500 test USD and 500,000 tokens and
   burned the LP tokens, and the StreakVault received the other 500,000 tokens and the 1,050 test USD
   prize (70% of the deposits). The Launcher was left holding nothing.
6. **First claim, straight after the launch.** Ana claimed (`StreakVault.claim`): [`0x31b4626b0035c8cea80de48f8a005bcfb2530d4abaea19eab978462a4244c03a`](https://testnet.bscscan.com/tx/0x31b4626b0035c8cea80de48f8a005bcfb2530d4abaea19eab978462a4244c03a).
   She received 333,333.333333333333333333 tokens and 700 test USD, which is 2/3 of the reserved
   tokens and 2/3 of the prize. There is no settle step and no list.
7. **Trading.** The deployer bought the token with 1,000 test USD and then sold and bought again
   8 times on the PancakeSwap pool (17 swaps; 3% tax on a buy, 5% on a sell). The token sold its
   collected tax into test USD four times, and each time an outside account, `0xB5b631ecfe0417e2F035EB34b6A0d2ab65242a1C`
   (not ours; `dispatch()` on the tax processor is open to anyone), dispatched it within a few
   blocks. The vault received 183.480561266277444141 test USD of tax in four payments:
   [`0x54778067…3e58d5`](https://testnet.bscscan.com/tx/0x54778067929be4eb2767ecaee5f79591147e2d3690afe6fcc37d57a3633e58d5), [`0x10d8a1e6…f2ffcb`](https://testnet.bscscan.com/tx/0x10d8a1e61e9ab0195dcc300158f4551ffd9a1ce5ca23886aac89800c15f2ffcb), [`0x9d225e2a…3407c4`](https://testnet.bscscan.com/tx/0x9d225e2a2678adf11f10a2f5dd2f5493c69deecbb0c0031a8cd18e818c3407c4), [`0x5750643f…44e7ff`](https://testnet.bscscan.com/tx/0x5750643f24f73da0c928ace4ec09527ecc91c343dd7d995375fc9a9cdc44e7ff). The script never had to call `dispatch()` itself.
8. **Claims after the tax.** Ana claimed again and received her 2/3 of the tax, 122.320374177518296094 test
   USD: [`0x66e3bd6755e9ae4e200a8c6cd27519f9dd02694bca9a8e7fb60ab90bd619bbfb`](https://testnet.bscscan.com/tx/0x66e3bd6755e9ae4e200a8c6cd27519f9dd02694bca9a8e7fb60ab90bd619bbfb). Ben claimed for the first time and received
   166,666.666666666666666666 tokens and 411.160187088759148047 test USD: [`0xc55c8913c45082e68fa7c4f3085abf47e19bc0b315eddcfa9e988569d9b97f4c`](https://testnet.bscscan.com/tx/0xc55c8913c45082e68fa7c4f3085abf47e19bc0b315eddcfa9e988569d9b97f4c).
   A dry run of `claim` from Chai's address reverts with `NothingToClaim` (no transaction was sent).

### Result, read from the chain

| Member | Paid | Days | Share | Tokens received | Test USD received | Why |
|---|---|---|---|---|---|---|
| Ana | 500 | 2 | 2/3 | 333,333.333333333333333333 | 822.320374177518296094 | 2 of the 3 check-ins: 700 of the prize in the first claim, 122.320374177518296094 of the tax in the second |
| Ben | 500 | 1 | 1/3 | 166,666.666666666666666666 | 411.160187088759148047 | 1 of the 3 check-ins: 350 of the prize and 61.160187088759148047 of the tax, in one claim |
| Chai | 500 | 0 | none | 0 | 0 | never checked in; a member with no days gets nothing |

The numbers add up as follows.

- Vault received: 1,050 (prize) + 183.480561266277444141 (trading tax) = 1,233.480561266277444141 test USD.
- Vault paid out: 822.320374177518296094 + 411.160187088759148047 = 1,233.480561266277444141 test USD. It holds 0 test USD now.
- Tokens: 500,000 reserved, 499,999.999999999999999999 paid; one smallest unit is left in the vault from rounding.
- The sponsor put in 1,050 test USD and received nothing back; it all went to the pool.
- The token balances and test USD balances of the three member wallets equal the amounts above.

### The server and the chain at each stage

After every stage the script read `GET /api/round` and `GET /api/me/<address>` for the three
members from the hosted server and compared them with its own reads of the chain: members, bar,
goal, deadline, deposits, sponsor money, token pool, launched, token, vault, and per member
membership, days, today's check-in, claimable and claimed amounts. All nine comparisons matched.

| Stage | Time (UTC) | Members | Bar | Launched | Days (Ana, Ben, Chai) | Claimed test USD (Ana, Ben, Chai) | Server = chain |
|---|---|---|---|---|---|---|---|
| round opened and set on the server | 16:29:30 | 0 | 0 of 3 | no | 0, 0, 0 | 0, 0, 0 | yes |
| three members joined | 16:30:01 | 3 | 0 of 3 | no | 0, 0, 0 | 0, 0, 0 | yes |
| sponsor money in | 16:30:15 | 3 | 0 of 3 | no | 0, 0, 0 | 0, 0, 0 | yes |
| Ana's check-in for 24 Nov | 16:30:26 | 3 | 1 of 3 | no | 1, 0, 0 | 0, 0, 0 | yes |
| check-ins for 25 Nov, bar full | 16:30:40 | 3 | 3 of 3 | no | 2, 1, 0 | 0, 0, 0 | yes |
| launched | 16:30:53 | 3 | 3 of 3 | yes | 2, 1, 0 | 0, 0, 0 | yes |
| Ana's first claim | 16:31:06 | 3 | 3 of 3 | yes | 2, 1, 0 | 700, 0, 0 | yes |
| after the trading tax arrived | 16:33:48 | 3 | 3 of 3 | yes | 2, 1, 0 | 700, 0, 0 | yes |
| after the final claims | 16:34:05 | 3 | 3 of 3 | yes | 2, 1, 0 | 822.320374177518296094, 411.160187088759148047, 0 | yes |

The server's own list of accepted days shows only 25 November for Ana, because her 24 November
check-in never went through it; its `daysOf` comes from the chain and shows 2.

### Every transaction, in order

43 transactions sent by the script and the 4 dispatches sent by the outside account. All 47 have
status success. Sender names: deployer `0xc1bD6aC9311b9345ae8023201875518429c8BF58`, Ana, Ben and Chai as above.

| # | Time (UTC) | Block | Sent by | What | Transaction |
|---|---|---|---|---|---|
| 1 | 16:29:19 | 144820125 | deployer | Portal.newLauncher (the deployer opens the round) | [`0xfe0ee10e…b2c33e`](https://testnet.bscscan.com/tx/0xfe0ee10e28b81bd8ac788656209a623b1da3bbc567e046fe640834b59db2c33e) |
| 2 | 16:29:32 | 144820153 | deployer | test BNB for gas to Ana | [`0x2bb3e67e…2f4fba`](https://testnet.bscscan.com/tx/0x2bb3e67efab06cf55ff4eb190bf3e12ef5b180cf22fd76032ff2c03c402f4fba) |
| 3 | 16:29:34 | 144820158 | deployer | mint 500 test USD to Ana | [`0x3373d51c…9a718c`](https://testnet.bscscan.com/tx/0x3373d51c0df3841a902d91484828aed3b2116243a05d3a2bb6058fbc909a718c) |
| 4 | 16:29:36 | 144820162 | Ana | Ana approves the Launcher for the deposit | [`0x3c872bce…837780`](https://testnet.bscscan.com/tx/0x3c872bcedc830090d1c3246618067efd661144ca425af459fc0f96a699837780) |
| 5 | 16:29:37 | 144820165 | Ana | Ana pays the deposit (CheckInLauncher.join) | [`0xea83ffad…4e0e44`](https://testnet.bscscan.com/tx/0xea83ffad1768468df81fe57b11ac388171dfc6c76c4942af221e97a1514e0e44) |
| 6 | 16:29:39 | 144820170 | deployer | test BNB for gas to Ben | [`0x5259c6dd…eb1bf6`](https://testnet.bscscan.com/tx/0x5259c6dd0e63666c97c1e5c2ded5a4fe4825f61b3a4cbe935bb8626cb3eb1bf6) |
| 7 | 16:29:41 | 144820175 | deployer | mint 500 test USD to Ben | [`0x9fb50988…6aac31`](https://testnet.bscscan.com/tx/0x9fb50988c109d55bd61b8b755a1e15314082b42dc0113dcfcf81c1e8276aac31) |
| 8 | 16:29:43 | 144820179 | Ben | Ben approves the Launcher for the deposit | [`0x3772449c…a10db3`](https://testnet.bscscan.com/tx/0x3772449c7c0978ee1c43d7571558d87c73b88f32c2ab6a4db38896353fa10db3) |
| 9 | 16:29:45 | 144820183 | Ben | Ben pays the deposit (CheckInLauncher.join) | [`0x4fd7c833…490e28`](https://testnet.bscscan.com/tx/0x4fd7c833059350ea9f95c33ad12214ba81e468e6307e50c03f5227aca2490e28) |
| 10 | 16:29:47 | 144820187 | deployer | test BNB for gas to Chai | [`0xf834ad35…20614b`](https://testnet.bscscan.com/tx/0xf834ad35b4f4424ad425efaaa0d7be1120f036c95bf9ec55275511dc2f20614b) |
| 11 | 16:29:49 | 144820192 | deployer | mint 500 test USD to Chai | [`0x18b81da5…cf1ae6`](https://testnet.bscscan.com/tx/0x18b81da556dc4cc1b825ebb2d3caf5d75ba8251360413f7bbf1a24da88cf1ae6) |
| 12 | 16:29:51 | 144820196 | Chai | Chai approves the Launcher for the deposit | [`0x24898f53…ab2913`](https://testnet.bscscan.com/tx/0x24898f539039ca1bcaac4516497021164e05604e90f5615f8a8379f3aaab2913) |
| 13 | 16:29:53 | 144820201 | Chai | Chai pays the deposit (CheckInLauncher.join) | [`0x9606a21e…e9f6d2`](https://testnet.bscscan.com/tx/0x9606a21ec238059ae236345f733476b1aac48e74d8ad76e09695d7e2fce9f6d2) |
| 14 | 16:30:03 | 144820223 | deployer | mint 1050 test USD to the sponsor | [`0x64542994…9bb53b`](https://testnet.bscscan.com/tx/0x6454299425ea34cb3b33d40c30ccb28074bd7c0edca6f6a02ce28ee2239bb53b) |
| 15 | 16:30:05 | 144820227 | deployer | the sponsor approves the Launcher | [`0x2139dc52…800a96`](https://testnet.bscscan.com/tx/0x2139dc52053ea9fcf2bc289c3b9c649be9d056d3c107fb3ac9ba25670d800a96) |
| 16 | 16:30:07 | 144820231 | deployer | CheckInLauncher.sponsor(1050 test USD): pool only, no share | [`0xc080cf7f…98df22`](https://testnet.bscscan.com/tx/0xc080cf7f414006afeb2c110e2cab3025c4dcdb69df3a476829d2055d2c98df22) |
| 17 | 16:30:17 | 144820255 | Ana | Ana checks in for yesterday (CheckInLauncher.checkIn, day 20781) | [`0x7ce64219…28279b`](https://testnet.bscscan.com/tx/0x7ce64219440253fcef1a08dcd96605dab933601c85d6f982fd698743fb28279b) |
| 18 | 16:30:28 | 144820279 | Ana | Ana checks in (CheckInLauncher.checkIn, day 20782) | [`0x200be595…dd6e85`](https://testnet.bscscan.com/tx/0x200be59551d0b69421d0ed1cbfbb41f0a61d02f3c06483e63cdff13395dd6e85) |
| 19 | 16:30:31 | 144820285 | Ben | Ben checks in (CheckInLauncher.checkIn, day 20782) | [`0xeaf494e7…125635`](https://testnet.bscscan.com/tx/0xeaf494e7dfdee5bc72de846eca5300ea81d2ec0415911239e8649b718f125635) |
| 20 | 16:30:42 | 144820309 | Ana | Ana sends CheckInLauncher.launch (the Flap launch) | [`0xe9d53da5…adb896`](https://testnet.bscscan.com/tx/0xe9d53da5e8ce1bc49e859a42a1f55879a6f056fb3a09b5dca8a9aa55e3adb896) |
| 21 | 16:30:54 | 144820336 | Ana | Ana claims (StreakVault.claim) | [`0x31b4626b…44c03a`](https://testnet.bscscan.com/tx/0x31b4626b0035c8cea80de48f8a005bcfb2530d4abaea19eab978462a4244c03a) |
| 22 | 16:31:08 | 144820366 | deployer | mint 1000 test USD to the trader | [`0xcbcf5e39…63223d`](https://testnet.bscscan.com/tx/0xcbcf5e393014d17448738c34f17a29131bb67d3503ed558aaf6db1ff0d63223d) |
| 23 | 16:31:09 | 144820369 | deployer | trader approves the router for test USD | [`0xc198b1ff…a3588c`](https://testnet.bscscan.com/tx/0xc198b1ff2799dbdde88c8b7c40c78de30df3eee300368a85842b0dd257a3588c) |
| 24 | 16:31:11 | 144820373 | deployer | trader approves the router for the token | [`0xa3643419…711f39`](https://testnet.bscscan.com/tx/0xa36434195480ac309b481fcb985b502b02988fbc9ab70edde7ea4fa948711f39) |
| 25 | 16:31:13 | 144820377 | deployer | buy the token with 1000 test USD (3% tax) | [`0x552ccdfe…66e67b`](https://testnet.bscscan.com/tx/0x552ccdfe8e67471e60668566da604dfcd5e5e70f3e7f16087e67a3353966e67b) |
| 26 | 16:31:16 | 144820385 | deployer | sell 30% of the tokens (5% tax), round 1 | [`0xd064cbf4…42564f`](https://testnet.bscscan.com/tx/0xd064cbf414655f9f085e016e8c10f3b9b6ca47394cd1efe434f0120e2642564f) |
| 27 | 16:31:19 | 144820391 | deployer | buy again with test USD (3% tax), round 1 | [`0xe7c1c6de…fe3390`](https://testnet.bscscan.com/tx/0xe7c1c6dec798c8bc9163372ec2ab47a7dde0520825140ad6b1c4769711fe3390) |
| 28 | 16:31:19 | 144820391 | outside account | **Not ours.** `dispatch` of the tax processor through contract `0x9eaFA518617880D4D9e472D7A29a96842FFc3aee`: 37.173735354404480852 test USD of tax paid to the vault | [`0x54778067…3e58d5`](https://testnet.bscscan.com/tx/0x54778067929be4eb2767ecaee5f79591147e2d3690afe6fcc37d57a3633e58d5) |
| 29 | 16:31:22 | 144820397 | deployer | sell 30% of the tokens (5% tax), round 2 | [`0xd8fd6803…da826d`](https://testnet.bscscan.com/tx/0xd8fd6803db409fe6d8c502dee91da5592f032fb1edeb913ebc09d3a114da826d) |
| 30 | 16:31:24 | 144820403 | deployer | buy again with test USD (3% tax), round 2 | [`0x76825643…cf7033`](https://testnet.bscscan.com/tx/0x7682564305be70204afb7043ea3892984687cbf09b927281c457465dbccf7033) |
| 31 | 16:31:28 | 144820411 | deployer | sell 30% of the tokens (5% tax), round 3 | [`0x59891c15…60f18d`](https://testnet.bscscan.com/tx/0x59891c151fb259d4f5033246858fca4b57edf8d7f7ef48c923aa4b7ab360f18d) |
| 32 | 16:31:29 | 144820413 | outside account | **Not ours.** `dispatch` of the tax processor through contract `0x9eaFA518617880D4D9e472D7A29a96842FFc3aee`: 53.54428161520104926 test USD of tax paid to the vault | [`0x10d8a1e6…f2ffcb`](https://testnet.bscscan.com/tx/0x10d8a1e61e9ab0195dcc300158f4551ffd9a1ce5ca23886aac89800c15f2ffcb) |
| 33 | 16:31:31 | 144820417 | deployer | buy again with test USD (3% tax), round 3 | [`0x78b9d41f…bc5e57`](https://testnet.bscscan.com/tx/0x78b9d41f07b62caafabfe881e1e67cbc6cb1355e4b00a9324f262af355bc5e57) |
| 34 | 16:31:33 | 144820423 | deployer | sell 30% of the tokens (5% tax), round 4 | [`0x9b91a310…508fac`](https://testnet.bscscan.com/tx/0x9b91a310bab4a505639431ba11d2c3fdd9670408b382e6422ba5b18666508fac) |
| 35 | 16:31:35 | 144820427 | deployer | buy again with test USD (3% tax), round 4 | [`0x6c779407…df61be`](https://testnet.bscscan.com/tx/0x6c779407b6f3fcb727f4aeefc2197711ce55c80b2cb0dc7e31dc51291cdf61be) |
| 36 | 16:31:39 | 144820436 | deployer | sell 30% of the tokens (5% tax), round 5 | [`0xe22feed3…6d2404`](https://testnet.bscscan.com/tx/0xe22feed381c457056734d8b068a75f42c6204002f77f784125560ff0d66d2404) |
| 37 | 16:31:42 | 144820442 | deployer | buy again with test USD (3% tax), round 5 | [`0x5d4cf81f…0e42d6`](https://testnet.bscscan.com/tx/0x5d4cf81f20141e6bd4524d469b891c6dffab8a6b70a342930bdd9ab6610e42d6) |
| 38 | 16:31:42 | 144820442 | outside account | **Not ours.** `dispatch` of the tax processor through contract `0x9eaFA518617880D4D9e472D7A29a96842FFc3aee`: 48.565917682085283203 test USD of tax paid to the vault | [`0x9d225e2a…3407c4`](https://testnet.bscscan.com/tx/0x9d225e2a2678adf11f10a2f5dd2f5493c69deecbb0c0031a8cd18e818c3407c4) |
| 39 | 16:31:45 | 144820448 | deployer | sell 30% of the tokens (5% tax), round 6 | [`0x623c3fdd…2ba945`](https://testnet.bscscan.com/tx/0x623c3fddaec020f77c6978732eee89e670f15a9b0eac9e750da14a2db92ba945) |
| 40 | 16:31:47 | 144820453 | deployer | buy again with test USD (3% tax), round 6 | [`0xea93c678…57e109`](https://testnet.bscscan.com/tx/0xea93c678382755632475b0e54961738e7ae06da1d7ff56ed5366e19b4c57e109) |
| 41 | 16:31:50 | 144820459 | deployer | sell 30% of the tokens (5% tax), round 7 | [`0x7037ad62…d9075c`](https://testnet.bscscan.com/tx/0x7037ad62e22c471ea83391fe2cadafde95bed157608cf692212c4a09ecd9075c) |
| 42 | 16:31:52 | 144820464 | deployer | buy again with test USD (3% tax), round 7 | [`0x4b0ccffb…2eae51`](https://testnet.bscscan.com/tx/0x4b0ccffbbb9c4052f3ab143ccc65f59404c6dbf33689e211918a076d722eae51) |
| 43 | 16:31:52 | 144820465 | outside account | **Not ours.** `dispatch` of the tax processor through contract `0x9eaFA518617880D4D9e472D7A29a96842FFc3aee`: 44.196626614586630826 test USD of tax paid to the vault | [`0x5750643f…44e7ff`](https://testnet.bscscan.com/tx/0x5750643f24f73da0c928ace4ec09527ecc91c343dd7d995375fc9a9cdc44e7ff) |
| 44 | 16:31:55 | 144820471 | deployer | sell 30% of the tokens (5% tax), round 8 | [`0x0562aee1…d6e0a4`](https://testnet.bscscan.com/tx/0x0562aee1526a6296bb2841fbcc09da23e2e449e12ab67bd34b44304a14d6e0a4) |
| 45 | 16:31:57 | 144820476 | deployer | buy again with test USD (3% tax), round 8 | [`0xf6086e8c…8ae507`](https://testnet.bscscan.com/tx/0xf6086e8c0399622bac87d00aa608130cecef95c7b9dfc99a67df74f13d8ae507) |
| 46 | 16:33:50 | 144820726 | Ana | Ana claims (StreakVault.claim) | [`0x66e3bd67…19bbfb`](https://testnet.bscscan.com/tx/0x66e3bd6755e9ae4e200a8c6cd27519f9dd02694bca9a8e7fb60ab90bd619bbfb) |
| 47 | 16:33:52 | 144820731 | Ben | Ben claims (StreakVault.claim) | [`0xc55c8913…b97f4c`](https://testnet.bscscan.com/tx/0xc55c8913c45082e68fa7c4f3085abf47e19bc0b315eddcfa9e988569d9b97f4c) |

## Round 2: Demo Day (open)

Left open on purpose, so that people can join, check in and send the launch from the hosted app.
It was set as the hosted server's featured round (`GET /api/round`). The table below is as it was on
25 November; what it read on 26 November is under "Read on 26 Nov 2026".

| | |
|---|---|
| **Launcher (this round)** | [`0x378d729aE7122e5Cf7d6f4ed8797710d2503EDb5`](https://testnet.bscscan.com/address/0x378d729aE7122e5Cf7d6f4ed8797710d2503EDb5) |
| Deposit | 500 test USD |
| Part of the deposits that seeds the pool | 30% |
| Bar (`checkInGoal`) | 5 check-ins |
| Bar then | **2 of 5** (read from the chain at 2026-11-25 16:42:14 UTC); 4 of 5 on 26 Nov |
| Members then | 2 (6 on 26 Nov): Ana [`0x7a38081096343B6A41109EF75ccE97863C21EB04`](https://testnet.bscscan.com/address/0x7a38081096343B6A41109EF75ccE97863C21EB04) and Ben [`0x71a60c1e46d74b08ba12197D8f568D1AEB664E58`](https://testnet.bscscan.com/address/0x71a60c1e46d74b08ba12197D8f568D1AEB664E58) (throwaway wallets of the script) |
| Sponsor | the deployer wallet, 1,500 test USD |
| Token pool if launched then | 1,800 test USD (1,500 sponsor + 30% of 1,000), already above Flap's 1,500 (2,400 on 26 Nov) |
| Prize if launched then | 700 test USD (2,100 on 26 Nov) |
| Opened | 2026-11-25 16:34:21 UTC |
| Deadline | 2026-11-28 16:34:21 UTC (Sat 28 Nov 2026 23:34 Bangkok) |
| Token | none yet: it exists only after somebody sends `launch()` with a full bar |

Both check-ins are self-reported test entries for 25 November made by the script and signed by the
hosted server. Three more check-ins filled the bar then (one more on 26 November); one wallet can check in once per UTC day (a new
day starts at 07:00 in Bangkok). After the deadline without a launch, everyone can take their money
back with `refund()`.

The server matched the chain at each stage of this round too:

| Stage | Time (UTC) | Members | Bar | Launched | Days (Ana, Ben) | Claimed test USD (Ana, Ben) | Server = chain |
|---|---|---|---|---|---|---|---|
| round opened and set on the server | 16:34:34 | 0 | 0 of 5 | no | 0, 0 | 0, 0 | yes |
| two members joined | 16:34:57 | 2 | 0 of 5 | no | 0, 0 | 0, 0 | yes |
| sponsor money in | 16:35:10 | 2 | 0 of 5 | no | 0, 0 | 0, 0 | yes |
| check-ins for 25 Nov | 16:35:24 | 2 | 2 of 5 | no | 1, 1 | 0, 0 | yes |

### Every transaction so far, in order

All 14 have status success.

| # | Time (UTC) | Block | Sent by | What | Transaction |
|---|---|---|---|---|---|
| 1 | 16:34:25 | 144820804 | deployer | Portal.newLauncher (the deployer opens the round) | [`0xf514f8da…94bc78`](https://testnet.bscscan.com/tx/0xf514f8dac4bdafd6f0c9a02590310740b6e2d4d619894f721583d523d294bc78) |
| 2 | 16:34:36 | 144820828 | deployer | test BNB for gas to Ana | [`0x128989a8…790230`](https://testnet.bscscan.com/tx/0x128989a8b0ec4d5c0b9865a106b7728a2927726088f00ffc629ccabd9c790230) |
| 3 | 16:34:39 | 144820835 | deployer | mint 500 test USD to Ana | [`0xf42a62d0…182ca7`](https://testnet.bscscan.com/tx/0xf42a62d09c089fa504812f89ecf28e0cfb986b6fc59627d3ae9a7b62ed182ca7) |
| 4 | 16:34:41 | 144820840 | Ana | Ana approves the Launcher for the deposit | [`0x264c5dd2…190b1b`](https://testnet.bscscan.com/tx/0x264c5dd29e7eacd57f405a23afdbd5f21078cbc33fa7488b7679ebf765190b1b) |
| 5 | 16:34:43 | 144820844 | Ana | Ana pays the deposit (CheckInLauncher.join) | [`0xf6321160…524f77`](https://testnet.bscscan.com/tx/0xf632116030d8037ad373f213bed1a1cb240dec46a9272226e448fa36c9524f77) |
| 6 | 16:34:45 | 144820849 | deployer | test BNB for gas to Ben | [`0x7d79e6e8…23f43f`](https://testnet.bscscan.com/tx/0x7d79e6e8e71f08ebfdc9eb8d90979af75e5b18ef24d2d3075914426c7623f43f) |
| 7 | 16:34:48 | 144820854 | deployer | mint 500 test USD to Ben | [`0x59f5eed4…d9cf27`](https://testnet.bscscan.com/tx/0x59f5eed47c214a3c973d49adf00477f520bef81b9c860a748501b2768fd9cf27) |
| 8 | 16:34:49 | 144820857 | Ben | Ben approves the Launcher for the deposit | [`0xd12df5c5…8b3dda`](https://testnet.bscscan.com/tx/0xd12df5c52f54f8c202c1cd99f76cc5a3c77e94e48a2b5c61b8a0a26ab48b3dda) |
| 9 | 16:34:51 | 144820862 | Ben | Ben pays the deposit (CheckInLauncher.join) | [`0x1fba7a2b…efe4fd`](https://testnet.bscscan.com/tx/0x1fba7a2bc0e2c9f08ea7f942fd97dcae718c346580ae1e1dc82fb9fda7efe4fd) |
| 10 | 16:34:59 | 144820879 | deployer | mint 1500 test USD to the sponsor | [`0x7c29a088…bd2020`](https://testnet.bscscan.com/tx/0x7c29a08825d6b245ea067d80b61ae7d79a84f0aa734a3857cea22b7bbabd2020) |
| 11 | 16:35:01 | 144820883 | deployer | the sponsor approves the Launcher | [`0xfaf96dc3…cebe14`](https://testnet.bscscan.com/tx/0xfaf96dc3838e3f9a0360af1d802c1db6c91183ab5c4e0302f6f1c34ca6cebe14) |
| 12 | 16:35:03 | 144820887 | deployer | CheckInLauncher.sponsor(1500 test USD): pool only, no share | [`0x4c66f1c4…c1c9e6`](https://testnet.bscscan.com/tx/0x4c66f1c4e27f4a78928098c1b84882c666a7cc5d1ea865b39e90b0a893c1c9e6) |
| 13 | 16:35:13 | 144820910 | Ana | Ana checks in (CheckInLauncher.checkIn, day 20782) | [`0x8dd90b97…945c2e`](https://testnet.bscscan.com/tx/0x8dd90b97132f536974cd6270601167ddb3963fac08b3b04abbe0bac658945c2e) |
| 14 | 16:35:16 | 144820916 | Ben | Ben checks in (CheckInLauncher.checkIn, day 20782) | [`0xb11356ce…16618d`](https://testnet.bscscan.com/tx/0xb11356cef0d10ee82e89fdd8a488d7ecd8552649511a6fee2a72fd0a8a16618d) |

## How to repeat or continue

```sh
cd verifier

# <host>: the server's current host, from
#   cast call 0xb9aD45Dc177C801f10670F2aac03B467f1C367d2 "origin()(string)" --rpc-url https://bsc-testnet-rpc.publicnode.com

# Round 1 as it was run (a new round each time; delete scripts/round-run.json first)
VERIFIER_URL=https://<host>/api ROUND_NAME="Bangkok Showup" DEPOSIT_USD=500 \
  CHECKIN_GOAL=3 YESTERDAY_CHECKIN=true npx tsx ../scripts/run-round.ts

# Round 2 as it was opened
VERIFIER_URL=https://<host>/api STATE_FILE=../scripts/demo-day-run.json ROUND_NAME="Demo Day" \
  ROUND_SYMBOL=<symbol> DEPOSIT_USD=500 CHECKIN_GOAL=5 MEMBER_COUNT=2 SPONSOR_USD=1500 DEADLINE_HOURS=72 \
  npx tsx ../scripts/run-round.ts

# Round 2 again later: on a new UTC day it adds Ana's check-in for that day, and once somebody has
# launched it does the trading and the claims
VERIFIER_URL=https://<host>/api STATE_FILE=../scripts/demo-day-run.json npx tsx ../scripts/run-round.ts
```

The records behind this page are `scripts/round-run.json` and `scripts/round-result.json` (round 1)
and `scripts/demo-day-run.json` (round 2): addresses and transaction hashes only, no keys.

## Not checked

- The hosted web app was not clicked through against round 2 by a person on 25 November; the server
  and the chain were compared by script only. The four later joins and two later check-ins in round 2
  (26 Nov reads above) came from other wallets; which were people and which tests was not recorded.
- No check-in in either round came from a phone's health data.
- The outside account that dispatched the tax is assumed to be a Flap service; that was not confirmed.
  If it stops, anyone can call `dispatch()` on the tax processor, and `scripts/run-round.ts` does so
  when it finds money waiting there.
- `refund()` was not exercised on testnet (it needs a round whose deadline has passed).
- The Flap page of the round 1 token was opened once in a browser and showed the token, its trades
  and 6 holders. Flap's testnet site is `abc.flap.sh`; the address `flap.sh/bnb-testnet/<token>`
  answers "page not found".

## Earlier design: one club season

Before the product was simplified to what is now Cypher Run, an earlier design (running club seasons, a kickoff
sent by our server and a settle step) also ran one complete season on BSC testnet on 25 November
2026, through the same Flap Portal call, on other contracts.

| | |
|---|---|
| Launcher of that season (`ClubLauncher`) | [`0xB06C603F7c09806bf83d14fAE20372385cB13b90`](https://testnet.bscscan.com/address/0xB06C603F7c09806bf83d14fAE20372385cB13b90) |
| Its token | [`0xecb984A239F0528934b693DA22820f405Ec17777`](https://testnet.bscscan.com/address/0xecb984A239F0528934b693DA22820f405Ec17777) |
| Its factory (`ClubLauncherFactory`) | [`0x6dd91a33E3599b559b57a3045C55c4E1D0c76445`](https://testnet.bscscan.com/address/0x6dd91a33E3599b559b57a3045C55c4E1D0c76445) |

The full record of that season, with every transaction, is kept in
[docs/archive/PROOF-club-season.md](docs/archive/PROOF-club-season.md).
