import { beforeEach, describe, expect, it } from "vitest";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { createAttester } from "../src/attest.js";
import type { Season } from "../src/season.js";
import { LAUNCHER, QUOTE, T, TOKEN, USD, VAULT, VECTOR_ATTESTER, freshRound, harness, lower } from "./fakes.js";

const accounts = Array.from({ length: 4 }, () => privateKeyToAccount(generatePrivateKey()));
const [alice, bob, carol, dave] = accounts as [(typeof accounts)[0], (typeof accounts)[0], (typeof accounts)[0], (typeof accounts)[0]];
const TODAY = 20782; // 2026-11-25
const ADMIN = { authorization: "Bearer s3cret" };

describe("GET /round (fake chain)", () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({ adminToken: "s3cret" });
  });

  it("answers 404 no_round until a round is set", async () => {
    h.start({ defaultRound: undefined });
    const res = await h.get("/round");
    expect(res.status).toBe(404);
    expect(res.body.error).toBe("no_round");
    expect((await h.get("/members")).status).toBe(404);
    expect((await h.get(`/me/${alice.address}`)).status).toBe(404);
    expect(h.chain.reads).toBe(0);
  });

  it("reports the round as the chain has it, amounts as decimal strings in whole tokens", async () => {
    const { status, body } = await h.get("/round");
    expect(status).toBe(200);
    expect(body).toEqual({
      launcher: LAUNCHER,
      name: "Morning Movers",
      quoteToken: QUOTE,
      deposit: "1000",
      liquidityBps: 3000,
      checkInGoal: 6,
      totalCheckIns: 0,
      memberCount: 3,
      totalDeposits: "3000",
      totalSponsored: "0",
      poolQuoteNow: "900",
      prizeNow: "2100",
      deadline: T("2026-12-05T00:00:00Z"),
      launched: false,
      token: null,
      vault: null,
      minSteps: 1000,
      flapUrl: null,
      today: "2026-11-25",
      dayIndex: TODAY,
      canLaunch: false,
      refundOpen: false,
      allowSelfReported: false,
      attester: VECTOR_ATTESTER.toLowerCase(),
      attesterReady: true,
      quoteDecimals: 18,
      // Not a Season round (no SEASON_* in this app).
      season: null,
      raw: {
        deposit: "1000000000000000000000",
        totalDeposits: "3000000000000000000000",
        totalSponsored: "0",
        poolQuoteNow: "900000000000000000000",
        prizeNow: "2100000000000000000000",
      },
    });
  });

  it("follows the chain: check-ins, a sponsor, fractions, and the server's own settings", async () => {
    Object.assign(h.chain.rounds.get(LAUNCHER)!, {
      totalCheckIns: 6,
      totalSponsored: 600n * USD + USD / 4n,
      poolQuoteNow: 1500n * USD + USD / 4n,
      canLaunch: true,
    });
    h.start({ minSteps: 4000, allowSelfReported: true });
    expect((await h.get("/round")).body).toMatchObject({
      totalCheckIns: 6,
      totalSponsored: "600.25",
      poolQuoteNow: "1500.25",
      canLaunch: true,
      minSteps: 4000,
      allowSelfReported: true,
    });
  });

  it("after the launch: token, vault, what the vault has received, and a Flap link when configured", async () => {
    Object.assign(h.chain.rounds.get(LAUNCHER)!, {
      launched: true,
      token: TOKEN,
      vault: VAULT,
      totalCheckIns: 6,
      prizeNow: 2100n * USD + 3717n * 10n ** 16n, // prize plus 37.17 of trading tax
    });
    expect((await h.get("/round")).body).toMatchObject({ launched: true, token: TOKEN, vault: VAULT, prizeNow: "2137.17", flapUrl: null });
    h.start({ flapTokenUrl: "https://example.test/token/{token}" });
    expect((await h.get("/round")).body.flapUrl).toBe("https://example.test/token/0xecb984A239F0528934b693DA22820f405Ec17777");
  });

  it("no Flap link before the launch, even when configured", async () => {
    h.start({ flapTokenUrl: "https://example.test/token/{token}" });
    expect((await h.get("/round")).body.flapUrl).toBeNull();
  });

  it("refunds are open after the deadline if the round has not launched", async () => {
    h.clock = T("2026-12-05T00:00:00Z");
    expect((await h.get("/round")).body).toMatchObject({ refundOpen: false, today: "2026-12-05" });
    h.clock += 1;
    expect((await h.get("/round")).body.refundOpen).toBe(true);
    h.chain.rounds.get(LAUNCHER)!.launched = true;
    expect((await h.get("/round")).body.refundOpen).toBe(false);
  });

  it("says when this server cannot sign for the round", async () => {
    h.start({ attester: undefined });
    expect((await h.get("/round")).body.attesterReady).toBe(false);
    h.start({ attester: createAttester(generatePrivateKey()) });
    expect((await h.get("/round")).body.attesterReady).toBe(false);
  });

  it("answers 503 when the chain cannot be read", async () => {
    h.chain.down = true;
    for (const path of ["/round", `/me/${alice.address}`]) {
      const res = await h.get(path);
      expect(res.status).toBe(503);
      expect(res.body.error).toBe("chain_unavailable");
    }
  });
});

describe("POST /admin/round", () => {
  const OTHER = "0x3000000000000000000000000000000000000003";
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({ adminToken: "s3cret", defaultRound: undefined });
    h.chain.rounds.set(OTHER, { ...freshRound(), name: "Evening Walkers", checkInGoal: 30 });
  });

  it("needs the admin token", async () => {
    expect((await h.post("/admin/round", { launcher: LAUNCHER })).status).toBe(401);
    expect((await h.post("/admin/round", { launcher: LAUNCHER }, { authorization: "Bearer wrong" })).status).toBe(401);
    h.start({ adminToken: undefined });
    expect((await h.post("/admin/round", { launcher: LAUNCHER }, ADMIN)).status).toBe(503);
    expect(await h.store.getRound()).toBeUndefined();
  });

  it("sets the round, with a display name or the Launcher's own", async () => {
    const set = await h.post("/admin/round", { launcher: LAUNCHER.toUpperCase().replace("0X", "0x"), name: "  November round " }, ADMIN);
    expect(set.status).toBe(200);
    expect(set.body).toMatchObject({ launcher: LAUNCHER, name: "November round", checkInGoal: 6 });
    expect((await h.get("/round")).body.name).toBe("November round");

    expect((await h.post("/admin/round", { launcher: OTHER }, ADMIN)).status).toBe(200);
    expect((await h.get("/round")).body).toMatchObject({ launcher: OTHER, name: "Evening Walkers", checkInGoal: 30 });
  });

  it("a round set here replaces the one from CURRENT_LAUNCHER", async () => {
    h.start({ defaultRound: { launcher: LAUNCHER, name: "From the environment" } });
    expect((await h.get("/round")).body).toMatchObject({ launcher: LAUNCHER, name: "From the environment" });
    await h.post("/admin/round", { launcher: OTHER }, ADMIN);
    expect((await h.get("/round")).body.launcher).toBe(OTHER);
  });

  it("changes nothing for a bad address, an unreadable launcher or another attester's round", async () => {
    expect((await h.post("/admin/round", { launcher: "0x12" }, ADMIN)).status).toBe(400);
    expect((await h.post("/admin/round", { launcher: LAUNCHER, name: "x".repeat(81) }, ADMIN)).status).toBe(400);
    const unknown = await h.post("/admin/round", { launcher: "0x4000000000000000000000000000000000000004" }, ADMIN);
    expect(unknown.status).toBe(503);
    h.chain.rounds.get(OTHER)!.attester = "0x5000000000000000000000000000000000000005";
    const mismatch = await h.post("/admin/round", { launcher: OTHER }, ADMIN);
    expect(mismatch.status).toBe(409);
    expect(mismatch.body.error).toBe("attester_mismatch");
    expect(await h.store.getRound()).toBeUndefined();
  });

  it("check-ins are kept per round", async () => {
    h.chain.joined.add(lower(alice));
    await h.post("/admin/round", { launcher: LAUNCHER }, ADMIN);
    expect((await h.checkIn(alice)).status).toBe(200);
    await h.post("/admin/round", { launcher: OTHER }, ADMIN);
    expect((await h.get(`/me/${alice.address}`)).body).toMatchObject({ days: [], streak: 0 });
    expect(await h.store.getCheckIns(LAUNCHER)).toHaveLength(1);
  });
});

describe("GET /me/:address", () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness();
  });

  it("a wallet that has not joined", async () => {
    const { status, body } = await h.get(`/me/${alice.address}`);
    expect(status).toBe(200);
    expect(body).toEqual({
      address: lower(alice),
      member: false,
      daysOf: 0,
      checkedInToday: false,
      streak: 0,
      bestStreak: 0,
      days: [],
      claimableTokens: "0",
      claimableQuote: "0",
      claimedTokens: "0",
      claimedQuote: "0",
      attestedToday: false,
      refundable: "0",
      raw: { claimableTokens: "0", claimableQuote: "0", claimedTokens: "0", claimedQuote: "0", refundable: "0" },
    });
    expect((await h.get("/me/nope")).status).toBe(400);
  });

  it("daysOf and checkedInToday are the chain's; days and streaks are this server's accepted check-ins", async () => {
    h.chain.joined.add(lower(alice));
    await h.checkIn(alice);
    // Accepted and signed here, but the member's transaction has not been sent yet.
    expect((await h.get(`/me/${alice.address}`)).body).toMatchObject({
      member: true,
      daysOf: 0,
      checkedInToday: false,
      attestedToday: true,
      streak: 1,
      days: ["2026-11-25"],
    });
    h.chain.submit(lower(alice), TODAY);
    expect((await h.get(`/me/${alice.address}`)).body).toMatchObject({ daysOf: 1, checkedInToday: true, attestedToday: true });
  });

  it("after the launch: the wallet's share of the vault", async () => {
    h.chain.joined.add(lower(alice));
    Object.assign(h.chain.rounds.get(LAUNCHER)!, { launched: true, token: TOKEN, vault: VAULT });
    h.chain.claimsOf.set(lower(alice), {
      claimableTokens: 0n,
      claimableQuote: 1859n * 10n ** 16n, // 18.59 of tax that arrived after the first claim
      claimedTokens: 250_000n * USD,
      claimedQuote: 1050n * USD,
      tokenDecimals: 18,
    });
    expect((await h.get(`/me/${alice.address}`)).body).toMatchObject({
      claimableTokens: "0",
      claimableQuote: "18.59",
      claimedTokens: "250000",
      claimedQuote: "1050",
      raw: { claimableQuote: "18590000000000000000", claimedTokens: "250000000000000000000000" },
    });
  });

  it("after a missed deadline: what refund() would pay", async () => {
    h.chain.joined.add(lower(alice));
    h.chain.refundableOf.set(lower(alice), 1600n * USD);
    expect((await h.get(`/me/${alice.address}`)).body).toMatchObject({ refundable: "1600", raw: { refundable: "1600000000000000000000" } });
  });
});

describe("season in the round view (SEASON_*)", () => {
  // Squad A of Season 1 and one round in no Season, both created by our (fake) factory. The featured
  // round (LAUNCHER, the stage demo) is in no Season either.
  const SQUAD = `0x${"5a".padEnd(40, "0")}`;
  const OTHER = `0x${"0b".padEnd(40, "0")}`;
  const SEASON_DEADLINE = 1_798_761_599; // 31 Dec 2026 23:59:59 UTC
  const season: Season = { name: "Season 1", launchers: [SQUAD], startDay: 20788, endDay: 20817, joinUntilDay: 20794, squadSize: 10 };
  const view = (day: number) => ({
    name: "Season 1",
    start: "2026-12-01",
    end: "2026-12-30",
    joinUntil: "2026-12-07",
    startDay: 20788,
    endDay: 20817,
    joinUntilDay: 20794,
    day,
    days: 30,
    squadSize: 10,
  });
  const item = (body: { rounds: { launcher: string }[] }, launcher: string) => body.rounds.find((r) => r.launcher === launcher) as any;

  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({ season, adminToken: "s3cret" });
    h.chain.create(SQUAD, alice.address, T("2026-11-20T00:00:00Z"), {
      name: "Season 1 Squad A",
      deposit: 100n * USD,
      liquidityBps: 0,
      checkInGoal: 240,
      deadline: SEASON_DEADLINE,
      memberCount: 4,
      totalCheckIns: 0,
      totalDeposits: 400n * USD,
      totalSponsored: 1500n * USD,
      poolQuoteNow: 1500n * USD,
      prizeNow: 400n * USD,
    });
    h.chain.create(OTHER, alice.address, T("2026-11-20T00:00:00Z"));
  });

  it("GET /rounds/:launcher and the GET /rounds item carry it for a Season round; it is null for the others", async () => {
    expect((await h.get(`/rounds/${SQUAD}`)).body.season).toEqual(view(0));
    expect((await h.get(`/rounds/${OTHER}`)).body.season).toBeNull();
    expect((await h.get(`/rounds/${LAUNCHER}`)).body.season).toBeNull();
    expect((await h.get("/round")).body.season).toBeNull();

    const list = (await h.get("/rounds")).body;
    expect(item(list, SQUAD).season).toEqual(view(0));
    expect(item(list, OTHER).season).toBeNull();
    expect(item(list, LAUNCHER).season).toBeNull();
    // What the app needs on a card for the Keep-Up Guarantee and the "you vs the average" line.
    expect(item(list, SQUAD)).toMatchObject({
      deposit: "100",
      liquidityBps: 0,
      totalSponsored: "1500",
      poolQuoteNow: "1500",
      checkInGoal: 240,
      totalCheckIns: 0,
      memberCount: 4,
      deadline: SEASON_DEADLINE,
      state: "open",
      featured: false,
    });
  });

  it("GET /round, GET /rounds and POST /admin/round carry it when the featured round is a Season round", async () => {
    const set = await h.post("/admin/round", { launcher: SQUAD }, ADMIN);
    expect(set.body.season).toEqual(view(0));
    expect((await h.get("/round")).body.season).toEqual(view(0));
    expect((await h.get("/rounds")).body.rounds[0]).toMatchObject({ launcher: SQUAD, featured: true, season: view(0) });
    expect(await h.get(`/rounds/${SQUAD}`)).toEqual({ status: 200, body: { ...(await h.get("/round")).body, unlisted: false } });
  });

  it("its day follows the server's clock: 0 before 1 Dec, 1 to 30 during the Season, 31 after it", async () => {
    const cases: [string, number][] = [
      ["2026-11-30T23:59:59Z", 0],
      ["2026-12-01T00:00:00Z", 1],
      ["2026-12-07T12:00:00Z", 7],
      ["2026-12-30T23:59:59Z", 30],
      ["2026-12-31T00:00:00Z", 31],
    ];
    for (const [at, day] of cases) {
      h.clock = T(at);
      expect((await h.get(`/rounds/${SQUAD}`)).body.season.day).toBe(day);
      expect(item((await h.get("/rounds")).body, SQUAD).season.day).toBe(day);
    }
  });
});

describe("GET /members", () => {
  it("lists the members this server has seen, by days then streak", async () => {
    const h = harness({}, T("2026-11-23T08:00:00Z"));
    for (const who of [alice, bob, carol, dave]) h.chain.joined.add(lower(who));
    expect((await h.get("/members")).body).toEqual([]);

    // Day 1: alice and bob. Day 2: alice. Day 3 (today): bob and carol; carol's is not on chain yet.
    for (const who of [alice, bob]) {
      await h.checkIn(who);
      h.chain.submit(lower(who), TODAY - 2);
    }
    h.clock += 86_400;
    await h.checkIn(alice);
    h.chain.submit(lower(alice), TODAY - 1);
    h.clock += 86_400;
    await h.checkIn(bob);
    h.chain.submit(lower(bob), TODAY);
    await h.checkIn(carol);
    // dave joined and opened the app, but has not checked in.
    await h.get(`/me/${dave.address}`);
    // A wallet that never joined does not appear, however often it asks.
    await h.get("/me/0x9000000000000000000000000000000000000009");

    const { status, body } = await h.get("/members");
    expect(status).toBe(200);
    expect(body).toEqual([
      // Two days each: alice's streak (ended yesterday, still alive) is 2, bob's (a gap, then today) is 1.
      { address: lower(alice), daysOf: 2, streak: 2, checkedInToday: false },
      { address: lower(bob), daysOf: 2, streak: 1, checkedInToday: true },
      { address: lower(carol), daysOf: 0, streak: 1, checkedInToday: false },
      { address: lower(dave), daysOf: 0, streak: 0, checkedInToday: false },
    ]);

    h.chain.down = true;
    expect((await h.get("/members")).status).toBe(503);
  });
});
