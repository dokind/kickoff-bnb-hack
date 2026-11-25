// A chain that lives in memory, so the API can be tested without an RPC.
import { privateKeyToAccount } from "viem/accounts";
import { createApp, type Deps } from "../src/app.js";
import { createAttester } from "../src/attest.js";
import type { Chain, ClaimState, FactoryLogs, FaucetWallet, RoundState } from "../src/chain.js";
import { checkInMessage, roundMessage } from "../src/product.js";
import { createRounds } from "../src/rounds.js";
import { LocalStore } from "../src/store.js";
import type { CreatedRound } from "../src/types.js";

export const T = (iso: string) => Date.parse(iso) / 1000;
export const USD = 10n ** 18n;

/** The well-known test key of the contracts' check-in vector (contracts/test/CheckInLauncher.t.sol). */
export const VECTOR_KEY = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
export const VECTOR_ATTESTER = "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c";
export const LAUNCHER = "0x1000000000000000000000000000000000000001";
export const TOKEN = "0xecb984a239f0528934b693da22820f405ec17777";
export const VAULT = "0x0f29643729ff2d6fd0726a4e26a31f084007a6bd";
export const QUOTE = "0x190c989d5665a0e404b444b53cae9abcfb600157";
/** Our factory and the block it was deployed in, as on BSC testnet. */
export const FACTORY = "0x2a872200b83dd025977d785cde05356d23ea4153";
export const FROM_BLOCK = 144_816_444;

export type Account = ReturnType<typeof privateKeyToAccount>;
export const lower = (a: { address: string }) => a.address.toLowerCase();

/** Three members at 1,000 test USD, no check-in yet, bar at 6, as in the contracts' fork test. */
export const freshRound = (): RoundState => ({
  name: "Morning Movers",
  quoteToken: QUOTE,
  quoteDecimals: 18,
  deposit: 1000n * USD,
  liquidityBps: 3000,
  checkInGoal: 6,
  deadline: T("2026-12-05T00:00:00Z"),
  attester: VECTOR_ATTESTER.toLowerCase(),
  totalCheckIns: 0,
  memberCount: 3,
  totalDeposits: 3000n * USD,
  totalSponsored: 0n,
  poolQuoteNow: 900n * USD,
  prizeNow: 2100n * USD,
  canLaunch: false,
  launched: false,
  token: null,
  vault: null,
});

export class FakeChain implements Chain {
  rounds = new Map<string, RoundState>([[LAUNCHER, freshRound()]]);
  joined = new Set<string>();
  /** "<address>#<dayIndex>" for every check-in that reached the chain. */
  onChain = new Set<string>();
  refundableOf = new Map<string, bigint>();
  claimsOf = new Map<string, ClaimState>();
  down = false;
  reads = 0;
  faucet?: FaucetWallet;

  // The factory's creation events. `rounds` above holds every readable Launcher, including ones
  // another factory made; only those in `created` are ours.
  head = FROM_BLOCK + 10;
  created: CreatedRound[] = [];
  /** Every eth_getLogs range that was answered, as [fromBlock, toBlock]. */
  logCalls: [number, number][] = [];
  /** The widest range (in blocks) this RPC answers; a wider one is refused. */
  maxRange = Infinity;
  factory: FactoryLogs = {
    address: FACTORY,
    head: async () => {
      if (this.down) throw new Error("rpc down");
      return this.head;
    },
    created: async (fromBlock, toBlock) => {
      if (this.down) throw new Error("rpc down");
      if (toBlock - fromBlock + 1 > this.maxRange) throw new Error(`exceed maximum block range: ${this.maxRange}`);
      this.logCalls.push([fromBlock, toBlock]);
      return this.created.filter((r) => r.block >= fromBlock && r.block <= toBlock).map((r) => ({ ...r }));
    },
  };
  /** Our factory creates a round: `blocks` later than the head, at unix time `at`. */
  create(launcher: string, creator: string, at: number, over: Partial<RoundState> = {}, blocks = 1) {
    this.head += blocks;
    this.created.push({ launcher, creator: creator.toLowerCase(), block: this.head, createdAt: at });
    this.rounds.set(launcher, { ...freshRound(), ...over });
  }
  /** Members and check-ins of one round only; `joined` and `onChain` below count in every round. */
  joinedIn = new Map<string, Set<string>>();
  onChainIn = new Map<string, Set<string>>();
  join(launcher: string, address: string) {
    if (!this.joinedIn.has(launcher)) this.joinedIn.set(launcher, new Set());
    this.joinedIn.get(launcher)!.add(address);
  }

  private up() {
    this.reads++;
    if (this.down) throw new Error("rpc down");
  }

  /** What the member's wallet does with the answer of POST /checkin. */
  submit(address: string, dayIndex: number, launcher?: string) {
    if (launcher) {
      if (!this.onChainIn.has(launcher)) this.onChainIn.set(launcher, new Set());
      this.onChainIn.get(launcher)!.add(`${address}#${dayIndex}`);
    } else this.onChain.add(`${address}#${dayIndex}`);
    this.rounds.get(launcher ?? LAUNCHER)!.totalCheckIns++;
  }
  private keys = (launcher: string) => [...this.onChain, ...(this.onChainIn.get(launcher) ?? [])];
  private daysOf = (launcher: string, address: string) => this.keys(launcher).filter((k) => k.startsWith(`${address}#`)).length;
  private checkedIn = (launcher: string, address: string, dayIndex: number) => this.keys(launcher).includes(`${address}#${dayIndex}`);

  round = async (launcher: string) => {
    this.up();
    const round = this.rounds.get(launcher);
    if (!round) throw new Error("not a launcher");
    return { ...round };
  };
  member = async (launcher: string, address: string, dayIndex: number) => {
    this.up();
    return {
      member: this.joined.has(address) || Boolean(this.joinedIn.get(launcher)?.has(address)),
      daysOf: this.daysOf(launcher, address),
      checkedIn: this.checkedIn(launcher, address, dayIndex),
      refundable: this.refundableOf.get(address) ?? 0n,
    };
  };
  members = async (launcher: string, addresses: string[], dayIndex: number) => {
    this.up();
    return addresses.map((a) => ({ daysOf: this.daysOf(launcher, a), checkedIn: this.checkedIn(launcher, a, dayIndex) }));
  };
  claims = async (_vault: string, address: string) => {
    this.up();
    return (
      this.claimsOf.get(address) ?? { claimableTokens: 0n, claimableQuote: 0n, claimedTokens: 0n, claimedQuote: 0n, tokenDecimals: 18 }
    );
  };
  balanceOf = async (_address: string) => 0n;
}

/** An app on a fake chain with a movable clock and the vector key as attester. */
export function harness(deps: Partial<Deps> = {}, startAt = T("2026-11-25T08:00:00Z")) {
  const chain = new FakeChain();
  const store = new LocalStore();
  const h = {
    chain,
    store,
    /** The rounds found in the fake factory's events, in 1,000-block chunks. */
    rounds: undefined as unknown as ReturnType<typeof createRounds>,
    /** A registry as a restarted server would build it: same store, nothing in memory. */
    newRounds: (over: Partial<Parameters<typeof createRounds>[0]> = {}) =>
      createRounds({ store, factory: chain.factory, fromBlock: FROM_BLOCK, chunkBlocks: 1000, nowMs: () => h.clock * 1000, ...over }),
    clock: startAt,
    app: undefined as unknown as ReturnType<typeof createApp>,
    /** Rebuilds the app with other settings; the chain, the store and the clock stay. */
    start(over: Partial<Deps> = {}) {
      h.rounds = over.rounds ?? deps.rounds ?? h.rounds ?? h.newRounds();
      h.app = createApp({
        store,
        chain,
        attester: createAttester(VECTOR_KEY),
        now: () => h.clock,
        defaultRound: { launcher: LAUNCHER },
        // Every GET /rounds reads the chain, and POST /rounds does not wait and look again.
        listCacheMs: 0,
        registerRetry: { times: 0, waitMs: 0 },
        ...deps,
        ...over,
        rounds: h.rounds,
      });
    },
    async get(path: string) {
      const res = await h.app.request(path);
      return { status: res.status, body: (await res.json()) as any };
    },
    async post(path: string, body: unknown, headers: Record<string, string> = {}) {
      const res = await h.app.request(path, {
        method: "POST",
        headers: { "content-type": "application/json", ...headers },
        body: JSON.stringify(body),
      });
      return { status: res.status, body: (await res.json()) as any };
    },
    /** POST /checkin signed by `who` for `signedDay` (default: the clock's UTC day). */
    async checkIn(
      who: Account,
      steps: number | string = 5000,
      over: { source?: string; signedDay?: string; signedSteps?: number | string; signedLauncher?: string; signer?: Account } = {},
    ) {
      const day = over.signedDay ?? new Date(h.clock * 1000).toISOString().slice(0, 10);
      const signature = await (over.signer ?? who).signMessage({
        message: checkInMessage(over.signedLauncher ?? LAUNCHER, day, over.signedSteps ?? steps),
      });
      return h.post("/checkin", { address: who.address, steps, source: over.source ?? "healthkit", signature });
    },
    /** POST /rounds/:launcher/checkin signed by `who` for that launcher and the clock's UTC day. */
    async checkInTo(launcher: string, who: Account, steps: number | string = 5000) {
      const day = new Date(h.clock * 1000).toISOString().slice(0, 10);
      const signature = await who.signMessage({ message: checkInMessage(launcher, day, steps) });
      return h.post(`/rounds/${launcher}/checkin`, { address: who.address, steps, source: "healthkit", signature });
    },
    /** POST /rounds: `who` signs the choice for `launcher` (lower-case in the text unless `signedLauncher` says otherwise). */
    async register(launcher: string, who: Account, unlisted: boolean, over: { signedUnlisted?: boolean; signedLauncher?: string } = {}) {
      const message = roundMessage(over.signedLauncher ?? launcher.toLowerCase(), over.signedUnlisted ?? unlisted);
      return h.post("/rounds", { launcher, unlisted, signature: await who.signMessage({ message }) });
    },
  };
  h.start();
  return h;
}
