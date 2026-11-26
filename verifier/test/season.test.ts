import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { getAddress } from "viem";
import { DAY_SECONDS, dayIndexOf } from "../src/days.js";
import {
  DEFAULT_SEASON_NAME,
  DEFAULT_SQUAD_SIZE,
  MAX_SEASON_SPAN_DAYS,
  dayLabel,
  seasonFromEnv,
  seasonRefusal,
  seasonView,
  type Season,
} from "../src/season.js";

// Season 1 as planned: check-ins from Tue 1 Dec to Wed 30 Dec 2026 (UTC days 20788 to 20817), the
// app's joining open until Mon 7 Dec, squads of 10. The squad addresses are made up; DEMO is the
// stage demo round on BSC testnet, which is in no Season.
const SQUAD_A = `0x${"5a".padEnd(40, "0")}`;
const SQUAD_B = `0x${"5b".padEnd(40, "0")}`;
const DEMO = "0xcf7957dc48e5c16732331d27e2c2a1b2a9fa5876";

const ENV = {
  SEASON_NAME: "Season 1",
  SEASON_LAUNCHERS: SQUAD_A,
  SEASON_START: "2026-12-01",
  SEASON_END: "2026-12-30",
  SEASON_JOIN_UNTIL: "2026-12-07",
  SEASON_SQUAD_SIZE: "10",
};
const SEASON_1: Season = { name: "Season 1", launchers: [SQUAD_A], startDay: 20788, endDay: 20817, joinUntilDay: 20794, squadSize: 10 };

const NOT_STARTED = { code: "season_not_started", message: "Season 1 check-ins open Tue 1 Dec (07:00 in Bangkok). Everyone starts at 0." };
const OVER = { code: "season_over", message: "Season 1 check-ins have ended. The last day was Wed 30 Dec." };

/** The SEASON_* lines of verifier/.env.example: the settings as shipped, and Season 1's values as
 *  its comment gives them (`# SEASON_...=`). */
function envExample() {
  const shipped: Record<string, string> = {};
  const season1: Record<string, string> = {};
  for (const line of readFileSync(new URL("../.env.example", import.meta.url), "utf8").split("\n")) {
    const m = /^(#\s*)?(SEASON_[A-Z_]+)=(.*)$/.exec(line.trim());
    if (m) (m[1] ? season1 : shipped)[m[2]!] = m[3]!;
  }
  return { shipped, season1 };
}

describe("Season 1's days", () => {
  it("1 to 30 Dec 2026 are UTC days 20788 to 20817; joining in the app ends with 7 Dec, day 20794", () => {
    const days = ["2026-11-30", "2026-12-01", "2026-12-07", "2026-12-30", "2026-12-31"];
    expect(days.map(dayIndexOf)).toEqual([20787, 20788, 20794, 20817, 20818]);
    expect([20787, 20788, 20794, 20817, 20818].map(dayLabel)).toEqual(["Mon 30 Nov", "Tue 1 Dec", "Mon 7 Dec", "Wed 30 Dec", "Thu 31 Dec"]);
    // The squads' deadline, 31 Dec 23:59:59 UTC, falls on day 20818: the day after the last Season day.
    expect(Math.floor(1_798_761_599 / DAY_SECONDS)).toBe(20818);
  });
});

describe("seasonFromEnv", () => {
  it("reads the six SEASON_* settings; .env.example ships them empty and gives Season 1's in a comment", () => {
    expect(seasonFromEnv(ENV)).toEqual(SEASON_1);
    const { shipped, season1 } = envExample();
    expect(shipped).toEqual(Object.fromEntries(Object.keys(ENV).map((name) => [name, ""])));
    expect(seasonFromEnv(shipped)).toBeUndefined();
    expect(Object.keys(season1).sort()).toEqual(Object.keys(ENV).sort());
    expect(seasonFromEnv({ ...season1, SEASON_LAUNCHERS: SQUAD_A })).toEqual(SEASON_1);
  });

  it("no SEASON_LAUNCHERS, no Season: nothing else is read, so nothing else can stop the server", () => {
    expect(seasonFromEnv({})).toBeUndefined();
    for (const empty of ["", "   ", ",", " , ", '""']) expect(seasonFromEnv({ ...ENV, SEASON_LAUNCHERS: empty })).toBeUndefined();
    expect(seasonFromEnv({ SEASON_NAME: "Season 1", SEASON_START: "not a date", SEASON_SQUAD_SIZE: "-1" })).toBeUndefined();
  });

  it("several squads: comma separated, any spelling of an address, spaces and repeats left out", () => {
    const upper = `0x${SQUAD_B.slice(2).toUpperCase()}`;
    const season = seasonFromEnv({ ...ENV, SEASON_LAUNCHERS: ` ${getAddress(SQUAD_A)} ,${upper},, ${SQUAD_A},` });
    expect(season?.launchers).toEqual([SQUAD_A, SQUAD_B]);
  });

  it("the name and the squad size have defaults; quotes around a value are removed", () => {
    const { SEASON_NAME: _name, SEASON_SQUAD_SIZE: _size, ...rest } = ENV;
    expect(seasonFromEnv(rest)).toMatchObject({ name: DEFAULT_SEASON_NAME, squadSize: DEFAULT_SQUAD_SIZE });
    expect([DEFAULT_SEASON_NAME, DEFAULT_SQUAD_SIZE]).toEqual(["Season", 10]);
    // docker run --env-file keeps quotes that other env file readers remove.
    const quoted = { ...ENV, SEASON_NAME: '"Season 1"', SEASON_LAUNCHERS: `'${SQUAD_A}'`, SEASON_START: '"2026-12-01"', SEASON_SQUAD_SIZE: "'10'" };
    expect(seasonFromEnv(quoted)).toEqual(SEASON_1);
  });

  it("a one-day Season is allowed, and so is a last day 89 days after the first", () => {
    const oneDay = { ...ENV, SEASON_START: "2026-12-01", SEASON_END: "2026-12-01", SEASON_JOIN_UNTIL: "2026-12-01" };
    expect(seasonFromEnv(oneDay)).toMatchObject({ startDay: 20788, endDay: 20788, joinUntilDay: 20788 });
    expect(MAX_SEASON_SPAN_DAYS).toBe(90);
    expect(seasonFromEnv({ ...ENV, SEASON_END: "2027-02-28" })?.endDay).toBe(20788 + 89);
  });

  it("refuses a value it cannot use with an error that names the variable and does not repeat the value", () => {
    const bad: [Record<string, string>, RegExp][] = [
      [{ SEASON_LAUNCHERS: `${SQUAD_A},0x1234` }, /^SEASON_LAUNCHERS must be .*; entry 2 is not an address\.$/],
      // A 32-byte key pasted into the wrong variable: refused, and not printed.
      [{ SEASON_LAUNCHERS: `0x${"ab".repeat(32)}` }, /^SEASON_LAUNCHERS /],
      [{ SEASON_START: "2026-12-32" }, /^SEASON_START must be a real date/],
      [{ SEASON_START: "1 Dec 2026" }, /^SEASON_START /],
      [{ SEASON_START: "" }, /^SEASON_START /],
      [{ SEASON_END: "2026-02-30" }, /^SEASON_END must be a real date/],
      [{ SEASON_JOIN_UNTIL: "tomorrow" }, /^SEASON_JOIN_UNTIL must be a real date/],
      [{ SEASON_END: "2026-11-30" }, /^SEASON_END must be on or after SEASON_START\.$/],
      [{ SEASON_END: "2027-03-01" }, /^SEASON_END must be fewer than 90 days after SEASON_START/],
      [{ SEASON_JOIN_UNTIL: "2026-11-30" }, /^SEASON_JOIN_UNTIL must be a day from SEASON_START to SEASON_END\.$/],
      [{ SEASON_JOIN_UNTIL: "2026-12-31" }, /^SEASON_JOIN_UNTIL must be a day from SEASON_START to SEASON_END\.$/],
      [{ SEASON_SQUAD_SIZE: "0" }, /^SEASON_SQUAD_SIZE must be a whole number from 1 to 1000\.$/],
      [{ SEASON_SQUAD_SIZE: "10.5" }, /^SEASON_SQUAD_SIZE /],
      [{ SEASON_SQUAD_SIZE: "ten" }, /^SEASON_SQUAD_SIZE /],
      [{ SEASON_SQUAD_SIZE: "1001" }, /^SEASON_SQUAD_SIZE /],
      [{ SEASON_SQUAD_SIZE: "-3" }, /^SEASON_SQUAD_SIZE /],
      [{ SEASON_NAME: "x".repeat(81) }, /^SEASON_NAME must be at most 80 characters\.$/],
    ];
    for (const [over, message] of bad) {
      let error = "";
      try {
        seasonFromEnv({ ...ENV, ...over });
      } catch (e) {
        error = (e as Error).message;
      }
      expect(error).toMatch(message);
      for (const value of Object.values(over)) if (value.length > 3) expect(error).not.toContain(value);
    }
  });
});

describe("seasonRefusal: which days a Season round gets check-ins signed", () => {
  it("none before the first day and none after the last; both ends are Season days", () => {
    expect(seasonRefusal(SEASON_1, SQUAD_A, 20782)).toEqual(NOT_STARTED); // 25 Nov
    expect(seasonRefusal(SEASON_1, SQUAD_A, 20787)).toEqual(NOT_STARTED); // 30 Nov
    expect(seasonRefusal(SEASON_1, SQUAD_A, 20788)).toBeNull(); // 1 Dec
    expect(seasonRefusal(SEASON_1, SQUAD_A, 20800)).toBeNull();
    expect(seasonRefusal(SEASON_1, SQUAD_A, 20817)).toBeNull(); // 30 Dec
    expect(seasonRefusal(SEASON_1, SQUAD_A, 20818)).toEqual(OVER); // 31 Dec
    expect(seasonRefusal(SEASON_1, SQUAD_A, 20819)).toEqual(OVER);
  });

  it("whatever the spelling of the squad's address", () => {
    expect(seasonRefusal(SEASON_1, getAddress(SQUAD_A), 20787)).toEqual(NOT_STARTED);
    expect(seasonRefusal(SEASON_1, `0x${SQUAD_A.slice(2).toUpperCase()}`, 20818)).toEqual(OVER);
  });

  it("null for every launcher outside the Season, and for every launcher when there is no Season", () => {
    for (const day of [20782, 20787, 20788, 20817, 20818]) {
      expect(seasonRefusal(SEASON_1, DEMO, day)).toBeNull();
      expect(seasonRefusal(SEASON_1, SQUAD_B, day)).toBeNull();
      expect(seasonRefusal(undefined, SQUAD_A, day)).toBeNull();
    }
  });

  it("the message uses the Season's own name and dates", () => {
    const other: Season = { ...SEASON_1, name: "Season 2", startDay: dayIndexOf("2027-01-01")!, endDay: dayIndexOf("2027-01-30")!, joinUntilDay: dayIndexOf("2027-01-07")! };
    expect(seasonRefusal(other, SQUAD_A, 20818)?.message).toBe("Season 2 check-ins open Fri 1 Jan (07:00 in Bangkok). Everyone starts at 0.");
    expect(seasonRefusal(other, SQUAD_A, dayIndexOf("2027-01-31")!)?.message).toBe("Season 2 check-ins have ended. The last day was Sat 30 Jan.");
  });
});

describe("seasonView: the Season as the app reads it", () => {
  const at = (today: number) => seasonView(SEASON_1, SQUAD_A, today);

  it("the dates as text and as day numbers, today's day in the Season and the squad size", () => {
    expect(at(20782)).toEqual({
      name: "Season 1",
      start: "2026-12-01",
      end: "2026-12-30",
      joinUntil: "2026-12-07",
      startDay: 20788,
      endDay: 20817,
      joinUntilDay: 20794,
      day: 0,
      days: 30,
      squadSize: 10,
    });
  });

  it("day: 0 before the first day, 1 on it, 30 on the last, 31 after it", () => {
    expect([20000, 20787, 20788, 20794, 20817, 20818, 21000].map((d) => at(d)?.day)).toEqual([0, 0, 1, 7, 30, 31, 31]);
  });

  it("null outside the Season and without one", () => {
    expect(seasonView(SEASON_1, DEMO, 20790)).toBeNull();
    expect(seasonView(SEASON_1, SQUAD_B, 20790)).toBeNull();
    expect(seasonView(undefined, SQUAD_A, 20790)).toBeNull();
    expect(seasonView(SEASON_1, getAddress(SQUAD_A), 20790)?.day).toBe(3);
  });
});
