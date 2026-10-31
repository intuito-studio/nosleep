// NoSleep's cat, transliterated from Sources/NoSleep/CatGlyph.swift. That
// file draws flipped, on a 230 × 200 grid, so its points are already y-down
// and map straight onto an SVG viewBox. Change one, change the other.

export const CAT_VIEWBOX = "0 0 230 200";

export const CAT_HEAD =
  "M0 120 L12 116 C12 70 28 10 42 0 C54 8 66 36 80 46 C102 36 128 36 150 46 " +
  "C164 36 176 8 188 0 C202 10 218 70 218 116 L230 120 C226 172 178 200 115 200 " +
  "C52 200 4 172 0 120 Z";

export const CAT_EYES = [
  { cx: 70, cy: 107, rx: 29, ry: 45 },
  { cx: 160, cy: 107, rx: 29, ry: 45 },
];

/** A tall lens, pointed at both ends, 12 in from the eye's top and bottom. */
export function catPupil(cx: number): string {
  const top = 74;
  const bottom = 140;
  return (
    `M${cx} ${top} C${cx + 8} ${top + 22} ${cx + 8} ${bottom - 22} ${cx} ${bottom} ` +
    `C${cx - 8} ${bottom - 22} ${cx - 8} ${top + 22} ${cx} ${top} Z`
  );
}

/** A closed eye: a downward curve, stroked 14 wide with round caps. */
export function catLid(cx: number): string {
  const y = 109;
  return `M${cx - 25} ${y} C${cx - 12} ${y + 20} ${cx + 12} ${y + 20} ${cx + 25} ${y}`;
}

export const CAT_BROWN = "#5c4530";
export const CAT_YELLOW = "#ffd13d";

/**
 * The menu bar's slit pupil, with its tips rounded off: at this size the
 * needle points read as sharp, not as a cat.
 */
export function softPupil(cx: number): string {
  const top = 75;
  const bottom = 139;
  const mid = (top + bottom) / 2;
  const w = 6.2;
  return (
    `M${cx} ${top} C${cx + 2.4} ${top} ${cx + w} ${top + 20} ${cx + w} ${mid} ` +
    `C${cx + w} ${bottom - 20} ${cx + 2.4} ${bottom} ${cx} ${bottom} ` +
    `C${cx - 2.4} ${bottom} ${cx - w} ${bottom - 20} ${cx - w} ${mid} ` +
    `C${cx - w} ${top + 20} ${cx - 2.4} ${top} ${cx} ${top} Z`
  );
}
