// The illustration under the panel: one evening on battery, under load. The
// rates are made up but the rules are NoSleep's: Low Power Mode below 40%,
// and the session ends at the timer or the battery stop, whichever is first.

export const START = 64;
const FAST = 18; // % an hour, Low Power Mode off
const SLOW = 11; // % an hour, Low Power Mode on
export const LOW_POWER_BELOW = 40;
export const HOURS = 6;
const FLAT = 2;

const toLowPower = (START - LOW_POWER_BELOW) / FAST;

export function levelAt(t: number): number {
  return t <= toLowPower ? START - FAST * t : LOW_POWER_BELOW - SLOW * (t - toLowPower);
}

export function timeToReach(level: number): number {
  return level >= LOW_POWER_BELOW ? (START - level) / FAST : toLowPower + (LOW_POWER_BELOW - level) / SLOW;
}

export type Ending = { at: number; reason: "timer" | "battery" | "flat" };

/** `stop` 0 means the battery stop is off; `timer` past HOURS means no limit. */
export function ending(stop: number, timer: number): Ending {
  const battery = stop > 0 ? timeToReach(stop) : Infinity;
  const flat = timeToReach(FLAT);
  if (timer <= battery && timer <= flat) return { at: timer, reason: "timer" };
  if (battery <= flat) return { at: battery, reason: "battery" };
  return { at: flat, reason: "flat" };
}
