// ARCHIVE. This is the script that ran the earlier product's club season (PROOF.md), kept as the
// record of how that run was made. It targets the old ClubLauncher / GoalVault contracts and the old
// server routes, which the current server no longer has, so it cannot be run against today's
// deployment. The current script is scripts/run-round.ts.
//
// One real, complete club season on BSC testnet (chain 97), against the deployed factories and a
// running verifier. Test assets only.
//
//   cd verifier && VERIFIER_URL=https://<host>/api npx tsx ../scripts/run-season.ts
//
// Run it from the verifier folder: viem is taken from verifier/node_modules.
//
// What it does, in order (the same steps as DEMO.md and contracts/test/ClubSeason.fork.t.sol):
//    1. The captain (the deployer wallet) opens a season with Portal.newLauncher and our
//       ClubLauncherFactory. The launch salt is mined so the club token address ends in 0x7777.
//    2. The season is registered with the verifier.
//    3. Three throwaway member wallets get a little test BNB and minted test USD, approve the
//       launcher and join on chain (contribute). Each registers a personal goal with the verifier.
//    4. Signed activity is posted. The verifier is first asked to start the season while the club is
//       short of its warm-up distance (it refuses), then again once the distance is reached.
//    5. The verifier sends ClubLauncher.kickoff(): the Flap launch (token, pool, GoalVault).
//    6. The captain wallet buys and sells the club token on PancakeSwap with test USD until the tax
//       has been sold into test USD, then calls dispatch() so the vault receives its share.
//    7. After the season end the verifier sends GoalVault.settle(root, count).
//    8. The two members who reached their goal claim. The third is checked: a claim would revert.
//    9. GET /seasons/past is read back and everything is written to a result file.
//
// IMPORTANT, said plainly: the distances in step 4 are made up by this script. They are signed by
// the member wallets and sent the way the app sends a health sync, but nobody ran them. The
// verifier (our server) judges runs; here it is judging test reports. Everything on chain is real.
//
// Keys: the deployer key is read from contracts/.env (PRIVATE_KEY) and the admin token from
// verifier/.env (ADMIN_TOKEN). They stay in memory and are never printed or written anywhere. The
// member keys are derived in memory from the deployer key and the run id, so a stopped run can be
// continued without any key on disk.
//
// Continuing a stopped run: the script saves each finished step (addresses and transaction hashes
// only) to STATE_FILE and skips those steps the next time. Delete the file to start a new season.
//
// Every transaction is a legacy transaction at 1 gwei with an explicit gas limit: fee estimation on
// this testnet can return 1 wei, and such transactions are never mined.
//
// Settings (environment variables, all optional except VERIFIER_URL):
//   VERIFIER_URL         base of the verifier API, e.g. https://<host>/api          (required)
//   RPC_URL              BSC testnet RPC            default: verifier/.env RPC_URL or publicnode
//   STATE_FILE           progress file              default: scripts/season-run.json
//   SEASON_NAME          default "Bangkok Demo Run"
//   SEASON_SYMBOL        default "BKKRUN"
//   RAISE_MINUTES        last moment to start the season, minutes from now      default 20
//   SEASON_END_MINUTES   season end, minutes from now (after RAISE_MINUTES)     default 23
//   WARMUP_KM            club warm-up distance in km                            default 12
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";

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

// ── Fixed addresses on BSC testnet ───────────────────────────────────────────
const PORTAL: Hex = "0x000042108465206185A077Edc3F3fd2b49060000";
const TOKEN_IMPL: Hex = "0x7777c57ff7dc441c1715b2e36fa581c48B782222";
const V2_ROUTER: Hex = "0xc9D63ddCB9549578057EAB6A83a543DdFEE2b8c3"; // PancakeSwap V2 router the Portal uses
const USD: Hex = "0x190C989D5665a0e404B444b53CAE9AbCfb600157"; // Flap's test USD: anyone can mint
const EXPLORER = "https://testnet.bscscan.com";

const GAS_PRICE = 1_000_000_000n; // 1 gwei, legacy
const GAS = {
  transfer: 21_000n,
  mint: 120_000n,
  approve: 120_000n,
  newLauncher: 3_000_000n,
  contribute: 400_000n,
  swap: 2_500_000n,
  dispatch: 2_500_000n,
  claim: 600_000n,
};

const JOIN_FEE = parseEther("500");
const TARGET_RAISE = parseEther("1500"); // three places; also the Portal's floor for a pool on testnet
const MEMBER_GAS_MONEY = parseEther("0.004");

// Goals and (made-up) distances in km. Ana and Ben reach their goal, Chai does not.
const MEMBERS = [
  { label: "Ana", goal: 5, distance: 6.2 },
  { label: "Ben", goal: 5, distance: 5.4 },
  { label: "Chai", goal: 10, distance: 3.1 },
] as const;

const portalAbi = parseAbi([
  "function SALT_LOCK_FEE() view returns (uint256)",
  "function featureFlags() view returns (uint256)",
  "function newLauncher(address launcherFactory, bytes data) payable returns (address)",
]);
const factoryAbi = parseAbi(["event ClubLauncherCreated(address indexed launcher, address indexed creator, bytes32 launchSalt)"]);
const launcherAbi = parseAbi([
  "function contribute()",
  "function kickoff()",
  "function filled() view returns (bool)",
  "function launched() view returns (bool)",
  "function isMember(address) view returns (bool)",
  "function memberCount() view returns (uint256)",
  "function raised() view returns (uint256)",
  "function deadline() view returns (uint256)",
  "function seasonEnd() view returns (uint256)",
  "function kickoffTarget() view returns (uint256)",
  "function verifier() view returns (address)",
  "function token() view returns (address)",
  "function pool() view returns (address)",
  "function vault() view returns (address)",
]);
const erc20Abi = parseAbi([
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount) returns (bool)",
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
  "function claim(bytes32[] proof)",
  "function settled() view returns (bool)",
  "function finishersRoot() view returns (bytes32)",
  "function finisherCount() view returns (uint256)",
  "function memberCount() view returns (uint256)",
  "function reservedTokens() view returns (uint256)",
  "function taxReceived() view returns (uint256)",
  "function claimed(address) view returns (bool)",
  "function seasonEnd() view returns (uint256)",
  "event Claimed(address indexed member, uint256 tokenAmount, uint256 quoteAmount)",
  "error NotSettled()",
  "error NotFinisher()",
  "error NothingToClaim()",
]);

// ── Small helpers ────────────────────────────────────────────────────────────
const root = resolve(process.cwd(), "..");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const log = (msg: string) => console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`);
const nowSec = () => Math.floor(Date.now() / 1000);

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

interface TxRecord {
  step: string;
  what: string;
  hash: string;
  from: string;
}
interface State {
  runId: string;
  startedAt: number;
  raiseDeadline: number;
  seasonEnd: number;
  done: Record<string, unknown>;
  txs: TxRecord[];
}

async function main() {
  const verifierEnv = envFile(join(root, "verifier/.env"));
  const contractsEnv = envFile(join(root, "contracts/.env"));
  const deployments = JSON.parse(readFileSync(join(root, "contracts/deployments/bsc-testnet.club-season.json"), "utf8"));
  const FACTORY = getAddress(deployments.clubLauncherFactory);

  const api = (process.env.VERIFIER_URL || "").replace(/\/$/, "");
  if (!api) throw new Error("Set VERIFIER_URL to the verifier API, e.g. https://<host>/api");
  const adminToken = process.env.ADMIN_TOKEN || verifierEnv.ADMIN_TOKEN;
  if (!adminToken) throw new Error("ADMIN_TOKEN not found in verifier/.env");
  const deployerKey = (process.env.PRIVATE_KEY || contractsEnv.PRIVATE_KEY) as Hex | undefined;
  if (!deployerKey) throw new Error("PRIVATE_KEY not found in contracts/.env");
  const rpcUrl = process.env.RPC_URL || verifierEnv.RPC_URL || "https://bsc-testnet-rpc.publicnode.com";

  const stateFile = process.env.STATE_FILE || join(root, "scripts/season-run.json");
  const raiseMinutes = Number(process.env.RAISE_MINUTES || 20);
  const endMinutes = Number(process.env.SEASON_END_MINUTES || 23);
  if (!(endMinutes > raiseMinutes)) throw new Error("SEASON_END_MINUTES must be after RAISE_MINUTES");
  const seasonName = process.env.SEASON_NAME || "Bangkok Demo Run";
  const seasonSymbol = process.env.SEASON_SYMBOL || "BKKRUN";
  const warmupKm = Number(process.env.WARMUP_KM || 12);

  let state: State;
  if (existsSync(stateFile)) {
    state = JSON.parse(readFileSync(stateFile, "utf8"));
    log(`Continuing run ${state.runId} from ${stateFile}`);
  } else {
    const t = nowSec();
    state = { runId: `${t}`, startedAt: t, raiseDeadline: t + raiseMinutes * 60, seasonEnd: t + endMinutes * 60, done: {}, txs: [] };
  }
  const save = () => writeFileSync(stateFile, JSON.stringify(state, null, 2) + "\n");

  const transport = http(rpcUrl, { retryCount: 5, retryDelay: 800 });
  const client = createPublicClient({ chain: bscTestnet, transport });
  if ((await client.getChainId()) !== 97) throw new Error("RPC is not BSC testnet (chain 97)");

  const captain = privateKeyToAccount(deployerKey);
  // Throwaway member keys, derived in memory. Nothing of them is written to disk.
  const members = MEMBERS.map((m, i) => ({
    ...m,
    account: privateKeyToAccount(keccak256(concat([deployerKey, toHex(`pacepact-season-${state.runId}-member-${i}`)]))),
  }));

  // One nonce counter per sender: a load-balanced public RPC can lag behind our own last send.
  const nonces = new Map<string, number>();
  async function send(
    step: string,
    what: string,
    account: ReturnType<typeof privateKeyToAccount>,
    tx: { to: Hex; data?: Hex; value?: bigint; gas: bigint },
  ) {
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
      body: body === undefined ? undefined : JSON.stringify(body),
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
  const get = async (path: string) => (await fetch(`${api}${path}`)).json() as Promise<any>;

  const read = <T>(address: Hex, abi: any, functionName: string, args: unknown[] = []) =>
    client.readContract({ address, abi, functionName, args } as any) as Promise<T>;

  /** Waits until the chain's own clock has passed `time`, printing progress. */
  async function waitForChainTime(time: number, why: string) {
    for (;;) {
      const block = await client.getBlock();
      const left = time - Number(block.timestamp);
      if (left < 0) return;
      log(`  waiting for ${why}: ${left + 1}s to go`);
      await sleep(Math.min(30_000, (left + 1) * 1000));
    }
  }

  // ── 0. Checks before anything is sent ──────────────────────────────────────
  const health = await get("/");
  if (!health?.ok) throw new Error(`verifier at ${api} did not answer ok`);
  const [captainBnb, saltFee, flags] = await Promise.all([
    client.getBalance({ address: captain.address }),
    read<bigint>(PORTAL, portalAbi, "SALT_LOCK_FEE"),
    read<bigint>(PORTAL, portalAbi, "featureFlags"),
  ]);
  if ((flags & 1n) !== 0n) throw new Error("the testnet Portal has creation paused");
  if (captainBnb < parseEther("0.05")) throw new Error(`captain ${captain.address} needs at least 0.05 test BNB`);
  log(`Verifier ${api} is up. Captain ${captain.address} holds ${formatEther(captainBnb)} test BNB.`);
  log(`Members: ${members.map((m) => `${m.label} ${m.account.address}`).join(", ")}`);
  log(`Last moment to start: ${new Date(state.raiseDeadline * 1000).toISOString()}  Season end: ${new Date(state.seasonEnd * 1000).toISOString()}`);

  // ── 1. The captain opens the season ───────────────────────────────────────
  const opened = await step("open", async () => {
    // The Portal deploys the token as a CREATE2 minimal proxy of TOKEN_IMPL; its address must end in
    // 0x7777. Same search as the app (app/lib/services/chain_service.dart): the counter overwrites
    // the last four bytes of a random 32-byte seed.
    const initCodeHash = keccak256(
      concat(["0x3d602d80600a3d3981f3363d3d373d3d3d363d73", TOKEN_IMPL, "0x5af43d82803e903d91602b57fd5bf3"]),
    );
    const input = Buffer.concat([
      Buffer.from("ff", "hex"),
      Buffer.from(PORTAL.slice(2), "hex"),
      Buffer.from(keccak256(toHex(`seed-${state.runId}-${Math.random()}`)).slice(2), "hex"),
      Buffer.from(initCodeHash.slice(2), "hex"),
    ]);
    let salt: Hex | null = null;
    for (let i = 0; i < 0xffffffff; i++) {
      input.writeUInt32BE(i, 49);
      const hash = keccak256(input, "bytes");
      if (hash[30] === 0x77 && hash[31] === 0x77) {
        salt = `0x${input.subarray(21, 53).toString("hex")}`;
        log(`  salt found after ${i + 1} tries; the club token will be 0x${Buffer.from(hash.subarray(12)).toString("hex")}`);
        break;
      }
    }
    if (!salt) throw new Error("no salt found");

    const verifierAddress = getAddress(process.env.VERIFIER_ADDRESS || "0x2F2ab3dA0b824F9cA3EdD2580443Ca0b271EfDD7");
    const config = encodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            { name: "name", type: "string" },
            { name: "symbol", type: "string" },
            { name: "meta", type: "string" },
            { name: "salt", type: "bytes32" },
            { name: "targetRaise", type: "uint256" },
            { name: "joinFee", type: "uint256" },
            { name: "raiseDeadline", type: "uint256" },
            { name: "seasonEnd", type: "uint256" },
            { name: "verifier", type: "address" },
            { name: "kickoffTarget", type: "uint256" },
          ],
        },
      ],
      [
        {
          name: seasonName,
          symbol: seasonSymbol,
          meta: "",
          salt,
          targetRaise: TARGET_RAISE,
          joinFee: JOIN_FEE,
          raiseDeadline: BigInt(state.raiseDeadline),
          seasonEnd: BigInt(state.seasonEnd),
          verifier: verifierAddress,
          kickoffTarget: BigInt(Math.round(warmupKm * 1000)), // goal unit x 1000 on chain
        },
      ],
    );
    const data = encodeFunctionData({ abi: portalAbi, functionName: "newLauncher", args: [FACTORY, config] });
    // Dry run first, so a refused config costs nothing.
    await client.call({ account: captain.address, to: PORTAL, data, value: saltFee, gas: GAS.newLauncher });
    const receipt = await send("open", "Portal.newLauncher (captain opens the season)", captain, {
      to: PORTAL,
      data,
      value: saltFee,
      gas: GAS.newLauncher,
    });
    for (const l of receipt.logs) {
      if (l.address.toLowerCase() !== FACTORY.toLowerCase()) continue;
      try {
        const ev = decodeEventLog({ abi: factoryAbi, data: l.data, topics: l.topics });
        return { launcher: getAddress((ev.args as any).launcher), salt, verifier: verifierAddress, tx: receipt.transactionHash };
      } catch {}
    }
    throw new Error("ClubLauncherCreated not found in the receipt");
  });
  const launcher = opened.launcher as Hex;
  log(`Launcher: ${launcher}`);

  // ── 2. Register the season with the verifier ──────────────────────────────
  await step("register", async () => {
    const r = await post("/seasons", {
      launcher,
      name: seasonName,
      goalUnit: "km",
      seasonEnd: state.seasonEnd,
      kickoffTarget: warmupKm,
    });
    if (r.status !== 201 && r.status !== 200) throw new Error(`register season: ${r.status} ${JSON.stringify(r.json)}`);
    return r.json;
  });

  // ── 3. Three members are funded, join on chain and set a goal ─────────────
  for (const [i, m] of members.entries()) {
    await step(`join-${i}`, async () => {
      const a = m.account.address;
      if ((await client.getBalance({ address: a })) < MEMBER_GAS_MONEY / 2n) {
        await send(`join-${i}`, `test BNB for gas to ${m.label}`, captain, { to: a, value: MEMBER_GAS_MONEY, gas: GAS.transfer });
      }
      if ((await read<bigint>(USD, erc20Abi, "balanceOf", [a])) < JOIN_FEE && !(await read<boolean>(launcher, launcherAbi, "isMember", [a]))) {
        await send(`join-${i}`, `mint 500 test USD to ${m.label}`, captain, {
          to: USD,
          data: encodeFunctionData({ abi: erc20Abi, functionName: "mint", args: [a, JOIN_FEE] }),
          gas: GAS.mint,
        });
      }
      let joinTx: string | null = null;
      if (!(await read<boolean>(launcher, launcherAbi, "isMember", [a]))) {
        await send(`join-${i}`, `${m.label} approves the launcher for 500 test USD`, m.account, {
          to: USD,
          data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [launcher, JOIN_FEE] }),
          gas: GAS.approve,
        });
        const receipt = await send(`join-${i}`, `${m.label} joins (ClubLauncher.contribute)`, m.account, {
          to: launcher,
          data: encodeFunctionData({ abi: launcherAbi, functionName: "contribute" }),
          gas: GAS.contribute,
        });
        joinTx = receipt.transactionHash;
      }
      // The goal is registered with the verifier, signed by the member, as the app does it.
      const signature = await m.account.signMessage({ message: `Pacepact join ${launcher.toLowerCase()} ${m.goal}` });
      let r = await post(`/seasons/${launcher}/members`, { address: a, goalValue: m.goal, signature });
      // The verifier reads membership from its own RPC, which can be a block behind ours.
      for (let tries = 0; r.status === 403 && tries < 10; tries++) {
        await sleep(2000);
        r = await post(`/seasons/${launcher}/members`, { address: a, goalValue: m.goal, signature });
      }
      if (r.status !== 201 && r.json?.error !== "already_registered") {
        throw new Error(`register ${m.label}: ${r.status} ${JSON.stringify(r.json)}`);
      }
      return { address: a, goalKm: m.goal, joinTx };
    });
  }
  const filled = await read<boolean>(launcher, launcherAbi, "filled");
  const launchedBefore = await read<boolean>(launcher, launcherAbi, "launched");
  log(`Raise full: ${filled}. Token launched: ${launchedBefore}. (A full raise does not launch the token.)`);
  if (!filled) throw new Error("the raise is not full after three joins");

  // ── 4. Warm-up: activity, a refused kickoff, more activity ────────────────
  const day = new Date().toISOString().slice(0, 10); // today in UTC
  async function report(i: number) {
    const m = members[i]!;
    const value = m.distance;
    const signature = await m.account.signMessage({ message: `Pacepact activity ${launcher.toLowerCase()} ${day} ${value}` });
    const r = await post(`/seasons/${launcher}/activity`, {
      address: m.account.address,
      day,
      value,
      source: "healthkit",
      manualEntry: false,
      signature,
    });
    if (r.status !== 200) throw new Error(`activity ${m.label}: ${r.status} ${JSON.stringify(r.json)}`);
    log(`  ${m.label} reported ${value} km for ${day} (test report made by this script)`);
    return { address: m.account.address, day, km: value };
  }

  if (!launchedBefore) {
    await step("activity-first", async () => [await report(0), await report(2)]);
    await step("kickoff-refused", async () => {
      const r = await post(`/seasons/${launcher}/kickoff`, undefined, true);
      if (r.status !== 409 || r.json?.error !== "club_total_short") {
        throw new Error(`expected the verifier to refuse (club_total_short), got ${r.status} ${JSON.stringify(r.json)}`);
      }
      log(`  verifier refused to start: ${r.json.clubTotal} of ${r.json.kickoffTarget} km. Nothing was sent.`);
      return { status: r.status, error: r.json.error, clubTotal: r.json.clubTotal, kickoffTarget: r.json.kickoffTarget };
    });
    await step("activity-second", async () => [await report(1)]);
  }

  // ── 5. Kickoff: the verifier starts the Flap launch ───────────────────────
  const kickoff = await step("kickoff", async () => {
    // Dry run of kickoff() from the verifier's address, so a launch the Portal would refuse is seen
    // here and not as a reverted transaction from the server.
    await client.call({
      account: opened.verifier as Hex,
      to: launcher,
      data: encodeFunctionData({ abi: launcherAbi, functionName: "kickoff" }),
      gas: 7_000_000n,
    });
    const check = await post(`/seasons/${launcher}/kickoff?dryRun=true`, undefined, true);
    if (!check.json?.ready) throw new Error(`verifier is not ready to start: ${JSON.stringify(check.json)}`);
    const r = await post(`/seasons/${launcher}/kickoff`, undefined, true);
    if (r.status !== 200 || !r.json?.txHash) throw new Error(`kickoff: ${r.status} ${JSON.stringify(r.json)}`);
    const hash = r.json.txHash as Hex;
    state.txs.push({ step: "kickoff", what: "ClubLauncher.kickoff (sent by the verifier: the Flap launch)", hash, from: opened.verifier as string });
    save();
    const receipt = await client.waitForTransactionReceipt({ hash, timeout: 180_000, pollingInterval: 1_500 });
    if (receipt.status !== "success") throw new Error(`kickoff transaction ${hash} reverted`);
    log(`  kickoff: ${hash} (gas ${receipt.gasUsed})`);
    return { tx: hash, clubTotal: r.json.clubTotal, kickoffTarget: r.json.kickoffTarget, gasUsed: receipt.gasUsed.toString() };
  });
  void kickoff;
  const [token, pool, vault] = (await Promise.all([
    read<Hex>(launcher, launcherAbi, "token"),
    read<Hex>(launcher, launcherAbi, "pool"),
    read<Hex>(launcher, launcherAbi, "vault"),
  ])) as [Hex, Hex, Hex];
  log(`Token: ${token}  Pool: ${pool}  Vault: ${vault}`);
  await step("addresses", async () => ({ token, pool, vault }));

  // ── 6. Trading on the pool; the tax reaches the vault ─────────────────────
  await step("trade", async () => {
    const trader = captain;
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
    const bal = (t: Hex, a: Hex) => read<bigint>(t, erc20Abi, "balanceOf", [a]);
    const liquidated = async () =>
      (await read<bigint>(processor, processorAbi, "feeQuoteBalance")) > 0n ||
      (await read<bigint>(processor, processorAbi, "marketQuoteBalance")) > 0n;

    await send("trade", "mint 1000 test USD to the trader", trader, {
      to: USD,
      data: encodeFunctionData({ abi: erc20Abi, functionName: "mint", args: [trader.address, parseEther("1000")] }),
      gas: GAS.mint,
    });
    await send("trade", "trader approves the router for test USD", trader, {
      to: USD,
      data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [V2_ROUTER, maxUint256] }),
      gas: GAS.approve,
    });
    await send("trade", "trader approves the router for the club token", trader, {
      to: token,
      data: encodeFunctionData({ abi: erc20Abi, functionName: "approve", args: [V2_ROUTER, maxUint256] }),
      gas: GAS.approve,
    });
    await swap(USD, token, parseEther("1000"), "buy the club token with 1000 test USD (3% tax)");
    let rounds = 0;
    for (; rounds < 8 && !(await liquidated()); rounds++) {
      await swap(token, USD, ((await bal(token, trader.address)) * 30n) / 100n, `sell 30% of the club tokens (5% tax), round ${rounds + 1}`);
      const usd = await bal(USD, trader.address);
      await swap(USD, token, usd < parseEther("400") ? usd : parseEther("400"), `buy again with test USD (3% tax), round ${rounds + 1}`);
    }
    if (!(await liquidated())) throw new Error("the token's tax was not sold into test USD within 8 rounds");
    const receipt = await send("trade", "TaxProcessor.dispatch (the vault's share of the tax is paid out)", trader, {
      to: processor,
      data: encodeFunctionData({ abi: processorAbi, functionName: "dispatch" }),
      gas: GAS.dispatch,
    });
    const inVault = await bal(USD, vault);
    log(`  test USD in the vault after dispatch: ${formatEther(inVault)}`);
    if (inVault === 0n) throw new Error("dispatch ran but no test USD reached the vault");
    return { processor, rounds, vaultUsd: formatEther(inVault), dispatchTx: receipt.transactionHash };
  });

  // ── 7. Season end, then the verifier settles ──────────────────────────────
  const vaultEnd = Number(await read<bigint>(vault, vaultAbi, "seasonEnd"));
  const settled = await step("settle", async () => {
    await waitForChainTime(vaultEnd + 5, "the season end");
    let r = await post(`/seasons/${launcher}/settle`, undefined, true);
    for (let tries = 0; r.status === 409 && r.json?.error === "season_not_over" && tries < 10; tries++) {
      await sleep(5000);
      r = await post(`/seasons/${launcher}/settle`, undefined, true);
    }
    if (r.status !== 200) throw new Error(`settle: ${r.status} ${JSON.stringify(r.json)}`);
    const hash = r.json.txHash as Hex | null;
    if (hash) {
      state.txs.push({ step: "settle", what: "GoalVault.settle (sent by the verifier)", hash, from: opened.verifier as string });
      save();
      const receipt = await client.waitForTransactionReceipt({ hash, timeout: 180_000, pollingInterval: 1_500 });
      if (receipt.status !== "success") throw new Error(`settle transaction ${hash} reverted`);
      log(`  settle: ${hash}`);
    }
    if (!(await read<boolean>(vault, vaultAbi, "settled"))) throw new Error("the vault is not settled after the settle call");
    return { tx: hash, root: r.json.root, count: r.json.count };
  });
  log(`Settled with ${settled.count} finishers, root ${settled.root}`);

  // ── 8. Finishers claim; the member who missed cannot ──────────────────────
  const claims = await step("claims", async () => {
    const out: any[] = [];
    for (const m of members) {
      const a = m.account.address;
      const proof = await get(`/seasons/${launcher}/proof/${a}`);
      if (proof.finisher) {
        const receipt = await send("claims", `${m.label} claims (GoalVault.claim)`, m.account, {
          to: vault,
          data: encodeFunctionData({ abi: vaultAbi, functionName: "claim", args: [proof.proof] }),
          gas: GAS.claim,
        });
        let tokens = 0n;
        let usd = 0n;
        for (const l of receipt.logs) {
          if (l.address.toLowerCase() !== vault.toLowerCase()) continue;
          try {
            const ev = decodeEventLog({ abi: vaultAbi, data: l.data, topics: l.topics });
            if (ev.eventName === "Claimed") {
              tokens = (ev.args as any).tokenAmount;
              usd = (ev.args as any).quoteAmount;
            }
          } catch {}
        }
        out.push({ label: m.label, address: a, finisher: true, tx: receipt.transactionHash, tokens: formatEther(tokens), usd: formatEther(usd) });
      } else {
        // Not sent: a dry run shows the vault would refuse, with or without a proof.
        let refusal = "did not revert";
        try {
          await client.simulateContract({ account: a, address: vault, abi: vaultAbi, functionName: "claim", args: [[]] });
        } catch (e: any) {
          refusal = e?.cause?.data?.errorName ?? e?.shortMessage ?? "reverted";
        }
        if (refusal === "did not revert") throw new Error(`${m.label} missed the goal but a claim would go through`);
        log(`  ${m.label} missed the goal; a claim would revert with ${refusal}`);
        out.push({ label: m.label, address: a, finisher: false, tx: null, refusal });
      }
    }
    return out;
  });

  // ── 9. Read everything back ────────────────────────────────────────────────
  const onChain = {
    settled: await read<boolean>(vault, vaultAbi, "settled"),
    finisherCount: Number(await read<bigint>(vault, vaultAbi, "finisherCount")),
    memberCount: Number(await read<bigint>(vault, vaultAbi, "memberCount")),
    reservedTokens: formatEther(await read<bigint>(vault, vaultAbi, "reservedTokens")),
    taxReceived: formatEther(await read<bigint>(vault, vaultAbi, "taxReceived")),
    members: await Promise.all(
      members.map(async (m) => ({
        label: m.label,
        address: m.account.address,
        claimed: await read<boolean>(vault, vaultAbi, "claimed", [m.account.address]),
        clubTokens: formatEther(await read<bigint>(token, erc20Abi, "balanceOf", [m.account.address])),
        testUsd: formatEther(await read<bigint>(USD, erc20Abi, "balanceOf", [m.account.address])),
      })),
    ),
  };
  const past = await get("/seasons/past");
  const pastSeason = (past.seasons ?? []).find((s: any) => s.launcher === launcher.toLowerCase()) ?? null;

  const result = {
    note: "Distances were test reports made by scripts/run-season.ts, not real runs. Everything on chain is real (BSC testnet, chain 97).",
    api,
    explorer: EXPLORER,
    season: { name: seasonName, symbol: seasonSymbol, joinFeeUsd: 500, targetUsd: 1500, warmupKm, day },
    times: { opened: state.startedAt, raiseDeadline: state.raiseDeadline, seasonEnd: vaultEnd },
    addresses: { factory: FACTORY, portal: PORTAL, launcher, token, pool, vault, usd: USD, router: V2_ROUTER, captain: captain.address, verifier: opened.verifier },
    steps: state.done,
    claims,
    onChain,
    pastSeason,
    transactions: state.txs.map((t) => ({ ...t, url: `${EXPLORER}/tx/${t.hash}` })),
  };
  const resultFile = join(dirname(stateFile), "season-result.json");
  writeFileSync(resultFile, JSON.stringify(result, null, 2) + "\n");
  log(`Done. Result written to ${resultFile}`);
  console.log(JSON.stringify({ onChain, pastSeason }, null, 2));
  if (!pastSeason) throw new Error("the season is not in GET /seasons/past yet");
}

main().catch((e) => {
  // Only the message: an error object from a wallet client can carry the request it was built from.
  console.error(`FAILED: ${e?.shortMessage ?? e?.message ?? e}`);
  process.exit(1);
});
