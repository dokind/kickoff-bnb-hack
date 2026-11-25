// One real, complete Cypher Run round on BSC testnet (chain 97), against the deployed factories and a
// running verifier (our server, the attester). Test assets only: test BNB and Flap's free-mint
// test USD, neither has any value.
//
//   cd verifier && VERIFIER_URL=https://<host>/api npx tsx ../scripts/run-round.ts
//
// Run it from the verifier folder: viem is taken from verifier/node_modules.
//
// What it does, in order:
//    1. The deployer wallet opens a round with Portal.newLauncher and our CheckInLauncherFactory.
//       The launch salt is mined from a random start so the token address ends in 0x7777.
//    2. The verifier is pointed at the round (POST /admin/round).
//    3. Three throwaway member wallets get a little test BNB and the deposit in test USD from the
//       deployer, approve the Launcher and join().
//    4. Optional sponsor: if the launch pool is under Flap's floor (1,500 test USD today), the
//       deployer sponsors the difference. Sponsor money goes to the pool only and earns no share.
//    5. Check-ins. Each member who shows up reports steps to the verifier with source "self"
//       (POST /checkin), gets the attester's signature back and sends
//       CheckInLauncher.checkIn(dayIndex, signature) from its own wallet. A dry run shows that
//       launch() is refused while the bar is not full.
//    6. launch(), sent from a member wallet (anyone may send it): the Flap launch. Half the supply
//       and the pool money go to the pool, the other half and the prize go to the StreakVault.
//    7. The member who launched claims straight away (claims open in the next transaction).
//    8. The deployer wallet buys and sells the token on PancakeSwap with test USD until the tax has
//       been sold into test USD and has reached the vault. dispatch() on the token's tax processor
//       pays the vault its share and anyone may call it; on testnet another account (not ours) has
//       been seen calling it within a few blocks, so the script calls it only when the money is
//       still waiting in the processor.
//    9. Every member with at least one day claims (the early claimer again, for the tax). The
//       member with no days is checked: a claim would revert.
//   10. The chain and the verifier are read back and everything is written to a result file.
//
// IMPORTANT, said plainly: the step counts in step 5 are made up by this script. They are sent as
// self-reported, signed by the member wallets, and the server must run with
// ALLOW_SELF_REPORTED=true to take them. Nobody walked them. Check-ins are attested by our server,
// not proven. Everything on chain is real.
//
// Who shows up: Ana every day the script runs, Ben on the first day only, Chai never. One wallet
// can check in once per UTC day, so:
//   CHECKIN_GOAL=2 (default)  the bar fills on the first day: Ana 1 day, Ben 1 day, Chai 0.
//   CHECKIN_GOAL=3            needs two UTC days: run it, then run it again after 00:00 UTC.
//                             Ana ends with 2 days, Ben 1, Chai 0, so the split is 2 : 1 : 0.
// If the bar is not full after today's check-ins the script stops and says when to run it again.
// To leave a round open for people to finish in the app, set CHECKIN_GOAL higher than the script
// can reach; once somebody has launched it in the app, run the script again for steps 8 to 10.
//
// Keys: the deployer key is read from contracts/.env (PRIVATE_KEY) and the admin token from
// verifier/.env (ADMIN_TOKEN). They stay in memory and are never printed or written anywhere. The
// member keys are derived in memory from the deployer key and the run id, so a stopped run can be
// continued without any key on disk.
//
// Continuing a stopped run: the script saves each finished step (addresses and transaction hashes
// only) to STATE_FILE and skips those steps the next time. Delete the file to start a new round.
// The round's own settings are read back from the chain, and MEMBER_COUNT and YESTERDAY_CHECKIN are
// kept in the state file, so a continued run only needs VERIFIER_URL and STATE_FILE.
//
// Every transaction is a legacy transaction at 1 gwei with an explicit gas limit: fee estimation on
// this testnet can return 1 wei, and such transactions are never mined.
//
// Settings (environment variables, all optional except VERIFIER_URL):
//   VERIFIER_URL       base of the verifier API, e.g. https://<host>/api            (required)
//   RPC_URL            BSC testnet RPC             default: verifier/.env RPC_URL or publicnode
//   STATE_FILE         progress file               default: scripts/round-run.json
//   ROUND_NAME         default "Bangkok Cypher Run"
//   ROUND_SYMBOL       symbol the Portal needs for the token; default "CYPHER"
//   DEPOSIT_USD        deposit per member in whole test USD                        default 1000
//   LIQUIDITY_BPS      part of the deposits that seeds the pool, basis points      default 3000
//   CHECKIN_GOAL       check-ins that fill the bar                                 default 2
//   DEADLINE_HOURS     round deadline, hours from the start of the run             default 30
//   SPONSOR_USD        "auto" (top the pool up to POOL_FLOOR_USD), or a whole number, or 0
//   POOL_FLOOR_USD     Flap's pool floor on testnet in whole test USD              default 1500
//   ATTESTER_ADDRESS   default: the address of the key in verifier/.env
//   MEMBER_COUNT       how many of the three throwaway members join (1 to 3)       default 3
//   YESTERDAY_CHECKIN  "true": Ana also checks in for yesterday (UTC), see below   default off
//
// YESTERDAY_CHECKIN, said plainly: the contract accepts a check-in for today or yesterday, but the
// server signs for today only. With this switch the script signs Ana's check-in for yesterday
// itself, with the attester key from verifier/.env (the same key the server holds), without any
// report going through the server. It is the operator signing by hand, which is exactly what
// "attested, not proven" allows. It exists so one sitting can show unequal days (Ana 2, Ben 1,
// Chai 0 with CHECKIN_GOAL=3). The server's own records (streaks) do not know about that day.
//
// After each stage the script reads GET /round and GET /me/<member> from the verifier and compares
// them with its own reads of the chain; a difference that does not go away stops the run.
//
// The result is written next to the state file: <name>-run.json gives <name>-result.json.
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
  parseEther,
  formatEther,
  keccak256,
  concat,
  toHex,
  encodeAbiParameters,
  encodeFunctionData,
  decodeEventLog,
  getAddress,
  maxUint256,
} = viem;

type Hex = `0x${string}`;
type Account = ReturnType<typeof privateKeyToAccount>;

// The product name. The texts members sign are built from it; the same name is in
// verifier/src/product.ts and app/lib/config.dart.
const PRODUCT_NAME = "Cypher Run";
const SERVICE_NAME = `${PRODUCT_NAME.toLowerCase().replace(/\s+/g, "-")}-verifier`;

// ── Fixed addresses on BSC testnet ───────────────────────────────────────────
const PORTAL: Hex = "0x000042108465206185A077Edc3F3fd2b49060000";
// keccak256 of the creation code of the token clone the Portal deploys (contracts/test/Salt.t.sol).
const TOKEN_INIT_CODE_HASH: Hex = "0xc7e15deb24b23c120ed65985516639441790ec6e89090f4aa0a87169aa9c2730";
const V2_ROUTER: Hex = "0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3"; // PancakeSwap V2 router the Portal uses
const USD: Hex = "0x190C989D5665a0e404B444b53CAE9AbCfb600157"; // Flap's test USD: anyone can mint
const EXPLORER = "https://testnet.bscscan.com";

const GAS_PRICE = 1_000_000_000n; // 1 gwei, legacy
const GAS = {
  transfer: 21_000n,
  mint: 150_000n,
  approve: 100_000n,
  newLauncher: 1_000_000n,
  join: 250_000n,
  sponsor: 200_000n,
  checkIn: 200_000n,
  launch: 7_000_000n, // uses about 5,000,000
  claim: 500_000n,
  swap: 2_500_000n,
  dispatch: 2_500_000n,
};
const gasMoney = (limits: bigint[]) => limits.reduce((a, b) => a + b, 0n) * GAS_PRICE;
// Test BNB each member needs at the gas limits above, with room. The first member also launches.
const MEMBER_GAS_MONEY =
  gasMoney([GAS.approve, GAS.join, GAS.checkIn, GAS.checkIn, GAS.checkIn, GAS.checkIn, GAS.claim, GAS.claim]) + parseEther("0.0005");
const LAUNCH_GAS_MONEY = gasMoney([GAS.launch]) + parseEther("0.0005");

// Who shows up. The step counts are made up by this script and sent as self-reported.
const MEMBERS = [
  { label: "Ana", showsUp: "every day", steps: 6200 },
  { label: "Ben", showsUp: "first day only", steps: 5400 },
  { label: "Chai", showsUp: "never", steps: 0 },
] as const;

const portalAbi = parseAbi([
  "function SALT_LOCK_FEE() view returns (uint256)",
  "function featureFlags() view returns (uint256)",
  "function newLauncher(address launcherFactory, bytes data) payable returns (address)",
]);
const factoryAbi = parseAbi(["event CheckInLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt)"]);
const launcherAbi = parseAbi([
  "function join()",
  "function sponsor(uint256 amount)",
  "function checkIn(uint256 day, bytes signature)",
  "function launch()",
  "function deposit() view returns (uint256)",
  "function liquidityBps() view returns (uint256)",
  "function checkInGoal() view returns (uint256)",
  "function deadline() view returns (uint256)",
  "function attester() view returns (address)",
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
  "function launched() view returns (bool)",
  "function token() view returns (address)",
  "function pool() view returns (address)",
  "function vault() view returns (address)",
  "event Launched(address indexed token, address indexed pool, address indexed vault, uint256 poolQuote, uint256 prizeQuote)",
  "error GoalNotReached(uint256 totalCheckIns, uint256 checkInGoal)",
  "error LaunchClosed()",
  "error AlreadyLaunched()",
  "error NoPoolQuote()",
]);
const erc20Abi = parseAbi([
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function taxProcessor() view returns (address)",
]);
const routerAbi = parseAbi([
  "function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, address[] path, address to, uint256 deadline)",
]);
const processorAbi = parseAbi([
  "function dispatch()",
  "function feeQuoteBalance() view returns (uint256)",
  "function marketQuoteBalance() view returns (uint256)",
]);
const vaultAbi = parseAbi([
  "function claim()",
  "function claimable(address member) view returns (uint256 tokenAmount, uint256 quoteAmount)",
  "function claimedTokens(address member) view returns (uint256)",
  "function claimedQuote(address member) view returns (uint256)",
  "function daysOf(address member) view returns (uint256)",
  "function totalCheckIns() view returns (uint256)",
  "function quoteReceived() view returns (uint256)",
  "function reservedTokens() view returns (uint256)",
  "function totalQuotePaid() view returns (uint256)",
  "function totalTokensPaid() view returns (uint256)",
  "event Claimed(address indexed member, uint256 tokenAmount, uint256 quoteAmount)",
  "error NothingToClaim()",
]);

// ── Small helpers ────────────────────────────────────────────────────────────
const root = resolve(process.cwd(), "..");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const log = (msg: string) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`);
const nowSec = () => Math.floor(Date.now() / 1000);
const usd = (whole: number | string) => parseEther(String(whole));

/** KEY=value lines of an env file. Values are returned, never printed. */
function envFile(path: string): Record<string, string> {
  if (!existsSync(path)) return {};
  const out: Record<string, string> = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line);
    if (m) out[m[1]!] = m[2]!.replace(/^["']|["']$/g, "");
  }
  return out;
}

const asKey = (value: string): Hex => (value.startsWith("0x") ? value : `0x${value}`) as Hex;

function wholeNumber(name: string, fallback: number, min: number, max: number): number {
  const n = Number(process.env[name] ?? fallback);
  if (!Number.isInteger(n) || n < min || n > max) throw new Error(`${name} must be a whole number from ${min} to ${max}`);
  return n;
}

interface TxRecord {
  step: string;
  what: string;
  hash: string;
  from: string;
}
interface State {
  runId: string;
  startedAt: number;
  deadline: number;
  /** Kept from the first run, so a continued run has the same members whatever the environment says. */
  memberCount?: number;
  yesterdayCheckIn?: boolean;
  done: Record<string, unknown>;
  txs: TxRecord[];
}

async function main() {
  const verifierEnv = envFile(join(root, "verifier/.env"));
  const contractsEnv = envFile(join(root, "contracts/.env"));
  const deployments = JSON.parse(readFileSync(join(root, "contracts/deployments/bsc-testnet.json"), "utf8"));
  if (deployments.chainId !== 97 || !deployments.checkInLauncherFactory) {
    throw new Error("contracts/deployments/bsc-testnet.json has no checkInLauncherFactory for chain 97; deploy the factories first");
  }
  const FACTORY = getAddress(deployments.checkInLauncherFactory);

  const api = (process.env.VERIFIER_URL || "").replace(/\/$/, "");
  if (!api) throw new Error("Set VERIFIER_URL to the verifier API, e.g. https://<host>/api");
  const adminToken = process.env.ADMIN_TOKEN || verifierEnv.ADMIN_TOKEN;
  if (!adminToken) throw new Error("ADMIN_TOKEN not found in verifier/.env");
  const deployerKey = process.env.PRIVATE_KEY || contractsEnv.PRIVATE_KEY;
  if (!deployerKey) throw new Error("PRIVATE_KEY not found in contracts/.env");
  const rpcUrl = process.env.RPC_URL || verifierEnv.RPC_URL || "https://bsc-testnet-rpc.publicnode.com";

  // The round must name the server's signing address as its attester, or the server cannot sign
  // for it. Only the address is derived here; the key itself is not kept.
  const attesterKey = verifierEnv.ATTESTER_PRIVATE_KEY || verifierEnv.VERIFIER_PRIVATE_KEY;
  const attesterAddress = process.env.ATTESTER_ADDRESS
    ? getAddress(process.env.ATTESTER_ADDRESS)
    : attesterKey
      ? privateKeyToAccount(asKey(attesterKey)).address
      : null;
  if (!attesterAddress) throw new Error("Set ATTESTER_ADDRESS to the address of the server's attester key");

  const stateFile = process.env.STATE_FILE || join(root, "scripts/round-run.json");
  const roundName = process.env.ROUND_NAME || "Bangkok Cypher Run";
  const roundSymbol = process.env.ROUND_SYMBOL || "CYPHER";
  const depositUsd = wholeNumber("DEPOSIT_USD", 1000, 1, 1_000_000);
  const liquidityBps = wholeNumber("LIQUIDITY_BPS", 3000, 0, 10_000);
  const checkInGoal = wholeNumber("CHECKIN_GOAL", 2, 1, 1000);
  const deadlineHours = wholeNumber("DEADLINE_HOURS", 30, 1, 90 * 24);
  const poolFloor = usd(wholeNumber("POOL_FLOOR_USD", 1500, 0, 1_000_000_000));
  const sponsorSetting = process.env.SPONSOR_USD || "auto";
  if (sponsorSetting !== "auto" && !/^\d+$/.test(sponsorSetting)) throw new Error('SPONSOR_USD must be "auto" or a whole number');
  const DEPOSIT = usd(depositUsd);

  let state: State;
  if (existsSync(stateFile)) {
    state = JSON.parse(readFileSync(stateFile, "utf8"));
    log(`Continuing run ${state.runId} from ${stateFile}`);
  } else {
    const t = nowSec();
    state = {
      runId: `${t}`,
      startedAt: t,
      deadline: t + deadlineHours * 3600,
      memberCount: wholeNumber("MEMBER_COUNT", 3, 1, MEMBERS.length),
      yesterdayCheckIn: process.env.YESTERDAY_CHECKIN === "true",
      done: {},
      txs: [],
    };
  }
  // A continued run keeps the members and the yesterday switch of its first run.
  const memberCount = state.memberCount ?? MEMBERS.length;
  const yesterdayCheckIn = state.yesterdayCheckIn ?? false;
  if (yesterdayCheckIn && !attesterKey) throw new Error("YESTERDAY_CHECKIN needs the attester key in verifier/.env");
  const save = () => writeFileSync(stateFile, JSON.stringify(state, null, 2) + "\n");

  const transport = http(rpcUrl, { retryCount: 5, retryDelay: 800 });
  const client = createPublicClient({ chain: bscTestnet, transport });
  if ((await client.getChainId()) !== 97) throw new Error("RPC is not BSC testnet (chain 97)");

  const deployer = privateKeyToAccount(asKey(deployerKey));
  // Throwaway member keys, derived in memory. Nothing of them is written to disk. The seed text
  // keeps the earlier working name so an unfinished run still gets the same members.
  const members = MEMBERS.slice(0, memberCount).map((m, i) => ({
    ...m,
    account: privateKeyToAccount(keccak256(concat([asKey(deployerKey), toHex(`showup-round-${state.runId}-member-${i}`)]))),
  }));

  // One nonce counter per sender: a load-balanced public RPC can lag behind our own last send.
  const nonces = new Map<string, number>();
  async function send(step: string, what: string, account: Account, tx: { to: Hex; data?: Hex; value?: bigint; gas: bigint }) {
    const from = account.address;
    const pending = await client.getTransactionCount({ address: from, blockTag: "pending" });
    const nonce = Math.max(pending, nonces.get(from) ?? 0);
    const wallet = createWalletClient({ account, chain: bscTestnet, transport });
    const hash = await wallet.sendTransaction({ ...tx, type: "legacy", gasPrice: GAS_PRICE, nonce });
    nonces.set(from, nonce + 1);
    state.txs.push({ step, what, hash, from });
    save();
    const receipt = await client.waitForTransactionReceipt({ hash, timeout: 180_000, pollingInterval: 1_500 });
    if (receipt.status !== "success") throw new Error(`${what}: transaction ${hash} reverted`);
    log(`  ${what}: ${hash} (gas ${receipt.gasUsed})`);
    return receipt;
  }

  /** Runs a step once; a finished step's result is kept in the state file and reused. */
  async function step<T>(name: string, fn: () => Promise<T>): Promise<T> {
    if (name in state.done) return state.done[name] as T;
    log(`STEP ${name}`);
    const result = await fn();
    state.done[name] = result ?? null;
    save();
    return result;
  }

  async function post(path: string, body: unknown, admin = false) {
    const res = await fetch(`${api}${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", ...(admin ? { authorization: `Bearer ${adminToken}` } : {}) },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    let json: any;
    try {
      json = JSON.parse(text);
    } catch {
      json = { raw: text.slice(0, 300) };
    }
    return { status: res.status, json };
  }
  async function get(path: string) {
    const res = await fetch(`${api}${path}`);
    const text = await res.text();
    try {
      return { status: res.status, json: JSON.parse(text) as any };
    } catch {
      return { status: res.status, json: { raw: text.slice(0, 300) } as any };
    }
  }

  const read = <T>(address: Hex, abi: any, functionName: string, args: unknown[] = []) =>
    client.readContract({ address, abi, functionName, args } as any) as Promise<T>;
  const bal = (token: Hex, holder: Hex) => read<bigint>(token, erc20Abi, "balanceOf", [holder]);

  /** The name of the error a call would revert with, or null when it would go through. Sends nothing. */
  async function wouldRevert(account: Hex, address: Hex, abi: any, functionName: string): Promise<string | null> {
    try {
      await client.simulateContract({ account, address, abi, functionName, args: [] } as any);
      return null;
    } catch (e: any) {
      return e?.cause?.data?.errorName ?? e?.cause?.shortMessage ?? e?.shortMessage ?? "reverted";
    }
  }

  /**
   * Reads GET /round and GET /me/<member> from the verifier and compares them with this script's own
   * reads of the chain. The verifier reads through its own RPC, which can be a block behind, so a
   * difference is retried for a while before it counts. The comparison is kept in the state file.
   */
  async function apiCheck(stage: string, launcher: Hex) {
    const key = `api-${stage}`;
    if (key in state.done) return;
    let diffs: string[] = [];
    let summary: any = null;
    for (let tries = 0; tries < 15; tries++) {
      diffs = [];
      const r = await get("/round");
      if (r.status !== 200) {
        diffs.push(`GET /round answered ${r.status}`);
      } else {
        const j = r.json;
        const launchedNow = await read<boolean>(launcher, launcherAbi, "launched");
        const zero = "0x0000000000000000000000000000000000000000";
        const lc = (v: unknown) => (typeof v === "string" && v.toLowerCase() !== zero ? v.toLowerCase() : null);
        const expectRound: Record<string, unknown> = {
          launcher: launcher.toLowerCase(),
          checkInGoal: Number(await read<bigint>(launcher, launcherAbi, "checkInGoal")),
          totalCheckIns: Number(await read<bigint>(launcher, launcherAbi, "totalCheckIns")),
          memberCount: Number(await read<bigint>(launcher, launcherAbi, "memberCount")),
          deadline: Number(await read<bigint>(launcher, launcherAbi, "deadline")),
          launched: launchedNow,
          token: lc(await read<Hex>(launcher, launcherAbi, "token")),
          vault: lc(await read<Hex>(launcher, launcherAbi, "vault")),
          dayIndex: Number(await read<bigint>(launcher, launcherAbi, "currentDay")),
        };
        const expectRaw: Record<string, string> = {
          deposit: (await read<bigint>(launcher, launcherAbi, "deposit")).toString(),
          totalDeposits: (await read<bigint>(launcher, launcherAbi, "totalDeposits")).toString(),
          totalSponsored: (await read<bigint>(launcher, launcherAbi, "totalSponsored")).toString(),
          poolQuoteNow: (await read<bigint>(launcher, launcherAbi, "poolQuoteNow")).toString(),
        };
        for (const [k, v] of Object.entries(expectRound)) {
          const got = k === "token" || k === "vault" ? lc(j[k]) : j[k];
          if (got !== v) diffs.push(`/round ${k}: server ${JSON.stringify(j[k])}, chain ${JSON.stringify(v)}`);
        }
        for (const [k, v] of Object.entries(expectRaw)) {
          if (j.raw?.[k] !== v) diffs.push(`/round raw.${k}: server ${j.raw?.[k]}, chain ${v}`);
        }
        const vaultNow = expectRound.vault as Hex | null;
        const me: any[] = [];
        for (const m of members) {
          const a = m.account.address;
          const mr = await get(`/me/${a.toLowerCase()}`);
          if (mr.status !== 200) {
            diffs.push(`GET /me for ${m.label} answered ${mr.status}`);
            continue;
          }
          const expectMe: Record<string, unknown> = {
            member: await read<boolean>(launcher, launcherAbi, "isMember", [a]),
            daysOf: Number(await read<bigint>(launcher, launcherAbi, "daysOf", [a])),
            checkedInToday: await read<boolean>(launcher, launcherAbi, "checkedInOn", [a, BigInt(expectRound.dayIndex as number)]),
          };
          const expectMeRaw: Record<string, string> = {};
          if (launchedNow && vaultNow) {
            const [ct, cq] = await read<[bigint, bigint]>(vaultNow, vaultAbi, "claimable", [a]);
            expectMeRaw.claimableTokens = ct.toString();
            expectMeRaw.claimableQuote = cq.toString();
            expectMeRaw.claimedTokens = (await read<bigint>(vaultNow, vaultAbi, "claimedTokens", [a])).toString();
            expectMeRaw.claimedQuote = (await read<bigint>(vaultNow, vaultAbi, "claimedQuote", [a])).toString();
          }
          for (const [k, v] of Object.entries(expectMe)) {
            if (mr.json[k] !== v) diffs.push(`/me ${m.label} ${k}: server ${JSON.stringify(mr.json[k])}, chain ${JSON.stringify(v)}`);
          }
          for (const [k, v] of Object.entries(expectMeRaw)) {
            if (mr.json.raw?.[k] !== v) diffs.push(`/me ${m.label} raw.${k}: server ${mr.json.raw?.[k]}, chain ${v}`);
          }
          me.push({ label: m.label, ...expectMe, ...expectMeRaw, serverDays: mr.json.days });
        }
        summary = { round: { ...expectRound, ...expectRaw, name: j.name, canLaunch: j.canLaunch, today: j.today }, me };
      }
      if (diffs.length === 0) break;
      await sleep(2000);
    }
    if (diffs.length > 0) throw new Error(`the verifier does not match the chain at stage "${stage}": ${diffs.join("; ")}`);
    const r = summary.round;
    log(
      `  API check "${stage}": /round and /me match the chain (members ${r.memberCount}, bar ${r.totalCheckIns} of ${r.checkInGoal}, ` +
        `launched ${r.launched}; days ${summary.me.map((x: any) => `${x.label} ${x.daysOf}`).join(", ")})`,
    );
    state.done[key] = { matches: true, at: nowSec(), ...summary };
    save();
  }

  // ── 0. Checks before anything is sent ──────────────────────────────────────
  // Behind the hosting proxy the service answers at <api>/; a verifier reached directly answers at
  // <api> without the slash.
  let health = await get("/");
  if (!health.json?.ok) health = await get("");
  if (!health.json?.ok) throw new Error(`verifier at ${api} did not answer ok`);
  if (health.json.service !== SERVICE_NAME) {
    throw new Error(`${api} answers as "${health.json.service}", not the ${PRODUCT_NAME} verifier. Is the new server deployed there?`);
  }
  const [deployerBnb, saltFee, flags, factoryCode] = await Promise.all([
    client.getBalance({ address: deployer.address }),
    read<bigint>(PORTAL, portalAbi, "SALT_LOCK_FEE"),
    read<bigint>(PORTAL, portalAbi, "featureFlags"),
    client.getCode({ address: FACTORY }),
  ]);
  if (!factoryCode || factoryCode === "0x") throw new Error(`no contract code at the CheckInLauncherFactory ${FACTORY}`);
  if ((flags & 1n) !== 0n) throw new Error("the testnet Portal has creation paused");
  if (!("open" in state.done) && deployerBnb < parseEther("0.06")) {
    throw new Error(`deployer ${deployer.address} needs at least 0.06 test BNB to start a round`);
  }
  log(`Verifier ${api} is up. Deployer ${deployer.address} holds ${formatEther(deployerBnb)} test BNB.`);
  log(`Members: ${members.map((m) => `${m.label} ${m.account.address}`).join(", ")}`);
  log(`Attester (our server): ${attesterAddress}. Deadline: ${new Date(state.deadline * 1000).toISOString()}`);

  // ── 1. The deployer opens the round ───────────────────────────────────────
  const opened = await step("open", async () => {
    // The Portal deploys the token as a CREATE2 clone; its address must end in 0x7777. The search
    // starts from a random seed: small sequential salts are already locked by others on testnet.
    // Same search as the app (app/lib/services/chain_service.dart): the counter overwrites the last
    // four bytes of the seed.
    const input = Buffer.concat([
      Buffer.from("ff", "hex"),
      Buffer.from(PORTAL.slice(2), "hex"),
      Buffer.from(keccak256(toHex(`seed-${state.runId}-${Math.random()}-${Date.now()}`)).slice(2), "hex"),
      Buffer.from(TOKEN_INIT_CODE_HASH.slice(2), "hex"),
    ]);
    let salt: Hex | null = null;
    for (let i = 0; i < 0xffffffff; i++) {
      input.writeUInt32BE(i, 49);
      const hash = keccak256(input, "bytes");
      if (hash[30] === 0x77 && hash[31] === 0x77) {
        salt = `0x${input.subarray(21, 53).toString("hex")}`;
        log(`  salt found after ${i + 1} tries; the token will be 0x${Buffer.from(hash.subarray(12)).toString("hex")}`);
        break;
      }
    }
    if (!salt) throw new Error("no salt found");

    // abi.encode(RoundConfig): ONE tuple, in the order the factory decodes it.
    const config = encodeAbiParameters(
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
          name: roundName,
          symbol: roundSymbol,
          meta: "",
          salt,
          deposit: DEPOSIT,
          liquidityBps: BigInt(liquidityBps),
          checkInGoal: BigInt(checkInGoal),
          deadline: BigInt(state.deadline),
          attester: attesterAddress,
        },
      ],
    );
    const data = encodeFunctionData({ abi: portalAbi, functionName: "newLauncher", args: [FACTORY, config] });
    // Dry run first, so a refused config costs nothing.
    await client.call({ account: deployer.address, to: PORTAL, data, value: saltFee, gas: GAS.newLauncher });
    const receipt = await send("open", "Portal.newLauncher (the deployer opens the round)", deployer, {
      to: PORTAL,
      data,
      value: saltFee,
      gas: GAS.newLauncher,
    });
    for (const l of receipt.logs) {
      if (l.address.toLowerCase() !== FACTORY.toLowerCase()) continue;
      try {
        const ev = decodeEventLog({ abi: factoryAbi, data: l.data, topics: l.topics });
        return { launcher: getAddress((ev.args as any).launcher), salt, attester: attesterAddress, tx: receipt.transactionHash };
      } catch {}
    }
    throw new Error("CheckInLauncherCreated not found in the receipt");
  });
  const launcher = opened.launcher as Hex;
  log(`Launcher (the round): ${launcher}`);
  const goal = Number(await read<bigint>(launcher, launcherAbi, "checkInGoal"));
  const deposit = await read<bigint>(launcher, launcherAbi, "deposit");
  const deadline = Number(await read<bigint>(launcher, launcherAbi, "deadline"));

  // ── 2. Point the verifier at the round ────────────────────────────────────
  const pointed = await step("point", async () => {
    let r = await post("/admin/round", { launcher, name: roundName }, true);
    // The verifier reads the new Launcher through its own RPC, which can be a block behind ours.
    for (let tries = 0; r.status === 503 && r.json?.error === "chain_unavailable" && tries < 10; tries++) {
      await sleep(2000);
      r = await post("/admin/round", { launcher, name: roundName }, true);
    }
    if (r.status !== 200) throw new Error(`POST /admin/round: ${r.status} ${JSON.stringify(r.json)}`);
    if (r.json.launcher !== launcher.toLowerCase()) throw new Error("the verifier answered with another launcher");
    if (!r.json.attesterReady) throw new Error("the verifier has no attester key for this round (attesterReady is false)");
    return { minSteps: r.json.minSteps, allowSelfReported: r.json.allowSelfReported, attester: r.json.attester };
  });
  if (!pointed.allowSelfReported) {
    throw new Error("the verifier refuses self-reported check-ins. Set ALLOW_SELF_REPORTED=true on the server, restart it and run again.");
  }
  // Somebody may have pointed the server at another round since (a stopped run that is continued).
  const servedNow = await get("/round");
  if (servedNow.status !== 200 || servedNow.json.launcher !== launcher.toLowerCase()) {
    throw new Error(
      `the verifier is serving ${servedNow.json?.launcher ?? "no round"}, not ${launcher.toLowerCase()}. ` +
        `Point it back with POST /admin/round before continuing this run.`,
    );
  }
  await apiCheck("opened", launcher);

  // ── 3. Three members are funded and join ──────────────────────────────────
  for (const [i, m] of members.entries()) {
    await step(`join-${i}`, async () => {
      const a = m.account.address;
      const gasMoneyNeeded = MEMBER_GAS_MONEY + (i === 0 ? LAUNCH_GAS_MONEY : 0n);
      if ((await client.getBalance({ address: a })) < gasMoneyNeeded) {
        await send(`join-${i}`, `test BNB for gas to ${m.label}`, deployer, { to: a, value: gasMoneyNeeded, gas: GAS.transfer });
      }
      let joinTx: string | null = null;
      if (!(await read<boolean>(launcher, launcherAbi, "isMember", [a]))) {
        if ((await bal(USD, a)) < deposit) {
          await send(`join-${i}`, `mint ${depositUsd} test USD to ${m.label}`, deployer, {
            to: USD,
            data: encodeFunctionData({ abi: erc20Abi, functionName: "mint", args: [a, deposit] }),
            gas: GAS.mint,
          });
        }
        await send(`join-${i}`, `${m.label} approves the Launcher for the deposit`, m.account, {
          to: USD,
          data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [launcher, deposit] }),
          gas: GAS.approve,
        });
        const receipt = await send(`join-${i}`, `${m.label} pays the deposit (CheckInLauncher.join)`, m.account, {
          to: launcher,
          data: encodeFunctionData({ abi: launcherAbi, functionName: "join" }),
          gas: GAS.join,
        });
        joinTx = receipt.transactionHash;
      }
      return { address: a, depositUsd, joinTx };
    });
  }

  await apiCheck("joined", launcher);

  // ── 4. Optional sponsor: top the launch pool up to Flap's floor ───────────
  const sponsored = await step("sponsor", async () => {
    const poolNow = await read<bigint>(launcher, launcherAbi, "poolQuoteNow");
    const amount = sponsorSetting === "auto" ? (poolNow < poolFloor ? poolFloor - poolNow : 0n) : usd(sponsorSetting);
    if (amount === 0n) {
      log(`  no sponsor needed: the pool would get ${formatEther(poolNow)} test USD`);
      return { amountUsd: "0", tx: null, poolBeforeUsd: formatEther(poolNow) };
    }
    log(`  the pool would get ${formatEther(poolNow)} test USD; the deployer sponsors ${formatEther(amount)}`);
    if ((await bal(USD, deployer.address)) < amount) {
      await send("sponsor", `mint ${formatEther(amount)} test USD to the sponsor`, deployer, {
        to: USD,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "mint", args: [deployer.address, amount] }),
        gas: GAS.mint,
      });
    }
    if ((await read<bigint>(USD, erc20Abi, "allowance", [deployer.address, launcher])) < amount) {
      await send("sponsor", "the sponsor approves the Launcher", deployer, {
        to: USD,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [launcher, amount] }),
        gas: GAS.approve,
      });
    }
    const receipt = await send("sponsor", `CheckInLauncher.sponsor(${formatEther(amount)} test USD): pool only, no share`, deployer, {
      to: launcher,
      data: encodeFunctionData({ abi: launcherAbi, functionName: "sponsor", args: [amount] }),
      gas: GAS.sponsor,
    });
    return { amountUsd: formatEther(amount), tx: receipt.transactionHash, poolBeforeUsd: formatEther(poolNow) };
  });
  void sponsored;
  await apiCheck("sponsored", launcher);

  // ── 5. Check-ins, one UTC day at a time ───────────────────────────────────
  let launched = await read<boolean>(launcher, launcherAbi, "launched");
  if (!launched) {
    const round = await get("/round");
    if (round.status !== 200) throw new Error(`GET /round: ${round.status} ${JSON.stringify(round.json)}`);
    const today = round.json.today as string;
    const firstDay = (state.done["first-day"] as string | undefined) ?? today;
    await step("first-day", async () => today);

    // Optional: Ana's check-in for yesterday (UTC). The contract accepts it; the server signs for
    // today only, so this signature is made here with the attester key, by hand, without a report
    // going through the server. See the note at the top of this file.
    if (yesterdayCheckIn) {
      await step("checkin-yesterday", async () => {
        const m = members[0]!;
        const a = m.account.address;
        const dayIndex = Number(await read<bigint>(launcher, launcherAbi, "currentDay")) - 1;
        const day = new Date(dayIndex * 86_400_000).toISOString().slice(0, 10);
        if (await read<boolean>(launcher, launcherAbi, "checkedInOn", [a, BigInt(dayIndex)])) {
          return { label: m.label, address: a, day, dayIndex, tx: null };
        }
        const inner = keccak256(
          encodeAbiParameters(
            [{ type: "uint256" }, { type: "address" }, { type: "address" }, { type: "uint256" }],
            [97n, launcher, a, BigInt(dayIndex)],
          ),
        );
        const signature = await privateKeyToAccount(asKey(attesterKey!)).signMessage({ message: { raw: inner } });
        log(`  ${m.label}'s check-in for ${day} (yesterday) is signed by this script with the attester key, not by the server`);
        const receipt = await send("checkin-yesterday", `${m.label} checks in for yesterday (CheckInLauncher.checkIn, day ${dayIndex})`, m.account, {
          to: launcher,
          data: encodeFunctionData({ abi: launcherAbi, functionName: "checkIn", args: [BigInt(dayIndex), signature] }),
          gas: GAS.checkIn,
        });
        return { label: m.label, address: a, day, dayIndex, signedBy: "this script, with the attester key (not through the server)", tx: receipt.transactionHash };
      });
      await apiCheck("checked-in-yesterday", launcher);
    }

    await step(`checkin-${today}`, async () => {
      const out: any[] = [];
      for (const m of members) {
        const shows = m.showsUp === "every day" || (m.showsUp === "first day only" && today === firstDay);
        if (!shows) continue;
        if (Number(await read<bigint>(launcher, launcherAbi, "totalCheckIns")) >= goal) break; // the bar is full
        const a = m.account.address;
        const steps = Math.max(m.steps, Number(pointed.minSteps));
        const signature = await m.account.signMessage({ message: `${PRODUCT_NAME} checkin ${launcher.toLowerCase()} ${today} ${steps}` });
        const body = { address: a, steps, source: "self", signature };
        let r = await post("/checkin", body);
        // Membership is read through the verifier's own RPC, which can be a block behind ours.
        for (let tries = 0; (r.status === 403 || r.json?.error === "chain_unavailable") && tries < 10; tries++) {
          await sleep(2000);
          r = await post("/checkin", body);
        }
        if (r.status === 409 && r.json?.error === "already_checked_in") {
          log(`  ${m.label} is already checked in for ${today}`);
          out.push({ label: m.label, address: a, day: today, steps, tx: null });
          continue;
        }
        if (r.status !== 200) throw new Error(`POST /checkin for ${m.label}: ${r.status} ${JSON.stringify(r.json)}`);
        log(`  ${m.label} reported ${steps} steps for ${r.json.day} (self-reported test value made by this script); the server signed`);
        const receipt = await send(`checkin-${today}`, `${m.label} checks in (CheckInLauncher.checkIn, day ${r.json.dayIndex})`, m.account, {
          to: launcher,
          data: encodeFunctionData({ abi: launcherAbi, functionName: "checkIn", args: [BigInt(r.json.dayIndex), r.json.attesterSignature] }),
          gas: GAS.checkIn,
        });
        out.push({ label: m.label, address: a, day: r.json.day, dayIndex: r.json.dayIndex, steps, source: "self", tx: receipt.transactionHash });

        // Once, while the bar is still short: launch() is refused for everyone. Nothing is sent.
        const total = Number(await read<bigint>(launcher, launcherAbi, "totalCheckIns"));
        if (total < goal && !("launch-refused" in state.done)) {
          const refusal = await wouldRevert(a, launcher, launcherAbi, "launch");
          if (refusal === null) throw new Error("launch() would go through before the bar is full");
          log(`  bar at ${total} of ${goal}: launch() would revert with ${refusal}. Nothing was sent.`);
          state.done["launch-refused"] = { totalCheckIns: total, checkInGoal: goal, error: refusal };
          save();
        }
      }
      return out;
    });

    await apiCheck(`checked-in-${today}`, launcher);
    const total = Number(await read<bigint>(launcher, launcherAbi, "totalCheckIns"));
    launched = await read<boolean>(launcher, launcherAbi, "launched");
    if (!launched && total < goal) {
      const nextDay = new Date((Math.floor(nowSec() / 86_400) + 1) * 86_400_000).toISOString();
      log(`The bar is at ${total} of ${goal} check-ins. One wallet can check in once per UTC day.`);
      log(`Run this script again after ${nextDay} and before the deadline ${new Date(deadline * 1000).toISOString()},`);
      log(`or let people fill the bar and launch in the app, then run it again for the trading and the claims.`);
      return;
    }
  }

  // ── 6. Launch: sent by a member, not by the server ────────────────────────
  await step("launch", async () => {
    if (await read<boolean>(launcher, launcherAbi, "launched")) {
      log("  the round is already launched (somebody else sent launch())");
      return { tx: null, by: null };
    }
    const by = members[0]!;
    // Dry run, so a launch the Portal would refuse (a pool under its floor) is seen here and not as
    // a reverted transaction.
    const refusal = await wouldRevert(by.account.address, launcher, launcherAbi, "launch");
    if (refusal !== null) {
      const poolNow = await read<bigint>(launcher, launcherAbi, "poolQuoteNow");
      throw new Error(`launch() would revert (${refusal}). The pool would get ${formatEther(poolNow)} test USD; Flap's floor is about ${formatEther(poolFloor)}.`);
    }
    const receipt = await send("launch", `${by.label} sends CheckInLauncher.launch (the Flap launch)`, by.account, {
      to: launcher,
      data: encodeFunctionData({ abi: launcherAbi, functionName: "launch" }),
      gas: GAS.launch,
    });
    let poolQuote = 0n;
    let prizeQuote = 0n;
    for (const l of receipt.logs) {
      if (l.address.toLowerCase() !== launcher.toLowerCase()) continue;
      try {
        const ev = decodeEventLog({ abi: launcherAbi, data: l.data, topics: l.topics });
        if (ev.eventName === "Launched") {
          poolQuote = (ev.args as any).poolQuote;
          prizeQuote = (ev.args as any).prizeQuote;
        }
      } catch {}
    }
    return {
      tx: receipt.transactionHash,
      by: by.account.address,
      gasUsed: receipt.gasUsed.toString(),
      poolUsd: formatEther(poolQuote),
      prizeUsd: formatEther(prizeQuote),
    };
  });
  const [token, pool, vault] = (await Promise.all([
    read<Hex>(launcher, launcherAbi, "token"),
    read<Hex>(launcher, launcherAbi, "pool"),
    read<Hex>(launcher, launcherAbi, "vault"),
  ])) as [Hex, Hex, Hex];
  log(`Token: ${token}  Pool: ${pool}  Vault: ${vault}`);
  await step("addresses", async () => ({ token, pool, vault }));
  await apiCheck("launched", launcher);

  async function claim(stepName: string, m: (typeof members)[number]) {
    const receipt = await send(stepName, `${m.label} claims (StreakVault.claim)`, m.account, {
      to: vault,
      data: encodeFunctionData({ abi: vaultAbi, functionName: "claim" }),
      gas: GAS.claim,
    });
    let tokens = 0n;
    let quote = 0n;
    for (const l of receipt.logs) {
      if (l.address.toLowerCase() !== vault.toLowerCase()) continue;
      try {
        const ev = decodeEventLog({ abi: vaultAbi, data: l.data, topics: l.topics });
        if (ev.eventName === "Claimed") {
          tokens = (ev.args as any).tokenAmount;
          quote = (ev.args as any).quoteAmount;
        }
      } catch {}
    }
    return { label: m.label, address: m.account.address, tx: receipt.transactionHash, tokens: formatEther(tokens), usd: formatEther(quote) };
  }

  // ── 7. A claim straight after the launch: no settle step, no list ─────────
  await step("claim-early", async () => {
    const m = members[0]!;
    const [tokens, quote] = await read<[bigint, bigint]>(vault, vaultAbi, "claimable", [m.account.address]);
    if (tokens === 0n && quote === 0n) return null;
    return claim("claim-early", m);
  });

  await apiCheck("claimed-early", launcher);

  // ── 8. Trading on the pool; the tax reaches the vault ─────────────────────
  await step("trade", async () => {
    const trader = deployer;
    const processor = await read<Hex>(token, erc20Abi, "taxProcessor");
    const swap = (from: Hex, to: Hex, amountIn: bigint, what: string) =>
      send("trade", what, trader, {
        to: V2_ROUTER,
        data: encodeFunctionData({
          abi: routerAbi,
          functionName: "swapExactTokensForTokensSupportingFeeOnTransferTokens",
          args: [amountIn, 0n, [from, to], trader.address, BigInt(nowSec() + 600)],
        }),
        gas: GAS.swap,
      });
    // The token sells its collected tax into test USD during a sell; the test USD then waits in the
    // tax processor until somebody calls dispatch(), which anyone may do.
    const liquidated = async () =>
      (await read<bigint>(processor, processorAbi, "feeQuoteBalance")) > 0n ||
      (await read<bigint>(processor, processorAbi, "marketQuoteBalance")) > 0n;
    // Everything the vault has received above the prize is trading tax. After the launch
    // prizeQuoteNow() is the prize that was sent to the vault in the launch transaction.
    const prize = await read<bigint>(launcher, launcherAbi, "prizeQuoteNow");
    const taxAtVault = async () => (await read<bigint>(vault, vaultAbi, "quoteReceived")) - prize;
    // On testnet another account (not ours) has been seen calling dispatch() within a few blocks of
    // a sale, so the tax can be at the vault before this script looks at the processor. Either state
    // ends the trading. This also makes the step safe to run again after it was stopped half way.
    const arrived = async () => (await taxAtVault()) > 0n || (await liquidated());

    if (!(await arrived())) {
      await send("trade", "mint 1000 test USD to the trader", trader, {
        to: USD,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "mint", args: [trader.address, usd(1000)] }),
        gas: GAS.mint,
      });
      await send("trade", "trader approves the router for test USD", trader, {
        to: USD,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [V2_ROUTER, maxUint256] }),
        gas: GAS.approve,
      });
      await send("trade", "trader approves the router for the token", trader, {
        to: token,
        data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [V2_ROUTER, maxUint256] }),
        gas: GAS.approve,
      });
      await swap(USD, token, usd(1000), "buy the token with 1000 test USD (3% tax)");
      for (let i = 0; i < 8 && !(await arrived()); i++) {
        await swap(token, USD, ((await bal(token, trader.address)) * 30n) / 100n, `sell 30% of the tokens (5% tax), round ${i + 1}`);
        const have = await bal(USD, trader.address);
        await swap(USD, token, have < usd(400) ? have : usd(400), `buy again with test USD (3% tax), round ${i + 1}`);
      }
      if (!(await arrived())) throw new Error("the token's tax was not sold into test USD within 8 rounds");
    } else {
      log("  trading tax has already reached the vault or waits in the tax processor; no more swaps are sent");
    }
    // Sell and buy rounds sent by this script, counted from its own record (a continued run included).
    const rounds = state.txs.filter((t) => t.step === "trade" && t.what.startsWith("sell")).length;

    let dispatchTx: string | null = null;
    if (await liquidated()) {
      try {
        const receipt = await send("trade", "TaxProcessor.dispatch (the vault's share of the tax is paid out)", trader, {
          to: processor,
          data: encodeFunctionData({ abi: processorAbi, functionName: "dispatch" }),
          gas: GAS.dispatch,
        });
        dispatchTx = receipt.transactionHash;
      } catch (e) {
        // Somebody else may have dispatched in the same moment; then there is nothing left to do.
        if ((await liquidated()) || (await taxAtVault()) === 0n) throw e;
        const last = state.txs[state.txs.length - 1];
        if (last && last.what.startsWith("TaxProcessor.dispatch")) last.what += " (reverted: another account had just dispatched)";
        save();
      }
    }
    const tax = await taxAtVault();
    if (tax === 0n) throw new Error("no trading tax reached the vault");
    const received = await read<bigint>(vault, vaultAbi, "quoteReceived");
    const dispatchedBy = dispatchTx ? "this script" : "another account (dispatch() is open to anyone; this script did not need to call it)";
    log(`  the vault has received ${formatEther(received)} test USD so far: the ${formatEther(prize)} prize and ${formatEther(tax)} of trading tax`);
    log(`  dispatch() was called by ${dispatchedBy}`);
    return { processor, rounds, prizeUsd: formatEther(prize), taxToVaultUsd: formatEther(tax), vaultReceivedUsd: formatEther(received), dispatchTx, dispatchedBy };
  });
  await apiCheck("traded", launcher);

  // ── 9. Everyone with days claims; the member with none cannot ─────────────
  const claims = await step("claims", async () => {
    const out: any[] = [];
    for (const m of members) {
      const a = m.account.address;
      const days = Number(await read<bigint>(vault, vaultAbi, "daysOf", [a]));
      if (days > 0) {
        const [tokens, quote] = await read<[bigint, bigint]>(vault, vaultAbi, "claimable", [a]);
        if (tokens === 0n && quote === 0n) {
          out.push({ label: m.label, address: a, days, tx: null, note: "nothing left to claim" });
          continue;
        }
        out.push({ ...(await claim("claims", m)), days });
      } else {
        // Not sent: a dry run shows the vault would refuse.
        const refusal = await wouldRevert(a, vault, vaultAbi, "claim");
        if (refusal === null) throw new Error(`${m.label} has no days but a claim would go through`);
        log(`  ${m.label} never checked in; a claim would revert with ${refusal}`);
        out.push({ label: m.label, address: a, days: 0, tx: null, refusal });
      }
    }
    return out;
  });

  await apiCheck("claimed", launcher);

  // ── 10. Read everything back ───────────────────────────────────────────────
  const totalCheckIns = Number(await read<bigint>(vault, vaultAbi, "totalCheckIns"));
  const onChain = {
    launched: await read<boolean>(launcher, launcherAbi, "launched"),
    checkInGoal: goal,
    totalCheckIns,
    memberCount: Number(await read<bigint>(launcher, launcherAbi, "memberCount")),
    totalDepositsUsd: formatEther(await read<bigint>(launcher, launcherAbi, "totalDeposits")),
    totalSponsoredUsd: formatEther(await read<bigint>(launcher, launcherAbi, "totalSponsored")),
    launcherUsdLeft: formatEther(await bal(USD, launcher)),
    vault: {
      reservedTokens: formatEther(await read<bigint>(vault, vaultAbi, "reservedTokens")),
      quoteReceivedUsd: formatEther(await read<bigint>(vault, vaultAbi, "quoteReceived")),
      totalQuotePaidUsd: formatEther(await read<bigint>(vault, vaultAbi, "totalQuotePaid")),
      totalTokensPaid: formatEther(await read<bigint>(vault, vaultAbi, "totalTokensPaid")),
    },
    members: await Promise.all(
      members.map(async (m) => ({
        label: m.label,
        address: m.account.address,
        days: Number(await read<bigint>(vault, vaultAbi, "daysOf", [m.account.address])),
        claimedTokens: formatEther(await read<bigint>(vault, vaultAbi, "claimedTokens", [m.account.address])),
        claimedUsd: formatEther(await read<bigint>(vault, vaultAbi, "claimedQuote", [m.account.address])),
        tokenBalance: formatEther(await bal(token, m.account.address)),
        testUsdBalance: formatEther(await bal(USD, m.account.address)),
      })),
    ),
  };
  const apiRound = await get("/round");
  const apiMembers = await get("/members");
  const apiMe = await Promise.all(members.map(async (m) => (await get(`/me/${m.account.address.toLowerCase()}`)).json));

  const result = {
    note: "Step counts were self-reported test values made by scripts/run-round.ts, not real activity. Check-ins are attested by our server, not proven. Everything on chain is real (BSC testnet, chain 97).",
    api,
    explorer: EXPLORER,
    round: { name: roundName, symbol: roundSymbol, depositUsd, liquidityBps, checkInGoal: goal, minSteps: pointed.minSteps },
    times: { opened: state.startedAt, deadline },
    addresses: {
      checkInLauncherFactory: FACTORY,
      streakVaultFactory: deployments.streakVaultFactory,
      portal: PORTAL,
      launcher,
      token,
      pool,
      vault,
      usd: USD,
      router: V2_ROUTER,
      deployer: deployer.address,
      attester: opened.attester,
    },
    steps: state.done,
    claims,
    onChain,
    verifier: { round: apiRound.json, members: apiMembers.json, me: apiMe },
    transactions: state.txs.map((t) => ({ ...t, url: `${EXPLORER}/tx/${t.hash}` })),
  };
  // <name>-run.json gives <name>-result.json, so two rounds kept side by side do not share a file.
  const resultFile = /-run\.json$/.test(stateFile) ? stateFile.replace(/-run\.json$/, "-result.json") : `${stateFile}.result.json`;
  writeFileSync(resultFile, JSON.stringify(result, null, 2) + "\n");
  log(`Done. Result written to ${resultFile}`);
  console.log(JSON.stringify({ onChain, verifierRound: apiRound.json }, null, 2));
  if (apiRound.status !== 200 || apiRound.json.launched !== true) throw new Error("GET /round does not show the round as launched");
}

main().catch((e) => {
  // Only the message: an error object from a wallet client can carry the request it was built from.
  console.error(`FAILED: ${e?.shortMessage ?? e?.message ?? e}`);
  process.exit(1);
});
