// The make-believe session on the hero's laptop. Its menu bar and the status
// line under the closed lid both read it, so they never disagree.

const started = typeof performance !== "undefined" ? performance.now() : 0;

/** Minutes left on the menu bar countdown: 1:42, ticking down, and starting
 * over rather than running out on a page left open. */
export function minutesLeft(): number {
  const seconds = (performance.now() - started) / 1000;
  return 102 - (Math.floor(seconds / 60) % 90);
}

export function clock(minutes: number): string {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}
