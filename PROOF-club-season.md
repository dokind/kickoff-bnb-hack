# Proof: one complete club season on BSC testnet

> **This page is about the earlier design** (running club seasons: `ClubLauncher`, `GoalVault`, a
> kickoff sent by our server and a settle step). It is kept as the record of a full launch through
> the Flap Portal on testnet. The product is now Cypher Run (see [README.md](README.md)); its contracts
> are new and are deployed at other addresses. The rounds run with them are in [PROOF.md](PROOF.md).

A full season of that earlier design (its working name was "Pacepact"), run on 25 November 2026 against the factories deployed for it and the hosted
verifier (https://columbus-authentication-spine-cuts.trycloudflare.com/api). BSC testnet only (chain 97), test BNB and test USD with no value.

**What makes the launch new:** a full raise does not launch the club token. The token only launches
through Flap after the club has run its warm-up distance together, and our server, the verifier,
is the one that decides the distance was reached and sends `kickoff()`.

**Read this first.** Everything on chain below is real and can be checked on testnet.bscscan.com.
The running distances are not: they are test reports made by `scripts/run-season.ts`, signed by
three throwaway wallets and sent to the verifier the same way the app sends a health sync. Nobody
ran them. The verifier (our server) judges runs; in this season it judged test reports.

## The season

| | |
|---|---|
| Name | Bangkok Demo Run |
| Join fee | 500 test USD, 3 places, target 1,500 test USD |
| Goals measured in | km |
| Club warm-up | 12 km |
| Opened | 2026-11-25 10:58:34 UTC |
| Last moment to start | 2026-11-25 11:18:34 UTC |
| Season end | 2026-11-25 11:21:34 UTC |

## Addresses

| What | Address |
|---|---|
| ClubLauncherFactory (ours) | [0x6dd91a33E3599b559b57a3045C55c4E1D0c76445](https://testnet.bscscan.com/address/0x6dd91a33E3599b559b57a3045C55c4E1D0c76445) |
| GoalVaultFactory (ours) | [0xB7D522d6cDA92b4dBF6B24E37e16c24C0D5bFC99](https://testnet.bscscan.com/address/0xB7D522d6cDA92b4dBF6B24E37e16c24C0D5bFC99) |
| Flap Portal | [0x000042108465206185A077Edc3F3fd2b49060000](https://testnet.bscscan.com/address/0x000042108465206185A077Edc3F3fd2b49060000) |
| Launcher (this season) | [0xB06C603F7c09806bf83d14fAE20372385cB13b90](https://testnet.bscscan.com/address/0xB06C603F7c09806bf83d14fAE20372385cB13b90) |
| Club token | [0xecb984A239F0528934b693DA22820f405Ec17777](https://testnet.bscscan.com/address/0xecb984A239F0528934b693DA22820f405Ec17777) |
| PancakeSwap pool | [0xCFd6ea9EC937b8C8bAFB631c7F620D5C5CB95FFA](https://testnet.bscscan.com/address/0xCFd6ea9EC937b8C8bAFB631c7F620D5C5CB95FFA) |
| GoalVault | [0x0f29643729FF2d6Fd0726a4e26A31F084007A6bD](https://testnet.bscscan.com/address/0x0f29643729FF2d6Fd0726a4e26A31F084007A6bD) |
| Tax processor of the token | [0xC5A05C45aaaB82Cd57EDfbc35CB5EBA0CbD82d30](https://testnet.bscscan.com/address/0xC5A05C45aaaB82Cd57EDfbc35CB5EBA0CbD82d30) |
| Test USD (join fee and pool quote) | [0x190C989D5665a0e404B444b53CAE9AbCfb600157](https://testnet.bscscan.com/address/0x190C989D5665a0e404B444b53CAE9AbCfb600157) |
| PancakeSwap V2 router | [0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3](https://testnet.bscscan.com/address/0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3) |
| Captain, also the trader (deployer wallet) | [0xc1bD6aC9311b9345ae8023201875518429c8BF58](https://testnet.bscscan.com/address/0xc1bD6aC9311b9345ae8023201875518429c8BF58) |
| Verifier (our server) | [0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7](https://testnet.bscscan.com/address/0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7) |
| Member Ana | [0x0A6490259cc6dE1698f920f047be70FFDc246ddE](https://testnet.bscscan.com/address/0x0A6490259cc6dE1698f920f047be70FFDc246ddE) |
| Member Ben | [0x97738DE8A10947b36A4fCBE473d3E507D1d64382](https://testnet.bscscan.com/address/0x97738DE8A10947b36A4fCBE473d3E507D1d64382) |
| Member Chai | [0x49D11A6a6c8CadEEAC4756E9A1B0d422208C1325](https://testnet.bscscan.com/address/0x49D11A6a6c8CadEEAC4756E9A1B0d422208C1325) |

## What happened

1. The captain opened the season with `Portal.newLauncher` and our ClubLauncherFactory.
2. Ana, Ben and Chai each paid the 500 test USD join fee (`contribute`). After the third join the
   raise was full and nothing had launched: no token existed yet.
3. Warm-up. With 9.3 of 12 km reported, the verifier was asked to start the season and refused
   (HTTP 409 `club_total_short`, no transaction). After Ben reported, the club total was 14.7 km.
4. The verifier sent `ClubLauncher.kickoff()`. In that one transaction the Flap Portal created the
   club token, seeded the pool with the 1,500 test USD and half the supply, and created the
   GoalVault holding the other half (500,000 tokens).
5. The trader bought and sold the club token on the pool (1,000 test USD buy, then four sell and
   buy rounds). After `dispatch()` the vault held 115.549566061557097588 test USD of trading tax.
6. After the season end the verifier sent `GoalVault.settle` with 2 finishers, Merkle root
   `0x227b87b39babd9f3f4e10c8dd33e4371ad880989c811133416cdc99da171ad50`.
7. Ana and Ben claimed. Chai did not reach the goal: a dry run of `claim` from Chai's address
   reverts with `NotFinisher` (no transaction was sent for it).

## Result, read from the chain

| Member | Goal | Reported | Reached goal | Claimed (`GoalVault.claimed`) | Club tokens received | Test USD received |
|---|---|---|---|---|---|---|
| Ana | 5 km | 6.2 km | yes | true | 250000 | 57.774783030778548794 |
| Ben | 5 km | 5.4 km | yes | true | 250000 | 57.774783030778548794 |
| Chai | 10 km | 3.1 km | no | false | 0 | 0 |

Vault: 3 members, 2 finishers, 500000 club tokens reserved, 115.549566061557097588 test USD of tax
received. Each finisher's share is half of both. "Goal" and "Reported" are the verifier's records;
the other columns are on chain.

The hosted verifier lists the season at `GET https://columbus-authentication-spine-cuts.trycloudflare.com/api/seasons/past` with 3 members, 2 finishers,
250000 club tokens and 57.774783030778548794 test USD per finisher, and the settle transaction.
The app's "Past seasons" screen reads that list.

## Every transaction, in order

All are legacy transactions at 1 gwei.

| # | What | Sent by | Transaction |
|---|---|---|---|
| 1 | Portal.newLauncher (captain opens the season) | captain | [0x035ed4ae1b245e3e746f37e56ea3e65b1345bcdce3822aef81bca786d7dd7959](https://testnet.bscscan.com/tx/0x035ed4ae1b245e3e746f37e56ea3e65b1345bcdce3822aef81bca786d7dd7959) |
| 2 | test BNB for gas to Ana | captain | [0x239e6ecc8e9ed5cc587ba25c57bfb1f906177607ae2332cee3025d8fd28b0c0d](https://testnet.bscscan.com/tx/0x239e6ecc8e9ed5cc587ba25c57bfb1f906177607ae2332cee3025d8fd28b0c0d) |
| 3 | mint 500 test USD to Ana | captain | [0xa98b55c8aac96ce48d6eebd2d2e8996da6f676e28f991b676ee88eb573720bab](https://testnet.bscscan.com/tx/0xa98b55c8aac96ce48d6eebd2d2e8996da6f676e28f991b676ee88eb573720bab) |
| 4 | Ana approves the launcher for 500 test USD | Ana | [0x7ab3d277018ee7c2224ee77da0387b46871f07aecb0f844bf9a8487639f375f8](https://testnet.bscscan.com/tx/0x7ab3d277018ee7c2224ee77da0387b46871f07aecb0f844bf9a8487639f375f8) |
| 5 | Ana joins (ClubLauncher.contribute) | Ana | [0x4b1e5b3fc87cda89a4fa688c8da323c47dd0c8a27c159cdf00a6f88a6f7972c6](https://testnet.bscscan.com/tx/0x4b1e5b3fc87cda89a4fa688c8da323c47dd0c8a27c159cdf00a6f88a6f7972c6) |
| 6 | test BNB for gas to Ben | captain | [0x60b83c10f4aff046c050fb54695012cbcd0e98b4327d40168c8b12fca6076f33](https://testnet.bscscan.com/tx/0x60b83c10f4aff046c050fb54695012cbcd0e98b4327d40168c8b12fca6076f33) |
| 7 | mint 500 test USD to Ben | captain | [0x1affdf594c06e7e29854fee3d19777ccf948213b563d444146191c75725f6b1f](https://testnet.bscscan.com/tx/0x1affdf594c06e7e29854fee3d19777ccf948213b563d444146191c75725f6b1f) |
| 8 | Ben approves the launcher for 500 test USD | Ben | [0x6f76a1c1d750ff88cfb8cb84f17a2db32535f3af6006b976c6bdf9410efc6a92](https://testnet.bscscan.com/tx/0x6f76a1c1d750ff88cfb8cb84f17a2db32535f3af6006b976c6bdf9410efc6a92) |
| 9 | Ben joins (ClubLauncher.contribute) | Ben | [0x0cbb39226b26f444d7d5331a41e6480d8bfd8e6e6c3a52e6a4784d30fddbdb77](https://testnet.bscscan.com/tx/0x0cbb39226b26f444d7d5331a41e6480d8bfd8e6e6c3a52e6a4784d30fddbdb77) |
| 10 | test BNB for gas to Chai | captain | [0x4845d8858407044bdebb49304f092ea031531397596c946ae7173248aa890925](https://testnet.bscscan.com/tx/0x4845d8858407044bdebb49304f092ea031531397596c946ae7173248aa890925) |
| 11 | mint 500 test USD to Chai | captain | [0xf386838b94fbe84d4bc5925fcfe2c18081124f91dc078012aa1065acf4c804ab](https://testnet.bscscan.com/tx/0xf386838b94fbe84d4bc5925fcfe2c18081124f91dc078012aa1065acf4c804ab) |
| 12 | Chai approves the launcher for 500 test USD | Chai | [0x46433a278c8ef8f87334fc843c982eae80df6d5f13a9b0c279c05d860c003c26](https://testnet.bscscan.com/tx/0x46433a278c8ef8f87334fc843c982eae80df6d5f13a9b0c279c05d860c003c26) |
| 13 | Chai joins (ClubLauncher.contribute) | Chai | [0x333c364b453bd9932e5e99f8340cf19c8bf2df008ea460250514c5a72d4bdbe6](https://testnet.bscscan.com/tx/0x333c364b453bd9932e5e99f8340cf19c8bf2df008ea460250514c5a72d4bdbe6) |
| 14 | ClubLauncher.kickoff (sent by the verifier: the Flap launch) | verifier | [0x58ffc9173a954d0c87a678f112c3d2f73074f561084a8ead77833b726cfa5b01](https://testnet.bscscan.com/tx/0x58ffc9173a954d0c87a678f112c3d2f73074f561084a8ead77833b726cfa5b01) |
| 15 | mint 1000 test USD to the trader | captain | [0xc545285486d72d6d253f6d70a5de140808d2939927bf89f2e4536e10496dceb2](https://testnet.bscscan.com/tx/0xc545285486d72d6d253f6d70a5de140808d2939927bf89f2e4536e10496dceb2) |
| 16 | trader approves the router for test USD | captain | [0x2fcced69ac3d189e01234cdaa695035dae4255ed68855c578e82ec32185ebd8e](https://testnet.bscscan.com/tx/0x2fcced69ac3d189e01234cdaa695035dae4255ed68855c578e82ec32185ebd8e) |
| 17 | trader approves the router for the club token | captain | [0xe750802cff1f18f787abb3af12f3f1d88d0b58d74441b565d678fdd9ad13bd5a](https://testnet.bscscan.com/tx/0xe750802cff1f18f787abb3af12f3f1d88d0b58d74441b565d678fdd9ad13bd5a) |
| 18 | buy the club token with 1000 test USD (3% tax) | captain | [0xcaf76e30987a46e60df33ec17c917f3b2a7eac761e28ba129699e8c833b41f80](https://testnet.bscscan.com/tx/0xcaf76e30987a46e60df33ec17c917f3b2a7eac761e28ba129699e8c833b41f80) |
| 19 | sell 30% of the club tokens (5% tax), round 1 | captain | [0x4a1ca99f3a88e8bf68b3c846f243dbb7cb4febfcd8781b1181e34c8d7e032c93](https://testnet.bscscan.com/tx/0x4a1ca99f3a88e8bf68b3c846f243dbb7cb4febfcd8781b1181e34c8d7e032c93) |
| 20 | buy again with test USD (3% tax), round 1 | captain | [0x4d39083c07669f1ab8e9b24a918f36454418947365d9b8daa34d0f0206fb57ec](https://testnet.bscscan.com/tx/0x4d39083c07669f1ab8e9b24a918f36454418947365d9b8daa34d0f0206fb57ec) |
| 21 | sell 30% of the club tokens (5% tax), round 2 | captain | [0xeac95a785965b5408405d09ef44aa3646b51db7da4c0ff6ca83abd1a0b019b37](https://testnet.bscscan.com/tx/0xeac95a785965b5408405d09ef44aa3646b51db7da4c0ff6ca83abd1a0b019b37) |
| 22 | buy again with test USD (3% tax), round 2 | captain | [0xa03570a2a207d9b9299fbf4bb1241af4d7e15ffee0d93b4a271a1bcb4ee424ad](https://testnet.bscscan.com/tx/0xa03570a2a207d9b9299fbf4bb1241af4d7e15ffee0d93b4a271a1bcb4ee424ad) |
| 23 | sell 30% of the club tokens (5% tax), round 3 | captain | [0x3c453681c4fd092d5a3ee574a76d36869d0562ca60a50470b37036191f53e138](https://testnet.bscscan.com/tx/0x3c453681c4fd092d5a3ee574a76d36869d0562ca60a50470b37036191f53e138) |
| 24 | buy again with test USD (3% tax), round 3 | captain | [0x18bb1677f04eae33200592a48d345303cc1881ca3244c2a6c5a34bc23e380d58](https://testnet.bscscan.com/tx/0x18bb1677f04eae33200592a48d345303cc1881ca3244c2a6c5a34bc23e380d58) |
| 25 | sell 30% of the club tokens (5% tax), round 4 | captain | [0x49f875dc5207f6c24fe0e2c4752e92223e2b166a60fa6ae61ccec43cd5af4fdd](https://testnet.bscscan.com/tx/0x49f875dc5207f6c24fe0e2c4752e92223e2b166a60fa6ae61ccec43cd5af4fdd) |
| 26 | buy again with test USD (3% tax), round 4 | captain | [0xe95717160545c34f68d7fc565c0ab80703dbfb7f9948e6799212ee426fd79cd8](https://testnet.bscscan.com/tx/0xe95717160545c34f68d7fc565c0ab80703dbfb7f9948e6799212ee426fd79cd8) |
| 27 | TaxProcessor.dispatch (the vault's share of the tax is paid out) | captain | [0x829e4192663a265649e0c6e3c9a974fe0bc901bcdcc41396df088b4ba663bf21](https://testnet.bscscan.com/tx/0x829e4192663a265649e0c6e3c9a974fe0bc901bcdcc41396df088b4ba663bf21) |
| 28 | GoalVault.settle (sent by the verifier) | verifier | [0x7fdb08731d9552d660d45941423305a5611da8ab9302ed2cadb50bd7478682d8](https://testnet.bscscan.com/tx/0x7fdb08731d9552d660d45941423305a5611da8ab9302ed2cadb50bd7478682d8) |
| 29 | Ana claims (GoalVault.claim) | Ana | [0xbd9abbee1af92a980fc3d97277eb22e06b56b5ef0f8194d3e2998fc9fede1d5f](https://testnet.bscscan.com/tx/0xbd9abbee1af92a980fc3d97277eb22e06b56b5ef0f8194d3e2998fc9fede1d5f) |
| 30 | Ben claims (GoalVault.claim) | Ben | [0x63bda585c99e7bd25bb87d0be7dd5362c965a7207588bb946906eade88e99029](https://testnet.bscscan.com/tx/0x63bda585c99e7bd25bb87d0be7dd5362c965a7207588bb946906eade88e99029) |

## Run it again

```sh
cd verifier && VERIFIER_URL=https://<host>/api npx tsx ../scripts/run-season.ts
```

The script and its settings are described at the top of `scripts/run-season.ts`. It saves its
progress in `scripts/season-run.json` (addresses and hashes only); move that file away to open a
new season. The full result of this run is in `scripts/season-result.json`.
