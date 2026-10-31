// What the laptop in the hero shows: a Mac desktop with NoSleep's panel open
// under its menu bar cat. A 2D canvas, used by three.js as the screen's
// texture, in the real display's proportions (3024 × 1964) at 2560 wide.
// Redrawn only when the countdown changes.
import { CAT_EYES, CAT_HEAD, CAT_BROWN, CAT_YELLOW, catPupil, softPupil } from "./cat";
import { clock, minutesLeft } from "./session";

export const SCREEN_W = 2560;
export const SCREEN_H = 1663;
/** Pixels per point: the 14-inch display looks like 1512 × 982 points. */
const PT = SCREEN_W / 1512;

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif';
const ORANGE = "#ff9f0a";

let wallpaper: HTMLImageElement | null = null;
let wallpaperReady = false;

/** Starts loading the wallpaper; `onReady` redraws once it has arrived. */
export function loadWallpaper(onReady: () => void) {
  if (wallpaper) {
    if (wallpaperReady) onReady();
    else wallpaper.addEventListener("load", onReady, { once: true });
    return;
  }
  wallpaper = new Image();
  wallpaper.decoding = "async";
  wallpaper.src = "/wallpaper.webp";
  wallpaper.addEventListener(
    "load",
    () => {
      wallpaperReady = true;
      onReady();
    },
    { once: true },
  );
}

function catImage(fill: string, eyes?: string): HTMLCanvasElement {
  const c = document.createElement("canvas");
  c.width = 230;
  c.height = 200;
  const g = c.getContext("2d")!;
  g.fillStyle = fill;
  g.fill(new Path2D(CAT_HEAD));
  g.globalCompositeOperation = eyes ? "source-over" : "destination-out";
  g.fillStyle = eyes ?? "#000";
  for (const e of CAT_EYES) {
    g.beginPath();
    g.ellipse(e.cx, e.cy, e.rx, e.ry, 0, 0, Math.PI * 2);
    g.fill();
  }
  g.globalCompositeOperation = "source-over";
  g.fillStyle = fill;
  for (const e of CAT_EYES) g.fill(new Path2D(catPupil(e.cx)));
  return c;
}

let cats: { bar: HTMLCanvasElement; badge: HTMLCanvasElement } | null = null;

function drawWallpaper(g: CanvasRenderingContext2D, x = 0, y = 0, w = SCREEN_W, h = SCREEN_H) {
  if (wallpaperReady && wallpaper) {
    g.drawImage(wallpaper, x, y, w, h);
    return;
  }
  const sky = g.createLinearGradient(0, 0, 0, SCREEN_H);
  sky.addColorStop(0, "#0d1530");
  sky.addColorStop(1, "#1d2a52");
  g.fillStyle = sky;
  g.fillRect(x, y, w, h);
}

/** A Liquid Glass sheet: the wallpaper behind it, blurred and brightened, with a lit rim. */
function glass(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  g.save();
  g.shadowColor = "rgba(0,0,0,0.35)";
  g.shadowBlur = 40 * PT;
  g.shadowOffsetY = 10 * PT;
  g.fillStyle = "rgba(20,24,40,0.4)";
  g.beginPath();
  g.roundRect(x, y, w, h, r);
  g.fill();
  g.restore();

  g.save();
  g.beginPath();
  g.roundRect(x, y, w, h, r);
  g.clip();
  g.filter = `blur(${18 * PT}px) saturate(1.5) brightness(1.25)`;
  drawWallpaper(g);
  g.filter = "none";
  g.fillStyle = "rgba(255,255,255,0.08)";
  g.fillRect(x, y, w, h);
  g.restore();

  const rim = g.createLinearGradient(x, y, x + w * 0.4, y + h);
  rim.addColorStop(0, "rgba(255,255,255,0.55)");
  rim.addColorStop(0.5, "rgba(255,255,255,0.08)");
  rim.addColorStop(1, "rgba(255,255,255,0.25)");
  g.strokeStyle = rim;
  g.lineWidth = 1.2 * PT;
  g.beginPath();
  g.roundRect(x + 0.6 * PT, y + 0.6 * PT, w - 1.2 * PT, h - 1.2 * PT, r);
  g.stroke();
}

function text(g: CanvasRenderingContext2D, s: string, x: number, y: number, size: number, weight = 400, alpha = 0.92) {
  g.font = `${weight} ${size * PT}px ${FONT}`;
  g.fillStyle = `rgba(255,255,255,${alpha})`;
  g.fillText(s, x, y);
  return g.measureText(s).width;
}

function slider(g: CanvasRenderingContext2D, x: number, y: number, w: number, at: number, label: string, value: string) {
  g.textBaseline = "alphabetic";
  text(g, label, x, y, 13, 500);
  g.textAlign = "right";
  text(g, value, x + w, y, 13, 500, 0.6);
  g.textAlign = "left";
  const ty = y + 16 * PT;
  g.fillStyle = "rgba(255,255,255,0.18)";
  g.beginPath();
  g.roundRect(x, ty, w, 6 * PT, 3 * PT);
  g.fill();
  g.fillStyle = "rgba(255,255,255,0.85)";
  g.beginPath();
  g.roundRect(x, ty, w * at, 6 * PT, 3 * PT);
  g.fill();
  g.save();
  g.shadowColor = "rgba(0,0,0,0.3)";
  g.shadowBlur = 6 * PT;
  g.fillStyle = "#f2f2f7";
  g.beginPath();
  g.roundRect(x + w * at - 13 * PT, ty - 5 * PT, 26 * PT, 16 * PT, 8 * PT);
  g.fill();
  g.restore();
}

export function drawScreen(g: CanvasRenderingContext2D) {
  if (!cats) cats = { bar: catImage("#fff"), badge: catImage(CAT_BROWN, CAT_YELLOW) };
  const W = SCREEN_W;
  g.textBaseline = "middle";
  g.textAlign = "left";
  drawWallpaper(g);

  // Menu bar: clear on macOS 26, with a soft shade so its text reads.
  const bar = 37 * PT;
  const shade = g.createLinearGradient(0, 0, 0, bar * 1.6);
  shade.addColorStop(0, "rgba(0,0,0,0.28)");
  shade.addColorStop(1, "rgba(0,0,0,0)");
  g.fillStyle = shade;
  g.fillRect(0, 0, W, bar * 1.6);

  const mid = bar / 2 + 1;
  let x = 22 * PT;
  for (const [item, weight] of [
    ["Finder", 700],
    ["File", 400],
    ["Edit", 400],
    ["View", 400],
    ["Go", 400],
    ["Window", 400],
  ] as const) {
    x += text(g, item, x, mid, 13.5, weight) + 20 * PT;
  }

  g.textAlign = "right";
  let right = W - 18 * PT;
  right -= text(g, "Fri 31 Oct  11:48 PM", right, mid, 13.5, 500) + 18 * PT;
  // Battery
  g.strokeStyle = "rgba(255,255,255,0.9)";
  g.lineWidth = 1.3 * PT;
  g.beginPath();
  g.roundRect(right - 25 * PT, mid - 6 * PT, 23 * PT, 12 * PT, 3.5 * PT);
  g.stroke();
  g.fillStyle = "rgba(255,255,255,0.9)";
  g.beginPath();
  g.roundRect(right - 23 * PT, mid - 4 * PT, 15 * PT, 8 * PT, 2 * PT);
  g.fill();
  g.fillRect(right - 1.5 * PT, mid - 2.5 * PT, 1.6 * PT, 5 * PT);
  right -= 25 * PT + 18 * PT;
  // Wi-Fi
  g.lineCap = "round";
  for (const [r, a] of [
    [11, 1],
    [7.3, 1],
  ]) {
    g.beginPath();
    g.arc(right - 9 * PT, mid + 5 * PT, r * PT, -Math.PI * 0.78, -Math.PI * 0.22);
    g.lineWidth = 1.9 * PT;
    g.strokeStyle = `rgba(255,255,255,${0.92 * a})`;
    g.stroke();
  }
  g.beginPath();
  g.arc(right - 9 * PT, mid + 5 * PT, 2 * PT, 0, Math.PI * 2);
  g.fill();
  right -= 18 * PT + 18 * PT;

  // NoSleep: the cat and its countdown, highlighted because its panel is open.
  const countdown = clock(minutesLeft());
  g.font = `500 ${13.5 * PT}px ${FONT}`;
  const cw = g.measureText(countdown).width;
  const itemW = cw + 22 * PT + 16 * PT;
  const itemX = right - itemW;
  g.fillStyle = "rgba(255,255,255,0.2)";
  g.beginPath();
  g.roundRect(itemX, 5 * PT, itemW, bar - 10 * PT, 6 * PT);
  g.fill();
  g.drawImage(cats.bar, itemX + 7 * PT, mid - 7.5 * PT, 17 * PT, 15 * PT);
  g.textAlign = "left";
  text(g, countdown, itemX + 28 * PT, mid, 13.5, 500);

  // The panel, hanging from the cat.
  const pw = 300 * PT;
  const ph = 236 * PT;
  const px = Math.min(W - pw - 10 * PT, itemX + itemW / 2 - pw / 2);
  const py = bar + 6 * PT;
  glass(g, px, py, pw, ph, 28 * PT);

  const pad = 10 * PT;
  const tx = px + pad;
  const tw = pw - pad * 2;
  // Switch tile
  g.fillStyle = "rgba(255,255,255,0.12)";
  g.beginPath();
  g.roundRect(tx, py + pad, tw, 88 * PT, 18 * PT);
  g.fill();
  const cx = tx + 44 * PT;
  const cy = py + pad + 44 * PT;
  g.fillStyle = ORANGE;
  g.beginPath();
  g.arc(cx, cy, 26 * PT, 0, Math.PI * 2);
  g.fill();
  g.drawImage(cats.badge, cx - 17 * PT, cy - 15 * PT, 34 * PT, 30 * PT);
  g.textBaseline = "alphabetic";
  text(g, "Awake", tx + 84 * PT, cy - 2 * PT, 17, 600, 0.96);
  text(g, `${clock(minutesLeft())} left`, tx + 84 * PT, cy + 18 * PT, 13, 400, 0.62);

  // Sliders tile
  const sy = py + pad + 88 * PT + pad;
  g.fillStyle = "rgba(255,255,255,0.12)";
  g.beginPath();
  g.roundRect(tx, sy, tw, ph - (sy - py) - pad, 18 * PT);
  g.fill();
  slider(g, tx + 16 * PT, sy + 28 * PT, tw - 32 * PT, 0.375, "Keep awake for", "2 hours");
  slider(g, tx + 16 * PT, sy + 80 * PT, tw - 32 * PT, 0.5, "Stop at battery", "20%");

  // The display's rounded top corners and the camera notch, in the bezel's black.
  g.fillStyle = "#000";
  const corner = 22 * PT;
  for (const [cx0, dir] of [
    [0, 1],
    [W, -1],
  ]) {
    g.beginPath();
    g.moveTo(cx0, 0);
    g.lineTo(cx0 + dir * corner, 0);
    g.arcTo(cx0, 0, cx0, corner, corner);
    g.closePath();
    g.fill();
  }
  const nw = 186 * PT;
  const nh = 32 * PT;
  g.beginPath();
  g.roundRect(W / 2 - nw / 2, -12 * PT, nw, nh + 12 * PT, 9 * PT);
  g.fill();
}

/** The top of the base: keyboard well, speaker grilles each side, trackpad. In millimetres-ish units of a 1024-wide map. */
export function drawDeck(g: CanvasRenderingContext2D, w: number, h: number) {
  g.fillStyle = "#2b2c2f";
  g.fillRect(0, 0, w, h);
  // Keyboard: 0.75 of the width, from just in front of the hinge.
  const kb = { x: w * 0.125, y: h * 0.07, w: w * 0.75, h: h * 0.43 };
  g.fillStyle = "#121214";
  g.beginPath();
  g.roundRect(kb.x - 6, kb.y - 6, kb.w + 12, kb.h + 12, 8);
  g.fill();
  const rows = 6;
  const cols = 14;
  const gap = 4;
  const kh = (kb.h - gap * (rows - 1)) / rows;
  const kw = (kb.w - gap * (cols - 1)) / cols;
  g.fillStyle = "#0b0b0c";
  for (let r = 0; r < rows; r++) {
    const keyH = r === 0 ? kh * 0.55 : kh;
    const y = kb.y + r * (kh + gap) + (r === 0 ? kh * 0.45 : 0);
    for (let c = 0; c < cols; c++) {
      if (r === 5 && c > 3 && c < 10) continue;
      g.beginPath();
      g.roundRect(kb.x + c * (kw + gap), y, kw, keyH, 4);
      g.fill();
    }
    if (r === 5) {
      g.beginPath();
      g.roundRect(kb.x + 4 * (kw + gap), y, kw * 6 + gap * 5, keyH, 4);
      g.fill();
    }
  }
  // Speaker grilles
  g.fillStyle = "#1a1a1c";
  for (const sx of [w * 0.045, w * 0.91]) {
    for (let yy = kb.y; yy < kb.y + kb.h; yy += 7) {
      for (let xx = sx; xx < sx + w * 0.045; xx += 7) {
        g.beginPath();
        g.arc(xx, yy, 1.5, 0, Math.PI * 2);
        g.fill();
      }
    }
  }
  // Trackpad
  const pad = { w: w * 0.43, h: h * 0.4 };
  g.fillStyle = "#313236";
  g.beginPath();
  g.roundRect((w - pad.w) / 2, h * 0.565, pad.w, pad.h, 14);
  g.fill();
  g.strokeStyle = "rgba(255,255,255,0.06)";
  g.lineWidth = 2;
  g.stroke();
}

/**
 * NoSleep's on-screen sign that it is on: the hero cat itself, big, rising
 * from behind the screen's bottom edge with its eyes lit and its two front
 * paws hooked over the edge, as it sits on the shut lid at the end of the
 * page. The cat is Liquid Glass: the screen's shader fills the silhouette
 * this returns with the desktop behind, blurred and lifted. Drawn here is
 * what sits around and on that glass: a soft shadow, a smoky brown tint, a
 * white rim along the top edges, the eyes and the toes. Both are
 * transparent maps the size of the screen; the shader slides them up from
 * below the bezel.
 */
export function drawScreenCat(g: CanvasRenderingContext2D, w: number, h: number) {
  g.clearRect(0, 0, w, h);
  // The head on its 230 × 200 grid, the chin below the bezel.
  const s = (w * 0.7) / 230;
  const mw = 56 * s;
  const top = h - mw * 0.76 - 132 * s;
  // The paws grip the bezel from outside the screen: only their backs come
  // over the bottom edge, the toes stay below it.
  const pawY = h - mw * 0.2;
  const placeHead = (c: CanvasRenderingContext2D) => {
    c.translate(w / 2 - 115 * s, top);
    c.scale(s, s);
  };
  const head = new Path2D(CAT_HEAD);
  // The paws as the hero cat's: a mitt with four toes over the edge.
  const sides = [-1, 1];
  const placePaw = (c: CanvasRenderingContext2D, side: number) => {
    // Out at the cheeks, the way a cat props itself on an edge.
    c.translate(w / 2 + side * w * 0.34, pawY);
    c.rotate(side * 0.12);
    c.scale(mw, mw);
  };
  const mitt = new Path2D();
  mitt.ellipse(0, 0.06, 0.46, 0.3, 0, 0, Math.PI * 2);
  for (const tx of [-0.3, -0.1, 0.1, 0.3]) {
    mitt.moveTo(tx + 0.13, 0.26);
    mitt.ellipse(tx, 0.26, 0.13, 0.12, 0, 0, Math.PI * 2);
  }

  const layer = (draw: (c: CanvasRenderingContext2D) => void) => {
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    draw(c.getContext("2d")!);
    return c;
  };
  const headShape = layer((c) => {
    placeHead(c);
    c.fill(head);
  });
  const pawShape = layer((c) => {
    for (const side of sides) {
      c.save();
      placePaw(c, side);
      c.fill(mitt, "nonzero");
      c.restore();
    }
  });
  const shape = layer((c) => {
    c.drawImage(headShape, 0, 0);
    c.drawImage(pawShape, 0, 0);
  });

  // The shadow alone: the silhouette's shadow, the silhouette cut back out,
  // since the glass goes there.
  g.save();
  g.shadowColor = "rgba(0, 0, 0, 0.35)";
  g.shadowBlur = mw * 0.5;
  g.shadowOffsetY = mw * 0.12;
  g.drawImage(shape, 0, 0);
  g.restore();
  g.save();
  g.globalCompositeOperation = "destination-out";
  g.drawImage(shape, 0, 0);
  g.restore();

  // Smoky brown glass, the hero cat's colour, the desktop still showing.
  const smoke = (c: HTMLCanvasElement, alpha: number) => {
    const tinted = layer((t) => {
      t.drawImage(c, 0, 0);
      t.globalCompositeOperation = "source-in";
      const fur = t.createLinearGradient(0, top, 0, h);
      fur.addColorStop(0, "#4a3726");
      fur.addColorStop(1, "#24190f");
      t.fillStyle = fur;
      t.fillRect(0, 0, w, h);
    });
    g.save();
    g.globalAlpha = alpha;
    g.drawImage(tinted, 0, 0);
    g.restore();
  };
  smoke(headShape, 0.5);
  // The paws lie over the head, so they cast onto it and are a shade deeper.
  g.save();
  g.shadowColor = "rgba(0, 0, 0, 0.45)";
  g.shadowBlur = mw * 0.3;
  g.shadowOffsetY = mw * 0.08;
  g.globalAlpha = 0.55;
  g.drawImage(layer((c) => {
    c.drawImage(pawShape, 0, 0);
    c.globalCompositeOperation = "source-in";
    c.fillStyle = "#2a1d12";
    c.fillRect(0, 0, w, h);
  }), 0, 0);
  g.restore();

  // The rim: the silhouette less itself moved down a touch, so only the
  // edges that face up stay, bright at the ears and gone by the chin.
  const rimOf = (c: HTMLCanvasElement) =>
    layer((r) => {
      r.drawImage(c, 0, 0);
      r.globalCompositeOperation = "destination-out";
      r.drawImage(c, 0, mw * 0.035);
      r.globalCompositeOperation = "source-in";
      const light = r.createLinearGradient(0, top, 0, h);
      light.addColorStop(0, "rgba(255, 255, 255, 0.85)");
      light.addColorStop(1, "rgba(255, 255, 255, 0.25)");
      r.fillStyle = light;
      r.fillRect(0, 0, w, h);
    });
  g.drawImage(rimOf(headShape), 0, 0);
  g.drawImage(rimOf(pawShape), 0, 0);

  // The eyes, lit, as the hero cat's: a glowing iris here; the pupil and
  // the glint go on in `look`, since the pupils follow the pointer.
  const eyes = CAT_EYES.map((e) => {
    const eye = new Path2D();
    eye.ellipse(e.cx, e.cy, e.rx, e.ry, 0, 0, Math.PI * 2);
    return eye;
  });
  const pupils = CAT_EYES.map((e) => new Path2D(softPupil(e.cx)));
  const iris = (c: CanvasRenderingContext2D) => {
    c.save();
    placeHead(c);
    for (const [i, e] of CAT_EYES.entries()) {
      c.save();
      c.shadowColor = "rgba(255, 209, 61, 0.55)";
      c.shadowBlur = 30 * s;
      const fill = c.createRadialGradient(e.cx, e.cy - 8, 4, e.cx, e.cy, e.ry);
      fill.addColorStop(0, "#ffe68a");
      fill.addColorStop(0.7, CAT_YELLOW);
      fill.addColorStop(1, "#d99a00");
      c.fillStyle = fill;
      c.fill(eyes[i]);
      c.restore();
    }
    c.restore();
  };
  const pupilsAt = (c: CanvasRenderingContext2D, x: number, y: number) => {
    c.save();
    placeHead(c);
    for (const [i, e] of CAT_EYES.entries()) {
      c.save();
      c.clip(eyes[i]);
      c.translate(x * 13, y * 16);
      c.fillStyle = "#120c07";
      c.fill(pupils[i]);
      c.restore();
      c.fillStyle = "rgba(255, 255, 255, 0.6)";
      c.beginPath();
      c.ellipse(e.cx - 10, e.cy - 22, 5, 7, -0.3, 0, Math.PI * 2);
      c.fill();
    }
    c.restore();
  };
  iris(g);

  // Between the toes, as on the hero cat's paws.
  for (const side of sides) {
    g.save();
    placePaw(g, side);
    g.strokeStyle = "rgba(0, 0, 0, 0.4)";
    g.lineWidth = 0.035;
    g.lineCap = "round";
    for (const tx of [-0.2, 0, 0.2]) {
      g.beginPath();
      g.moveTo(tx, 0.18);
      g.lineTo(tx, 0.34);
      g.stroke();
    }
    g.restore();
  }
  const base = layer((c) => c.drawImage(g.canvas, 0, 0));
  // The eyes alone, for the very end: the screen floods with their light and
  // only they are left on it.
  const eyeMap = layer(() => {});
  const eg = eyeMap.getContext("2d")!;
  /** Redraws the pupils looking toward (x, y), each −1…1, as the hero cat's do. */
  const look = (x: number, y: number) => {
    g.clearRect(0, 0, w, h);
    g.drawImage(base, 0, 0);
    pupilsAt(g, x, y);
    eg.clearRect(0, 0, w, h);
    iris(eg);
    pupilsAt(eg, x, y);
  };
  look(0, 0);
  // Each eye's centre, in the map's uv (y up), for the flood to start from.
  const eyeCentres = CAT_EYES.map((e) => [(w / 2 + (e.cx - 115) * s) / w, 1 - (top + e.cy * s) / h] as [number, number]);
  return { shape, look, eyeMap, eyeCentres };
}
