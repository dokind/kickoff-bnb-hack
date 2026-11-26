// Seasons. Pure functions, no I/O.
//
// A Season is one event with one set of dates. It is made of squads, and each squad is its own
// round: one CheckInLauncher, one bar, one piggy bank (StreakVault), one coin. Everyone in a Season
// starts on the same day, at 0 days.
//
// The contract has no start date: it takes a check-in on any day from a member's join until the
// launch or the deadline. So the Season's dates are a rule of this server, like the 1,000-step
// minimum, and should be disclosed like it: for a launcher listed in SEASON_LAUNCHERS, this server
// signs no check-in before the Season's first day or after its last one. Days are UTC days, as the
// contract counts them; a day starts at 07:00 in Bangkok. Every other launcher is not touched.
//
// Joining is not gated here. The contract takes joins until the launch or the deadline; the app
// stops offering Join after `joinUntil`, or once a squad has `squadSize` members.
import { isAddress } from "viem";
import { DAY_SECONDS, dayIndexOf, dayString } from "./days.js";

export interface Season {
  /** Display name, such as "Season 1". */
  name: string;
  /** The squads: CheckInLauncher addresses, lower-case. */
  launchers: string[];
  /** First check-in day, as the contract numbers days (unix time / 86400). */
  startDay: number;
  /** Last check-in day, included. */
  endDay: number;
  /** Last day the app offers Join, included. From startDay to endDay. */
  joinUntilDay: number;
  /** The app stops offering Join at this many members. The contract has no cap. */
  squadSize: number;
}

export interface SeasonRefusal {
  code: "season_not_started" | "season_over";
  /** One plain sentence or two for the member; the app shows it as the error. */
  message: string;
}

/** What GET /round, GET /rounds/:launcher and the items of GET /rounds carry as `season`. */
export interface SeasonView {
  name: string;
  /** The first and last check-in day and the last join day, as YYYY-MM-DD (UTC). */
  start: string;
  end: string;
  joinUntil: string;
  /** The same three days as the contract's day numbers. */
  startDay: number;
  endDay: number;
  joinUntilDay: number;
  /** Today in the Season: 0 before the first day, 1 on it, `days` on the last day, `days + 1` after it. */
  day: number;
  /** Check-in days in the Season, the first and last included. */
  days: number;
  squadSize: number;
}

/** A Season's last day is fewer than this many days after its first: a round runs at most 90 days. */
export const MAX_SEASON_SPAN_DAYS = 90;
/** SEASON_NAME when it is not set. */
export const DEFAULT_SEASON_NAME = "Season";
/** SEASON_SQUAD_SIZE when it is not set. */
export const DEFAULT_SQUAD_SIZE = 10;
export const MAX_SQUAD_SIZE = 1000;
const MAX_NAME_LENGTH = 80;

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** A day number as a person reads it, in UTC: "Tue 1 Dec". */
export function dayLabel(day: number): string {
  const date = new Date(day * DAY_SECONDS * 1000);
  return `${WEEKDAYS[date.getUTCDay()]} ${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`;
}

/** The value without surrounding spaces and one pair of matching quotes around it, which some ways
 *  of passing an env file (docker run --env-file) keep: SEASON_NAME="Season 1". */
function unquote(value: string | undefined): string {
  const v = (value ?? "").trim();
  return v.length >= 2 && (v[0] === '"' || v[0] === "'") && v.at(-1) === v[0] ? v.slice(1, -1).trim() : v;
}

function dateSetting(name: string, value: string | undefined): number {
  const day = dayIndexOf(unquote(value));
  if (day === null) throw new Error(`${name} must be a real date written YYYY-MM-DD (a UTC day), such as 2026-12-01.`);
  return day;
}

/**
 * The Season set with SEASON_NAME, SEASON_LAUNCHERS (a comma list), SEASON_START, SEASON_END,
 * SEASON_JOIN_UNTIL (dates as YYYY-MM-DD) and SEASON_SQUAD_SIZE. Undefined when SEASON_LAUNCHERS is
 * unset or empty: then no launcher is gated, and the other SEASON_* values are not read.
 *
 * Throws an error that names the variable when a value cannot be used. No error repeats the value
 * it was given (a key pasted into the wrong variable must not end up in a log).
 */
export function seasonFromEnv(env: Record<string, string | undefined>): Season | undefined {
  const entries = unquote(env.SEASON_LAUNCHERS)
    .split(",")
    .map(unquote)
    .filter((entry) => entry !== "");
  if (entries.length === 0) return undefined;
  entries.forEach((entry, i) => {
    if (!isAddress(entry, { strict: false })) {
      throw new Error(`SEASON_LAUNCHERS must be launcher addresses separated by commas; entry ${i + 1} is not an address.`);
    }
  });
  const launchers = [...new Set(entries.map((entry) => entry.toLowerCase()))];

  const name = unquote(env.SEASON_NAME) || DEFAULT_SEASON_NAME;
  if (name.length > MAX_NAME_LENGTH) throw new Error(`SEASON_NAME must be at most ${MAX_NAME_LENGTH} characters.`);

  const startDay = dateSetting("SEASON_START", env.SEASON_START);
  const endDay = dateSetting("SEASON_END", env.SEASON_END);
  const joinUntilDay = dateSetting("SEASON_JOIN_UNTIL", env.SEASON_JOIN_UNTIL);
  if (endDay < startDay) throw new Error("SEASON_END must be on or after SEASON_START.");
  if (endDay - startDay >= MAX_SEASON_SPAN_DAYS) {
    throw new Error(`SEASON_END must be fewer than ${MAX_SEASON_SPAN_DAYS} days after SEASON_START: a round runs at most ${MAX_SEASON_SPAN_DAYS} days.`);
  }
  if (joinUntilDay < startDay || joinUntilDay > endDay) throw new Error("SEASON_JOIN_UNTIL must be a day from SEASON_START to SEASON_END.");

  const size = unquote(env.SEASON_SQUAD_SIZE);
  const squadSize = size === "" ? DEFAULT_SQUAD_SIZE : /^\d+$/.test(size) ? Number(size) : NaN;
  if (!Number.isInteger(squadSize) || squadSize < 1 || squadSize > MAX_SQUAD_SIZE) {
    throw new Error(`SEASON_SQUAD_SIZE must be a whole number from 1 to ${MAX_SQUAD_SIZE}.`);
  }

  return { name, launchers, startDay, endDay, joinUntilDay, squadSize };
}

function inSeason(season: Season | undefined, launcher: string): season is Season {
  return season !== undefined && season.launchers.includes(launcher.toLowerCase());
}

/**
 * Why this server does not sign a check-in for `launcher` on day `today`, or null when the Season
 * allows it. Always null for a launcher that is not in the Season, and when there is no Season.
 */
export function seasonRefusal(season: Season | undefined, launcher: string, today: number): SeasonRefusal | null {
  if (!inSeason(season, launcher)) return null;
  if (today < season.startDay) {
    return {
      code: "season_not_started",
      message: `${season.name} check-ins open ${dayLabel(season.startDay)} (07:00 in Bangkok). Everyone starts at 0.`,
    };
  }
  if (today > season.endDay) {
    return { code: "season_over", message: `${season.name} check-ins have ended. The last day was ${dayLabel(season.endDay)}.` };
  }
  return null;
}

/** The Season of `launcher` as the app reads it on day `today`, or null when it is in none. */
export function seasonView(season: Season | undefined, launcher: string, today: number): SeasonView | null {
  if (!inSeason(season, launcher)) return null;
  const days = season.endDay - season.startDay + 1;
  return {
    name: season.name,
    start: dayString(season.startDay),
    end: dayString(season.endDay),
    joinUntil: dayString(season.joinUntilDay),
    startDay: season.startDay,
    endDay: season.endDay,
    joinUntilDay: season.joinUntilDay,
    day: Math.min(Math.max(today - season.startDay + 1, 0), days + 1),
    days,
    squadSize: season.squadSize,
  };
}
