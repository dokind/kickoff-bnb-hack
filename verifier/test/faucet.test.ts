import { beforeEach, describe, expect, it } from "vitest";
import { getAddress } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { createApp, type Deps } from "../src/app.js";
import { DRIP_BNB_WEI, GLOBAL_CAP, MIN_BALANCE_WEI, PER_IP_PER_HOUR, RESERVE_WEI, faucetRefusal } from "../src/faucet.js";
import { faucetMessage } from "../src/product.js";
import { LocalStore } from "../src/store.js";
import type { FaucetDrip } from "../src/types.js";
import { FakeChain, T, lower } from "./fakes.js";

const BNB = 10n ** 18n;

// Throwaway keys generated per run.
const accounts = Array.from({ length: 8 }, () => privateKeyToAccount(generatePrivateKey()));
const [alice, bob] = accounts as [(typeof accounts)[0], (typeof accounts)[0]];

describe("faucet limits (pure)", () => {
  const drip = (address: string, ip: string, at: number, failed = false): FaucetDrip => ({ address, ip, at, bnbTx: "0x1", failed });

  it("once per address, unless the first try failed", () => {
    expect(faucetRefusal([], "0xa", "1.1.1.1", 1000)).toBeNull();
    expect(faucetRefusal([drip("0xa", "9.9.9.9", 10)], "0xa", "1.1.1.1", 1000)).toBe("already_funded");
    expect(faucetRefusal([drip("0xa", "9.9.9.9", 10, true)], "0xa", "1.1.1.1", 1000)).toBeNull();
    expect(faucetRefusal([drip("0xa", "9.9.9.9", 10)], "0xb", "1.1.1.1", 1000)).toBeNull();
  });

  it(`stops for good after ${GLOBAL_CAP} wallets; failed tries do not count`, () => {
    const full = Array.from({ length: GLOBAL_CAP }, (_, i) => drip(`0x${i}`, `10.0.0.${i}`, 10));
    expect(faucetRefusal(full, "0xnew", "1.1.1.1", 10_000)).toBe("cap_reached");
    expect(faucetRefusal(full.slice(1), "0xnew", "1.1.1.1", 10_000)).toBeNull();
    expect(faucetRefusal([...full.slice(1), drip("0xf", "2.2.2.2", 10, true)], "0xnew", "1.1.1.1", 10_000)).toBeNull();
  });

  it(`allows ${PER_IP_PER_HOUR} per IP in any hour`, () => {
    const now = 100_000;
    const recent = Array.from({ length: PER_IP_PER_HOUR }, (_, i) => drip(`0x${i}`, "1.1.1.1", now - 3599 + i));
    expect(faucetRefusal(recent, "0xnew", "1.1.1.1", now)).toBe("rate_limited");
    expect(faucetRefusal(recent, "0xnew", "2.2.2.2", now)).toBeNull();
    expect(faucetRefusal(recent.slice(1), "0xnew", "1.1.1.1", now)).toBeNull();
    // The oldest one is exactly an hour old a second later.
    expect(faucetRefusal(recent, "0xnew", "1.1.1.1", now + 1)).toBeNull();
  });
});

describe("POST /faucet", () => {
  let clock: number;
  let store: LocalStore;
  let app: ReturnType<typeof createApp>;
  let chain: FakeChain;
  let balances: Map<string, bigint>;
  let walletBalance: bigint;
  let sent: { to: string; amount: bigint }[];
  let failSend: boolean;
  let failReads: boolean;

  function start(deps: Partial<Deps> = {}) {
    app = createApp({
      store,
      chain,
      now: () => clock,
      faucetEnabled: true,
      clientIp: (c) => c.req.header("x-test-ip") ?? "203.0.113.1",
      ...deps,
    });
  }
  async function ask(who: (typeof accounts)[0], ip?: string, signedAs: string = lower(who)) {
    const signature = await who.signMessage({ message: faucetMessage(signedAs) });
    const res = await app.request("/faucet", {
      method: "POST",
      headers: { "content-type": "application/json", ...(ip ? { "x-test-ip": ip } : {}) },
      body: JSON.stringify({ address: who.address, signature }),
    });
    return { status: res.status, body: (await res.json()) as Record<string, unknown> };
  }

  beforeEach(() => {
    clock = T("2026-11-25T08:00:00Z");
    store = new LocalStore();
    balances = new Map();
    walletBalance = BNB;
    sent = [];
    failSend = failReads = false;
    chain = new FakeChain();
    chain.balanceOf = async (address) => {
      if (failReads) throw new Error("rpc down");
      return balances.get(address) ?? 0n;
    };
    chain.faucet = {
      balance: async () => walletBalance,
      sendBnb: async (to, amount) => {
        if (failSend) throw new Error("rpc down");
        // A slow node, so overlapping requests would interleave if they were not queued.
        await new Promise((r) => setTimeout(r, 5));
        sent.push({ to, amount });
        walletBalance -= amount;
        balances.set(to, (balances.get(to) ?? 0n) + amount);
        return `0xbnb${sent.length}`;
      },
    };
    start();
  });

  it("sends 0.03 test BNB to a new wallet, and no test USD", async () => {
    const { status, body } = await ask(alice);
    expect(status).toBe(200);
    expect(body).toEqual({ funded: true, bnbTx: "0xbnb1" });
    expect(DRIP_BNB_WEI).toBe(3n * 10n ** 16n);
    expect(sent).toEqual([{ to: lower(alice), amount: 3n * 10n ** 16n }]);
    expect(await store.getFaucetDrips()).toEqual([{ address: lower(alice), ip: "203.0.113.1", at: clock, bnbTx: "0xbnb1" }]);
  });

  it("works with no round set: a wallet needs gas before it can join one", async () => {
    expect((await app.request("/round")).status).toBe(404);
    expect((await ask(alice)).body.funded).toBe(true);
  });

  it("accepts a signature over the checksummed address too", async () => {
    expect((await ask(alice, undefined, getAddress(alice.address))).body.funded).toBe(true);
  });

  it("is off unless FAUCET_ENABLED=true, and off without a wallet", async () => {
    start({ faucetEnabled: undefined });
    expect((await ask(alice)).body).toMatchObject({ funded: false, bnbTx: null, reason: "faucet_disabled" });
    chain.faucet = undefined;
    start();
    expect((await ask(alice)).body.reason).toBe("faucet_disabled");
    expect(sent).toEqual([]);
  });

  it("needs the wallet's own signature", async () => {
    const forged = await bob.signMessage({ message: faucetMessage(lower(alice)) });
    const res = await app.request("/faucet", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ address: alice.address, signature: forged }),
    });
    expect(res.status).toBe(401);
    expect(((await res.json()) as { error: string }).error).toBe("bad_signature");
    // A signature for someone else's address does not work either.
    expect((await ask(alice, undefined, lower(bob))).status).toBe(401);
    const bad = await app.request("/faucet", { method: "POST", body: JSON.stringify({ address: "nope" }) });
    expect(bad.status).toBe(400);
    expect(sent).toEqual([]);
  });

  it("funds an address once, even after the wallet has spent it all", async () => {
    expect((await ask(alice)).body.funded).toBe(true);
    balances.set(lower(alice), 0n);
    clock += 30 * 86_400;
    const again = await ask(alice, "198.51.100.7");
    expect(again.status).toBe(200);
    expect(again.body).toMatchObject({ funded: false, bnbTx: null, reason: "already_funded" });
    expect(sent).toHaveLength(1);
  });

  it("two requests at the same moment still pay once", async () => {
    const [a, b] = await Promise.all([ask(alice), ask(alice)]);
    expect([a.body.funded, b.body.funded].sort()).toEqual([false, true]);
    expect(sent).toHaveLength(1);
  });

  it("does not fund a wallet that already holds 0.002 test BNB or more", async () => {
    balances.set(lower(alice), MIN_BALANCE_WEI);
    expect((await ask(alice)).body).toMatchObject({ funded: false, reason: "has_funds" });
    expect(await store.getFaucetDrips()).toEqual([]);
    // Just under the line is funded, and being turned away earlier did not use up the one payout.
    balances.set(lower(alice), MIN_BALANCE_WEI - 1n);
    expect((await ask(alice)).body.funded).toBe(true);
  });

  it(`limits one IP to ${PER_IP_PER_HOUR} wallets an hour`, async () => {
    for (let i = 0; i < PER_IP_PER_HOUR; i++) {
      clock += 60;
      expect((await ask(accounts[i]!)).body.funded).toBe(true);
    }
    clock += 60;
    const sixth = accounts[PER_IP_PER_HOUR]!;
    expect((await ask(sixth)).body).toMatchObject({ funded: false, reason: "rate_limited" });
    // Another network is not affected, and the first IP is let in again once an hour has passed.
    expect((await ask(accounts[6]!, "198.51.100.7")).body.funded).toBe(true);
    clock += 3600 - PER_IP_PER_HOUR * 60;
    expect((await ask(sixth)).body.funded).toBe(true);
    expect(sent).toHaveLength(PER_IP_PER_HOUR + 2);
  });

  it(`stops after ${GLOBAL_CAP} wallets in total`, async () => {
    for (let i = 0; i < GLOBAL_CAP - 1; i++) {
      await store.putFaucetDrip({ address: `0x${(i + 1).toString(16).padStart(40, "0")}`, ip: `10.0.${i >> 8}.${i & 255}`, at: clock - 86_400, bnbTx: "0x1" });
    }
    expect((await ask(alice)).body.funded).toBe(true); // number 200
    expect((await ask(bob, "198.51.100.7")).body).toMatchObject({ funded: false, reason: "cap_reached" });
    clock += 365 * 86_400;
    expect((await ask(bob, "198.51.100.7")).body.reason).toBe("cap_reached");
    expect(sent).toHaveLength(1);
  });

  it("keeps test BNB back in the server wallet", async () => {
    walletBalance = DRIP_BNB_WEI + RESERVE_WEI - 1n;
    expect((await ask(alice)).body).toMatchObject({ funded: false, reason: "faucet_empty" });
    walletBalance = DRIP_BNB_WEI + RESERVE_WEI;
    expect((await ask(alice)).body.funded).toBe(true);
  });

  it("sends nothing when the chain cannot be read", async () => {
    failReads = true;
    expect((await ask(alice)).body).toMatchObject({ funded: false, reason: "chain_unavailable" });
    expect(sent).toEqual([]);
    failReads = false;
    expect((await ask(alice)).body.funded).toBe(true);
  });

  it("a failed transfer can be asked for again", async () => {
    failSend = true;
    expect((await ask(alice)).body).toMatchObject({ funded: false, bnbTx: null, reason: "send_failed" });
    failSend = false;
    expect((await ask(alice)).body).toEqual({ funded: true, bnbTx: "0xbnb1" });
  });
});
