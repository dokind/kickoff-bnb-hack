import { afterEach, describe, expect, it, vi } from "vitest";
import { generatePrivateKey } from "viem/accounts";
import type { OriginRegistryChain, TxStatus } from "../src/chain.js";
import { serverFromEnv } from "../src/config.js";
import { PENDING_GIVE_UP_MS, createOriginAnnouncer, hostFromSource, isPlainHost } from "../src/origin.js";
import { harness } from "./fakes.js";

const REGISTRY = "0xb9ad45dc177c801f10670f2aac03b467f1c367d2";
const ME = "0x2f2ab3da0b824f9ca3edd2580443ca0b271efdd7";
const HOST = "calm-river-blue-moon.trycloudflare.com";
const NEW_HOST = "quiet-forest-red-sun.trycloudflare.com";

/** An OriginRegistry in memory. A sent setOrigin stays pending until `mine()`. */
class FakeRegistry implements OriginRegistryChain {
  address = REGISTRY;
  sender = ME;
  announcerAddress = ME;
  origin = "";
  sent: string[] = [];
  /** Hash -> host for transactions not mined yet. */
  pendingTxs = new Map<`0x${string}`, string>();
  outcome = new Map<`0x${string}`, TxStatus>();
  down = false;
  failSend = false;

  private up() {
    if (this.down) throw new Error("rpc down at https://rpc.example/secret-key");
  }
  announcer = async () => {
    this.up();
    return this.announcerAddress;
  };
  read = async () => {
    this.up();
    return this.origin;
  };
  announce = async (host: string) => {
    this.up();
    if (this.failSend) throw new Error("nonce too low");
    this.sent.push(host);
    const hash = `0x${this.sent.length.toString(16).padStart(64, "0")}` as `0x${string}`;
    this.pendingTxs.set(hash, host);
    return hash;
  };
  status = async (hash: `0x${string}`): Promise<TxStatus> => {
    this.up();
    return this.outcome.get(hash) ?? (this.pendingTxs.has(hash) ? "pending" : "success");
  };
  /** Every pending setOrigin lands, in order. */
  mine() {
    for (const [hash, host] of this.pendingTxs) {
      this.origin = host;
      this.outcome.set(hash, "success");
    }
    this.pendingTxs.clear();
  }
}

function setup(host: () => Promise<string>) {
  const registry = new FakeRegistry();
  const logs: string[] = [];
  const warnings: string[] = [];
  let ms = 1_795_900_000_000;
  const announcer = createOriginAnnouncer({
    registry,
    host,
    intervalMs: 60_000,
    log: (l) => logs.push(l),
    warn: (l) => warnings.push(l),
    nowMs: () => ms,
  });
  return { registry, announcer, logs, warnings, advance: (by: number) => (ms += by) };
}

afterEach(() => vi.restoreAllMocks());

describe("plain hostnames", () => {
  it("accepts a quick tunnel host and other plain names", () => {
    for (const ok of [HOST, "api.example.com", "a-b.c1.io", "x.y"]) expect(isPlainHost(ok), ok).toBe(true);
  });
  it("refuses anything that is not a plain hostname", () => {
    for (const bad of [
      "",
      "localhost",
      "https://name.trycloudflare.com",
      "name.trycloudflare.com/",
      "name.trycloudflare.com:443",
      "name.trycloudflare.com/api",
      "user@name.trycloudflare.com",
      "name.trycloudflare.com.",
      "-name.trycloudflare.com",
      "name-.trycloudflare.com",
      "na_me.trycloudflare.com",
      "Name.trycloudflare.com",
      "name..trycloudflare.com",
      "name trycloudflare.com",
      "10.0.0.1",
      "[::1]",
      "evil.com\n",
      `${"a".repeat(64)}.com`,
      `${"a.".repeat(127)}com`,
      42,
      null,
    ]) {
      expect(isPlainHost(bad), String(bad)).toBe(false);
    }
  });
});

describe("the tunnel's /quicktunnel answer", () => {
  const answer = (status: number, body: unknown) =>
    (async () => new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;

  it("gives the hostname, lower-cased", async () => {
    expect(await hostFromSource("http://tunnel:20241/quicktunnel", answer(200, { hostname: "Calm-River.trycloudflare.com" }))).toBe(
      "calm-river.trycloudflare.com",
    );
  });
  it("fails on an error status or an answer without a hostname", async () => {
    await expect(hostFromSource("http://x/quicktunnel", answer(503, { hostname: HOST }))).rejects.toThrow();
    await expect(hostFromSource("http://x/quicktunnel", answer(200, { hostname: "" }))).resolves.toBe("");
    await expect(hostFromSource("http://x/quicktunnel", answer(200, {}))).rejects.toThrow(/hostname/);
    await expect(hostFromSource("http://x/quicktunnel", answer(200, { hostname: 7 }))).rejects.toThrow(/hostname/);
  });
});

describe("origin announcer", () => {
  it("an unchanged host sends nothing", async () => {
    const t = setup(async () => HOST);
    t.registry.origin = HOST;
    await t.announcer.tick();
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([]);
    expect(t.announcer.health()).toMatchObject({ registry: REGISTRY, host: HOST, onChain: HOST, lastTx: null, pending: false, lastError: null });
    expect(t.logs).toEqual([]);
  });

  it("a changed host is sent once, logged with the tx hash, and not again once mined", async () => {
    let host = HOST;
    const t = setup(async () => host);
    t.registry.origin = HOST;
    await t.announcer.tick();
    host = NEW_HOST; // the tunnel restarted
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([NEW_HOST]);
    const { lastTx } = t.announcer.health();
    expect(lastTx).toMatch(/^0x[0-9a-f]{64}$/);
    expect(t.announcer.health()).toMatchObject({ host: NEW_HOST, onChain: HOST, lastTxHost: NEW_HOST, pending: true });
    expect(t.logs.join("\n")).toContain(lastTx!);
    expect(t.logs.join("\n")).toContain(NEW_HOST);

    t.registry.mine();
    await t.announcer.tick(); // sees the receipt
    await t.announcer.tick(); // reads the registry: equal
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([NEW_HOST]);
    expect(t.announcer.health()).toMatchObject({ onChain: NEW_HOST, lastTx, pending: false, lastError: null });
  });

  it("the first announce on an empty registry", async () => {
    const t = setup(async () => HOST);
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([HOST]);
    expect(t.logs[0]).toContain('registry said ""');
  });

  it("a pending transaction is not doubled, by later checks or by checks that overlap", async () => {
    const t = setup(async () => NEW_HOST);
    t.registry.origin = HOST;
    await Promise.all([t.announcer.tick(), t.announcer.tick(), t.announcer.tick()]);
    expect(t.registry.sent).toEqual([NEW_HOST]);
    for (let i = 0; i < 5; i++) {
      t.advance(60_000);
      await t.announcer.tick();
    }
    expect(t.registry.sent).toEqual([NEW_HOST]);
    expect(t.announcer.health().pending).toBe(true);
  });

  it("a transaction with no receipt for ten minutes is given up and sent again", async () => {
    const t = setup(async () => NEW_HOST);
    t.registry.origin = HOST;
    await t.announcer.tick();
    t.advance(PENDING_GIVE_UP_MS);
    await t.announcer.tick();
    expect(t.announcer.health()).toMatchObject({ pending: false, lastError: "tx_dropped" });
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([NEW_HOST, NEW_HOST]);
  });

  it("a reverted transaction is reported and tried again on a later check", async () => {
    const t = setup(async () => NEW_HOST);
    t.registry.origin = HOST;
    await t.announcer.tick();
    t.registry.outcome.set(t.announcer.health().lastTx as `0x${string}`, "reverted");
    await t.announcer.tick();
    expect(t.announcer.health()).toMatchObject({ pending: false, lastError: "tx_reverted" });
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([NEW_HOST, NEW_HOST]);
  });

  it("a bad host is refused and nothing is sent", async () => {
    for (const bad of ["https://evil.example.com", "evil.example.com/path", "evil.example.com:8443", "localhost", ""]) {
      const t = setup(async () => bad);
      await t.announcer.tick();
      expect(t.registry.sent, bad).toEqual([]);
      expect(t.announcer.health()).toMatchObject({ host: null, lastError: "bad_host" });
      expect(t.warnings).toHaveLength(1);
    }
  });

  it("the source being down sends nothing, logs once, and the next check after it is back sends", async () => {
    let up = false;
    const t = setup(async () => {
      if (!up) throw new Error("connect ECONNREFUSED tunnel:20241");
      return NEW_HOST;
    });
    t.registry.origin = HOST;
    await t.announcer.tick();
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([]);
    expect(t.announcer.health()).toMatchObject({ lastError: "source_unavailable", checkedAt: expect.any(Number) });
    expect(t.warnings).toHaveLength(1);
    up = true;
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([NEW_HOST]);
  });

  it("an RPC that is down sends nothing, and no log line repeats the error's text", async () => {
    const t = setup(async () => NEW_HOST);
    t.registry.down = true;
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([]);
    expect(t.announcer.health().lastError).toBe("registry_unavailable");
    t.registry.down = false;
    t.registry.failSend = true;
    await t.announcer.tick();
    expect(t.announcer.health().lastError).toBe("send_failed");
    expect([...t.logs, ...t.warnings].join("\n")).not.toMatch(/secret-key|nonce too low|rpc\.example/);
    t.registry.failSend = false;
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([NEW_HOST]);
  });

  it("sends nothing when the attester is not the registry's announcer", async () => {
    const t = setup(async () => NEW_HOST);
    t.registry.announcerAddress = "0x000000000000000000000000000000000000dead";
    await t.announcer.tick();
    await t.announcer.tick();
    expect(t.registry.sent).toEqual([]);
    expect(t.announcer.health().lastError).toBe("not_announcer");
  });

  it("start() checks at once and on its timer, and stops", async () => {
    vi.useFakeTimers();
    try {
      let host = HOST;
      const registry = new FakeRegistry();
      registry.origin = HOST;
      const reads = vi.spyOn(registry, "read");
      const announcer = createOriginAnnouncer({ registry, host: async () => host, intervalMs: 60_000, log: () => {}, warn: () => {} });
      const stop = announcer.start();
      await vi.advanceTimersByTimeAsync(0);
      expect(reads).toHaveBeenCalledTimes(1);
      host = NEW_HOST;
      await vi.advanceTimersByTimeAsync(60_000);
      expect(registry.sent).toEqual([NEW_HOST]);
      stop();
      await vi.advanceTimersByTimeAsync(600_000);
      expect(reads).toHaveBeenCalledTimes(2);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("GET /health", () => {
  it("shows the last known host and the last announce tx, at the root and under /api", async () => {
    const t = setup(async () => NEW_HOST);
    t.registry.origin = HOST;
    await t.announcer.tick();
    const h = harness({ originHealth: t.announcer.health });
    const expected = {
      service: "cypher-run-verifier",
      ok: true,
      attester: "0xfcad0b19bb29d4674531d6f115237e16afce377c",
      faucetWallet: null,
      origin: { registry: REGISTRY, host: NEW_HOST, onChain: HOST, lastTx: t.announcer.health().lastTx, lastTxHost: NEW_HOST, pending: true },
    };
    expect(await h.get("/health")).toMatchObject({ status: 200, body: expected });
  });

  it("origin is null when the announcer is off; served under /api by the env-built app", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const env = { RPC_URL: "http://127.0.0.1:9", DATA_FILE: "/nonexistent/cypher-run-test.json" } as NodeJS.ProcessEnv;
    const { app } = serverFromEnv(env);
    for (const path of ["/health", "/api/health"]) {
      const res = await app.request(path);
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({ service: "cypher-run-verifier", ok: true, attester: null, faucetWallet: null, origin: null });
    }
  });
});

describe("origin settings from the environment", () => {
  const env = { RPC_URL: "http://127.0.0.1:9", DATA_FILE: "/nonexistent/cypher-run-test.json" } as NodeJS.ProcessEnv;
  const key = generatePrivateKey();

  it("off without ORIGIN_REGISTRY; off with a warning without the attester key", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
    expect(serverFromEnv({ ...env, ATTESTER_PRIVATE_KEY: key }).origin).toBeUndefined();
    expect(serverFromEnv({ ...env, ORIGIN_REGISTRY: REGISTRY }).origin).toBeUndefined();
    expect(warn.mock.calls.flat().join("\n")).toMatch(/ORIGIN_REGISTRY/);
  });

  it("on with the registry and the key; the sender is the attester", () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const { origin } = serverFromEnv({ ...env, ATTESTER_PRIVATE_KEY: key, ORIGIN_REGISTRY: REGISTRY });
    expect(origin?.health()).toMatchObject({ registry: REGISTRY, host: null, lastTx: null, pending: false });
  });

  it("ORIGIN_HOST is used as given and validated at start", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const fetchSpy = vi.spyOn(globalThis, "fetch");
    const on = { ...env, ATTESTER_PRIVATE_KEY: key, ORIGIN_REGISTRY: REGISTRY };
    const { origin } = serverFromEnv({ ...on, ORIGIN_HOST: "API.Example.com" });
    // No registry is listening, so the check stops at the read; the host was found without asking the tunnel.
    await origin!.tick();
    expect(origin!.health()).toMatchObject({ host: "api.example.com", lastError: "registry_unavailable" });
    // The only requests made were to the RPC, none to the tunnel.
    expect(fetchSpy.mock.calls.map(([url]) => String(url instanceof Request ? url.url : url)).filter((u) => !u.startsWith("http://127.0.0.1:9"))).toEqual([]);
    for (const bad of ["https://api.example.com", "api.example.com/x", "localhost"]) {
      expect(() => serverFromEnv({ ...on, ORIGIN_HOST: bad })).toThrow(/ORIGIN_HOST/);
    }
  });

  it("refuses a bad registry, interval or source", () => {
    vi.spyOn(console, "warn").mockImplementation(() => undefined);
    const on = { ...env, ATTESTER_PRIVATE_KEY: key, ORIGIN_REGISTRY: REGISTRY };
    expect(() => serverFromEnv({ ...on, ORIGIN_REGISTRY: "0x1234" })).toThrow(/ORIGIN_REGISTRY/);
    for (const bad of ["0", "5", "3601", "abc"]) expect(() => serverFromEnv({ ...on, ORIGIN_CHECK_SECONDS: bad })).toThrow(/ORIGIN_CHECK_SECONDS/);
    expect(() => serverFromEnv({ ...on, ORIGIN_CHECK_SECONDS: "30" })).not.toThrow();
    expect(() => serverFromEnv({ ...on, ORIGIN_SOURCE_URL: "tunnel:20241/quicktunnel" })).toThrow(/ORIGIN_SOURCE_URL/);
  });
});
