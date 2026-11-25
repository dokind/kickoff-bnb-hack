// End-to-end check of this server against the real contracts, on a local fork of BSC testnet.
// Not part of `npm test`. It needs the contracts built (../contracts/out) and anvil running:
//
//   anvil --fork-url https://bsc-testnet-rpc.publicnode.com --chain-id 97 --port 8546
//   npm run e2e:fork                                # or FORK_RPC_URL=http://127.0.0.1:8546
//
// It deploys the two factories on the fork, opens a round through Flap's Portal, and then walks
// three members through join, check-in (POST /checkin, then the member's own checkIn transaction
// with the attester's signature), launch by a wallet with no role, and claim, reading the API
// after each step. Every key here is one of anvil's well-known test keys; nothing touches the real
// testnet and nothing is written outside this process.
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  createPublicClient,
  createTestClient,
  createWalletClient,
  decodeEventLog,
  encodeAbiParameters,
  getContractAddress,
  http,
  keccak256,
  concat,
  parseAbi,
  toHex,
  type Abi,
  type Hex,
} from "viem";
import { mnemonicToAccount } from "viem/accounts";
import { bscTestnet } from "viem/chains";
import { createApp } from "../src/app.js";
import { createAttester } from "../src/attest.js";
import { createChain } from "../src/chain.js";
import { checkInMessage } from "../src/product.js";
import { LocalStore } from "../src/store.js";

const RPC = process.env.FORK_RPC_URL || "http://127.0.0.1:8546";
const PORTAL = "0x000042108465206185A077Edc3F3fd2b49060000";
const GUARDIAN = "0x00004d58290854c5E9880F4b5B1993c6Ad8b0000";
const QUOTE = "0x190C989D5665a0e404B444b53CAE9AbCfb600157";
const TOKEN_INIT_CODE_HASH = "0xc7e15deb24b23c120ed65985516639441790ec6e89090f4aa0a87169aa9c2730";
const USD = 10n ** 18n;
const legacy = { type: "legacy", gasPrice: 1_000_000_000n } as const;

const artifact = (name: string) => {
  const file = fileURLToPath(new URL(`../../contracts/out/${name}.sol/${name}.json`, import.meta.url));
  const json = JSON.parse(readFileSync(file, "utf8")) as { abi: Abi; bytecode: { object: Hex } };
  return { abi: json.abi, bytecode: json.bytecode.object };
};

const transport = http(RPC);
const client = createPublicClient({ chain: bscTestnet, transport });
// anvil's default accounts (the public "test test ... junk" phrase).
const TEST_PHRASE = "test test test test test test test test test test test junk";
const account = (i: number) => mnemonicToAccount(TEST_PHRASE, { addressIndex: i });
const [deployer, alice, bob, carol, outsider] = [0, 1, 2, 3, 4].map(account) as [
  ReturnType<typeof account>,
  ReturnType<typeof account>,
  ReturnType<typeof account>,
  ReturnType<typeof account>,
  ReturnType<typeof account>,
];
// The attester is its own key, with no funds and no other role in the round.
const ATTESTER_KEY = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const attester = createAttester(ATTESTER_KEY);
const walletOf = (a: ReturnType<typeof account>) => createWalletClient({ account: a, chain: bscTestnet, transport });

async function mined(hash: Hex, what: string) {
  const receipt = await client.waitForTransactionReceipt({ hash });
  assert.equal(receipt.status, "success", `${what} reverted (${hash}, ${receipt.gasUsed} gas)`);
  console.log(`  ${what}: ${receipt.gasUsed} gas`);
  return receipt;
}

const tokenAbi = parseAbi([
  "function mint(address to, uint256 amount)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function balanceOf(address) view returns (uint256)",
]);

async function main() {
  assert.equal(await client.getChainId(), 97, "the fork must report chain id 97");
  for (const a of [deployer, alice, bob, carol, outsider]) {
    await createTestClient({ mode: "anvil", chain: bscTestnet, transport }).setBalance({ address: a.address, value: 10n ** 18n });
  }

  // 1. The two factories, as contracts/script/Deploy.s.sol deploys them.
  console.log("deploy");
  const vaultFactory = artifact("StreakVaultFactory");
  const launcherFactory = artifact("CheckInLauncherFactory");
  const launcher = artifact("CheckInLauncher");
  const vault = artifact("StreakVault");
  const nonce = await client.getTransactionCount({ address: deployer.address });
  const predicted = getContractAddress({ from: deployer.address, nonce: BigInt(nonce + 1) });
  const d1 = await mined(
    await walletOf(deployer).deployContract({ ...vaultFactory, args: [predicted], ...legacy, gas: 7_000_000n }),
    "StreakVaultFactory",
  );
  const d2 = await mined(
    await walletOf(deployer).deployContract({ ...launcherFactory, args: [PORTAL, GUARDIAN, d1.contractAddress!, QUOTE], ...legacy, gas: 8_000_000n }),
    "CheckInLauncherFactory",
  );
  assert.equal(d2.contractAddress!.toLowerCase(), predicted.toLowerCase());

  // 2. A round: 1,000 test USD deposit, 30% to the pool, a bar of 3 check-ins, 7 days.
  // The salt must give a token address ending in 7777 and must not be taken: small numbers are
  // already locked by others on testnet, so the search starts from a random value.
  let salt = keccak256(toHex(randomBytes(32)));
  while (!keccak256(concat(["0xff", PORTAL, salt, TOKEN_INIT_CODE_HASH])).endsWith("7777")) salt = keccak256(salt);
  const block = await client.getBlock();
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
        name: "Fork Movers",
        symbol: "FORK",
        meta: "",
        salt,
        deposit: 1000n * USD,
        liquidityBps: 3000n,
        checkInGoal: 3n,
        deadline: block.timestamp + 7n * 86_400n,
        attester: attester.address as Hex,
      },
    ],
  );
  const portalAbi = parseAbi([
    "function SALT_LOCK_FEE() view returns (uint256)",
    "function newLauncher(address factory, bytes data) payable returns (address)",
  ]);
  const fee = await client.readContract({ address: PORTAL, abi: portalAbi, functionName: "SALT_LOCK_FEE" });
  const created = await mined(
    await walletOf(deployer).writeContract({
      address: PORTAL,
      abi: portalAbi,
      functionName: "newLauncher",
      args: [d2.contractAddress!, config],
      value: fee,
      ...legacy,
      gas: 1_000_000n,
    }),
    "Portal.newLauncher",
  );
  let round: Hex | undefined;
  for (const log of created.logs) {
    if (log.address.toLowerCase() !== d2.contractAddress!.toLowerCase()) continue;
    try {
      const event = decodeEventLog({ abi: launcherFactory.abi, data: log.data, topics: log.topics });
      if (event.eventName === "CheckInLauncherCreated") round = (event.args as unknown as { launcher: Hex }).launcher;
    } catch {
      // not one of the factory's own events
    }
  }
  assert.ok(round, "no CheckInLauncherCreated event");
  console.log(`  launcher ${round}`);

  // 3. This server, pointed at the fork and at that round. Its clock is the fork's.
  let chainNow = Number(block.timestamp);
  const tick = async () => (chainNow = Number((await client.getBlock()).timestamp));
  const app = createApp({
    store: new LocalStore(),
    chain: createChain(RPC),
    attester,
    now: () => chainNow,
    defaultRound: { launcher: round },
    allowSelfReported: true,
  });
  const get = async (path: string) => {
    await tick();
    const res = await app.request(path);
    return { status: res.status, body: (await res.json()) as any };
  };
  const post = async (path: string, body: unknown) => {
    await tick();
    const res = await app.request(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    return { status: res.status, body: (await res.json()) as any };
  };

  console.log("GET /round (new round)");
  let r = await get("/round");
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.deepEqual(
    { ...r.body, today: undefined, dayIndex: undefined, deadline: undefined, raw: undefined },
    {
      launcher: round.toLowerCase(),
      name: "Fork Movers",
      quoteToken: QUOTE.toLowerCase(),
      deposit: "1000",
      liquidityBps: 3000,
      checkInGoal: 3,
      totalCheckIns: 0,
      memberCount: 0,
      totalDeposits: "0",
      totalSponsored: "0",
      poolQuoteNow: "0",
      prizeNow: "0",
      deadline: undefined,
      launched: false,
      token: null,
      vault: null,
      minSteps: 1000,
      flapUrl: null,
      today: undefined,
      dayIndex: undefined,
      canLaunch: false,
      refundOpen: false,
      allowSelfReported: true,
      attester: attester.address.toLowerCase(),
      attesterReady: true,
      quoteDecimals: 18,
      raw: undefined,
    },
  );
  const dayIndex: number = r.body.dayIndex;
  const today: string = r.body.today;

  // 4. Three members join; a wallet with no role sponsors 600 so the pool reaches Flap's floor.
  console.log("join and sponsor");
  const members = [alice, bob, carol];
  for (const who of [...members, outsider]) {
    const w = walletOf(who);
    await mined(await w.writeContract({ address: QUOTE, abi: tokenAbi, functionName: "mint", args: [who.address, 1000n * USD], ...legacy, gas: 120_000n }), "mint");
    await mined(await w.writeContract({ address: QUOTE, abi: tokenAbi, functionName: "approve", args: [round, 1000n * USD], ...legacy, gas: 100_000n }), "approve");
  }
  // A check-in before joining is refused by this server.
  const early = await post("/checkin", {
    address: alice.address,
    steps: 5000,
    source: "self",
    signature: await alice.signMessage({ message: checkInMessage(round.toLowerCase(), today, 5000) }),
  });
  assert.equal(early.body.error, "not_a_member", JSON.stringify(early.body));
  for (const who of members) {
    await mined(await walletOf(who).writeContract({ address: round, abi: launcher.abi, functionName: "join", ...legacy, gas: 250_000n }), "join");
  }
  await mined(
    await walletOf(outsider).writeContract({ address: round, abi: launcher.abi, functionName: "sponsor", args: [600n * USD], ...legacy, gas: 200_000n }),
    "sponsor",
  );
  r = await get("/round");
  assert.deepEqual(
    [r.body.memberCount, r.body.totalDeposits, r.body.totalSponsored, r.body.poolQuoteNow, r.body.prizeNow, r.body.canLaunch],
    [3, "3000", "600", "1500", "2100", false],
  );
  assert.equal(r.body.raw.poolQuoteNow, (1500n * USD).toString());

  // 5. Check-ins: the report goes to this server, the transaction comes from the member.
  console.log("check in");
  for (const [i, who] of members.entries()) {
    const steps = 4000 + i;
    const answer = await post("/checkin", {
      address: who.address,
      steps,
      source: i === 0 ? "self" : "healthkit",
      // Lower-case for one member, checksummed for the others: both forms are accepted.
      signature: await who.signMessage({ message: checkInMessage(i === 1 ? round.toLowerCase() : round, today, steps) }),
    });
    assert.equal(answer.status, 200, JSON.stringify(answer.body));
    assert.deepEqual([answer.body.day, answer.body.dayIndex, answer.body.repeat], [today, dayIndex, false]);
    let me = await get(`/me/${who.address}`);
    assert.deepEqual([me.body.member, me.body.daysOf, me.body.checkedInToday, me.body.attestedToday, me.body.streak], [true, 0, false, true, 1]);
    await mined(
      await walletOf(who).writeContract({
        address: round,
        abi: launcher.abi,
        functionName: "checkIn",
        args: [BigInt(answer.body.dayIndex), answer.body.attesterSignature],
        ...legacy,
        gas: 200_000n,
      }),
      "checkIn with the attester's signature",
    );
    me = await get(`/me/${who.address}`);
    assert.deepEqual([me.body.daysOf, me.body.checkedInToday, me.body.days], [1, true, [today]]);
  }
  // Once the day is on chain there is nothing left to sign.
  const again = await post("/checkin", {
    address: alice.address,
    steps: 4000,
    source: "self",
    signature: await alice.signMessage({ message: checkInMessage(round, today, 4000) }),
  });
  assert.equal(again.body.error, "already_checked_in", JSON.stringify(again.body));

  r = await get("/round");
  assert.deepEqual([r.body.totalCheckIns, r.body.canLaunch], [3, true]);
  const list = await get("/members");
  assert.equal(list.status, 200);
  assert.deepEqual(
    list.body,
    members
      .map((m) => ({ address: m.address.toLowerCase(), daysOf: 1, streak: 1, checkedInToday: true }))
      .sort((a, b) => (a.address < b.address ? -1 : 1)),
  );

  // 6. Launch, by the wallet that is neither a member nor the attester nor the creator.
  console.log("launch");
  await mined(await walletOf(outsider).writeContract({ address: round, abi: launcher.abi, functionName: "launch", ...legacy, gas: 7_000_000n }), "launch");
  r = await get("/round");
  assert.equal(r.body.launched, true);
  assert.match(r.body.token, /^0x[0-9a-f]{36}7777$/);
  assert.match(r.body.vault, /^0x[0-9a-f]{40}$/);
  assert.deepEqual([r.body.prizeNow, r.body.poolQuoteNow, r.body.canLaunch, r.body.flapUrl], ["2100", "1500", false, null]);
  console.log(`  token ${r.body.token}, vault ${r.body.vault}`);

  const closed = await post("/checkin", {
    address: alice.address,
    steps: 4000,
    source: "self",
    signature: await alice.signMessage({ message: checkInMessage(round, today, 4000) }),
  });
  assert.equal(closed.body.error, "round_launched", JSON.stringify(closed.body));

  // 7. Claim: each of the three has one day of three.
  console.log("claim");
  let me = await get(`/me/${alice.address}`);
  assert.deepEqual(
    [me.body.claimableTokens, me.body.claimableQuote, me.body.claimedTokens, me.body.claimedQuote],
    ["166666.666666666666666666", "700", "0", "0"],
  );
  const before = await client.readContract({ address: QUOTE, abi: tokenAbi, functionName: "balanceOf", args: [alice.address] });
  await mined(await walletOf(alice).writeContract({ address: r.body.vault, abi: vault.abi, functionName: "claim", ...legacy, gas: 500_000n }), "claim");
  const after = await client.readContract({ address: QUOTE, abi: tokenAbi, functionName: "balanceOf", args: [alice.address] });
  assert.equal(after - before, 700n * USD);
  me = await get(`/me/${alice.address}`);
  assert.deepEqual(
    [me.body.claimableTokens, me.body.claimableQuote, me.body.claimedTokens, me.body.claimedQuote],
    ["0", "0", "166666.666666666666666666", "700"],
  );
  const stranger = await get(`/me/${outsider.address}`);
  assert.deepEqual([stranger.body.member, stranger.body.daysOf, stranger.body.claimableTokens, stranger.body.claimableQuote], [false, 0, "0", "0"]);

  console.log("ok: the server and the contracts agree on a full round");
}

main().then(
  () => process.exit(0),
  (e) => {
    console.error(e);
    process.exit(1);
  },
);
