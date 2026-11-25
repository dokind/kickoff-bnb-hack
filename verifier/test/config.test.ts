import { afterEach, describe, expect, it, vi } from "vitest";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { appFromEnv } from "../src/config.js";
import { recoverMessageAddress } from "viem";
import { PRODUCT_NAME, SERVICE_NAME, checkInMessage, faucetMessage } from "../src/product.js";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { LocalStore } from "../src/store.js";

// Nothing here reaches the RPC: the address is never contacted by the routes these tests call.
// DATA_FILE points nowhere and is only written on a put.
const env = { RPC_URL: "http://127.0.0.1:9", DATA_FILE: "/nonexistent/cypher-run-test.json" } as NodeJS.ProcessEnv;

afterEach(() => vi.restoreAllMocks());

describe("product name", () => {
  // The app builds the same texts from its own constant (app/lib/config.dart) and pins the same two
  // signatures in app/test/services_test.dart, made with its test key.
  const APP_TEST_ADDRESS = "0xfcad0b19bb29d4674531d6f115237e16afce377c";
  const LAUNCHER = "0x1000000000000000000000000000000000000001";

  it("is Cypher Run, and the service name is built from it", () => {
    expect(PRODUCT_NAME).toBe("Cypher Run");
    expect(SERVICE_NAME).toBe("cypher-run-verifier");
  });

  it("builds the texts a member signs, byte for byte as the app does", async () => {
    const checkIn = checkInMessage(LAUNCHER, "2026-11-25", 6214);
    const faucet = faucetMessage(APP_TEST_ADDRESS);
    expect(checkIn).toBe(`Cypher Run checkin ${LAUNCHER} 2026-11-25 6214`);
    expect(faucet).toBe(`Cypher Run faucet ${APP_TEST_ADDRESS}`);
    const signer = async (message: string, signature: `0x${string}`) =>
      (await recoverMessageAddress({ message, signature })).toLowerCase();
    expect(
      await signer(
        checkIn,
        "0xbe5e14862e2dc6280ef3e223922bc904426546c063fc0dd45aadacd5d72a810a793954c447e70f4a4635300757543dacb3c936abb5bb6b958ca05dddb6bb1edc1c",
      ),
    ).toBe(APP_TEST_ADDRESS);
    expect(
      await signer(
        faucet,
        "0x27f14d6ae2fae90c9b299470c6f7b506982a744fd3dcd37eafebd292d760deb81d269fd8f50023efdccc7ba6be924a7e6b6ea7521220ce9ab1824c766d72463f1c",
      ),
    ).toBe(APP_TEST_ADDRESS);
  });
});

describe("app built from the environment", () => {
  it("serves every route at the root and again under /api (the web app's same-origin path)", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const app = appFromEnv(env);
    for (const prefix of ["", "/api"]) {
      const home = await app.request(prefix || "/");
      expect(home.status).toBe(200);
      expect(await home.json()).toEqual({ service: "cypher-run-verifier", ok: true });
      expect(home.headers.get("access-control-allow-origin")).toBe("*");
      for (const path of ["/round", "/members", "/me/0x00000000000000000000000000000000000000aa"]) {
        const res = await app.request(prefix + path);
        expect(res.status).toBe(404);
        expect(((await res.json()) as { error: string }).error).toBe("no_round");
      }
      const preflight = await app.request(`${prefix}/checkin`, { method: "OPTIONS" });
      expect(preflight.status).toBe(204);
    }
  });

  it("the routes of the earlier club-season product are gone", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const app = appFromEnv(env);
    for (const path of ["/seasons/past", "/leaderboard", "/world/leaderboard", "/seasons/0x00000000000000000000000000000000000000aa"]) {
      expect((await app.request(path)).status).toBe(404);
      expect((await app.request(`/api${path}`)).status).toBe(404);
    }
    const kickoff = await app.request("/seasons/0x00000000000000000000000000000000000000aa/kickoff", { method: "POST" });
    expect(kickoff.status).toBe(404);
  });

  it("without a key it signs nothing and the faucet is off, even with FAUCET_ENABLED=true", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const who = privateKeyToAccount(generatePrivateKey());
    const signature = await who.signMessage({ message: faucetMessage(who.address.toLowerCase()) });
    for (const extra of [{}, { FAUCET_ENABLED: "true" }]) {
      const app = appFromEnv({ ...env, ...extra });
      const res = await app.request("/api/faucet", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ address: who.address, signature }),
      });
      expect(await res.json()).toMatchObject({ funded: false, bnbTx: null, reason: "faucet_disabled" });
    }
    expect(warn).toHaveBeenCalled();
  });

  it("starts with a key under either name, with or without the 0x prefix", () => {
    const key = generatePrivateKey();
    expect(() => appFromEnv({ ...env, ATTESTER_PRIVATE_KEY: key })).not.toThrow();
    expect(() => appFromEnv({ ...env, VERIFIER_PRIVATE_KEY: key.slice(2) })).not.toThrow();
  });

  it("an error about a malformed key does not repeat the key", () => {
    const bad = "0xnot-a-key-0123456789abcdef";
    try {
      appFromEnv({ ...env, ATTESTER_PRIVATE_KEY: bad });
      expect.unreachable();
    } catch (e) {
      expect(String(e)).toContain("ATTESTER_PRIVATE_KEY");
      expect(String(e)).not.toContain("not-a-key");
    }
  });

  it("refuses to start without an RPC, on another chain, or with settings it cannot use", () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    expect(() => appFromEnv({} as NodeJS.ProcessEnv)).toThrow(/RPC_URL/);
    expect(() => appFromEnv({ ...env, CHAIN_ID: "56" })).toThrow(/CHAIN_ID/);
    expect(() => appFromEnv({ ...env, CHAIN_ID: "97" })).not.toThrow();
    expect(() => appFromEnv({ ...env, CURRENT_LAUNCHER: "0x1234" })).toThrow(/CURRENT_LAUNCHER/);
    for (const bad of ["0", "-5", "abc", "80001", "1000.5"]) {
      expect(() => appFromEnv({ ...env, MIN_STEPS: bad })).toThrow(/MIN_STEPS/);
    }
    expect(() => appFromEnv({ ...env, MIN_STEPS: "4000", ALLOW_SELF_REPORTED: "true" })).not.toThrow();
  });
});

describe("data file", () => {
  it("keeps the round, members, check-ins and faucet record across restarts", async () => {
    const dir = mkdtempSync(join(tmpdir(), "cypher-run-store-"));
    try {
      const file = join(dir, "nested", "store.json");
      const first = new LocalStore(file);
      await first.putRound({ launcher: "0xl", name: "November", setAt: 5 });
      await first.addMember("0xl", "0xa", 10);
      await first.addMember("0xl", "0xa", 99); // already known: first seen stays
      await first.putCheckIn("0xl", { address: "0xa", day: "2026-11-25", dayIndex: 20782, steps: 5000, source: "self", selfReported: true, at: 11 });
      await first.putFaucetDrip({ address: "0xa", ip: "1.1.1.1", at: 12, bnbTx: "0x1" });
      expect(existsSync(file)).toBe(true);

      const second = new LocalStore(file);
      expect(await second.getRound()).toEqual({ launcher: "0xl", name: "November", setAt: 5 });
      expect(await second.getMembers("0xl")).toEqual(["0xa"]);
      expect(await second.getCheckIns("0xl")).toMatchObject([{ address: "0xa", steps: 5000, selfReported: true }]);
      expect(await second.getFaucetDrips()).toHaveLength(1);
      expect(JSON.parse(readFileSync(file, "utf8")).roundMembers["0xl"]["0xa"]).toBe(10);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it("reads a file left by the earlier server for its faucet record only", async () => {
    const dir = mkdtempSync(join(tmpdir(), "cypher-run-store-"));
    try {
      const file = join(dir, "store.json");
      writeFileSync(
        file,
        JSON.stringify({
          seasons: { "0xold": { launcher: "0xold" } },
          members: { "0xold": { "0xa": { address: "0xa", goalValue: 5 } } },
          worldMembers: {},
          faucet: { "0xa": { address: "0xa", ip: "1.1.1.1", at: 1, bnbTx: "0x1", usdTx: "0x2" } },
        }),
      );
      const store = new LocalStore(file);
      expect(await store.getRound()).toBeUndefined();
      expect(await store.getMembers("0xold")).toEqual([]);
      expect(await store.getFaucetDrips()).toMatchObject([{ address: "0xa", bnbTx: "0x1" }]);
      // The first write leaves the old records out.
      await store.addMember("0xnew", "0xb", 2);
      expect(Object.keys(JSON.parse(readFileSync(file, "utf8"))).sort()).toEqual(["checkIns", "faucet", "roundMembers"]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
