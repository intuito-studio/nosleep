// The big cat behind the laptop in the hero, drawn on two 2D canvases from
// the same paths as the app's icon: its head behind the WebGL laptop, its
// paws in front, hooked over the back edge of the shut lid. It comes up from
// behind asleep and opens its eyes once the lid is down: the Mac is shut, and
// still awake. Awake, its eyes follow the pointer and a click surprises it.

import { CAT_EYES, CAT_HEAD, CAT_YELLOW, catLid, softPupil } from "@/lib/cat";
import type { Point } from "@/lib/laptop-scene";

export type Behind = { desk: number; centre: number; width: number; paws: [Point, Point] };

type Spring = { value: number; target: number; speed: number };
const spring = (value: number, speed: number): Spring => ({ value, target: value, speed });
const step = (s: Spring, dt: number) => {
  s.value += (s.target - s.value) * (1 - Math.exp(-s.speed * dt));
};
const clamp01 = (t: number) => Math.max(0, Math.min(1, t));

const FUR_TOP = "#0f0b08";
const FUR = "#2a2018";
const FUR_LOW = "#18120d";
const LID = "#231a13";
const RIM = "255, 180, 107";

type Firefly = { x: number; y: number; r: number; phase: number; speed: number; front: boolean };

export class CatCanvas {
  private back: CanvasRenderingContext2D;
  private front: CanvasRenderingContext2D;
  private head = new Path2D(CAT_HEAD);
  private pupils = CAT_EYES.map((e) => new Path2D(softPupil(e.cx)));
  private lids = CAT_EYES.map((e) => new Path2D(catLid(e.cx)));
  private dpr = 1;
  private W = 0;
  private H = 0;
  /** Where the head was last drawn: centre of the eyes and scale, for hit tests. */
  private at = { x: 0, y: 0, scale: 1 };

  private story = { rise: 0, wake: 0, night: 0 };
  private behind: () => Behind | null = () => null;

  private lookX = spring(0, 7);
  private lookY = spring(0, 7);
  private dilate = spring(1.5, 4);
  private blinkLid = spring(0, 22);
  private hop = spring(0, 9);
  private nextBlink = 2;
  private blinkUntil = 0;
  private peekUntil = 0;
  private lastPointer = -10;
  private nextWander = 0;
  private time = 0;
  private last = 0;
  private frame = 0;
  private running = false;
  private still: boolean;
  private flies: Firefly[];

  constructor(
    private backCanvas: HTMLCanvasElement,
    private frontCanvas: HTMLCanvasElement,
  ) {
    this.back = backCanvas.getContext("2d")!;
    this.front = frontCanvas.getContext("2d")!;
    this.still = matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Seeded, so the fireflies sit in the same places on every visit.
    let seed = 7;
    const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    this.flies = Array.from({ length: 22 }, (_, i) => ({
      x: rand(),
      y: 0.35 + rand() * 0.6,
      r: 1.2 + rand() * 2,
      phase: rand() * Math.PI * 2,
      speed: 0.15 + rand() * 0.35,
      front: i % 6 === 0,
    }));
    this.resize();
  }

  /** Reads where the laptop is each frame. */
  follow(behind: () => Behind | null) {
    this.behind = behind;
  }

  /** rise 0–1 brings the head up; wake 0–1 opens its eyes; night 0–1 shows the fireflies. */
  set(story: Partial<typeof this.story>) {
    const wasAwake = this.story.wake > 0.5;
    Object.assign(this.story, story);
    // Waking up wide-eyed.
    if (!wasAwake && this.story.wake > 0.5) this.dilate.target = 2.6;
    if (!this.running) this.draw();
  }

  /** The pointer, in viewport pixels. */
  look(clientX: number, clientY: number) {
    const r = this.backCanvas.getBoundingClientRect();
    const dx = clientX - r.left - this.at.x;
    const dy = clientY - r.top - this.at.y;
    const reach = this.at.scale * 220;
    const speed = Math.hypot(dx / reach - this.lookX.target, dy / reach - this.lookY.target);
    this.lookX.target = Math.max(-1, Math.min(1, dx / reach));
    this.lookY.target = Math.max(-1, Math.min(1, dy / reach));
    // A quick flick of the pointer catches its attention.
    if (this.awake) this.dilate.target = Math.min(2.6, this.dilate.target + speed * 1.5);
    this.lastPointer = this.time;
  }

  /** True when the point is on the cat's head, so the page can show a hand cursor. */
  hits(clientX: number, clientY: number) {
    if (this.story.rise < 0.5) return false;
    const r = this.backCanvas.getBoundingClientRect();
    const px = (clientX - r.left - this.at.x) / this.at.scale + 115;
    const py = (clientY - r.top - this.at.y) / this.at.scale + 107;
    this.back.save();
    this.back.setTransform(1, 0, 0, 1, 0, 0);
    const hit = this.back.isPointInPath(this.head, px, py);
    this.back.restore();
    return hit;
  }

  poke() {
    if (this.awake) {
      this.dilate.target = 2.8;
      this.blink(this.time, 2);
    } else {
      // Asleep, it opens one eye's worth of both, then dozes off again.
      this.peekUntil = this.time + 0.9;
    }
    if (!this.still) this.hop.target = 1;
  }

  resize() {
    const r = this.backCanvas.getBoundingClientRect();
    this.dpr = Math.min(window.devicePixelRatio, 2);
    this.W = r.width;
    this.H = r.height;
    for (const c of [this.backCanvas, this.frontCanvas]) {
      c.width = Math.round(r.width * this.dpr);
      c.height = Math.round(r.height * this.dpr);
    }
    this.draw();
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.last = performance.now();
    const tick = (now: number) => {
      if (!this.running) return;
      const dt = Math.min(0.05, (now - this.last) / 1000);
      this.last = now;
      this.update(dt);
      this.draw();
      this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  }

  stop() {
    this.running = false;
    cancelAnimationFrame(this.frame);
  }

  private get awake() {
    return this.story.wake > 0.9;
  }

  private blink(now: number, times = 1) {
    this.blinkUntil = now + 0.13 + (times - 1) * 0.26;
    this.nextBlink = now + 2.5 + Math.random() * 4;
  }

  private update(dt: number) {
    const t = (this.time += dt);
    if (this.awake && t > this.nextBlink) this.blink(t);
    // Two quick blinks read as one long one unless the lid opens between them.
    const inBlink = t < this.blinkUntil && (this.blinkUntil - t) % 0.26 > 0.1;
    this.blinkLid.target = inBlink ? 1 : 0;

    // Nobody pointing (a phone, or a still mouse): it looks around by itself.
    if (t - this.lastPointer > 3 && t > this.nextWander) {
      this.lookX.target = (Math.random() * 2 - 1) * 0.7;
      this.lookY.target = (Math.random() * 2 - 1) * 0.4;
      this.nextWander = t + 1.6 + Math.random() * 2.4;
    }
    // In the dark, wide pupils; they settle back after a surprise.
    this.dilate.target += (1.5 - this.dilate.target) * (1 - Math.exp(-0.8 * dt));
    if (this.hop.value > 0.95) this.hop.target = 0;

    for (const s of [this.lookX, this.lookY, this.dilate, this.blinkLid, this.hop]) step(s, dt);
  }

  private draw() {
    for (const g of [this.back, this.front]) {
      g.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      g.clearRect(0, 0, this.W, this.H);
    }
    this.drawFlies();
    const b = this.behind();
    if (!b || this.story.rise <= 0.001) return;

    const g = this.back;
    // As wide as the laptop, so its ears and cheeks show around it.
    const scale = (b.width * 0.92) / 230;
    const headH = 200 * scale;
    const breathe = this.still ? 0 : Math.sin(this.time * (this.awake ? 1.3 : 0.8)) * (this.awake ? 0.006 : 0.012);
    // Resting: its cheeks level with the lid's back edge, chin hidden behind.
    const rest = (b.paws[0].y + b.paws[1].y) / 2 - 168 * scale;
    const y = rest + (1 - this.story.rise) * headH * 1.15 - this.hop.value * 12;
    const x = b.centre;
    const tilt = this.awake ? this.lookX.value * 0.03 : -0.05;
    this.at = { x, y: y + 107 * scale, scale };

    g.save();
    // Hidden below the line where the desk meets the back of the laptop.
    g.beginPath();
    g.rect(0, 0, this.W, b.desk);
    g.clip();
    g.translate(x, y + 107 * scale);
    g.rotate(tilt);
    g.scale(scale * (1 + breathe), scale * (1 + breathe));
    g.translate(-115, -107);

    const fur = g.createLinearGradient(0, 0, 0, 200);
    fur.addColorStop(0, FUR_TOP);
    fur.addColorStop(0.45, FUR);
    fur.addColorStop(1, FUR_LOW);
    g.fillStyle = fur;
    g.fill(this.head);

    g.save();
    g.clip(this.head);
    const rim = g.createLinearGradient(0, 0, 230, 0);
    rim.addColorStop(0, `rgba(${RIM}, 0.05)`);
    rim.addColorStop(1, `rgba(${RIM}, 0.3)`);
    g.strokeStyle = rim;
    g.lineWidth = 3.4;
    g.stroke(this.head);
    g.restore();

    const peek = this.time < this.peekUntil ? 0.45 : 1;
    const closed = Math.max(this.blinkLid.value, Math.min(peek, 1 - clamp01((this.story.wake - 0.6) / 0.4)));
    for (const [i, e] of CAT_EYES.entries()) this.drawEye(e, this.pupils[i], this.lids[i], closed);
    g.restore();

    this.drawPaws(b, scale);
  }

  private drawEye(e: (typeof CAT_EYES)[number], pupil: Path2D, lid: Path2D, closed: number) {
    const g = this.back;
    if (closed > 0.98) {
      // Asleep: the closed-eye curve from the menu bar icon, lit faintly.
      g.strokeStyle = `rgba(${RIM}, 0.55)`;
      g.lineWidth = 7;
      g.lineCap = "round";
      g.stroke(lid);
      return;
    }
    const eye = new Path2D();
    eye.ellipse(e.cx, e.cy, e.rx, e.ry, 0, 0, Math.PI * 2);

    g.save();
    g.shadowColor = `rgba(255, 209, 61, ${0.5 * (1 - closed)})`;
    g.shadowBlur = 36 * this.at.scale * this.dpr;
    const iris = g.createRadialGradient(e.cx, e.cy - 8, 4, e.cx, e.cy, e.ry);
    iris.addColorStop(0, "#ffe68a");
    iris.addColorStop(0.7, CAT_YELLOW);
    iris.addColorStop(1, "#d99a00");
    g.fillStyle = iris;
    g.fill(eye);
    g.restore();

    g.save();
    g.clip(eye);
    const follow = this.awake ? 1 : 0;
    g.translate(e.cx + this.lookX.value * 13 * follow, this.lookY.value * 16 * follow);
    g.scale(this.dilate.value, 1);
    g.translate(-e.cx, 0);
    g.fillStyle = "#120c07";
    g.fill(pupil);
    g.restore();

    g.save();
    g.clip(eye);
    g.fillStyle = "rgba(255, 255, 255, 0.55)";
    g.beginPath();
    g.ellipse(e.cx - 10, e.cy - 22, 5, 7, -0.3, 0, Math.PI * 2);
    g.fill();
    // The lid comes down from above, its edge curved like an eyelid.
    const drop = closed * 2.04 * e.ry;
    g.fillStyle = LID;
    g.beginPath();
    g.ellipse(e.cx, e.cy - 2.04 * e.ry + drop, e.rx * 1.25, e.ry * 1.02, 0, 0, Math.PI * 2);
    g.fill();
    g.restore();
  }

  /** Two front paws hooked over the lid's back edge, toes towards us. */
  private drawPaws(b: Behind, scale: number) {
    const reach = clamp01((this.story.rise - 0.55) / 0.45);
    if (reach <= 0) return;
    const g = this.front;
    const w = 56 * scale;
    for (const [i, p] of b.paws.entries()) {
      const side = i === 0 ? -1 : 1;
      const angle = Math.atan2(b.paws[1].y - b.paws[0].y, b.paws[1].x - b.paws[0].x);
      g.save();
      g.globalAlpha = Math.min(1, reach * 1.6);
      // They come up from behind the edge and settle on it.
      g.translate(p.x, p.y - (1 - reach) * w * 0.6);
      g.rotate(angle + side * 0.08);

      g.save();
      g.shadowColor = "rgba(0,0,0,0.55)";
      g.shadowBlur = w * 0.35 * this.dpr;
      g.shadowOffsetY = w * 0.12 * this.dpr;
      const mitt = new Path2D();
      mitt.ellipse(0, w * 0.06, w * 0.46, w * 0.3, 0, 0, Math.PI * 2);
      for (const tx of [-0.3, -0.1, 0.1, 0.3]) mitt.ellipse(tx * w, w * 0.26, w * 0.13, w * 0.12, 0, 0, Math.PI * 2);
      const fur = g.createLinearGradient(0, -w * 0.25, 0, w * 0.4);
      fur.addColorStop(0, "#2e231a");
      fur.addColorStop(1, "#1d1611");
      g.fillStyle = fur;
      g.fill(mitt, "nonzero");
      g.restore();

      // Between the toes, and the warm rim light along the top.
      g.strokeStyle = "rgba(0,0,0,0.45)";
      g.lineWidth = Math.max(1, w * 0.03);
      g.lineCap = "round";
      for (const tx of [-0.2, 0, 0.2]) {
        g.beginPath();
        g.moveTo(tx * w, w * 0.18);
        g.lineTo(tx * w, w * 0.34);
        g.stroke();
      }
      g.strokeStyle = `rgba(${RIM}, 0.32)`;
      g.lineWidth = Math.max(1, w * 0.035);
      g.beginPath();
      g.ellipse(0, w * 0.06, w * 0.44, w * 0.28, 0, Math.PI * 1.1, Math.PI * 1.9);
      g.stroke();
      g.restore();
    }
  }

  /** Fireflies in the dark around the desk; a few drift close, out of focus. */
  private drawFlies() {
    const night = this.story.night;
    if (night <= 0.01) return;
    const t = this.still ? 0 : this.time;
    for (const f of this.flies) {
      const g = f.front ? this.front : this.back;
      const x = (f.x + Math.sin(t * f.speed + f.phase) * 0.03) * this.W;
      const y = (f.y + Math.cos(t * f.speed * 0.8 + f.phase) * 0.025) * this.H;
      const twinkle = 0.45 + 0.55 * Math.max(0, Math.sin(t * (0.7 + f.speed) + f.phase * 3));
      const r = f.front ? f.r * 5 : f.r;
      const a = night * twinkle * (f.front ? 0.35 : 1);
      const glow = g.createRadialGradient(x, y, 0, x, y, r * 6);
      glow.addColorStop(0, `rgba(255, 214, 120, ${a})`);
      glow.addColorStop(0.25, `rgba(255, 190, 80, ${a * 0.35})`);
      glow.addColorStop(1, "rgba(255, 170, 60, 0)");
      g.fillStyle = glow;
      g.beginPath();
      g.arc(x, y, r * 6, 0, Math.PI * 2);
      g.fill();
    }
  }
}
