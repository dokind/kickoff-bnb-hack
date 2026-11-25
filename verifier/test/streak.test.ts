import { describe, expect, it } from "vitest";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { dayIndexAt, dayIndexOf, dayString, streaks } from "../src/days.js";
import { T, harness, lower } from "./fakes.js";

const on = (today: string, days: string[]) => streaks(days, dayIndexOf(today)!);

describe("UTC days", () => {
  it("a day number is unix time / 86400, the same as the contract's", () => {
    expect(dayIndexAt(T("2026-11-25T00:00:00Z"))).toBe(20782);
    expect(dayIndexAt(T("2026-11-25T23:59:59Z"))).toBe(20782);
    expect(dayIndexAt(T("2026-11-26T00:00:00Z"))).toBe(20783);
    expect(dayString(20782)).toBe("2026-11-25");
    expect(dayIndexOf("2026-11-25")).toBe(20782);
  });

  it("rejects strings that are not real dates", () => {
    for (const bad of ["2026-02-30", "2026-13-01", "26-11-25", "2026-11-25T00:00", "", "today"]) {
      expect(dayIndexOf(bad)).toBeNull();
    }
    expect(dayIndexOf("2028-02-29")).not.toBeNull(); // a leap day
  });
});

describe("streaks", () => {
  it("no check-ins, no streak", () => {
    expect(on("2026-11-25", [])).toEqual({ streak: 0, bestStreak: 0 });
  });

  it("counts consecutive days ending today", () => {
    expect(on("2026-11-25", ["2026-11-25"])).toEqual({ streak: 1, bestStreak: 1 });
    expect(on("2026-11-25", ["2026-11-23", "2026-11-24", "2026-11-25"])).toEqual({ streak: 3, bestStreak: 3 });
  });

  it("still counts when the run ends yesterday: today is not over yet", () => {
    expect(on("2026-11-26", ["2026-11-24", "2026-11-25"])).toEqual({ streak: 2, bestStreak: 2 });
  });

  it("is lost after one full day without a check-in, but the best streak stays", () => {
    expect(on("2026-11-27", ["2026-11-24", "2026-11-25"])).toEqual({ streak: 0, bestStreak: 2 });
  });

  it("a gap starts a new run; the best streak is the longest run, old or current", () => {
    const days = ["2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-20", "2026-11-21"];
    expect(on("2026-11-21", days)).toEqual({ streak: 2, bestStreak: 4 });
    expect(on("2026-11-21", [...days, "2026-11-17", "2026-11-18", "2026-11-19"])).toEqual({ streak: 5, bestStreak: 5 });
  });

  it("runs across the end of a month, a year and a leap day", () => {
    expect(on("2026-12-01", ["2026-11-29", "2026-11-30", "2026-12-01"]).streak).toBe(3);
    expect(on("2027-01-01", ["2026-12-30", "2026-12-31", "2027-01-01"]).streak).toBe(3);
    expect(on("2028-03-01", ["2028-02-28", "2028-02-29", "2028-03-01"]).streak).toBe(3);
    expect(on("2027-03-01", ["2027-02-28", "2027-03-01"]).streak).toBe(2);
  });

  it("ignores order, duplicates and strings that are not dates", () => {
    expect(on("2026-11-25", ["2026-11-25", "2026-11-23", "nope", "2026-11-24", "2026-11-24"])).toEqual({ streak: 3, bestStreak: 3 });
  });

  it("a day later than today does not extend the current streak", () => {
    expect(on("2026-11-25", ["2026-11-25", "2026-11-26"])).toEqual({ streak: 1, bestStreak: 2 });
  });
});

describe("streaks through the API, across midnight UTC", () => {
  const alice = privateKeyToAccount(generatePrivateKey());

  it("a check-in just before midnight and one just after are two days in a row", async () => {
    const h = harness({}, T("2026-11-25T23:59:50Z"));
    h.chain.joined.add(lower(alice));
    const me = async () => (await h.get(`/me/${alice.address}`)).body;

    const first = await h.checkIn(alice);
    expect(first.body).toMatchObject({ day: "2026-11-25", dayIndex: 20782 });
    h.chain.submit(lower(alice), 20782);
    expect(await me()).toMatchObject({ streak: 1, bestStreak: 1, checkedInToday: true, days: ["2026-11-25"] });

    // Twenty seconds later it is the next UTC day: the streak holds, today is still open.
    h.clock = T("2026-11-26T00:00:10Z");
    expect(await me()).toMatchObject({ streak: 1, bestStreak: 1, checkedInToday: false, attestedToday: false });

    const second = await h.checkIn(alice);
    expect(second.body).toMatchObject({ day: "2026-11-26", dayIndex: 20783 });
    h.chain.submit(lower(alice), 20783);
    expect(await me()).toMatchObject({ streak: 2, bestStreak: 2, daysOf: 2, checkedInToday: true, days: ["2026-11-25", "2026-11-26"] });

    // The whole of the 27th passes without a check-in.
    h.clock = T("2026-11-27T23:59:59Z");
    expect(await me()).toMatchObject({ streak: 2, checkedInToday: false });
    h.clock = T("2026-11-28T00:00:00Z");
    expect(await me()).toMatchObject({ streak: 0, bestStreak: 2, daysOf: 2 });

    // A new run starts at one.
    await h.checkIn(alice);
    expect(await me()).toMatchObject({ streak: 1, bestStreak: 2, days: ["2026-11-25", "2026-11-26", "2026-11-28"] });
  });
});
