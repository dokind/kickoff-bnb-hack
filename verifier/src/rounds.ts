// Which rounds exist: every CheckInLauncher our factory created, found in the factory's creation
// events and kept in the store.
//
// The scan starts at the block the factory was deployed in and asks for the events in chunks of
// blocks, because public RPCs refuse a wide range. A range the RPC refuses is halved and asked again.
// How far the scan got is stored, so a restart continues where the last run stopped. Every scan goes
// back a few blocks before that point: a load-balanced RPC can answer from a node that is slightly
// behind, and an event missed that way would otherwise be missed for good.
import type { FactoryLogs } from "./chain.js";
import type { Store } from "./store.js";
import type { CreatedRound, Discovery } from "./types.js";

/**
 * A round nobody registered appears in the public list this long after its creation. The delay gives
 * the creator's app time to register the round as unlisted before anyone else is shown it.
 */
export const LISTING_DELAY_SECONDS = 180;
/** Blocks asked for in one eth_getLogs call, unless LOG_CHUNK_BLOCKS says otherwise. */
export const DEFAULT_CHUNK_BLOCKS = 10_000;
/** A range this small that still fails is not a range problem: the scan stops and is tried again later. */
const MIN_CHUNK_BLOCKS = 250;
/** Blocks before the stored position that every scan reads again. */
const OVERLAP_BLOCKS = 64;

export interface RoundsOptions {
  store: Store;
  /** Undefined: nothing is discovered and only the featured round is known. */
  factory?: FactoryLogs;
  /** The block the factory was deployed in. */
  fromBlock?: number;
  chunkBlocks?: number;
  /** A lookup of an unknown launcher does not start a new scan sooner than this after the last one. */
  minGapMs?: number;
  nowMs?: () => number;
}

export interface Rounds {
  /** False when no factory is configured. */
  readonly enabled: boolean;
  /** Scans up to the chain's head. True when it got there. Never throws; one scan runs at a time. */
  refresh(): Promise<boolean>;
  /** refresh(), unless a scan reached the head less than `maxAgeMs` ago. Waits at most `waitMs`. */
  fresh(maxAgeMs: number, waitMs: number): Promise<void>;
  /** Every round found so far. */
  all(): Promise<CreatedRound[]>;
  /** A round found so far. Does not touch the chain. */
  known(launcher: string): Promise<CreatedRound | undefined>;
  /**
   * Like `known`, but scans first when the launcher is not known yet (it may have been created a
   * moment ago). `complete: false` with no round means the scan did not reach the head, so "not one
   * of ours" cannot be said.
   */
  find(launcher: string): Promise<{ round?: CreatedRound; complete: boolean }>;
  /** The factory was scanned to the head at least once, now or by an earlier run. */
  scanned(): Promise<boolean>;
}

export function createRounds({
  store,
  factory,
  fromBlock = 0,
  chunkBlocks = DEFAULT_CHUNK_BLOCKS,
  minGapMs = 0,
  nowMs = Date.now,
}: RoundsOptions): Rounds {
  let state: Discovery | undefined;
  let savedNext = -1;
  let running: Promise<boolean> | null = null;
  let lastComplete = -Infinity;
  /** True once any scan, in this run or an earlier one, got to the head. */
  let everComplete = false;

  async function load(): Promise<Discovery> {
    if (state) return state;
    const saved = factory ? await store.getDiscovery() : undefined;
    if (saved && factory && saved.factory === factory.address) {
      state = { factory: saved.factory, nextBlock: saved.nextBlock, rounds: saved.rounds.map((r) => ({ ...r })) };
      savedNext = saved.nextBlock;
      everComplete = true;
    } else {
      state = { factory: factory?.address ?? "", nextBlock: fromBlock, rounds: [] };
    }
    return state;
  }

  /** Keeps what was found for the next start. If the store cannot be written the rounds are still
   *  known in memory, and the write is tried again on the next scan. */
  async function keep(s: Discovery) {
    try {
      await store.putDiscovery(s);
      savedNext = s.nextBlock;
    } catch {
      // Nothing is lost: a restart scans these blocks again.
    }
  }

  async function scan(logs: FactoryLogs): Promise<boolean> {
    const s = await load();
    const head = await logs.head();
    let from = Math.max(fromBlock, s.nextBlock - OVERLAP_BLOCKS);
    let size = Math.max(1, chunkBlocks);
    while (from <= head) {
      const to = Math.min(head, from + size - 1);
      let found: CreatedRound[];
      try {
        found = await logs.created(from, to);
      } catch (e) {
        if (size <= MIN_CHUNK_BLOCKS) throw e;
        size = Math.max(MIN_CHUNK_BLOCKS, Math.floor(size / 2));
        continue;
      }
      let added = false;
      for (const round of found) {
        if (s.rounds.some((r) => r.launcher === round.launcher)) continue;
        s.rounds.push(round);
        added = true;
      }
      s.nextBlock = Math.max(s.nextBlock, to + 1);
      from = to + 1;
      // Written when there is something new to keep: a round, or a chunk's worth of progress.
      if (added || savedNext < 0 || s.nextBlock - savedNext >= chunkBlocks) await keep(s);
    }
    if (savedNext < 0) await keep(s);
    return true;
  }

  function refresh(): Promise<boolean> {
    if (!factory) return Promise.resolve(true);
    running ??= scan(factory)
      .then(() => {
        lastComplete = nowMs();
        everComplete = true;
        return true;
      })
      .catch(() => false)
      .finally(() => {
        running = null;
      });
    return running;
  }

  const known = async (launcher: string) => (await load()).rounds.find((r) => r.launcher === launcher);

  return {
    enabled: Boolean(factory),
    refresh,
    async fresh(maxAgeMs, waitMs) {
      if (!factory || nowMs() - lastComplete < maxAgeMs) return;
      let timer: ReturnType<typeof setTimeout> | undefined;
      const timeout = new Promise<void>((resolve) => (timer = setTimeout(resolve, waitMs)));
      await Promise.race([refresh(), timeout]);
      clearTimeout(timer);
    },
    all: async () => [...(await load()).rounds],
    known,
    async find(launcher) {
      const round = await known(launcher);
      if (round || !factory) return { round, complete: true };
      if (nowMs() - lastComplete < minGapMs) return { complete: true };
      const complete = await refresh();
      return { round: await known(launcher), complete };
    },
    async scanned() {
      await load();
      return !factory || everComplete;
    },
  };
}
