import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { STATS_CACHE_MS } from "../src/app.js";
import { appFromEnv } from "../src/config.js";
import { totals, walletTotals } from "../src/stats.js";
import { LAUNCHER, T, USD, VAULT, freshRound, harness, lower } from "./fakes.js";

const accounts = Array.from({ length: 4 }, () => privateKeyToAccount(generatePrivateKey()));
const [owner, alice, bob, carol] = accounts as [(typeof accounts)[0], (typeof accounts)[0], (typeof accounts)[0], (typeof accounts)[0]];
const TODAY = 20782; // 2026-11-25
const NOW = T("2026-11-25T08:00:00Z");
const LONG_AGO = NOW - 86_400;

const A = "0x74b9218cc901fa4b295c3b021c246e6f1022915b";
const B = "0xb000000000000000000000000000000000000002";
const C = "0xc000000000000000000000000000000000000003";

afterEach(() => vi.restoreAllMocks());

describe("totals (pure)", () => {
  it("adds the chain's numbers up and counts a wallet in two rounds as one person", () => {
    const open = { ...freshRound(), totalCheckIns: 3 };
    const launched = { ...freshRound(), totalCheckIns: 4, totalDeposits: 1000n * USD, launched: true };
    expect(totals([open, launched], [["0xa", "0xb"], ["0xa", "0xc"]])).toEqual({
      rounds: 2,
      people: 3,
      checkIns: 7,
      deposited: "4000",
      launched: 1,
      complete: true,
      raw: { deposited: (4000n * USD).toString() },
    });
  });

  it("with nothing to count every number is zero", () => {
    expect(totals([], [])).toEqual({ rounds: 0, people: 0, checkIns: 0, deposited: "0", launched: 0, complete: true, raw: { deposited: "0" } });
  });

  it("a quote token with other decimals is added at its own scale", () => {
    const six = { ...freshRound(), quoteDecimals: 6, totalDeposits: 500_250_000n };
    expect(totals([freshRound(), six], [[], []]).deposited).toBe("3500.25");
  });

  it("a round that could not be read is left out and the sum says so", () => {
    const sum = totals([freshRound(), null], [["0xa"], ["0xb"]]);
    expect(sum).toMatchObject({ rounds: 2, people: 2, checkIns: 0, deposited: "3000", complete: false });
  });

  it("one wallet: days and claims over its rounds", () => {
    expect(
      walletTotals("0xa", [
        { daysOf: 2, claimedQuote: 0n, quoteDecimals: 18 },
        { daysOf: 3, claimedQuote: 350n * USD + USD / 2n, quoteDecimals: 18 },
      ]),
    ).toEqual({ address: "0xa", rounds: 2, days: 5, claimed: "350.5", raw: { claimed: (350n * USD + USD / 2n).toString() } });
    expect(walletTotals("0xa", [])).toEqual({ address: "0xa", rounds: 0, days: 0, claimed: "0", raw: { claimed: "0" } });
  });
});

describe("GET /stats", () => {
  let h: ReturnType<typeof harness>;

  /**
   * Three rounds our factory created. A is listed and open: alice has two days, bob one. B is
   * unlisted and launched: alice has two days, carol two, and alice has claimed 300. C is listed,
   * open and empty, with a 6-decimal quote token.
   */
  async function threeRounds() {
    h = harness({ defaultRound: undefined, statsCacheMs: 0 });
    h.chain.create(A, owner.address, LONG_AGO);
    h.chain.create(B, owner.address, LONG_AGO, {
      memberCount: 2,
      totalDeposits: 2000n * USD,
      prizeNow: 1400n * USD,
      launched: true,
      vault: VAULT,
    });
    h.chain.create(C, owner.address, LONG_AGO, { memberCount: 1, quoteDecimals: 6, totalDeposits: 500_000_000n });
    expect((await h.register(B, owner, true)).status).toBe(200);

    for (const [launcher, who, daysBack] of [
      [A, alice, [1, 0]],
      [A, bob, [0]],
      [B, alice, [3, 2]],
      [B, carol, [3, 2]],
    ] as const) {
      h.chain.join(launcher, lower(who));
      for (const back of daysBack) h.chain.submit(lower(who), TODAY - back, launcher);
      // The app asks for the wallet's place in the round; that is how this server comes to know it.
      expect((await h.get(`/rounds/${launcher}/me/${who.address}`)).body.member).toBe(true);
    }
    h.chain.claimsOf.set(lower(alice), {
      claimableTokens: 0n,
      claimableQuote: 0n,
      claimedTokens: 250_000n * USD,
      claimedQuote: 300n * USD,
      tokenDecimals: 18,
    });
  }

  beforeEach(() => {
    h = harness({ defaultRound: undefined, statsCacheMs: 0 });
  });

  it("adds up every round our factory created; an unlisted round counts and is never named", async () => {
    await threeRounds();
    // B is not in the public list.
    expect((await h.get("/rounds")).body.rounds.map((r: { launcher: string }) => r.launcher).sort()).toEqual([A, C].sort());

    const { status, body } = await h.get("/stats");
    expect(status).toBe(200);
    expect(body).toEqual({
      rounds: 3,
      // alice is in two rounds and is one person.
      people: 3,
      checkIns: 7,
      // 3,000 in A, 2,000 in B, 500 in C (6 decimals).
      deposited: "5500",
      launched: 1,
      complete: true,
      raw: { deposited: (5500n * USD).toString() },
    });
    // Numbers only: no address of any round, vault or wallet.
    expect(JSON.stringify(body)).not.toMatch(/0x[0-9a-f]{40}/i);
  });

  it("a round created with another attester is left out, as in GET /rounds: its check-ins, deposits, launch and members", async () => {
    await threeRounds();
    const before = (await h.get("/stats")).body;
    const D = "0xd000000000000000000000000000000000000004";
    const OTHER_ATTESTER = "0x00000000000000000000000000000000000000ee";
    const dave = privateKeyToAccount(generatePrivateKey());
    h.chain.create(D, owner.address, LONG_AGO, { attester: OTHER_ATTESTER, memberCount: 1, totalDeposits: 1000n * USD, launched: true, vault: VAULT });
    h.chain.join(D, lower(dave));
    for (const back of [4, 3, 2, 1, 0]) h.chain.submit(lower(dave), TODAY - back, D);
    expect(h.chain.rounds.get(D)!.totalCheckIns).toBe(5);
    expect((await h.get(`/rounds/${D}/me/${dave.address}`)).body.member).toBe(true);
    h.clock += 30; // the next request looks for new rounds again

    expect((await h.get("/rounds")).body.rounds.map((r: { launcher: string }) => r.launcher)).not.toContain(D);
    const after = (await h.get("/stats")).body;
    expect(after).toEqual(before);
    expect(after).toMatchObject({ rounds: 3, people: 3, checkIns: 7, deposited: "5500", launched: 1 });
    expect((await h.get(`/stats/${dave.address}`)).body.you).toMatchObject({ rounds: 0, days: 0 });

    // The featured round is the one exception, as in GET /rounds.
    h.start({ defaultRound: { launcher: D } });
    expect((await h.get("/stats")).body).toMatchObject({ rounds: 4, people: 4, checkIns: 12, deposited: "6500", launched: 2 });
  });

  it("small real numbers are answered as they are: a server with nothing answers zeros", async () => {
    expect(await h.get("/stats")).toEqual({
      status: 200,
      body: { rounds: 0, people: 0, checkIns: 0, deposited: "0", launched: 0, complete: true, raw: { deposited: "0" } },
    });
  });

  it("the featured round is counted too, once, whether or not the factory's events show it", async () => {
    h.start({ defaultRound: { launcher: LAUNCHER } });
    expect((await h.get("/stats")).body).toMatchObject({ rounds: 1, deposited: "3000", checkIns: 0 });
    h.chain.create(LAUNCHER, owner.address, LONG_AGO);
    h.clock += 30; // the next request looks for new rounds again
    expect((await h.get("/stats")).body).toMatchObject({ rounds: 1, deposited: "3000" });
  });

  it("GET /stats/:address adds `you`: that wallet across the rounds it joined, unlisted included", async () => {
    await threeRounds();
    const everyone = (await h.get("/stats")).body;

    const mine = await h.get(`/stats/${alice.address}`);
    expect(mine.status).toBe(200);
    expect(mine.body).toEqual({
      ...everyone,
      you: { address: lower(alice), rounds: 2, days: 4, claimed: "300", raw: { claimed: (300n * USD).toString() } },
    });
    // The checksummed and the lower-case address are the same wallet.
    expect((await h.get(`/stats/${lower(alice)}`)).body.you).toEqual(mine.body.you);

    expect((await h.get(`/stats/${bob.address}`)).body.you).toMatchObject({ rounds: 1, days: 1, claimed: "0" });
    // A wallet this server has never seen as a member: zeros, not an error.
    expect((await h.get(`/stats/${owner.address}`)).body.you).toEqual({ address: lower(owner), rounds: 0, days: 0, claimed: "0", raw: { claimed: "0" } });
    expect(await h.get("/stats/nope")).toMatchObject({ status: 400, body: { error: "bad_address" } });
  });

  it("is answered from memory for a short time, then counted again", async () => {
    await threeRounds();
    h.start({ statsCacheMs: STATS_CACHE_MS });
    expect((await h.get("/stats")).body.checkIns).toBe(7);
    const reads = h.chain.reads;

    h.chain.submit(lower(bob), TODAY - 1, A);
    h.clock += STATS_CACHE_MS / 1000 - 1;
    expect((await h.get("/stats")).body.checkIns).toBe(7);
    expect(h.chain.reads).toBe(reads);

    h.clock += 2;
    expect((await h.get("/stats")).body.checkIns).toBe(8);
    expect(h.chain.reads).toBeGreaterThan(reads);
  });

  it("a round that cannot be read is left out, said so, and tried again on the next request", async () => {
    await threeRounds();
    h.start({ statsCacheMs: STATS_CACHE_MS });
    const kept = h.chain.rounds.get(C)!;
    h.chain.rounds.delete(C);
    expect((await h.get("/stats")).body).toMatchObject({ rounds: 3, deposited: "5000", complete: false });
    // alice is not in C, so her own numbers are still whole.
    expect((await h.get(`/stats/${alice.address}`)).body.you).toMatchObject({ rounds: 2, days: 4 });

    h.chain.rounds.set(C, kept);
    expect((await h.get("/stats")).body).toMatchObject({ deposited: "5500", complete: true });
  });

  it("`you` is null, not a low number, when a round the wallet joined cannot be read", async () => {
    await threeRounds();
    h.chain.rounds.delete(B);
    const { status, body } = await h.get(`/stats/${alice.address}`);
    expect(status).toBe(200);
    expect(body.complete).toBe(false);
    expect(body.you).toBeNull();
    // bob is only in A, which can be read.
    expect((await h.get(`/stats/${bob.address}`)).body.you).toMatchObject({ rounds: 1, days: 1 });
  });

  it("503 chain_unavailable when nothing can be read, instead of zeros", async () => {
    await threeRounds();
    h.chain.down = true;
    expect(await h.get("/stats")).toMatchObject({ status: 503, body: { error: "chain_unavailable" } });
    expect(await h.get(`/stats/${alice.address}`)).toMatchObject({ status: 503, body: { error: "chain_unavailable" } });
  });

  it("is served at the root and again under /api", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    // Nothing here reaches the RPC: a bad address is refused before the chain is asked.
    const app = appFromEnv({ RPC_URL: "http://127.0.0.1:9", DATA_FILE: "/nonexistent/cypher-run-test.json" } as NodeJS.ProcessEnv);
    for (const prefix of ["", "/api"]) {
      const res = await app.request(`${prefix}/stats/nope`);
      expect(res.status).toBe(400);
      expect(((await res.json()) as { error: string }).error).toBe("bad_address");
    }
  });
});
