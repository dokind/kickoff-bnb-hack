import { createServer, type Server } from "node:http";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { getAddress, recoverMessageAddress } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { checkInInner } from "../src/attest.js";
import { createChain, factoryAbi } from "../src/chain.js";
import { DEFAULT_FACTORY, DEFAULT_FACTORY_FROM_BLOCK, appFromEnv, serverFromEnv } from "../src/config.js";
import { roundMessage } from "../src/product.js";
import { LISTING_DELAY_SECONDS } from "../src/rounds.js";
import { LocalStore } from "../src/store.js";
import { FACTORY, FROM_BLOCK, LAUNCHER, T, TOKEN, USD, VAULT, VECTOR_ATTESTER, harness, lower } from "./fakes.js";

const accounts = Array.from({ length: 4 }, () => privateKeyToAccount(generatePrivateKey()));
const [owner, stranger, alice, bob] = accounts as [(typeof accounts)[0], (typeof accounts)[0], (typeof accounts)[0], (typeof accounts)[0]];
const TODAY = 20782; // 2026-11-25
const NOW = T("2026-11-25T08:00:00Z");
const LONG_AGO = NOW - 86_400;

// Launchers our (fake) factory creates in these tests. A is the letters-in-it one, to cover both spellings.
const A = "0x74b9218cc901fa4b295c3b021c246e6f1022915b";
const B = "0xb000000000000000000000000000000000000002";
const C = "0xc000000000000000000000000000000000000003";
const D = "0xd000000000000000000000000000000000000004";
const E = "0xe000000000000000000000000000000000000005";
const F = "0xf000000000000000000000000000000000000006";
/** A readable CheckInLauncher that some other factory created. */
const FOREIGN = "0x9000000000000000000000000000000000000009";

const launchers = (body: { rounds: { launcher: string }[] }) => body.rounds.map((r) => r.launcher);

describe("discovery: rounds are found in the factory's creation events", () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({ defaultRound: undefined });
  });

  it("scans from the factory's block to the head in chunks, and keeps what it found in the store", async () => {
    h.chain.create(A, owner.address, LONG_AGO, {}, 500);
    h.chain.create(B, owner.address, LONG_AGO, {}, 1500);
    h.chain.create(C, stranger.address, LONG_AGO, {}, 700);
    const head = h.chain.head;

    expect(launchers((await h.get("/rounds")).body).sort()).toEqual([A, B, C].sort());
    // 1,000 blocks per call, each range starting where the one before ended, up to the head.
    expect(h.chain.logCalls).toEqual([
      [FROM_BLOCK, FROM_BLOCK + 999],
      [FROM_BLOCK + 1000, FROM_BLOCK + 1999],
      [FROM_BLOCK + 2000, head],
    ]);
    expect(await h.store.getDiscovery()).toEqual({
      factory: FACTORY,
      nextBlock: head + 1,
      rounds: [
        { launcher: A, creator: lower(owner), block: FROM_BLOCK + 510, createdAt: LONG_AGO },
        { launcher: B, creator: lower(owner), block: FROM_BLOCK + 2010, createdAt: LONG_AGO },
        { launcher: C, creator: lower(stranger), block: head, createdAt: LONG_AGO },
      ],
    });
  });

  it("does not scan again for a while; then it reads only the new blocks and a few before them", async () => {
    h.chain.create(A, owner.address, LONG_AGO, {}, 2500);
    await h.get("/rounds");
    const calls = h.chain.logCalls.length;
    const scannedTo = h.chain.head;
    await h.get("/rounds");
    await h.get(`/rounds/${A}`);
    expect(h.chain.logCalls).toHaveLength(calls);

    h.chain.create(B, owner.address, LONG_AGO, {}, 30);
    h.clock += 19;
    expect(launchers((await h.get("/rounds")).body)).toEqual([A]);
    h.clock += 2; // older than the 20 seconds a scan is good for
    expect(launchers((await h.get("/rounds")).body).sort()).toEqual([A, B].sort());
    expect(h.chain.logCalls.slice(calls)).toEqual([[scannedTo + 1 - 64, h.chain.head]]);
    // The overlap found A a second time; it is kept once.
    expect((await h.store.getDiscovery())!.rounds.map((r) => r.launcher)).toEqual([A, B]);
  });

  it("a restarted server knows the rounds from the store and continues where the scan stopped", async () => {
    h.chain.create(A, owner.address, LONG_AGO, {}, 2500);
    await h.rounds.refresh();
    const scannedTo = h.chain.head;
    h.chain.logCalls = [];

    const restarted = h.newRounds();
    expect(await restarted.known(A)).toMatchObject({ launcher: A, creator: lower(owner) });
    expect(await restarted.scanned()).toBe(true);
    expect(h.chain.logCalls).toEqual([]);
    h.chain.create(B, owner.address, NOW, {}, 5);
    expect(await restarted.refresh()).toBe(true);
    expect(h.chain.logCalls).toEqual([[scannedTo + 1 - 64, h.chain.head]]);
    expect((await restarted.all()).map((r) => r.launcher)).toEqual([A, B]);
  });

  it("progress is written to the store a chunk at a time, not on every scan", async () => {
    h.chain.create(A, owner.address, LONG_AGO);
    await h.rounds.refresh();
    const first = (await h.store.getDiscovery())!.nextBlock;
    h.chain.head += 400;
    await h.rounds.refresh();
    expect((await h.store.getDiscovery())!.nextBlock).toBe(first);
    h.chain.head += 700; // more than one chunk (1,000 blocks) since the last write
    await h.rounds.refresh();
    expect((await h.store.getDiscovery())!.nextBlock).toBe(h.chain.head + 1);
  });

  it("a store that cannot be written does not stop discovery", async () => {
    h.chain.create(A, owner.address, LONG_AGO, {}, 1500);
    const put = h.store.putDiscovery.bind(h.store);
    h.store.putDiscovery = async () => {
      throw new Error("disk full");
    };
    expect(await h.rounds.refresh()).toBe(true);
    expect(launchers((await h.get("/rounds")).body)).toEqual([A]);
    expect(await h.store.getDiscovery()).toBeUndefined();
    // Written as soon as the store works again.
    h.store.putDiscovery = put;
    await h.rounds.refresh();
    expect((await h.store.getDiscovery())!.rounds).toHaveLength(1);
  });

  it("halves a range the RPC refuses and asks again", async () => {
    h.chain.create(A, owner.address, LONG_AGO, {}, 100);
    h.chain.create(B, owner.address, LONG_AGO, {}, 1200);
    h.chain.maxRange = 300;
    expect(await h.rounds.refresh()).toBe(true);
    // 1,000 is refused, 500 is refused, 250 is answered.
    expect(h.chain.logCalls.every(([from, to]) => to - from + 1 <= 250)).toBe(true);
    expect(h.chain.logCalls[0]).toEqual([FROM_BLOCK, FROM_BLOCK + 249]);
    expect(h.chain.logCalls.at(-1)![1]).toBe(h.chain.head);
    expect((await h.rounds.all()).map((r) => r.launcher)).toEqual([A, B]);
  });

  it("a scan that cannot read the chain changes nothing and is picked up again later", async () => {
    h.chain.create(A, owner.address, LONG_AGO, {}, 1500);
    h.chain.down = true;
    expect(await h.rounds.refresh()).toBe(false);
    expect(await h.rounds.scanned()).toBe(false);
    expect(await h.store.getDiscovery()).toBeUndefined();
    // Nothing is known yet, so the list says the chain could not be read instead of "no rounds".
    const list = await h.get("/rounds");
    expect(list.status).toBe(503);
    expect(list.body.error).toBe("chain_unavailable");

    h.chain.down = false;
    expect((await h.get("/rounds")).body.rounds).toHaveLength(1);
    // The chain goes away again: the list shows what it read last for five minutes, then says so.
    h.chain.down = true;
    h.clock += 299;
    expect((await h.get("/rounds")).body.rounds).toHaveLength(1);
    h.clock += 1;
    const gone = await h.get("/rounds");
    expect([gone.status, gone.body.error]).toEqual([503, "chain_unavailable"]);
  });

  it("an empty factory is an empty list, not an error", async () => {
    expect(await h.get("/rounds")).toEqual({ status: 200, body: { rounds: [] } });
  });

  it("a launcher nobody has asked about yet is looked for on demand", async () => {
    await h.get("/rounds"); // scanned a moment ago: the list itself would not scan again yet
    h.chain.create(A, owner.address, NOW);
    const calls = h.chain.logCalls.length;
    const res = await h.get(`/rounds/${A}`);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ launcher: A, name: "Morning Movers", unlisted: false });
    expect(h.chain.logCalls).toHaveLength(calls + 1);
    // Known now: asking again reads no events.
    await h.get(`/rounds/${A}`);
    expect(h.chain.logCalls).toHaveLength(calls + 1);
  });

  it("asking for unknown launchers over and over does not scan more often than the gap allows", async () => {
    const rounds = h.newRounds({ minGapMs: 750 });
    h.start({ rounds });
    expect((await h.get(`/rounds/${FOREIGN}`)).status).toBe(404);
    const calls = h.chain.logCalls.length;
    for (let i = 0; i < 5; i++) expect((await h.get(`/rounds/${FOREIGN}`)).status).toBe(404);
    expect(h.chain.logCalls).toHaveLength(calls);
    h.clock += 1;
    await h.get(`/rounds/${FOREIGN}`);
    expect(h.chain.logCalls).toHaveLength(calls + 1);
  });

  it("starts over when the store holds another factory's rounds", async () => {
    await h.store.putDiscovery({
      factory: "0x00000000000000000000000000000000000000f1",
      nextBlock: h.chain.head + 1,
      rounds: [{ launcher: FOREIGN, creator: lower(stranger), block: FROM_BLOCK + 1, createdAt: LONG_AGO }],
    });
    h.chain.create(A, owner.address, LONG_AGO);
    const rounds = h.newRounds();
    expect(await rounds.known(FOREIGN)).toBeUndefined();
    expect(await rounds.scanned()).toBe(false);
    await rounds.refresh();
    expect((await rounds.all()).map((r) => r.launcher)).toEqual([A]);
    expect(h.chain.logCalls[0]![0]).toBe(FROM_BLOCK);
    expect((await h.store.getDiscovery())!.factory).toBe(FACTORY);
  });

  it("with no factory configured only the featured round is known", async () => {
    h.start({ rounds: h.newRounds({ factory: undefined }), defaultRound: { launcher: LAUNCHER } });
    h.chain.create(A, owner.address, LONG_AGO);
    expect(launchers((await h.get("/rounds")).body)).toEqual([LAUNCHER]);
    expect((await h.get(`/rounds/${LAUNCHER}`)).status).toBe(200);
    expect((await h.get(`/rounds/${A}`)).status).toBe(404);
    expect(h.chain.logCalls).toEqual([]);
  });
});

describe("GET /rounds: the public list", () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({ defaultRound: undefined });
  });

  it("one item per listed round, amounts as decimal strings as in GET /round", async () => {
    h.chain.create(A, owner.address, LONG_AGO, { name: "morning movers", totalCheckIns: 2, totalSponsored: 600n * USD + USD / 4n, poolQuoteNow: 1500n * USD + USD / 4n });
    const { status, body } = await h.get("/rounds");
    expect(status).toBe(200);
    expect(body).toEqual({
      rounds: [
        {
          launcher: A,
          name: "morning movers",
          deposit: "1000",
          liquidityBps: 3000,
          checkInGoal: 6,
          totalCheckIns: 2,
          memberCount: 3,
          totalSponsored: "600.25",
          prizeNow: "2100",
          poolQuoteNow: "1500.25",
          deadline: T("2026-12-05T00:00:00Z"),
          launched: false,
          token: null,
          vault: null,
          season: null,
          state: "open",
          featured: false,
        },
      ],
    });
    // The same numbers as the round's own page.
    const own = (await h.get(`/rounds/${A}`)).body;
    for (const key of Object.keys(body.rounds[0]).filter((k) => k !== "state" && k !== "featured")) expect(own[key]).toEqual(body.rounds[0][key]);
  });

  it("order: featured, open by nearest deadline, launched newest first, then expired; with the three states", async () => {
    const day = 86_400;
    // Created in this order, on purpose not the order they are listed in.
    h.chain.create(E, owner.address, NOW - 9 * day, { deadline: NOW - 2 * day }); // expired two days ago
    h.chain.create(C, owner.address, NOW - 8 * day, { launched: true, token: TOKEN, vault: VAULT, deadline: NOW - day }); // launched, older
    h.chain.create(B, owner.address, NOW - 7 * day, { deadline: NOW + 9 * day }); // open, later deadline
    h.chain.create(F, owner.address, NOW - 6 * day, { deadline: NOW - 1 }); // expired a second ago
    h.chain.create(D, owner.address, NOW - 5 * day, { launched: true, token: TOKEN, vault: VAULT, deadline: NOW + 3 * day }); // launched, newer
    h.chain.create(A, owner.address, NOW - 4 * day, { deadline: NOW + 2 * day }); // open, nearest deadline
    h.chain.create(LAUNCHER, owner.address, NOW - 3 * day, { deadline: NOW + 20 * day }); // open, and featured
    h.start({ defaultRound: { launcher: LAUNCHER, name: "Demo Day" } });

    const { body } = await h.get("/rounds");
    expect(body.rounds.map((r: any) => [r.launcher, r.state, r.featured])).toEqual([
      [LAUNCHER, "open", true],
      [A, "open", false],
      [B, "open", false],
      [D, "launched", false],
      [C, "launched", false],
      [F, "expired", false],
      [E, "expired", false],
    ]);
    // The featured round carries the display name it was given, as in GET /round.
    expect(body.rounds[0].name).toBe("Demo Day");
    expect((await h.get("/round")).body.name).toBe("Demo Day");
    expect(body.rounds[3]).toMatchObject({ launched: true, token: TOKEN, vault: VAULT });
  });

  it("a round is open up to and including its deadline, expired after it, launched once launched", async () => {
    const deadline = NOW + 100;
    h.chain.create(A, owner.address, LONG_AGO, { deadline });
    h.clock = deadline;
    expect((await h.get("/rounds")).body.rounds[0].state).toBe("open");
    h.clock = deadline + 1;
    expect((await h.get("/rounds")).body.rounds[0].state).toBe("expired");
    expect((await h.get(`/rounds/${A}`)).body.refundOpen).toBe(true);
    // A launch is final, whatever the clock says.
    Object.assign(h.chain.rounds.get(A)!, { launched: true, token: TOKEN, vault: VAULT });
    expect((await h.get("/rounds")).body.rounds[0]).toMatchObject({ state: "launched", launched: true });
  });

  it("the featured round moves when the operator points the server at another round", async () => {
    h.chain.create(A, owner.address, LONG_AGO, { deadline: NOW + 1000 });
    h.chain.create(B, owner.address, LONG_AGO, { deadline: NOW + 2000 });
    h.start({ adminToken: "s3cret" });
    expect((await h.get("/rounds")).body.rounds.map((r: any) => [r.launcher, r.featured])).toEqual([[A, false], [B, false]]);
    expect((await h.post("/admin/round", { launcher: B }, { authorization: "Bearer s3cret" })).status).toBe(200);
    expect((await h.get("/rounds")).body.rounds.map((r: any) => [r.launcher, r.featured])).toEqual([[B, true], [A, false]]);
    expect((await h.get("/round")).body.launcher).toBe(B);
  });

  it("the featured round is listed even when our factory did not create it", async () => {
    h.start({ defaultRound: { launcher: LAUNCHER } });
    h.chain.create(A, owner.address, LONG_AGO);
    expect((await h.get("/rounds")).body.rounds.map((r: any) => [r.launcher, r.featured])).toEqual([[LAUNCHER, true], [A, false]]);
  });

  it("leaves out rounds this server cannot sign check-ins for; they still answer by address", async () => {
    h.chain.create(A, owner.address, LONG_AGO);
    h.chain.create(B, stranger.address, LONG_AGO, { attester: "0x5000000000000000000000000000000000000005" });
    expect(launchers((await h.get("/rounds")).body)).toEqual([A]);
    expect((await h.get(`/rounds/${B}`)).body).toMatchObject({ launcher: B, attesterReady: false, unlisted: false });
    h.chain.join(B, lower(alice));
    const res = await h.checkInTo(B, alice);
    expect(res.status).toBe(503);
    expect(res.body.error).toBe("attester_mismatch");
  });

  it("reads an open round from the chain at most every few seconds, a closed one less often", async () => {
    h.start({ listCacheMs: 4000 });
    h.chain.create(A, owner.address, LONG_AGO);
    h.chain.create(B, owner.address, LONG_AGO, { launched: true, token: TOKEN, vault: VAULT });
    await h.get("/rounds");
    const reads = h.chain.reads;
    expect(reads).toBe(2);
    h.chain.rounds.get(A)!.totalCheckIns = 5;
    h.clock += 3;
    expect((await h.get("/rounds")).body.rounds[0].totalCheckIns).toBe(0);
    expect(h.chain.reads).toBe(reads);
    h.clock += 1;
    expect((await h.get("/rounds")).body.rounds[0].totalCheckIns).toBe(5);
    expect(h.chain.reads).toBe(reads + 1); // A again; B, launched, is kept for a minute
    h.clock += 60;
    await h.get("/rounds");
    expect(h.chain.reads).toBe(reads + 3);
    // The round's own page is never answered from memory.
    h.chain.rounds.get(A)!.totalCheckIns = 6;
    expect((await h.get(`/rounds/${A}`)).body.totalCheckIns).toBe(6);
    // When the chain cannot be read, the list answers with what it read last.
    h.chain.down = true;
    h.clock += 120;
    const stale = await h.get("/rounds");
    expect(stale.status).toBe(200);
    expect(stale.body.rounds.map((r: any) => r.totalCheckIns)).toEqual([5, 0]);
  });
});

describe("listing: three minutes, or the creator's choice", () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({ defaultRound: undefined });
  });

  it("a round nobody registered appears three minutes after its creation", async () => {
    expect(LISTING_DELAY_SECONDS).toBe(180);
    h.chain.create(A, owner.address, NOW);
    expect((await h.get("/rounds")).body.rounds).toEqual([]);
    // Not listed yet, but it answers for whoever has its address.
    expect((await h.get(`/rounds/${A}`)).body).toMatchObject({ launcher: A, unlisted: false });
    h.clock = NOW + 179;
    expect((await h.get("/rounds")).body.rounds).toEqual([]);
    h.clock = NOW + 180;
    expect(launchers((await h.get("/rounds")).body)).toEqual([A]);
  });

  it("registered as listed, it appears at once", async () => {
    h.chain.create(A, owner.address, NOW);
    h.clock = NOW + 5;
    const res = await h.register(A, owner, false);
    expect(res).toEqual({ status: 200, body: { launcher: A, unlisted: false } });
    expect(launchers((await h.get("/rounds")).body)).toEqual([A]);
  });

  it("registered as unlisted, it never appears in the list, and still answers by address", async () => {
    h.chain.create(A, owner.address, NOW);
    h.chain.create(B, owner.address, NOW);
    h.clock = NOW + 5;
    expect(await h.register(A, owner, true)).toEqual({ status: 200, body: { launcher: A, unlisted: true } });
    expect(await h.store.getListing(A)).toEqual({ unlisted: true, by: lower(owner), at: NOW + 5 });
    for (const later of [NOW + 60, NOW + 180, NOW + 30 * 86_400]) {
      h.clock = later;
      expect(launchers((await h.get("/rounds")).body)).not.toContain(A);
    }
    h.clock = NOW + 200;
    expect(launchers((await h.get("/rounds")).body)).toEqual([B]);
    // "Unlisted" is only about the list: the round's own routes work for anyone who has the address.
    expect((await h.get(`/rounds/${A}`)).body).toMatchObject({ launcher: A, unlisted: true, checkInGoal: 6 });
    expect((await h.get(`/rounds/${A}/members`)).status).toBe(200);
    h.chain.join(A, lower(alice));
    expect((await h.checkInTo(A, alice)).status).toBe(200);
  });

  it("the creator may change the choice, in both directions", async () => {
    h.chain.create(A, owner.address, LONG_AGO);
    expect(launchers((await h.get("/rounds")).body)).toEqual([A]);
    await h.register(A, owner, true);
    expect((await h.get("/rounds")).body.rounds).toEqual([]);
    await h.register(A, owner, false);
    expect(launchers((await h.get("/rounds")).body)).toEqual([A]);
    expect((await h.get(`/rounds/${A}`)).body.unlisted).toBe(false);
  });

  it("the featured round skips the three minutes, but not its creator's choice", async () => {
    h.chain.create(A, owner.address, NOW);
    h.start({ defaultRound: { launcher: A } });
    expect((await h.get("/rounds")).body.rounds).toMatchObject([{ launcher: A, featured: true }]);
    await h.register(A, owner, true);
    expect((await h.get("/rounds")).body.rounds).toEqual([]);
    // The single-round routes still serve it: they are that round's own page.
    expect((await h.get("/round")).body.launcher).toBe(A);
    expect((await h.get(`/rounds/${A}`)).body.unlisted).toBe(true);
  });
});

describe("POST /rounds: only the wallet that created the round", () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    h = harness({ defaultRound: undefined });
    h.chain.create(A, owner.address, NOW);
  });

  it("the signed text is `Cypher Run round <launcher lower-case> <listed|unlisted>`", async () => {
    expect(roundMessage(A, true)).toBe(`Cypher Run round ${A} unlisted`);
    expect(roundMessage(A, false)).toBe(`Cypher Run round ${A} listed`);
    const signature = await owner.signMessage({ message: `Cypher Run round ${A} unlisted` });
    expect(await h.post("/rounds", { launcher: A, unlisted: true, signature })).toEqual({ status: 200, body: { launcher: A, unlisted: true } });
  });

  it("refuses any other signer and stores nothing", async () => {
    for (const unlisted of [true, false]) {
      const res = await h.register(A, stranger, unlisted);
      expect(res.status).toBe(401);
      expect(res.body.error).toBe("bad_signature");
    }
    expect(await h.store.getListing(A)).toBeUndefined();
    // The creator of one round has no say over another's.
    h.chain.create(B, stranger.address, NOW);
    expect((await h.register(B, owner, true)).status).toBe(401);
    expect((await h.register(B, stranger, true)).status).toBe(200);
    expect(await h.store.getListing(A)).toBeUndefined();
  });

  it("the signature must be over exactly this launcher and this choice", async () => {
    expect((await h.register(A, owner, true, { signedUnlisted: false })).status).toBe(401);
    expect((await h.register(A, owner, false, { signedUnlisted: true })).status).toBe(401);
    expect((await h.register(A, owner, true, { signedLauncher: B })).status).toBe(401);
    expect(await h.store.getListing(A)).toBeUndefined();
    // The launcher may be sent, and signed, checksummed.
    expect((await h.register(getAddress(A), owner, true)).body).toEqual({ launcher: A, unlisted: true });
    expect((await h.register(A, owner, false, { signedLauncher: getAddress(A) })).status).toBe(200);
  });

  it("answers a malformed request without looking at the chain", async () => {
    const signature = await owner.signMessage({ message: roundMessage(A, true) });
    const bad = async (body: unknown, status: number, error: string) => {
      const res = await h.post("/rounds", body);
      expect([res.status, res.body.error]).toEqual([status, error]);
    };
    await bad({ launcher: "0x12", unlisted: true, signature }, 400, "bad_launcher");
    await bad({ unlisted: true, signature }, 400, "bad_launcher");
    await bad({ launcher: A, unlisted: "true", signature }, 400, "bad_unlisted");
    await bad({ launcher: A, signature }, 400, "bad_unlisted");
    await bad({ launcher: A, unlisted: true }, 401, "bad_signature");
    await bad({ launcher: A, unlisted: true, signature: "0x1234" }, 401, "bad_signature");
    expect(h.chain.logCalls).toEqual([]);
    expect(await h.store.getListing(A)).toBeUndefined();
  });

  it("404 for a launcher our factory did not create; 503 when that cannot be told", async () => {
    h.chain.rounds.set(FOREIGN, h.chain.rounds.get(A)!);
    const res = await h.register(FOREIGN, owner, true);
    expect(res.status).toBe(404);
    expect(res.body.error).toBe("no_round");
    h.chain.down = true;
    const down = await h.register(FOREIGN, owner, true);
    expect(down.status).toBe(503);
    expect(down.body.error).toBe("chain_unavailable");
    // A round already known is registered without the chain.
    expect((await h.register(A, owner, true)).status).toBe(200);
  });

  it("looks again for a round the RPC does not show yet (registered right after its creation)", async () => {
    h.start({ registerRetry: { times: 2, waitMs: 5 } });
    await h.rounds.refresh();
    // The creation transaction is mined, but the node this server reads from is a moment behind.
    setTimeout(() => h.chain.create(B, owner.address, NOW), 2);
    expect(await h.register(B, owner, true)).toEqual({ status: 200, body: { launcher: B, unlisted: true } });
  });
});

describe("per-round routes", () => {
  let h: ReturnType<typeof harness>;
  beforeEach(() => {
    // LAUNCHER is the featured round and one our factory created, as "Demo Day" is on testnet.
    h = harness({ defaultRound: { launcher: LAUNCHER, name: "Demo Day" } });
    h.chain.create(LAUNCHER, owner.address, LONG_AGO);
    h.chain.create(A, owner.address, LONG_AGO, { name: "morning movers", checkInGoal: 30 });
  });

  it("for the featured round they answer exactly as the single-round routes do", async () => {
    h.chain.joined.add(lower(alice));
    h.chain.joined.add(lower(bob));
    await h.checkIn(alice);
    h.chain.submit(lower(alice), TODAY);
    await h.checkIn(bob, 7000);

    const round = await h.get("/round");
    expect(await h.get(`/rounds/${LAUNCHER}`)).toEqual({ status: 200, body: { ...round.body, unlisted: false } });
    expect(await h.get(`/rounds/${getAddress(LAUNCHER)}`)).toEqual({ status: 200, body: { ...round.body, unlisted: false } });
    for (const who of [alice, bob, stranger]) {
      expect(await h.get(`/rounds/${LAUNCHER}/me/${who.address}`)).toEqual(await h.get(`/me/${who.address}`));
    }
    const members = await h.get("/members");
    expect(members.body).toHaveLength(2);
    expect(await h.get(`/rounds/${LAUNCHER}/members`)).toEqual(members);

    // Check-in: the same signed text (it already names the launcher), the same answer, one record.
    const single = await h.checkIn(bob, 7000);
    const named = await h.checkInTo(LAUNCHER, bob, 7000);
    expect(single.body).toMatchObject({ day: "2026-11-25", dayIndex: TODAY, repeat: true });
    expect(named).toEqual(single);
    expect(await h.store.getCheckIns(LAUNCHER)).toHaveLength(2);

    // And the same refusals.
    expect((await h.checkInTo(LAUNCHER, stranger)).body.error).toBe("not_a_member");
    expect((await h.checkIn(stranger)).body.error).toBe("not_a_member");
    expect((await h.checkInTo(LAUNCHER, alice)).body.error).toBe("already_checked_in");
    expect((await h.checkIn(alice)).body.error).toBe("already_checked_in");
    expect((await h.get(`/rounds/${LAUNCHER}/me/nope`)).body.error).toBe("bad_address");
  });

  it("another round has its own members, check-ins and signatures", async () => {
    h.chain.join(A, lower(alice));
    expect((await h.get(`/rounds/${A}`)).body).toMatchObject({ launcher: A, name: "morning movers", checkInGoal: 30, attesterReady: true, unlisted: false });
    expect((await h.get(`/rounds/${A}/me/${alice.address}`)).body).toMatchObject({ member: true, daysOf: 0, days: [] });
    expect((await h.get(`/me/${alice.address}`)).body.member).toBe(false);

    const res = await h.checkInTo(A, alice, 6214);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ day: "2026-11-25", dayIndex: TODAY, repeat: false });
    // The attester's signature is for this launcher: the contract of another round would reject it.
    const signer = (launcher: string) =>
      recoverMessageAddress({ message: { raw: checkInInner(97, launcher, alice.address, TODAY) }, signature: res.body.attesterSignature });
    expect(await signer(A)).toBe(VECTOR_ATTESTER);
    expect(await signer(LAUNCHER)).not.toBe(VECTOR_ATTESTER);

    expect(await h.store.getCheckIns(A)).toMatchObject([{ address: lower(alice), steps: 6214, day: "2026-11-25" }]);
    expect(await h.store.getCheckIns(LAUNCHER)).toEqual([]);
    expect((await h.get(`/rounds/${A}/me/${alice.address}`)).body).toMatchObject({ attestedToday: true, checkedInToday: false, streak: 1 });
    h.chain.submit(lower(alice), TODAY, A);
    expect((await h.get(`/rounds/${A}/me/${alice.address}`)).body).toMatchObject({ daysOf: 1, checkedInToday: true });
    expect((await h.get(`/rounds/${A}/members`)).body).toEqual([{ address: lower(alice), daysOf: 1, streak: 1, checkedInToday: true }]);
    expect((await h.get(`/rounds/${A}`)).body.totalCheckIns).toBe(1);
    // Nothing of it shows in the featured round.
    expect((await h.get("/members")).body).toEqual([]);
    expect((await h.get("/round")).body.totalCheckIns).toBe(0);
  });

  it("the rules of POST /checkin apply unchanged", async () => {
    h.chain.join(A, lower(alice));
    // A report signed for the featured round is not one for this round.
    const day = "2026-11-25";
    const forOther = await alice.signMessage({ message: `Cypher Run checkin ${LAUNCHER} ${day} 5000` });
    const wrong = await h.post(`/rounds/${A}/checkin`, { address: alice.address, steps: 5000, source: "healthkit", signature: forOther });
    expect([wrong.status, wrong.body.error]).toEqual([401, "bad_signature"]);
    expect((await h.checkInTo(A, alice, 999)).body.error).toBe("not_enough_steps");
    expect((await h.checkInTo(A, bob)).body.error).toBe("not_a_member");
    h.chain.rounds.get(A)!.launched = true;
    expect((await h.checkInTo(A, alice)).body.error).toBe("round_launched");
    h.chain.rounds.get(A)!.launched = false;
    h.clock = h.chain.rounds.get(A)!.deadline + 1;
    expect((await h.checkInTo(A, alice)).body.error).toBe("round_closed");
    expect(await h.store.getCheckIns(A)).toEqual([]);
  });

  it("503 when the round cannot be read", async () => {
    await h.get(`/rounds/${A}`);
    h.chain.down = true;
    for (const path of [`/rounds/${A}`, `/rounds/${A}/me/${alice.address}`, `/rounds/${LAUNCHER}`]) {
      const res = await h.get(path);
      expect([res.status, res.body.error]).toEqual([503, "chain_unavailable"]);
    }
    // A launcher not seen before: whether it is ours cannot be told either.
    expect((await h.get(`/rounds/${FOREIGN}`)).status).toBe(503);
  });
});

describe("a launcher from another factory", () => {
  it("404 no_round on every per-round route, and it is not in the list", async () => {
    const h = harness();
    h.chain.create(A, owner.address, LONG_AGO);
    // A real, readable CheckInLauncher with our attester, but our factory did not create it.
    h.chain.rounds.set(FOREIGN, { ...h.chain.rounds.get(A)!, name: "Somebody else's" });
    h.chain.join(FOREIGN, lower(alice));

    for (const path of [`/rounds/${FOREIGN}`, `/rounds/${FOREIGN}/me/${alice.address}`, `/rounds/${FOREIGN}/members`]) {
      const res = await h.get(path);
      expect([path, res.status, res.body.error]).toEqual([path, 404, "no_round"]);
    }
    const checkIn = await h.checkInTo(FOREIGN, alice);
    expect([checkIn.status, checkIn.body.error]).toEqual([404, "no_round"]);
    expect(await h.store.getCheckIns(FOREIGN)).toEqual([]);
    expect((await h.register(FOREIGN, alice, false)).status).toBe(404);
    expect(launchers((await h.get("/rounds")).body)).toEqual([LAUNCHER, A]);

    // Not an address at all is a different answer.
    const bad = await h.get("/rounds/0x1234");
    expect([bad.status, bad.body.error]).toEqual([400, "bad_launcher"]);
    expect((await h.get("/rounds/0x1234/members")).status).toBe(400);
  });
});

// The factory's event as this server decodes it, against the ABI the contracts folder exports and
// against a log taken from BSC testnet.
describe("CheckInLauncherCreated", () => {
  const abiFile = fileURLToPath(new URL("../../contracts/abi/CheckInLauncherFactory.json", import.meta.url));

  it.skipIf(!existsSync(abiFile))("the fragment matches contracts/abi", () => {
    const json = JSON.parse(readFileSync(abiFile, "utf8")) as any;
    const exported = (Array.isArray(json) ? json : json.abi).find((f: any) => f.type === "event" && f.name === "CheckInLauncherCreated");
    const shape = (f: any) => f.inputs.map((i: any) => [i.name, i.type, Boolean(i.indexed)]);
    expect(exported).toBeDefined();
    expect(shape(factoryAbi[0])).toEqual(shape(exported));
  });

  // The log of the round "morning movers", created from the app on 26 November 2026, as
  // eth_getLogs returned it.
  const LOG = {
    address: FACTORY,
    topics: [
      "0xed94e0617397203451d10ef884497281481cf818778db8ba4555231d1928856b",
      "0x00000000000000000000000074b9218cc901fa4b295c3b021c246e6f1022915b",
      "0x000000000000000000000000580d21e31b49d8d21ad1d4e79f676142577e2997",
    ],
    data: "0x863737c8137032388ef672bfbddb86c31970b8c29ec583a4b8e024ba00014240",
    blockHash: "0x3003513e1182c8dcc772a6fbd5ec74fd6d0d5dc1026e5cc10b210ae42006e81a",
    blockNumber: "0x8a1e5ee",
    blockTimestamp: "0x6b071a89",
    transactionHash: "0x84905dbb25d2d85e3f4165d239a91a74686daef4f80251e48407cb170fa93097",
    transactionIndex: "0x0",
    logIndex: "0x2",
    removed: false,
  };
  let rpc: Server | undefined;
  afterEach(() => rpc?.close());

  /** A JSON-RPC endpoint on this machine that answers the three calls discovery makes. */
  async function fakeRpc(log: Record<string, unknown>) {
    const calls: { method: string; params: any[] }[] = [];
    rpc = createServer((req, res) => {
      let raw = "";
      req.on("data", (chunk) => (raw += chunk));
      req.on("end", () => {
        const { id, method, params } = JSON.parse(raw);
        calls.push({ method, params });
        const result =
          method === "eth_blockNumber" ? "0x8a1e9c9" : method === "eth_getLogs" ? [log] : method === "eth_getBlockByNumber" ? { number: params[0], timestamp: "0x6b071a89", transactions: [] } : null;
        res.setHeader("content-type", "application/json");
        res.end(JSON.stringify({ jsonrpc: "2.0", id, result }));
      });
    });
    await new Promise<void>((resolve) => rpc!.listen(0, "127.0.0.1", resolve));
    const { port } = rpc.address() as { port: number };
    return { url: `http://127.0.0.1:${port}`, calls };
  }

  it("reads launcher, creator, block and time from a real log", async () => {
    const { url, calls } = await fakeRpc(LOG);
    const factory = createChain(url, undefined, getAddress(FACTORY)).factory!;
    expect(factory.address).toBe(FACTORY);
    expect(await factory.head()).toBe(144_828_873);
    expect(await factory.created(144_816_444, 144_828_873)).toEqual([
      { launcher: A, creator: "0x580d21e31b49d8d21ad1d4e79f676142577e2997", block: 144_827_886, createdAt: 1_795_627_657 },
    ]);
    const getLogs = calls.find((c) => c.method === "eth_getLogs")!;
    expect(getLogs.params[0]).toMatchObject({ address: FACTORY, fromBlock: "0x8a1b93c", toBlock: "0x8a1e9c9", topics: [LOG.topics[0]] });
    expect(calls.some((c) => c.method === "eth_getBlockByNumber")).toBe(false);
  });

  it("asks for the block when the node leaves the timestamp off the log", async () => {
    const { blockTimestamp: _, ...bare } = LOG;
    const { url, calls } = await fakeRpc(bare);
    const found = await createChain(url, undefined, FACTORY).factory!.created(144_827_886, 144_827_886);
    expect(found).toMatchObject([{ launcher: A, block: 144_827_886, createdAt: 1_795_627_657 }]);
    expect(calls.filter((c) => c.method === "eth_getBlockByNumber")).toHaveLength(1);
  });

  it("no factory, no discovery", () => {
    expect(createChain("http://127.0.0.1:9").factory).toBeUndefined();
  });
});

describe("from the environment", () => {
  // No RPC is listening at this address, and DATA_FILE is never written by these tests.
  const env = { RPC_URL: "http://127.0.0.1:9", DATA_FILE: "/nonexistent/cypher-run-test.json" } as NodeJS.ProcessEnv;
  afterEach(() => vi.restoreAllMocks());

  it("looks at our factory on BSC testnet from the block it was deployed in, unless told otherwise", () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const deployed = fileURLToPath(new URL("../../contracts/deployments/bsc-testnet.json", import.meta.url));
    if (existsSync(deployed)) {
      const record = JSON.parse(readFileSync(deployed, "utf8")) as { checkInLauncherFactory: string; deployedAt: number };
      expect(DEFAULT_FACTORY).toBe(record.checkInLauncherFactory);
      expect(DEFAULT_FACTORY_FROM_BLOCK).toBe(record.deployedAt);
    }
    expect(DEFAULT_FACTORY.toLowerCase()).toBe(FACTORY);
    expect(DEFAULT_FACTORY_FROM_BLOCK).toBe(FROM_BLOCK);
    const server = serverFromEnv(env);
    expect(server.rounds.enabled).toBe(true);
    expect(server.refreshSeconds).toBe(10);
    expect(serverFromEnv({ ...env, ROUNDS_REFRESH_SECONDS: "30", LOG_CHUNK_BLOCKS: "5000", FACTORY_FROM_BLOCK: "1", LAUNCHER_FACTORY: A }).refreshSeconds).toBe(30);
    expect(() => appFromEnv({ ...env, LAUNCHER_FACTORY: "0x1234" })).toThrow(/LAUNCHER_FACTORY/);
    expect(() => appFromEnv({ ...env, FACTORY_FROM_BLOCK: "-1" })).toThrow(/FACTORY_FROM_BLOCK/);
    expect(() => appFromEnv({ ...env, LOG_CHUNK_BLOCKS: "0" })).toThrow(/LOG_CHUNK_BLOCKS/);
    expect(() => appFromEnv({ ...env, ROUNDS_REFRESH_SECONDS: "1" })).toThrow(/ROUNDS_REFRESH_SECONDS/);
  });

  it("serves the new routes at the root and under /api, and says so when the chain cannot be reached", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const app = appFromEnv(env);
    for (const prefix of ["", "/api"]) {
      const bad = await app.request(`${prefix}/rounds/0x1234`);
      expect([bad.status, ((await bad.json()) as { error: string }).error]).toEqual([400, "bad_launcher"]);
      const post = await app.request(`${prefix}/rounds`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}" });
      expect([post.status, ((await post.json()) as { error: string }).error]).toEqual([400, "bad_launcher"]);
      const preflight = await app.request(`${prefix}/rounds`, { method: "OPTIONS" });
      expect(preflight.status).toBe(204);
      expect(preflight.headers.get("access-control-allow-methods")).toContain("POST");
    }
    // Nothing answers at the RPC address: the list and an unknown launcher are 503, not empty or 404.
    const list = await app.request("/api/rounds");
    expect([list.status, ((await list.json()) as { error: string }).error]).toEqual([503, "chain_unavailable"]);
    const unknown = await app.request(`/api/rounds/${A}`);
    expect([unknown.status, ((await unknown.json()) as { error: string }).error]).toEqual([503, "chain_unavailable"]);
  }, 20_000);

  it("the data file keeps the rounds found and the creators' choices across restarts", async () => {
    const dir = mkdtempSync(join(tmpdir(), "cypher-run-rounds-"));
    try {
      const file = join(dir, "store.json");
      const first = new LocalStore(file);
      // A store that has nothing of this yet writes neither key.
      await first.addMember(A, lower(alice), 1);
      expect(Object.keys(JSON.parse(readFileSync(file, "utf8"))).sort()).toEqual(["checkIns", "faucet", "roundMembers"]);
      const found = { factory: FACTORY, nextBlock: FROM_BLOCK + 50, rounds: [{ launcher: A, creator: lower(owner), block: FROM_BLOCK + 7, createdAt: NOW }] };
      await first.putDiscovery(found);
      await first.putListing(A, { unlisted: true, by: lower(owner), at: NOW + 5 });

      const second = new LocalStore(file);
      expect(await second.getDiscovery()).toEqual(found);
      expect(await second.getListing(A)).toEqual({ unlisted: true, by: lower(owner), at: NOW + 5 });
      expect(await second.getListing(B)).toBeUndefined();
      expect(await second.getMembers(A)).toEqual([lower(alice)]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
