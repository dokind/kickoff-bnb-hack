import { beforeEach, describe, expect, it } from "vitest";
import { getAddress, recoverMessageAddress } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { checkInInner, createAttester } from "../src/attest.js";
import { checkInMessage } from "../src/product.js";
import { DEFAULT_MIN_STEPS, MAX_STEPS, checkReport, parseSteps } from "../src/rules.js";
import { LAUNCHER, T, VECTOR_ATTESTER, harness, lower } from "./fakes.js";

// Throwaway keys generated per run.
const alice = privateKeyToAccount(generatePrivateKey());
const bob = privateKeyToAccount(generatePrivateKey());
const TODAY = 20782; // 2026-11-25

describe("report rules (pure)", () => {
  const check = (steps: unknown, source: unknown = "healthkit", allowSelfReported = false, minSteps = DEFAULT_MIN_STEPS) =>
    checkReport({ steps, source, minSteps, allowSelfReported });

  it("needs at least 1000 steps by default and at most 80000", () => {
    expect(DEFAULT_MIN_STEPS).toBe(1000);
    expect(MAX_STEPS).toBe(80_000);
    expect(check(999)).toMatchObject({ ok: false, status: 422, code: "not_enough_steps" });
    expect(check(1000)).toEqual({ ok: true });
    expect(check(80_000)).toEqual({ ok: true });
    expect(check(80_001)).toMatchObject({ ok: false, status: 422, code: "implausible_steps" });
  });

  it("MIN_STEPS moves the lower line", () => {
    expect(check(4999, "healthkit", false, 5000)).toMatchObject({ code: "not_enough_steps" });
    expect(check(5000, "healthkit", false, 5000)).toEqual({ ok: true });
  });

  it("steps are a whole number, as a JSON number or a plain string of digits", () => {
    expect(parseSteps(5000)).toBe(5000);
    expect(parseSteps("5000")).toBe(5000);
    for (const bad of [5000.5, -1, NaN, Infinity, "5e3", "5000.0", "05000", " 5000", "", null, undefined, true, [5000]]) {
      expect(parseSteps(bad)).toBeNull();
      expect(check(bad)).toMatchObject({ ok: false, status: 400, code: "bad_steps" });
    }
  });

  it("sources: healthkit and healthconnect always, self only when allowed", () => {
    expect(check(5000, "healthkit")).toEqual({ ok: true });
    expect(check(5000, "healthconnect")).toEqual({ ok: true });
    expect(check(5000, "self")).toMatchObject({ ok: false, status: 422, code: "self_report_disabled" });
    expect(check(5000, "self", true)).toEqual({ ok: true });
    for (const bad of ["manual", "", null, 1]) expect(check(5000, bad, true)).toMatchObject({ status: 400, code: "bad_source" });
  });
});

describe("POST /checkin", () => {
  let h: ReturnType<typeof harness>;

  beforeEach(() => {
    h = harness();
    h.chain.joined.add(lower(alice));
  });

  it("answers a member's report with the signature the contract requires", async () => {
    const { status, body } = await h.checkIn(alice, 5000);
    expect(status).toBe(200);
    expect(body).toMatchObject({ day: "2026-11-25", dayIndex: TODAY, repeat: false });
    // The contract recovers the attester from personal_sign(keccak256(abi.encode(97, launcher, wallet, day))).
    const inner = checkInInner(97, LAUNCHER, alice.address, TODAY);
    expect(await recoverMessageAddress({ message: { raw: inner }, signature: body.attesterSignature })).toBe(VECTOR_ATTESTER);
    expect(await h.store.getCheckIns(LAUNCHER)).toEqual([
      { address: lower(alice), day: "2026-11-25", dayIndex: TODAY, steps: 5000, source: "healthkit", selfReported: false, at: h.clock },
    ]);
  });

  it("accepts steps sent as a string and the launcher written checksummed in the signed text", async () => {
    expect((await h.checkIn(alice, "5000", { source: "healthconnect" })).status).toBe(200);
    h.chain.joined.add(lower(bob));
    const mixed = "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c"; // a launcher address with letters in it
    h.chain.rounds.set(mixed.toLowerCase(), h.chain.rounds.get(LAUNCHER)!);
    h.start({ defaultRound: { launcher: mixed.toLowerCase() } });
    expect((await h.checkIn(bob, 5000, { signedLauncher: getAddress(mixed) })).status).toBe(200);
    expect((await h.checkIn(bob, 5000, { signedLauncher: mixed.toLowerCase() })).status).toBe(200);
  });

  it("is for members of the round only (isMember on chain)", async () => {
    const res = await h.checkIn(bob);
    expect(res.status).toBe(403);
    expect(res.body.error).toBe("not_a_member");
    expect(await h.store.getCheckIns(LAUNCHER)).toEqual([]);
  });

  it("needs the minimum steps, and MIN_STEPS can raise it", async () => {
    expect((await h.checkIn(alice, 999)).body.error).toBe("not_enough_steps");
    expect((await h.checkIn(alice, 80_001)).body.error).toBe("implausible_steps");
    expect((await h.checkIn(alice, 1000.5)).status).toBe(400);
    h.start({ minSteps: 6000 });
    expect((await h.checkIn(alice, 5999)).status).toBe(422);
    expect((await h.checkIn(alice, 6000)).status).toBe(200);
    expect(await h.store.getCheckIns(LAUNCHER)).toHaveLength(1);
  });

  it("refuses a typed-in count unless ALLOW_SELF_REPORTED=true, and stores it flagged", async () => {
    const off = await h.checkIn(alice, 5000, { source: "self" });
    expect(off.status).toBe(422);
    expect(off.body.error).toBe("self_report_disabled");
    expect((await h.checkIn(alice, 5000, { source: "typed" })).body.error).toBe("bad_source");
    h.start({ allowSelfReported: true });
    expect((await h.checkIn(alice, 5000, { source: "self" })).status).toBe(200);
    expect(await h.store.getCheckIns(LAUNCHER)).toMatchObject([{ source: "self", selfReported: true, steps: 5000 }]);
  });

  it("needs the member's own signature over exactly what was sent", async () => {
    const forged = await h.checkIn(alice, 5000, { signer: bob });
    expect(forged.status).toBe(401);
    expect(forged.body.error).toBe("bad_signature");
    expect((await h.checkIn(alice, 5000, { signedSteps: 4000 })).status).toBe(401);
    expect((await h.checkIn(alice, 5000, { signedLauncher: "0x1000000000000000000000000000000000000002" })).status).toBe(401);
    expect((await h.post("/checkin", { address: alice.address, steps: 5000, source: "healthkit" })).status).toBe(401);
    expect((await h.post("/checkin", { address: alice.address, steps: 5000, source: "healthkit", signature: "0x1234" })).status).toBe(401);
    expect((await h.post("/checkin", { address: "nope", steps: 5000, source: "healthkit" })).status).toBe(400);
    expect(await h.store.getCheckIns(LAUNCHER)).toEqual([]);
  });

  it("accepts today (UTC) only: a report signed for another day is turned away", async () => {
    const yesterday = await h.checkIn(alice, 5000, { signedDay: "2026-11-24" });
    expect(yesterday.status).toBe(422);
    expect(yesterday.body).toMatchObject({ error: "wrong_day" });
    expect(yesterday.body.message).toContain("2026-11-25");
    expect((await h.checkIn(alice, 5000, { signedDay: "2026-11-26" })).body.error).toBe("wrong_day");
    expect((await h.checkIn(alice, 5000, { signedDay: "2026-11-20" })).status).toBe(401);
    // Signed at 23:59:59, received a second later: it is now the next day.
    h.clock = T("2026-11-25T23:59:59Z");
    const message = checkInMessage(LAUNCHER, "2026-11-25", 5000);
    const signature = await alice.signMessage({ message });
    h.clock = T("2026-11-26T00:00:00Z");
    const late = await h.post("/checkin", { address: alice.address, steps: 5000, source: "healthkit", signature });
    expect(late.body.error).toBe("wrong_day");
    expect(await h.store.getCheckIns(LAUNCHER)).toEqual([]);
  });

  it("one accepted check-in per member per day: asking again returns the same signature", async () => {
    const first = await h.checkIn(alice, 5000);
    h.clock += 600;
    const again = await h.checkIn(alice, 9000);
    expect(again.status).toBe(200);
    expect(again.body).toEqual({ ...first.body, repeat: true });
    // The first accepted report stands.
    expect(await h.store.getCheckIns(LAUNCHER)).toMatchObject([{ steps: 5000, at: h.clock - 600 }]);
    // A repeat still has to pass the rules.
    expect((await h.checkIn(alice, 10)).status).toBe(422);
  });

  it("the next day is a new check-in with a new signature", async () => {
    const first = await h.checkIn(alice);
    h.clock += 86_400;
    const second = await h.checkIn(alice);
    expect(second.body).toMatchObject({ day: "2026-11-26", dayIndex: TODAY + 1, repeat: false });
    expect(second.body.attesterSignature).not.toBe(first.body.attesterSignature);
    expect(await h.store.getCheckIns(LAUNCHER)).toHaveLength(2);
  });

  it("two members get different signatures for the same day", async () => {
    h.chain.joined.add(lower(bob));
    const [a, b] = await Promise.all([h.checkIn(alice), h.checkIn(bob)]);
    expect(a.body.attesterSignature).not.toBe(b.body.attesterSignature);
    const inner = checkInInner(97, LAUNCHER, bob.address, TODAY);
    expect(await recoverMessageAddress({ message: { raw: inner }, signature: b.body.attesterSignature })).toBe(VECTOR_ATTESTER);
  });

  it("says so when today's check-in is already on chain", async () => {
    await h.checkIn(alice);
    h.chain.submit(lower(alice), TODAY);
    const res = await h.checkIn(alice);
    expect(res.status).toBe(409);
    expect(res.body.error).toBe("already_checked_in");
  });

  it("is closed once the round has launched or its deadline has passed", async () => {
    h.chain.rounds.get(LAUNCHER)!.launched = true;
    const launched = await h.checkIn(alice);
    expect(launched.status).toBe(409);
    expect(launched.body.error).toBe("round_launched");
    h.chain.rounds.get(LAUNCHER)!.launched = false;

    const deadline = h.chain.rounds.get(LAUNCHER)!.deadline;
    h.clock = deadline; // the contract accepts check-ins up to and including the deadline
    expect((await h.checkIn(alice)).status).toBe(200);
    h.clock = deadline + 1;
    const closed = await h.checkIn(alice);
    expect(closed.status).toBe(409);
    expect(closed.body.error).toBe("round_closed");
  });

  it("signs nothing without the round's attester key", async () => {
    h.start({ attester: undefined });
    const none = await h.checkIn(alice);
    expect(none.status).toBe(503);
    expect(none.body.error).toBe("attester_disabled");
    // A key that is not the round's attester would only produce signatures the contract rejects.
    h.start({ attester: createAttester(generatePrivateKey()) });
    const other = await h.checkIn(alice);
    expect(other.status).toBe(503);
    expect(other.body.error).toBe("attester_mismatch");
    expect(await h.store.getCheckIns(LAUNCHER)).toEqual([]);
  });

  it("accepts nothing when the chain cannot be read", async () => {
    h.chain.down = true;
    const res = await h.checkIn(alice);
    expect(res.status).toBe(503);
    expect(res.body.error).toBe("chain_unavailable");
    expect(await h.store.getCheckIns(LAUNCHER)).toEqual([]);
    h.chain.down = false;
    expect((await h.checkIn(alice)).status).toBe(200);
  });

  it("answers 404 no_round when no round is set", async () => {
    h.start({ defaultRound: undefined });
    const res = await h.checkIn(alice);
    expect(res.status).toBe(404);
    expect(res.body.error).toBe("no_round");
  });
});
