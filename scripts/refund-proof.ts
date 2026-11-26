// Refund proof: the "group falls short" ending, run for real on BSC testnet (chain 97). Test assets
// only: test BNB for gas and Flap's free-mint test USD, neither has any value.
//
//   cd verifier && npx tsx ../scripts/refund-proof.ts            first run
//   cd verifier && npx tsx ../scripts/refund-proof.ts --again    a new round after a recorded success
//
// Run it from the verifier folder: viem is taken from verifier/node_modules. It needs no server, sends
// nothing to our API and never touches the featured round. It takes about 12 minutes, most of it
// waiting for the round's deadline.
//
// One wallet, the deployer (PRIVATE_KEY in contracts/.env), plays every part of a tiny round:
//   creator   opens it through our CheckInLauncherFactory (Portal.newLauncher): deposit 100 test USD,
//             liquidityBps 3000 (30% of each deposit would build the shop), goal 1 check-in, deadline
//             DEADLINE_MINUTES (default 10) after the opening block;
//   attester  the round names the deployer as its attester, not our server's key, so our server can't
//             sign for it and leaves it out of GET /rounds and /stats. The one check-in is signed here by
//             hand over the contract's own checkInDigest(wallet, day);
//   member    join() pays the 100 deposit;
//   sponsor   sponsor(50) adds 50 to the shop.
//
// Then, in order:
//   1. The hand-signed check-in: 1 of 1, the bar is full.
//   2. eth_call launch(): it reverts. The shop would get 50 + 30% of 100 = 80 test USD and Flap's Portal
//      wants at least its floor (1,500 at our factory's 1x). Nothing is sent.
//   3. eth_call refund(): RefundUnavailable, the deadline has not passed. Nothing is sent.
//   4. Wait until a block's timestamp is past the deadline: the chain's clock, not this computer's.
//   5. refund(): the wallet gets 150 test USD back (its 100 deposit and its 50 of sponsor money);
//      isMember turns false and refundable() turns 0.
//   6. eth_call refund() again: NothingToRefund.
// Everything is written to scripts/refund-result.json as it happens: every transaction hash and block,
// the launcher address, the balances before and after, and a list of checks. "ok": true means every
// check passed; the exit code is 1 otherwise.
//
// What it proves: a round whose bar is full but which never launched (here, because its shop is under
// Flap's floor) gives every wallet back exactly what it paid once the deadline has passed. Days don't
// count, sponsor money comes back too, and a wallet can take it back once.
//
// Running it again: it refuses when refund-result.json already records a success (pass --again for a
// new round; the old result is kept under previousRuns). A stopped run continues the same round from
// where it stopped, the wait for the deadline included, because the file keeps its progress.
//
// Every transaction is a legacy transaction at 1 gwei with an explicit gas limit, after an eth_call dry
// run: fee estimation on this testnet can return 1 wei, and such transactions are never mined. The
// deployer needs about 0.012 test BNB (0.005 is the Portal's salt lock fee); test USD is minted here.
//
// The key: only PRIVATE_KEY is read from contracts/.env. It stays in memory and is never printed or
// written anywhere. Do not run another script with the same key at the same time (nonces would clash).
//
// Settings (environment variables, all optional):
//   RPC_URL            BSC testnet RPC                   default https://bsc-testnet-rpc.publicnode.com
//   DEADLINE_MINUTES   deadline after the opening block  default 10 (3 to 60)
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { join, resolve } from "node:path";

const require_ = createRequire(join(process.cwd(), "package.json"));
const viem = require_("viem") as typeof import("viem");
const { privateKeyToAccount } = require_("viem/accounts") as typeof import("viem/accounts");
const { bscTestnet } = require_("viem/chains") as typeof import("viem/chains");
const {
  createPublicClient,
  createWalletClient,
  http,
  parseAbi,
  parseAbiItem,
  parseEther,
  formatEther,
  keccak256,
  toHex,
  encodeAbiParameters,
  decodeAbiParameters,
  encodeFunctionData,
  decodeEventLog,
  decodeErrorResult,
  hashMessage,
  recoverAddress,
  getAddress,
  isAddressEqual,
} = viem;

type Hex = `0x${string}`;
type Receipt = import("viem").TransactionReceipt;

// ── Fixed addresses on BSC testnet ───────────────────────────────────────────
const PORTAL: Hex = "0x000042108465206185A077Edc3F3fd2b49060000";
// keccak256 of the creation code of the token clone the Portal deploys (contracts/test/Salt.t.sol).
const TOKEN_INIT_CODE_HASH: Hex = "0xc7e15deb24b23c120ed65985516639441790ec6e89090f4aa0a87169aa9c2730";
const USD: Hex = "0x190C989D5665a0e404B444b53CAE9AbCfb600157"; // Flap's test USD: anyone can mint
const EXPLORER = "https://testnet.bscscan.com";
/**
 * What the live Portal reverts with when the shop money is below its floor: this selector, then two
 * words (pool quote offered, floor required). Its name is not in the interface Flap publishes
 * (contracts/test/ShowupRound.fork.t.sol, PORTAL_BELOW_FLOOR).
 */
const PORTAL_BELOW_FLOOR = "0xa32ef056";

// ── The round ────────────────────────────────────────────────────────────────
const ROUND_NAME = "Refund Proof";
const ROUND_SYMBOL = "REFUND";
const DEPOSIT = parseEther("100");
const LIQUIDITY_BPS = 3000n;
const CHECKIN_GOAL = 1n;
const SPONSOR = parseEther("50");
/** What the wallet pays in, and so what refund() must pay back: the deposit plus the sponsor money. */
const PAID_IN = DEPOSIT + SPONSOR;
/** What launch() would offer Flap's Portal for the shop: all sponsor money + 30% of the deposits = 80. */
const SHOP = SPONSOR + (DEPOSIT * LIQUIDITY_BPS) / 10_000n;

const GAS_PRICE = 1_000_000_000n; // 1 gwei, legacy
const GAS = {
  newLauncher: 1_000_000n, // about 530,000 used
  mint: 150_000n,
  approve: 100_000n,
  join: 250_000n,
  sponsor: 200_000n,
  checkIn: 200_000n,
  refund: 150_000n, // about 61,000 used
};

const portalAbi = parseAbi([
  "function SALT_LOCK_FEE() view returns (uint256)",
  "function featureFlags() view returns (uint256)",
  "function launcherFactoryMultiplier(address factory) view returns (bool enabled, uint16 multiplierBps)",
  "function newLauncher(address launcherFactory, bytes data) payable returns (address)",
]);
const factoryAbi = parseAbi([
  "event CheckInLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt)",
  "error ZeroAddress()",
  "error InvalidData()",
  "error EmptyField()",
  "error InvalidDeposit()",
  "error InvalidLiquidityBps(uint256 liquidityBps)",
  "error InvalidCheckInGoal()",
  "error InvalidDeadline(uint256 deadline)",
]);
const launcherAbi = parseAbi([
  "function join()",
  "function sponsor(uint256 amount)",
  "function checkIn(uint256 day, bytes signature)",
  "function launch()",
  "function refund()",
  "function name() view returns (string)",
  "function deposit() view returns (uint256)",
  "function liquidityBps() view returns (uint256)",
  "function checkInGoal() view returns (uint256)",
  "function deadline() view returns (uint256)",
  "function attester() view returns (address)",
  "function creator() view returns (address)",
  "function launchSalt() view returns (bytes32)",
  "function currentDay() view returns (uint256)",
  "function isMember(address account) view returns (bool)",
  "function memberCount() view returns (uint256)",
  "function daysOf(address member) view returns (uint256)",
  "function totalCheckIns() view returns (uint256)",
  "function checkedInOn(address member, uint256 day) view returns (bool)",
  "function sponsoredBy(address account) view returns (uint256)",
  "function totalDeposits() view returns (uint256)",
  "function totalSponsored() view returns (uint256)",
  "function poolQuoteNow() view returns (uint256)",
  "function prizeQuoteNow() view returns (uint256)",
  "function canLaunch() view returns (bool)",
  "function refundable(address account) view returns (uint256)",
  "function launched() view returns (bool)",
  "function checkInDigest(address wallet, uint256 day) view returns (bytes32)",
  "event Refunded(address indexed account, uint256 amount)",
  "error InvalidConfig()",
  "error LaunchInProgress()",
  "error RoundClosed()",
  "error AlreadyMember()",
  "error ZeroAmount()",
  "error NotMember()",
  "error CheckInsClosed()",
  "error InvalidDay(uint256 day, uint256 today)",
  "error AlreadyCheckedIn(uint256 day)",
  "error InvalidSignature()",
  "error AlreadyLaunched()",
  "error GoalNotReached(uint256 totalCheckIns, uint256 checkInGoal)",
  "error LaunchClosed()",
  "error NoPoolQuote()",
  "error VaultMissing()",
  "error RefundUnavailable()",
  "error NothingToRefund()",
]);
const erc20Abi = parseAbi([
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "event Transfer(address indexed from, address indexed to, uint256 value)",
]);
const refundedEvent = parseAbiItem("event Refunded(address indexed account, uint256 amount)");
/** Every custom error a call in this script can meet, for decoding reverts by name. */
const errorsAbi = [...launcherAbi, ...factoryAbi];

// ── Small helpers ────────────────────────────────────────────────────────────
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const log = (msg: string) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`);
const iso = (seconds: number | bigint) => new Date(Number(seconds) * 1000).toISOString();
const usd = (wei: bigint) => formatEther(wei);
const gasMoney = (limits: bigint[]) => limits.reduce((a, b) => a + b, 0n) * GAS_PRICE;

/** The value of ONE variable of an env file, or null. Nothing else is kept, and nothing is printed. */
function envValue(path: string, name: string): string | null {
  if (!existsSync(path)) return null;
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = /^\s*(?:export\s+)?([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (!m || m[1] !== name) continue;
    const value = (m[2] ?? "").replace(/^["']|["']$/g, "");
    return value === "" ? null : value;
  }
  return null;
}

function asKey(value: string): Hex {
  const key = value.startsWith("0x") ? value : `0x${value}`;
  if (!/^0x[0-9a-fA-F]{64}$/.test(key)) throw new Error("PRIVATE_KEY in contracts/.env is not a 32-byte hex key");
  return key as Hex;
}

function wholeNumber(name: string, fallback: number, min: number, max: number): number {
  const raw = process.env[name];
  const n = raw === undefined || raw === "" ? fallback : Number(raw);
  if (!Number.isInteger(n) || n < min || n > max) throw new Error(`${name} must be a whole number from ${min} to ${max}`);
  return n;
}

/**
 * The Portal deploys the token as a CREATE2 clone; its address must end in 0x7777. The search starts
 * from a random seed (small sequential salts are already locked by others on testnet) and the counter
 * overwrites the last four bytes of the seed: the same search as scripts/run-round.ts and the app.
 */
function mineSalt(): { salt: Hex; token: Hex; tries: number } {
  const input = Buffer.concat([
    Buffer.from("ff", "hex"),
    Buffer.from(PORTAL.slice(2), "hex"),
    Buffer.from(keccak256(toHex(`refund-proof-${Date.now()}-${Math.random()}`)).slice(2), "hex"),
    Buffer.from(TOKEN_INIT_CODE_HASH.slice(2), "hex"),
  ]);
  for (let i = 0; i < 0xffffffff; i++) {
    input.writeUInt32BE(i, 49);
    const hash = keccak256(input, "bytes");
    if (hash[30] === 0x77 && hash[31] === 0x77) {
      return {
        salt: `0x${input.subarray(21, 53).toString("hex")}`,
        token: getAddress(`0x${Buffer.from(hash.subarray(12)).toString("hex")}`),
        tries: i + 1,
      };
    }
  }
  throw new Error("no salt found");
}

/** abi.encode(RoundConfig): ONE tuple, in the order the factory decodes it. */
function encodeConfig(salt: Hex, deadline: number, attester: Hex): Hex {
  return encodeAbiParameters(
    [
      {
        type: "tuple",
        components: [
          { name: "name", type: "string" },
          { name: "symbol", type: "string" },
          { name: "meta", type: "string" },
          { name: "salt", type: "bytes32" },
          { name: "deposit", type: "uint256" },
          { name: "liquidityBps", type: "uint256" },
          { name: "checkInGoal", type: "uint256" },
          { name: "deadline", type: "uint256" },
          { name: "attester", type: "address" },
        ],
      },
    ],
    [
      {
        name: ROUND_NAME,
        symbol: ROUND_SYMBOL,
        meta: "",
        salt,
        deposit: DEPOSIT,
        liquidityBps: LIQUIDITY_BPS,
        checkInGoal: CHECKIN_GOAL,
        deadline: BigInt(deadline),
        attester,
      },
    ],
  );
}

/** The revert data somewhere in a viem error's chain of causes, or null. */
function revertData(e: unknown): Hex | null {
  let cur: any = e;
  for (let depth = 0; cur && depth < 12; depth++) {
    for (const v of [cur.raw, cur.data, cur.data?.data, cur.error?.data]) {
      if (typeof v === "string" && /^0x[0-9a-fA-F]{8,}$/.test(v)) return v as Hex;
    }
    cur = cur.cause;
  }
  return null;
}

interface Revert {
  error: string;
  args: string[];
  raw: Hex | null;
}

/** Names a revert: Flap's floor error, one of our contracts' errors, Error(string) or Panic. */
function describeRevert(raw: Hex | null): Revert {
  if (!raw) return { error: "reverted without data", args: [], raw };
  if (raw.slice(0, 10).toLowerCase() === PORTAL_BELOW_FLOOR) {
    const [offered, floor] = decodeAbiParameters([{ type: "uint256" }, { type: "uint256" }], `0x${raw.slice(10)}`);
    return { error: "PortalBelowFloor", args: [offered.toString(), floor.toString()], raw };
  }
  try {
    const d = decodeErrorResult({ abi: errorsAbi as any, data: raw }) as { errorName: string; args?: readonly unknown[] };
    return { error: d.errorName, args: (d.args ?? []).map((a) => String(a)), raw };
  } catch {
    return { error: `unknown error ${raw.slice(0, 10)}`, args: [], raw };
  }
}

interface TxRecord {
  step: string;
  what: string;
  hash: Hex;
  url: string;
  block?: number;
  gasUsed?: string;
  status?: string;
}
interface Check {
  name: string;
  pass: boolean;
  detail: string;
}
interface Result {
  ok: boolean;
  status: string;
  about: string;
  network: string;
  explorer: string;
  startedAt: string;
  updatedAt: string;
  round: Record<string, unknown>;
  addresses: { portal: Hex; factory: Hex; testUsd: Hex; deployer: Hex; launcher?: Hex };
  links: Record<string, string>;
  steps: Record<string, any>;
  balances: Record<string, unknown>;
  checks: Check[];
  transactions: TxRecord[];
  previousRuns?: unknown[];
}

/** Set once the result file is open, so a failure is written into it. */
let recordFailure: ((message: string) => void) | null = null;

async function main() {
  const args = process.argv.slice(2);
  const again = args.includes("--again");
  const unknownArg = args.find((a) => a !== "--again");
  if (unknownArg) throw new Error(`unknown argument "${unknownArg}"; the only option is --again`);

  const root = resolve(process.cwd(), "..");
  const deploymentsFile = join(root, "contracts/deployments/bsc-testnet.json");
  if (!existsSync(deploymentsFile)) {
    throw new Error("run this from the verifier folder: cd verifier && npx tsx ../scripts/refund-proof.ts");
  }
  const deployments = JSON.parse(readFileSync(deploymentsFile, "utf8"));
  if (deployments.chainId !== 97 || !deployments.checkInLauncherFactory) {
    throw new Error("contracts/deployments/bsc-testnet.json has no checkInLauncherFactory for chain 97");
  }
  const FACTORY = getAddress(deployments.checkInLauncherFactory) as Hex;
  const resultFile = join(root, "scripts/refund-result.json");

  const previous: Result | null = existsSync(resultFile) ? JSON.parse(readFileSync(resultFile, "utf8")) : null;
  if (previous?.ok && !again) {
    log(`${resultFile} already records a successful refund proof:`);
    log(`  launcher ${previous.addresses.launcher}, refund ${previous.steps.refund?.tx ?? "?"}`);
    log("Refusing to run again; nothing was sent. Pass --again to run a new round.");
    return;
  }

  const keyValue = envValue(join(root, "contracts/.env"), "PRIVATE_KEY") ?? process.env.PRIVATE_KEY ?? null;
  if (!keyValue) throw new Error("PRIVATE_KEY not found in contracts/.env");
  const deployer = privateKeyToAccount(asKey(keyValue));
  const me = deployer.address as Hex;
  const rpcUrl = process.env.RPC_URL || "https://bsc-testnet-rpc.publicnode.com";
  const deadlineMinutes = wholeNumber("DEADLINE_MINUTES", 10, 3, 60);

  const resume = previous !== null && !previous.ok && !again && previous.addresses?.deployer === me;
  const state: Result = resume
    ? previous
    : {
        ok: false,
        status: "starting",
        about:
          "The refund ending on BSC testnet with test USD: a round whose bar was full but which never launched " +
          "(its shop money was under Flap's floor) paid every test dollar back to the wallet that paid it, after " +
          "the deadline. One wallet played creator, attester, member and sponsor; our server was not involved.",
        network: "BSC testnet (chain 97)",
        explorer: EXPLORER,
        startedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        round: {
          name: ROUND_NAME,
          symbol: ROUND_SYMBOL,
          depositUsd: usd(DEPOSIT),
          liquidityBps: Number(LIQUIDITY_BPS),
          checkInGoal: Number(CHECKIN_GOAL),
          sponsorUsd: usd(SPONSOR),
          shopWouldGetUsd: usd(SHOP),
          paidInUsd: usd(PAID_IN),
          deadlineMinutes,
        },
        addresses: { portal: PORTAL, factory: FACTORY, testUsd: USD, deployer: me },
        links: {},
        steps: {},
        balances: {},
        checks: [],
        transactions: [],
      };
  if (!resume && previous) {
    const prior = {
      startedAt: previous.startedAt,
      ok: previous.ok,
      status: previous.status,
      launcher: previous.addresses?.launcher ?? null,
      refundTx: previous.steps?.refund?.tx ?? null,
    };
    state.previousRuns = [...(previous.previousRuns ?? []), prior];
    if (!previous.ok && prior.launcher) {
      log(`The unfinished run's round ${prior.launcher} is left as it is. If it holds test USD, the wallet can`);
      log(`still take it back with refund() after that round's deadline.`);
    }
  }
  const save = () => {
    state.updatedAt = new Date().toISOString();
    writeFileSync(resultFile, JSON.stringify(state, null, 2) + "\n");
  };
  recordFailure = (message) => {
    state.ok = false;
    state.status = `stopped: ${message}`;
    save();
  };
  save();
  if (resume) log(`Continuing the unfinished refund proof in ${resultFile}`);

  const transport = http(rpcUrl, { retryCount: 5, retryDelay: 800 });
  const client = createPublicClient({ chain: bscTestnet, transport });
  const wallet = createWalletClient({ account: deployer, chain: bscTestnet, transport });
  if ((await client.getChainId()) !== 97) throw new Error("RPC is not BSC testnet (chain 97)");

  const read = <T>(address: Hex, abi: readonly unknown[], functionName: string, args: readonly unknown[] = [], blockNumber?: bigint) =>
    client.readContract({ address, abi, functionName, args, blockNumber } as any) as Promise<T>;
  const bal = (holder: Hex, blockNumber?: bigint) => read<bigint>(USD, erc20Abi, "balanceOf", [holder], blockNumber);

  /** eth_call: whether it would revert, and with what. Sends nothing. Retries a network hiccup. */
  async function tryCall(to: Hex, data: Hex, opts: { value?: bigint; blockNumber?: bigint } = {}) {
    for (let attempt = 0; ; attempt++) {
      try {
        await client.call({ account: me, to, data, value: opts.value, blockNumber: opts.blockNumber });
        return { reverted: false, error: null as string | null, args: [] as string[], raw: null as Hex | null, message: null as string | null };
      } catch (e: any) {
        const raw = revertData(e);
        const message: string = e?.shortMessage ?? e?.message ?? String(e);
        if (raw !== null || /revert/i.test(message)) return { reverted: true, ...describeRevert(raw), message };
        if (attempt >= 4) throw e;
        await sleep(1500);
      }
    }
  }

  /** Retries a read: a load-balanced public RPC can answer from a node a block or two behind. */
  async function retry<T>(fn: () => Promise<T>, tries = 8): Promise<T> {
    for (let i = 1; ; i++) {
      try {
        return await fn();
      } catch (e) {
        if (i >= tries) throw e;
        await sleep(1_500);
      }
    }
  }

  /** The latest block number, but never before `atLeast` (a block this script already saw). */
  async function blockAtLeast(atLeast: number | null): Promise<bigint> {
    const latest = await client.getBlockNumber({ cacheTime: 0 });
    return atLeast !== null && BigInt(atLeast) > latest ? BigInt(atLeast) : latest;
  }

  // One nonce counter: a load-balanced public RPC can lag behind our own last send.
  let nextNonce = 0;
  async function send(step: string, what: string, tx: { to: Hex; data: Hex; value?: bigint; gas: bigint }): Promise<Receipt> {
    // Dry run first, so a refused call costs nothing and says why. A node a block behind can refuse
    // a call that depends on our previous transaction, so a refusal is asked again for a few seconds.
    let dry = await tryCall(tx.to, tx.data, { value: tx.value });
    for (let i = 0; dry.reverted && i < 5; i++) {
      await sleep(2_000);
      dry = await tryCall(tx.to, tx.data, { value: tx.value });
    }
    if (dry.reverted) {
      throw new Error(`${what} would revert with ${dry.error}${dry.args.length ? ` (${dry.args.join(", ")})` : ""}; nothing was sent`);
    }
    const pending = await client.getTransactionCount({ address: me, blockTag: "pending" });
    const nonce = Math.max(pending, nextNonce);
    const hash = await wallet.sendTransaction({
      to: tx.to,
      data: tx.data,
      value: tx.value ?? 0n,
      gas: tx.gas,
      type: "legacy",
      gasPrice: GAS_PRICE,
      nonce,
    });
    nextNonce = nonce + 1;
    const record: TxRecord = { step, what, hash, url: `${EXPLORER}/tx/${hash}` };
    state.transactions.push(record);
    save();
    const receipt = await client.waitForTransactionReceipt({ hash, timeout: 180_000, pollingInterval: 1_500 });
    record.block = Number(receipt.blockNumber);
    record.gasUsed = receipt.gasUsed.toString();
    record.status = receipt.status;
    save();
    if (receipt.status !== "success") throw new Error(`${what}: transaction ${hash} reverted`);
    log(`  ${what}: ${hash} (block ${receipt.blockNumber}, gas ${receipt.gasUsed})`);
    return receipt;
  }

  /** The receipt of a transaction a stopped run already sent for this step, if it went through. */
  async function sentBefore(step: string): Promise<Receipt | null> {
    for (const record of [...state.transactions].reverse()) {
      if (record.step !== step) continue;
      try {
        const receipt = await client.waitForTransactionReceipt({ hash: record.hash, timeout: 60_000, pollingInterval: 1_500 });
        record.block = Number(receipt.blockNumber);
        record.gasUsed = receipt.gasUsed.toString();
        record.status = receipt.status;
        save();
        if (receipt.status === "success") return receipt;
      } catch {
        // Never mined (dropped): the step sends again.
      }
    }
    return null;
  }

  /** Runs a step once; its result is kept in the result file, and a continued run reuses it. */
  async function step<T>(name: string, fn: () => Promise<T>): Promise<T> {
    if (name in state.steps) return state.steps[name] as T;
    log(`STEP ${name}`);
    state.status = `running: ${name}`;
    save();
    const out = await fn();
    state.steps[name] = out ?? null;
    save();
    return out;
  }

  // ── 0. Checks before anything is sent ──────────────────────────────────────
  const [bnb, saltFee, flags, factoryCode, multiplier] = await Promise.all([
    client.getBalance({ address: me }),
    read<bigint>(PORTAL, portalAbi, "SALT_LOCK_FEE"),
    read<bigint>(PORTAL, portalAbi, "featureFlags"),
    client.getCode({ address: FACTORY }),
    read<readonly [boolean, number]>(PORTAL, portalAbi, "launcherFactoryMultiplier", [FACTORY]),
  ]);
  if (!factoryCode || factoryCode === "0x") throw new Error(`no contract code at the CheckInLauncherFactory ${FACTORY}`);
  if ((flags & 1n) !== 0n) throw new Error("the testnet Portal has creation paused");
  if (!multiplier[0]) throw new Error(`the Portal does not accept the factory ${FACTORY} right now`);
  const bnbNeeded = saltFee + gasMoney(Object.values(GAS)) + parseEther("0.005");
  if (!("open" in state.steps) && bnb < bnbNeeded) {
    throw new Error(`the deployer ${me} needs at least ${formatEther(bnbNeeded)} test BNB; it holds ${formatEther(bnb)}`);
  }
  log(`Deployer ${me} (creator, attester, member and sponsor) holds ${formatEther(bnb)} test BNB.`);
  log(`Factory ${FACTORY} is enabled on the testnet Portal (floor multiplier ${multiplier[1]} bps).`);

  // ── 1. Open the round ──────────────────────────────────────────────────────
  const opened = await step("open", async () => {
    let receipt = await sentBefore("open");
    let mined: { salt: Hex; token: Hex; tries: number } | null = null;
    if (!receipt) {
      const head = await client.getBlock({ blockTag: "latest" });
      const deadline = Number(head.timestamp) + deadlineMinutes * 60;
      mined = mineSalt();
      state.round.deadlineMinutes = deadlineMinutes;
      log(`  salt found after ${mined.tries} tries (a launch would make the coin at ${mined.token}, which never happens here)`);
      log(`  deadline ${iso(deadline)}: ${deadlineMinutes} minutes after block ${head.number}`);
      const data = encodeFunctionData({ abi: portalAbi, functionName: "newLauncher", args: [FACTORY, encodeConfig(mined.salt, deadline, me)] });
      receipt = await send("open", "Portal.newLauncher: the deployer opens the round and names itself the attester", {
        to: PORTAL,
        data,
        value: saltFee,
        gas: GAS.newLauncher,
      });
    }
    let launcher: Hex | null = null;
    for (const l of receipt.logs) {
      if (!isAddressEqual(l.address, FACTORY)) continue;
      try {
        const ev = decodeEventLog({ abi: factoryAbi, data: l.data, topics: l.topics });
        if (ev.eventName === "CheckInLauncherCreated") launcher = getAddress(ev.args.launcher) as Hex;
      } catch {}
    }
    if (!launcher) throw new Error("CheckInLauncherCreated not found in the receipt");
    const found = launcher;
    const at = receipt.blockNumber;
    const deadline = Number(await retry(() => read<bigint>(found, launcherAbi, "deadline", [], at)));
    return {
      launcher,
      tx: receipt.transactionHash,
      block: Number(at),
      salt: mined?.salt ?? (await retry(() => read<Hex>(found, launcherAbi, "launchSalt", [], at))),
      deadline,
      deadlineIso: iso(deadline),
    };
  });
  const launcher = opened.launcher as Hex;
  const deadline = Number(opened.deadline);
  state.addresses.launcher = launcher;
  state.round.deadline = deadline;
  state.round.deadlineIso = iso(deadline);
  state.links.launcher = `${EXPLORER}/address/${launcher}`;
  save();
  log(`Launcher (the round): ${launcher}. Deadline ${iso(deadline)}.`);

  const config = await step("config", async () => {
    const at = await blockAtLeast(opened.block);
    return retry(async () => ({
      readAtBlock: Number(at),
      name: await read<string>(launcher, launcherAbi, "name", [], at),
      depositUsd: usd(await read<bigint>(launcher, launcherAbi, "deposit", [], at)),
      liquidityBps: Number(await read<bigint>(launcher, launcherAbi, "liquidityBps", [], at)),
      checkInGoal: Number(await read<bigint>(launcher, launcherAbi, "checkInGoal", [], at)),
      attester: getAddress(await read<Hex>(launcher, launcherAbi, "attester", [], at)),
      creator: getAddress(await read<Hex>(launcher, launcherAbi, "creator", [], at)),
      deadline: Number(await read<bigint>(launcher, launcherAbi, "deadline", [], at)),
    }));
  });

  // ── 2. Test USD for the deposit and the sponsor money ─────────────────────
  await step("fund", async () => {
    const before = await bal(me);
    let mintTx: Hex | null = null;
    let approveTx: Hex | null = null;
    if (before < PAID_IN) {
      const r = await send("fund", `mint ${usd(PAID_IN)} test USD to the deployer (Flap's test USD: anyone can mint)`, {
        to: USD,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "mint", args: [me, PAID_IN] }),
        gas: GAS.mint,
      });
      mintTx = r.transactionHash;
    }
    if ((await read<bigint>(USD, erc20Abi, "allowance", [me, launcher])) < PAID_IN) {
      const r = await send("fund", `approve the Launcher for ${usd(PAID_IN)} test USD (the deposit and the sponsor money)`, {
        to: USD,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [launcher, PAID_IN] }),
        gas: GAS.approve,
      });
      approveTx = r.transactionHash;
    }
    return { testUsdBefore: usd(before), mintTx, approveTx, testUsdAfter: usd(await bal(me)) };
  });

  // ── 3. Join with the 100 deposit ───────────────────────────────────────────
  await step("join", async () => {
    let receipt = await sentBefore("join");
    if (!receipt && !(await read<boolean>(launcher, launcherAbi, "isMember", [me]))) {
      receipt = await send("join", "CheckInLauncher.join: the deployer pays the 100 test USD deposit", {
        to: launcher,
        data: encodeFunctionData({ abi: launcherAbi, functionName: "join" }),
        gas: GAS.join,
      });
    }
    const at = await blockAtLeast(receipt ? Number(receipt.blockNumber) : null);
    return {
      tx: receipt?.transactionHash ?? null,
      block: receipt ? Number(receipt.blockNumber) : null,
      isMember: await retry(() => read<boolean>(launcher, launcherAbi, "isMember", [me], at)),
      memberCount: Number(await retry(() => read<bigint>(launcher, launcherAbi, "memberCount", [], at))),
      totalDepositsUsd: usd(await retry(() => read<bigint>(launcher, launcherAbi, "totalDeposits", [], at))),
    };
  });

  // ── 4. Sponsor 50 ──────────────────────────────────────────────────────────
  await step("sponsor", async () => {
    let receipt = await sentBefore("sponsor");
    if (!receipt && (await read<bigint>(launcher, launcherAbi, "sponsoredBy", [me])) < SPONSOR) {
      receipt = await send("sponsor", "CheckInLauncher.sponsor(50 test USD): shop money only, no share", {
        to: launcher,
        data: encodeFunctionData({ abi: launcherAbi, functionName: "sponsor", args: [SPONSOR] }),
        gas: GAS.sponsor,
      });
    }
    const at = await blockAtLeast(receipt ? Number(receipt.blockNumber) : null);
    return {
      tx: receipt?.transactionHash ?? null,
      block: receipt ? Number(receipt.blockNumber) : null,
      sponsoredByUsd: usd(await retry(() => read<bigint>(launcher, launcherAbi, "sponsoredBy", [me], at))),
      shopWouldGetUsd: usd(await retry(() => read<bigint>(launcher, launcherAbi, "poolQuoteNow", [], at))),
      launcherHoldsUsd: usd(await retry(() => bal(launcher, at))),
    };
  });

  // ── 5. One check-in, signed here by hand: the bar is full ─────────────────
  const checkedIn = await step("checkIn", async () => {
    let receipt = await sentBefore("checkIn");
    let signed: Record<string, unknown> = {};
    if (!receipt && (await read<bigint>(launcher, launcherAbi, "totalCheckIns")) < CHECKIN_GOAL) {
      const day = await read<bigint>(launcher, launcherAbi, "currentDay");
      // The contract's own digest, checked against the documented formula before it is signed.
      const digest = await read<Hex>(launcher, launcherAbi, "checkInDigest", [me, day]);
      const inner = keccak256(
        encodeAbiParameters([{ type: "uint256" }, { type: "address" }, { type: "address" }, { type: "uint256" }], [97n, launcher, me, day]),
      );
      if (hashMessage({ raw: inner }) !== digest) throw new Error("the contract's checkInDigest differs from the documented formula");
      const signature = await deployer.sign({ hash: digest });
      const signer = await recoverAddress({ hash: digest, signature });
      if (!isAddressEqual(signer, me)) throw new Error("the hand-made signature does not recover to the attester");
      log(`  the attester (the deployer) signs the check-in for UTC day ${day} (${iso(day * 86_400n).slice(0, 10)}) by hand`);
      receipt = await send("checkIn", `CheckInLauncher.checkIn(day ${day}): the hand-signed check-in`, {
        to: launcher,
        data: encodeFunctionData({ abi: launcherAbi, functionName: "checkIn", args: [day, signature] }),
        gas: GAS.checkIn,
      });
      signed = { day: Number(day), dayUtc: iso(day * 86_400n).slice(0, 10), digest, signature, signer: getAddress(signer) };
    }
    // Read at the check-in's block (or later), not at whatever block a lagging node calls "latest".
    const at = await blockAtLeast(receipt ? Number(receipt.blockNumber) : null);
    return {
      tx: receipt?.transactionHash ?? null,
      block: receipt ? Number(receipt.blockNumber) : null,
      ...signed,
      readAtBlock: Number(at),
      daysOfDeployer: Number(await retry(() => read<bigint>(launcher, launcherAbi, "daysOf", [me], at))),
      totalCheckIns: Number(await retry(() => read<bigint>(launcher, launcherAbi, "totalCheckIns", [], at))),
      checkInGoal: Number(await retry(() => read<bigint>(launcher, launcherAbi, "checkInGoal", [], at))),
    };
  });

  // ── 6. launch() would revert: the shop is under Flap's floor ──────────────
  const launchRefused = await step("launchRefused", async () => {
    // At the check-in's block or later, so the bar is seen full whichever node answers.
    const at = await blockAtLeast(checkedIn.block);
    const head = await retry(() => client.getBlock({ blockNumber: at }));
    const [canLaunch, pool, prize, total, goal] = await retry(() =>
      Promise.all([
        read<boolean>(launcher, launcherAbi, "canLaunch", [], at),
        read<bigint>(launcher, launcherAbi, "poolQuoteNow", [], at),
        read<bigint>(launcher, launcherAbi, "prizeQuoteNow", [], at),
        read<bigint>(launcher, launcherAbi, "totalCheckIns", [], at),
        read<bigint>(launcher, launcherAbi, "checkInGoal", [], at),
      ]),
    );
    const r = await tryCall(launcher, encodeFunctionData({ abi: launcherAbi, functionName: "launch" }), { blockNumber: at });
    const belowFloor = r.error === "PortalBelowFloor";
    log(
      r.reverted
        ? `  bar ${total} of ${goal}; eth_call launch() reverts with ${r.error}${r.args.length ? ` (${r.args.join(", ")})` : ""}. Nothing was sent.`
        : "  WARNING: eth_call launch() would go through. Nothing was sent; the proof continues to the refund.",
    );
    return {
      block: Number(at),
      blockTime: iso(head.timestamp),
      bar: `${total} of ${goal}`,
      canLaunch,
      shopWouldGetUsd: usd(pool),
      prizeUsd: usd(prize),
      reverted: r.reverted,
      error: r.error,
      errorArgs: r.args,
      offeredUsd: belowFloor ? usd(BigInt(r.args[0] ?? "0")) : null,
      floorUsd: belowFloor ? usd(BigInt(r.args[1] ?? "0")) : null,
      revertData: r.raw,
      sent: false,
    };
  });

  // ── 7. refund() would revert before the deadline ──────────────────────────
  const refundClosed = await step("refundClosed", async () => {
    const atBlock = await blockAtLeast(checkedIn.block);
    const head = await retry(() => client.getBlock({ blockNumber: atBlock }));
    const at = { block: Number(head.number), blockTime: iso(head.timestamp), deadline: iso(deadline), sent: false };
    if (Number(head.timestamp) > deadline) {
      log("  the deadline had already passed: the before-the-deadline refund check could not run");
      return { ...at, skipped: true, reverted: false, error: null as string | null, refundableUsd: null as string | null };
    }
    const r = await tryCall(launcher, encodeFunctionData({ abi: launcherAbi, functionName: "refund" }), { blockNumber: atBlock });
    const owed = await retry(() => read<bigint>(launcher, launcherAbi, "refundable", [me], atBlock));
    log(`  ${deadline - Number(head.timestamp)} s before the deadline, eth_call refund() reverts with ${r.error}. Nothing was sent.`);
    return { ...at, skipped: false, reverted: r.reverted, error: r.error, refundableUsd: usd(owed) as string | null };
  });

  // ── 8. Wait for the chain's clock to pass the deadline ────────────────────
  await step("deadlinePassed", async () => {
    log(`  waiting for a block after ${iso(deadline)} (the chain's clock; this computer's clock is not used)`);
    const giveUpAt = Date.now() + (Math.max(0, deadline - Math.floor(Date.now() / 1000)) + 1800) * 1000;
    let lastLog = 0;
    for (;;) {
      const b = await client.getBlock({ blockTag: "latest" });
      const t = Number(b.timestamp);
      if (t > deadline) {
        log(`  block ${b.number} at ${iso(t)} is past the deadline`);
        return { block: Number(b.number), blockTime: iso(t), secondsPastDeadline: t - deadline };
      }
      if (Date.now() > giveUpAt) throw new Error("the chain's clock has not passed the deadline; run the script again to keep waiting");
      if (Date.now() - lastLog > 30_000) {
        log(`  chain time ${iso(t)}: ${deadline - t + 1} s to go`);
        lastLog = Date.now();
      }
      await sleep(Math.min(10_000, Math.max(2_000, (deadline - t) * 500)));
    }
  });

  // ── 9. refund(): 150 back ──────────────────────────────────────────────────
  const refunded = await step("refund", async () => {
    let receipt = await sentBefore("refund");
    if (!receipt) {
      // A public RPC can answer from a node a few blocks behind: wait until it sees the deadline pass.
      let owed = 0n;
      for (let tries = 0; tries < 15; tries++) {
        owed = await retry(() => read<bigint>(launcher, launcherAbi, "refundable", [me]));
        if (owed !== 0n || !(await retry(() => read<boolean>(launcher, launcherAbi, "isMember", [me])))) break;
        await sleep(2_000);
      }
      if (owed === 0n) {
        // Already refunded outside this script? Then its Refunded event is on chain.
        const logs = await client.getLogs({ address: launcher, event: refundedEvent, args: { account: me }, fromBlock: BigInt(opened.block), toBlock: "latest" });
        const found = logs.at(-1);
        if (!found) throw new Error("refundable() is 0 and no refund to the deployer was found; run the script again in a minute");
        receipt = await client.getTransactionReceipt({ hash: found.transactionHash });
      } else {
        if (owed !== PAID_IN) throw new Error(`refundable() is ${usd(owed)} test USD, not ${usd(PAID_IN)}`);
        receipt = await send("refund", "CheckInLauncher.refund: the deployer takes back its deposit and its sponsor money", {
          to: launcher,
          data: encodeFunctionData({ abi: launcherAbi, functionName: "refund" }),
          gas: GAS.refund,
        });
      }
    }
    const n = receipt.blockNumber;
    // Balances pinned to the block before the refund and the refund's own block.
    const [before, after, launcherBefore, launcherAfter] = await retry(() =>
      Promise.all([bal(me, n - 1n), bal(me, n), bal(launcher, n - 1n), bal(launcher, n)]),
    );
    let event: bigint | null = null;
    let transfer: bigint | null = null;
    for (const l of receipt.logs) {
      try {
        if (isAddressEqual(l.address, launcher)) {
          const ev = decodeEventLog({ abi: launcherAbi, data: l.data, topics: l.topics });
          if (ev.eventName === "Refunded" && isAddressEqual(ev.args.account, me)) event = ev.args.amount;
        } else if (isAddressEqual(l.address, USD)) {
          const ev = decodeEventLog({ abi: erc20Abi, data: l.data, topics: l.topics });
          if (ev.eventName === "Transfer" && isAddressEqual(ev.args.from, launcher) && isAddressEqual(ev.args.to, me)) transfer = ev.args.value;
        }
      } catch {}
    }
    const block = await retry(() => client.getBlock({ blockNumber: n }));
    const after_ = await retry(async () => ({
      isMember: await read<boolean>(launcher, launcherAbi, "isMember", [me], n),
      refundableUsd: usd(await read<bigint>(launcher, launcherAbi, "refundable", [me], n)),
      sponsoredByUsd: usd(await read<bigint>(launcher, launcherAbi, "sponsoredBy", [me], n)),
      memberCount: Number(await read<bigint>(launcher, launcherAbi, "memberCount", [], n)),
      totalDepositsUsd: usd(await read<bigint>(launcher, launcherAbi, "totalDeposits", [], n)),
      totalSponsoredUsd: usd(await read<bigint>(launcher, launcherAbi, "totalSponsored", [], n)),
      launched: await read<boolean>(launcher, launcherAbi, "launched", [], n),
      daysOfDeployer: Number(await read<bigint>(launcher, launcherAbi, "daysOf", [me], n)),
    }));
    log(`  the deployer's test USD: ${usd(before)} before, ${usd(after)} after (block ${n})`);
    return {
      tx: receipt.transactionHash,
      block: Number(n),
      blockTime: iso(block.timestamp),
      gasUsed: receipt.gasUsed.toString(),
      refundedEventUsd: event === null ? null : usd(event),
      transferToDeployerUsd: transfer === null ? null : usd(transfer),
      deployerTestUsd: { beforeWei: before.toString(), afterWei: after.toString(), before: usd(before), after: usd(after), delta: usd(after - before) },
      launcherTestUsd: { before: usd(launcherBefore), after: usd(launcherAfter) },
      after: after_,
    };
  });
  state.links.refundTx = `${EXPLORER}/tx/${refunded.tx}`;

  // ── 10. A second refund() would revert ─────────────────────────────────────
  const secondRefund = await step("secondRefund", async () => {
    // At the refund's own block: the state right after it, whatever node answers.
    const r = await tryCall(launcher, encodeFunctionData({ abi: launcherAbi, functionName: "refund" }), { blockNumber: BigInt(refunded.block) });
    log(`  eth_call refund() again reverts with ${r.error}. Nothing was sent.`);
    return { block: refunded.block, reverted: r.reverted, error: r.error, sent: false };
  });

  // ── The checks ─────────────────────────────────────────────────────────────
  const delta = BigInt(refunded.deployerTestUsd.afterWei) - BigInt(refunded.deployerTestUsd.beforeWei);
  const checks: Check[] = [];
  const check = (name: string, pass: boolean, detail: string) => checks.push({ name, pass, detail });
  check(
    "The round was opened through our factory with the deployer as creator and attester",
    isAddressEqual(config.creator as Hex, me) && isAddressEqual(config.attester as Hex, me),
    `creator ${config.creator}, attester ${config.attester}`,
  );
  check(
    "Its config: deposit 100 test USD, liquidityBps 3000, goal 1 check-in",
    config.depositUsd === usd(DEPOSIT) && config.liquidityBps === Number(LIQUIDITY_BPS) && config.checkInGoal === Number(CHECKIN_GOAL),
    `deposit ${config.depositUsd}, liquidityBps ${config.liquidityBps}, goal ${config.checkInGoal}, deadline ${iso(config.deadline)}`,
  );
  check(
    "One hand-signed check-in filled the bar",
    checkedIn.totalCheckIns >= checkedIn.checkInGoal && checkedIn.daysOfDeployer === 1,
    `bar ${checkedIn.totalCheckIns} of ${checkedIn.checkInGoal}`,
  );
  check(
    "launch() reverts: the shop would get 80 test USD, under Flap's floor",
    launchRefused.reverted &&
      launchRefused.error === "PortalBelowFloor" &&
      launchRefused.errorArgs[0] === SHOP.toString() &&
      BigInt(launchRefused.errorArgs[1] ?? "0") > SHOP,
    launchRefused.reverted
      ? `${launchRefused.error}${launchRefused.errorArgs.length ? ` (offered ${launchRefused.offeredUsd ?? "?"}, floor ${launchRefused.floorUsd ?? "?"} test USD)` : ""}; canLaunch() ${launchRefused.canLaunch}`
      : "launch() would have gone through",
  );
  check(
    "refund() before the deadline reverts with RefundUnavailable",
    refundClosed.reverted && refundClosed.error === "RefundUnavailable",
    refundClosed.skipped
      ? `not checked: the deadline had already passed at block ${refundClosed.block}`
      : `${refundClosed.error} at block ${refundClosed.block} (${refundClosed.blockTime}, deadline ${refundClosed.deadline}), refundable ${refundClosed.refundableUsd}`,
  );
  check(
    "refund() after the deadline pays exactly 150 test USD back to the wallet that paid it",
    delta === PAID_IN && refunded.refundedEventUsd === usd(PAID_IN) && refunded.transferToDeployerUsd === usd(PAID_IN),
    `balance ${refunded.deployerTestUsd.before} -> ${refunded.deployerTestUsd.after} (+${usd(delta)}), Refunded event ${refunded.refundedEventUsd}`,
  );
  check(
    "After the refund: isMember false, refundable 0, sponsoredBy 0",
    refunded.after.isMember === false && refunded.after.refundableUsd === "0" && refunded.after.sponsoredByUsd === "0",
    `isMember ${refunded.after.isMember}, refundable ${refunded.after.refundableUsd}, sponsoredBy ${refunded.after.sponsoredByUsd}`,
  );
  check(
    "The round never launched and holds no test USD afterwards",
    refunded.after.launched === false && refunded.launcherTestUsd.after === "0",
    `launched ${refunded.after.launched}, Launcher test USD ${refunded.launcherTestUsd.before} -> ${refunded.launcherTestUsd.after}`,
  );
  check("A second refund() reverts with NothingToRefund", secondRefund.reverted && secondRefund.error === "NothingToRefund", `${secondRefund.error}`);

  state.balances = {
    deployerTestUsd: {
      atStart: state.steps.fund?.testUsdBefore ?? null,
      beforeRefund: refunded.deployerTestUsd.before,
      afterRefund: refunded.deployerTestUsd.after,
      change: usd(delta),
      readAtBlocks: [refunded.block - 1, refunded.block],
    },
    launcherTestUsd: { beforeRefund: refunded.launcherTestUsd.before, afterRefund: refunded.launcherTestUsd.after },
  };
  state.checks = checks;
  state.ok = checks.every((c) => c.pass);
  state.status = state.ok ? "done" : "failed: see checks";
  save();

  for (const c of checks) log(`${c.pass ? "PASS" : "FAIL"}  ${c.name}: ${c.detail}`);
  log(`Launcher ${launcher}  ${state.links.launcher}`);
  log(`Refund   ${refunded.tx}  ${state.links.refundTx}`);
  log(`${state.ok ? "Refund proof done" : "Refund proof FAILED"}. Result written to ${resultFile}`);
  if (!state.ok) process.exitCode = 1;
}

main().catch((e) => {
  // Only the message: an error object from a wallet client can carry the request it was built from.
  const message = `${e?.shortMessage ?? e?.message ?? e}`;
  console.error(`FAILED: ${message}`);
  try {
    recordFailure?.(message);
  } catch {}
  process.exit(1);
});
