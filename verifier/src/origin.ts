// Origin announcer: keeps OriginRegistry.origin() equal to the host this server is reached at.
//
// The server sits behind a Cloudflare quick tunnel whose host changes whenever the tunnel restarts.
// The apps read the host from the OriginRegistry on chain instead of having it built in, so every
// ORIGIN_CHECK_SECONDS this server finds its public host (ORIGIN_HOST, or the tunnel's own
// /quicktunnel answer), reads origin() from the registry, and sends setOrigin(host) from the
// attester key when the two differ.
//
// It never blocks request handling: each check runs on a timer, one at a time. A failed step is
// logged and tried again on the next check. While a setOrigin transaction is pending no second
// one is sent. Log lines name the host and the transaction hash, never an error's own text (an RPC
// error can contain the RPC's address, which may hold a key).
import type { OriginRegistryChain, TxStatus } from "./chain.js";

/** How often the host is checked, unless ORIGIN_CHECK_SECONDS says otherwise. */
export const DEFAULT_ORIGIN_CHECK_SECONDS = 60;
/** Where cloudflared's metrics server says which quick tunnel host it got. */
export const DEFAULT_ORIGIN_SOURCE_URL = "http://tunnel:20241/quicktunnel";
/** A setOrigin with no receipt after this long is treated as dropped, and may be sent again. */
export const PENDING_GIVE_UP_MS = 10 * 60_000;
/** The source must answer within this long. */
const SOURCE_TIMEOUT_MS = 5_000;

/**
 * True for a plain DNS hostname such as "name.trycloudflare.com": letters, digits and hyphens in
 * dot-separated labels, at least two labels, no scheme, port, path, user, IP literal or trailing dot.
 * Lower-case only; callers lower-case first.
 */
export function isPlainHost(host: unknown): host is string {
  if (typeof host !== "string" || host.length === 0 || host.length > 253) return false;
  const labels = host.split(".");
  if (labels.length < 2) return false;
  if (!labels.every((l) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(l))) return false;
  // The last label is a name, not a number: "10.0.0.1" is an address, not a host.
  return /[a-z]/.test(labels[labels.length - 1]!);
}

/** The host from a cloudflared /quicktunnel answer, {"hostname":"<name>.trycloudflare.com"}.
 *  Returned as given (lower-cased); the announcer validates it. */
export async function hostFromSource(url: string, fetchImpl: typeof fetch = fetch): Promise<string> {
  const res = await fetchImpl(url, { signal: AbortSignal.timeout(SOURCE_TIMEOUT_MS) });
  if (!res.ok) throw new Error(`source answered ${res.status}`);
  const body = (await res.json()) as { hostname?: unknown };
  if (typeof body?.hostname !== "string") throw new Error("source answer has no hostname");
  return body.hostname.trim().toLowerCase();
}

/** What GET /health shows about the announcer. */
export interface OriginHealth {
  /** The OriginRegistry's address. */
  registry: string;
  /** This server's public host, as last found (ORIGIN_HOST or the tunnel). Null until found. */
  host: string | null;
  /** origin() as last read from the registry. Null until read. */
  onChain: string | null;
  /** The last setOrigin transaction this server sent, and the host it set. */
  lastTx: string | null;
  lastTxHost: string | null;
  /** Unix seconds of lastTx. */
  lastTxAt: number | null;
  /** True while lastTx has no receipt yet. */
  pending: boolean;
  /** Unix seconds of the last finished check. */
  checkedAt: number | null;
  /** What stopped the last check, as a code; null when it went through. */
  lastError: OriginError | null;
}

export type OriginError =
  | "source_unavailable"
  | "bad_host"
  | "registry_unavailable"
  | "not_announcer"
  | "send_failed"
  | "tx_reverted"
  | "tx_dropped";

export interface OriginAnnouncer {
  /** One check. Safe to call at any time; a call while another runs returns at once. */
  tick(): Promise<void>;
  /** Checks now and then every `intervalMs` until the returned function is called. */
  start(): () => void;
  health(): OriginHealth;
}

export interface AnnouncerDeps {
  registry: OriginRegistryChain;
  /** This server's public host: ORIGIN_HOST, or a read of ORIGIN_SOURCE_URL. */
  host: () => Promise<string>;
  intervalMs: number;
  log?: (line: string) => void;
  warn?: (line: string) => void;
  nowMs?: () => number;
}

export function createOriginAnnouncer({
  registry,
  host: findHost,
  intervalMs,
  log = (l) => console.log(l),
  warn = (l) => console.warn(l),
  nowMs = () => Date.now(),
}: AnnouncerDeps): OriginAnnouncer {
  const state: OriginHealth = {
    registry: registry.address,
    host: null,
    onChain: null,
    lastTx: null,
    lastTxHost: null,
    lastTxAt: null,
    pending: false,
    checkedAt: null,
    lastError: null,
  };
  let pendingSince = 0;
  /** True once the registry confirmed our key is its announcer. */
  let allowed = false;
  let running = false;
  /** The last error that was logged, so a repeated failure is logged once, not every check. */
  let logged: OriginError | null = null;

  const seconds = () => Math.floor(nowMs() / 1000);
  const fail = (code: OriginError, line: string) => {
    state.lastError = code;
    if (logged !== code) warn(`Origin: ${line}`);
    logged = code;
  };

  async function check() {
    // 1. A transaction already sent: wait for it before anything else.
    if (state.pending && state.lastTx) {
      let status: TxStatus;
      try {
        status = await registry.status(state.lastTx as `0x${string}`);
      } catch {
        return fail("registry_unavailable", "could not read the pending setOrigin transaction; it will be checked again.");
      }
      if (status === "pending") {
        if (nowMs() - pendingSince < PENDING_GIVE_UP_MS) return;
        state.pending = false;
        return fail("tx_dropped", `setOrigin ${state.lastTx} has no receipt after ${PENDING_GIVE_UP_MS / 60_000} minutes; it may be sent again.`);
      }
      state.pending = false;
      if (status === "reverted") return fail("tx_reverted", `setOrigin ${state.lastTx} reverted; it will be tried again.`);
      log(`Origin: setOrigin ${state.lastTx} is mined; the registry now says ${state.lastTxHost}.`);
      state.onChain = state.lastTxHost;
      state.lastError = null;
      logged = null;
      // The next check reads the registry again, by when the RPC has caught up.
      return;
    }

    // 2. Where this server is reached now.
    let host: string;
    try {
      host = (await findHost()).trim().toLowerCase();
    } catch {
      return fail("source_unavailable", "could not find this server's public host; nothing was sent.");
    }
    if (!isPlainHost(host)) return fail("bad_host", "the host found is not a plain hostname; nothing was sent.");
    state.host = host;

    // 3. What the registry says.
    let onChain: string;
    try {
      if (!allowed) {
        if ((await registry.announcer()) !== registry.sender) {
          return fail("not_announcer", `the attester ${registry.sender} is not this registry's announcer; nothing is sent.`);
        }
        allowed = true;
      }
      onChain = await registry.read();
    } catch {
      return fail("registry_unavailable", "could not read the registry; nothing was sent.");
    }
    state.onChain = onChain;
    if (onChain === host) {
      state.lastError = null;
      logged = null;
      return;
    }

    // 4. Different: announce.
    let hash: `0x${string}`;
    try {
      hash = await registry.announce(host);
    } catch {
      return fail("send_failed", `could not send setOrigin(${host}); it will be tried again.`);
    }
    state.lastTx = hash;
    state.lastTxHost = host;
    state.lastTxAt = seconds();
    state.pending = true;
    pendingSince = nowMs();
    state.lastError = null;
    logged = null;
    log(`Origin: host is ${host} (registry said "${onChain}"); sent setOrigin in tx ${hash}.`);
  }

  async function tick() {
    if (running) return;
    running = true;
    try {
      await check();
    } catch {
      // check() handles its own failures; this only keeps a surprise from escaping a timer.
      fail("registry_unavailable", "the check failed; it will run again.");
    } finally {
      state.checkedAt = seconds();
      running = false;
    }
  }

  return {
    tick,
    start() {
      void tick();
      const timer = setInterval(() => void tick(), intervalMs);
      timer.unref();
      return () => clearInterval(timer);
    },
    health: () => ({ ...state }),
  };
}
