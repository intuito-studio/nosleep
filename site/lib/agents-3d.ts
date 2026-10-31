// Three AI agents at work on the shut lid, the proof that the Mac is still
// running: little glass toys, one coding at a laptop, one painting at an
// easel, one juggling mail, a document and a call. Built from primitives so
// every limb can move; the glass is a cheap shader (tinted glow, white rim,
// a sharp highlight) rather than a transmission pass, which would render the
// whole scene twice a frame.
import * as THREE from "three";
import { SVGLoader } from "three/examples/jsm/loaders/SVGLoader.js";
import { CLAUDE, CLAUDE_CODE, CODEX, GEMINI } from "./agent-logos";

const glassVertex = /* glsl */ `
  varying vec3 vNormal;
  varying vec3 vView;
  varying float vHeight;
  void main() {
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    vNormal = normalize(normalMatrix * normal);
    vView = normalize(-mv.xyz);
    vHeight = (modelMatrix * vec4(position, 1.0)).y;
    gl_Position = projectionMatrix * mv;
  }
`;

const glassFragment = /* glsl */ `
  uniform vec3 uTint;
  uniform vec3 uTint2;
  uniform float uOpacity;
  uniform float uGlow;
  uniform float uRainbow;
  varying vec3 vNormal;
  varying vec3 vView;
  varying float vHeight;
  void main() {
    vec3 n = normalize(vNormal);
    vec3 v = normalize(vView);
    if (!gl_FrontFacing) n = -n;
    float ndv = clamp(dot(n, v), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 2.6);
    // A second tint, blended by height in the world, for the gradient figure.
    vec3 tint = mix(uTint, uTint2, smoothstep(0.45, 0.95, vHeight));
    // Gemini's star: blue, with red, yellow and green washing in from the
    // left, red above, green below. Here by the surface's facing.
    float left = clamp(-n.x, 0.0, 1.0);
    float a = atan(n.y, -n.x);
    vec3 side = a > 0.0
      ? mix(vec3(0.98, 0.74, 0.07), vec3(0.98, 0.27, 0.26), clamp(a / 0.9, 0.0, 1.0))
      : mix(vec3(0.98, 0.74, 0.07), vec3(0.03, 0.73, 0.38), clamp(-a / 0.9, 0.0, 1.0));
    tint = mix(tint, side, left * 0.8 * uRainbow);
    // Lit from within: the middle glows, the edge goes pale and bright.
    vec3 c = tint * (0.42 + 0.7 * ndv) * uGlow;
    c += mix(tint, vec3(1.0), 0.35) * fres * 0.9;
    // One soft key light up and to the left, as in a studio shot.
    vec3 l = normalize(vec3(-0.45, 0.75, 0.55));
    vec3 h = normalize(l + v);
    float nh = max(dot(n, h), 0.0);
    c += vec3(1.0) * (pow(nh, 90.0) * 1.6 + pow(nh, 14.0) * 0.12);
    gl_FragColor = vec4(c, uOpacity);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }
`;

function glass(tint: string, tint2 = tint, glow = 1, rainbow = 0) {
  return new THREE.ShaderMaterial({
    vertexShader: glassVertex,
    fragmentShader: glassFragment,
    uniforms: {
      uTint: { value: new THREE.Color(tint) },
      uTint2: { value: new THREE.Color(tint2) },
      uOpacity: { value: 1 },
      uGlow: { value: glow },
      uRainbow: { value: rainbow },
    },
    transparent: false,
    // Its own colours are the picture: ACES would grey the tint.
    toneMapped: false,
  });
}

function canvasTexture(w: number, h: number, draw: (g: CanvasRenderingContext2D) => void) {
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  draw(c.getContext("2d")!);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}

function roundRect(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  g.beginPath();
  g.roundRect(x, y, w, h, r);
}

/** Solid once shown: the toys are only see-through while they pop in. */
function fade(m: THREE.ShaderMaterial, opacity: number) {
  m.uniforms.uOpacity.value = opacity;
  m.transparent = opacity < 0.999;
}

const backOut = (t: number) => 1 + 2.4 * (t - 1) ** 3 + 1.4 * (t - 1) ** 2;
const clamp01 = (t: number) => Math.min(1, Math.max(0, t));
/** The figures are modelled half a unit tall; on the lid they stand this much taller. */
const SIZE = 1.6;

type Figure = {
  root: THREE.Group;
  body: THREE.Group;
  head: THREE.Mesh;
  armL: THREE.Group;
  armR: THREE.Group;
  materials: THREE.ShaderMaterial[];
};

export class LidAgents {
  readonly group = new THREE.Group();
  private figures: Figure[] = [];
  private disposables: { dispose(): void }[] = [];
  private codeLines: THREE.Mesh[] = [];
  private tiles: THREE.Mesh[] = [];
  private brush!: THREE.Group;
  private shown = 0;
  private badges: THREE.MeshBasicMaterial[] = [];
  private critter = new THREE.Group();
  private critterMaterial!: THREE.ShaderMaterial;

  // Shared shapes, scaled per part.
  private sphere = new THREE.SphereGeometry(1, 40, 28);
  private capsule = new THREE.CapsuleGeometry(1, 1, 8, 20);

  constructor() {
    this.disposables.push(this.sphere, this.capsule);
    const claude = this.figure("#e0805c", "#e0805c");
    // Codex is blue; Gemini is its star's blue with the rainbow at its edge.
    const gpt = this.figure("#3d63ff", "#6f8bff");
    const gemini = this.figure("#3186ff", "#3186ff", 1);

    // A triangle on the lid: one at the back, two in front.
    claude.root.position.set(0.05, 0, 0.98);
    gpt.root.position.set(-0.74, 0, 1.6);
    gemini.root.position.set(0.74, 0, 1.6);
    claude.root.rotation.y = 0;
    gpt.root.rotation.y = 0.42;
    gemini.root.rotation.y = -0.18;

    this.badge(claude, CLAUDE, "evenodd");
    this.badge(gpt, CODEX, "evenodd");
    this.badge(gemini, GEMINI);
    this.laptop(claude);
    this.easel(gpt);
    this.juggle(gemini);
    for (const f of [claude, gpt, gemini]) this.group.add(f.root);
    this.claudeCode();
    this.figures = [claude, gpt, gemini];
    this.group.visible = false;
  }

  /** One glass toy: a big round head, a round body, stubby limbs. */
  private figure(tint: string, tint2: string, rainbow = 0): Figure {
    const mat = glass(tint, tint2, 1, rainbow);
    const limb = glass(tint, tint2, 0.9, rainbow);
    const root = new THREE.Group();
    const body = new THREE.Group();
    root.add(body);

    const glow = new THREE.Mesh(
      new THREE.PlaneGeometry(0.62, 0.62),
      new THREE.MeshBasicMaterial({
        map: this.glowTexture(),
        color: tint,
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        toneMapped: false,
      }),
    );
    glow.rotation.x = -Math.PI / 2;
    glow.position.y = 0.003;
    root.add(glow);
    this.disposables.push(glow.geometry, glow.material as THREE.Material);

    const part = (geo: THREE.BufferGeometry, m: THREE.Material, s: [number, number, number], p: [number, number, number]) => {
      const mesh = new THREE.Mesh(geo, m);
      mesh.scale.set(...s);
      mesh.position.set(...p);
      return mesh;
    };
    // Legs and feet.
    for (const x of [-0.045, 0.045]) {
      body.add(part(this.capsule, limb, [0.034, 0.03, 0.034], [x, 0.07, 0]));
      body.add(part(this.sphere, limb, [0.043, 0.03, 0.05], [x, 0.03, 0.012]));
    }
    // Torso: a soft pear.
    body.add(part(this.sphere, mat, [0.095, 0.105, 0.085], [0, 0.17, 0]));
    // Head: big and round, the toy's whole character.
    const head = part(this.sphere, mat, [0.13, 0.13, 0.13], [0, 0.375, 0]);
    body.add(head);

    // Arms hang from shoulder pivots, so a rotation swings the whole arm.
    const arm = (side: number) => {
      const pivot = new THREE.Group();
      pivot.position.set(side * 0.085, 0.235, 0);
      const upper = part(this.capsule, limb, [0.028, 0.06, 0.028], [0, -0.055, 0]);
      const hand = part(this.sphere, limb, [0.034, 0.034, 0.034], [0, -0.12, 0]);
      pivot.add(upper, hand);
      body.add(pivot);
      return pivot;
    };
    const armL = arm(-1);
    const armR = arm(1);
    this.disposables.push(mat, limb);
    return { root, body, head, armL, armR, materials: [mat, limb] };
  }

  /**
   * The agent's mark on the front of its head, its face: a patch of a sphere
   * just outside the head, so it curves with it, tipped up toward the
   * camera above the lid.
   */
  private badge(f: Figure, d: string, rule: CanvasFillRule = "nonzero") {
    const map = canvasTexture(256, 256, (g) => {
      g.translate(128, 128);
      g.scale(8.6, 8.6);
      g.translate(-12, -12);
      g.shadowColor = "rgba(255, 255, 255, 0.7)";
      g.shadowBlur = 18;
      g.fillStyle = "#ffffff";
      g.fill(new Path2D(d), rule);
    });
    const span = 1.3;
    const lift = 0.36;
    const geometry = new THREE.SphereGeometry(1.012, 24, 24, Math.PI / 2 - span / 2, span, Math.PI / 2 - lift - span / 2, span);
    const material = new THREE.MeshBasicMaterial({ map, transparent: true, depthWrite: false, toneMapped: false });
    f.head.add(new THREE.Mesh(geometry, material));
    this.badges.push(material);
    this.disposables.push(map, geometry, material);
  }

  /**
   * Claude Code's critter, standing on its own beside Claude: its mark cut
   * from the SVG and extruded into a little glass block creature.
   */
  private claudeCode() {
    const svg = new SVGLoader().parse(`<svg viewBox="0 0 24 24"><path d="${CLAUDE_CODE}"/></svg>`);
    const shapes = svg.paths.flatMap((p) => SVGLoader.createShapes(p));
    const geometry = new THREE.ExtrudeGeometry(shapes, {
      depth: 3.2,
      bevelEnabled: true,
      bevelSize: 0.35,
      bevelThickness: 0.45,
      bevelSegments: 3,
    });
    // SVG y runs down: flip it, stand it on its feet, centre it.
    geometry.scale(1, -1, 1);
    geometry.computeBoundingBox();
    const box = geometry.boundingBox!;
    geometry.translate(-(box.min.x + box.max.x) / 2, -box.min.y, -(box.min.z + box.max.z) / 2);
    geometry.computeVertexNormals();
    this.critterMaterial = glass("#e0805c", "#e8936f");
    const mesh = new THREE.Mesh(geometry, this.critterMaterial);
    // About half Claude's height.
    mesh.scale.setScalar(0.012);
    this.critter.add(mesh);
    this.critter.position.set(0.42, 0, 0.8);
    this.critter.rotation.y = -0.12;
    this.group.add(this.critter);
    this.disposables.push(geometry, this.critterMaterial);
  }

  private glowTexture() {
    const t = canvasTexture(128, 128, (g) => {
      const r = g.createRadialGradient(64, 64, 0, 64, 64, 64);
      r.addColorStop(0, "rgba(255,255,255,0.55)");
      r.addColorStop(0.45, "rgba(255,255,255,0.18)");
      r.addColorStop(1, "rgba(255,255,255,0)");
      g.fillStyle = r;
      g.fillRect(0, 0, 128, 128);
    });
    this.disposables.push(t);
    return t;
  }

  /** Claude: a little glass laptop held at the waist, code rising off it. */
  private laptop(f: Figure) {
    const shell = glass("#f3b49a", "#f3b49a", 0.8);
    const kit = new THREE.Group();
    kit.position.set(0, 0.2, 0.13);
    const base = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.012, 0.12), shell);
    const lid = new THREE.Group();
    lid.position.set(0, 0.006, 0.06);
    const back = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.13, 0.008), shell);
    back.position.y = 0.065;
    lid.add(back);
    // The screen faces the figure; the viewer reads the code through the glass.
    const code = canvasTexture(256, 160, (g) => {
      g.fillStyle = "#2a130b";
      roundRect(g, 0, 0, 256, 160, 14);
      g.fill();
      const rows: [number, number, string][] = [
        [16, 120, "#ffb38f"], [30, 80, "#ffd9c7"], [30, 140, "#ff8a5c"], [44, 60, "#ffd9c7"],
        [44, 110, "#ffb38f"], [30, 90, "#ff8a5c"], [16, 70, "#ffd9c7"], [16, 130, "#ffb38f"],
      ];
      rows.forEach(([x, w, c], i) => {
        g.fillStyle = c;
        roundRect(g, x, 14 + i * 17, w, 8, 4);
        g.fill();
      });
    });
    const screen = new THREE.Mesh(
      new THREE.PlaneGeometry(0.18, 0.112),
      new THREE.MeshBasicMaterial({ map: code, toneMapped: false, side: THREE.DoubleSide, transparent: true, opacity: 0.95 }),
    );
    screen.position.set(0, 0.065, -0.005);
    screen.rotation.y = Math.PI;
    lid.add(screen);
    lid.rotation.x = -0.35;
    kit.add(base, lid);
    // Turned to face the figure, so the screen is on the far side from us.
    kit.rotation.y = Math.PI;
    f.body.add(kit);
    this.disposables.push(shell, base.geometry, back.geometry, screen.geometry, screen.material as THREE.Material, code);

    // Short lines of code drifting up off the screen.
    const line = canvasTexture(128, 24, (g) => {
      g.fillStyle = "#ffffff";
      roundRect(g, 2, 4, 124, 16, 8);
      g.fill();
    });
    this.disposables.push(line);
    const lineGeo = new THREE.PlaneGeometry(1, 0.018);
    this.disposables.push(lineGeo);
    for (let i = 0; i < 4; i++) {
      const m = new THREE.MeshBasicMaterial({
        map: line,
        color: ["#ffb38f", "#ffe0d0", "#ff8a5c", "#ffd0b8"][i],
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        toneMapped: false,
      });
      const mesh = new THREE.Mesh(lineGeo, m);
      mesh.scale.x = [0.08, 0.05, 0.1, 0.06][i];
      f.root.add(mesh);
      this.codeLines.push(mesh);
      this.disposables.push(m);
    }
  }

  /** ChatGPT: a glass easel with a glowing landscape, one brush in hand. */
  private easel(f: Figure) {
    const frame = glass("#a9bcff", "#a9bcff", 0.8);
    const stand = new THREE.Group();
    stand.position.set(0.22, 0, 0.02);
    stand.rotation.y = -0.75;
    const leg = new THREE.CylinderGeometry(0.008, 0.008, 0.42, 8);
    for (const [x, rz] of [[-0.07, -0.12], [0.07, 0.12]] as const) {
      const m = new THREE.Mesh(leg, frame);
      m.position.set(x, 0.2, 0);
      m.rotation.z = rz;
      stand.add(m);
    }
    const mast = new THREE.Mesh(leg, frame);
    mast.position.set(0, 0.22, -0.05);
    mast.rotation.x = -0.18;
    stand.add(mast);
    const ledge = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.014, 0.03), frame);
    ledge.position.set(0, 0.17, 0.01);
    stand.add(ledge);
    const board = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.18, 0.012), frame);
    board.position.set(0, 0.27, 0.0);
    stand.add(board);
    const picture = canvasTexture(256, 208, (g) => {
      const sky = g.createLinearGradient(0, 0, 0, 208);
      sky.addColorStop(0, "#14246b");
      sky.addColorStop(1, "#5a86ff");
      g.fillStyle = sky;
      roundRect(g, 0, 0, 256, 208, 12);
      g.fill();
      g.fillStyle = "#eef2ff";
      g.beginPath();
      g.arc(180, 62, 24, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = "#bccbff";
      g.beginPath();
      g.moveTo(10, 190);
      g.lineTo(90, 80);
      g.lineTo(150, 160);
      g.lineTo(190, 115);
      g.lineTo(248, 190);
      g.closePath();
      g.fill();
    });
    const art = new THREE.Mesh(
      new THREE.PlaneGeometry(0.196, 0.156),
      new THREE.MeshBasicMaterial({ map: picture, toneMapped: false }),
    );
    art.position.set(0, 0.27, 0.0075);
    stand.add(art);
    f.root.add(stand);
    this.disposables.push(frame, leg, ledge.geometry, board.geometry, art.geometry, art.material as THREE.Material, picture);

    // The brush, in the right hand, reaching for the canvas.
    this.brush = new THREE.Group();
    const handle = new THREE.Mesh(new THREE.CylinderGeometry(0.006, 0.006, 0.14, 8), new THREE.MeshBasicMaterial({ color: "#7a4b2a" }));
    handle.position.y = -0.05;
    const tip = new THREE.Mesh(new THREE.ConeGeometry(0.01, 0.03, 10), new THREE.MeshBasicMaterial({ color: "#cfd9ff", toneMapped: false }));
    tip.position.y = -0.135;
    tip.rotation.x = Math.PI;
    this.brush.add(handle, tip);
    this.brush.position.set(0, -0.12, 0);
    this.brush.rotation.x = -1.2;
    f.armR.add(this.brush);
    this.disposables.push(handle.geometry, handle.material as THREE.Material, tip.geometry, tip.material as THREE.Material);
  }

  /** Gemini: mail, a page and a call, kept in the air. */
  private juggle(f: Figure) {
    const icon = (draw: (g: CanvasRenderingContext2D) => void) =>
      canvasTexture(128, 128, (g) => {
        const bg = g.createLinearGradient(0, 0, 128, 128);
        bg.addColorStop(0, "rgba(140,170,255,0.95)");
        bg.addColorStop(1, "rgba(170,110,250,0.95)");
        g.fillStyle = bg;
        roundRect(g, 4, 4, 120, 120, 28);
        g.fill();
        g.strokeStyle = "rgba(255,255,255,0.9)";
        g.lineWidth = 4;
        roundRect(g, 6, 6, 116, 116, 26);
        g.stroke();
        g.fillStyle = "#ffffff";
        g.strokeStyle = "#ffffff";
        draw(g);
      });
    const textures = [
      icon((g) => {
        // Envelope.
        roundRect(g, 26, 38, 76, 52, 8);
        g.fill();
        g.strokeStyle = "#6f7ff5";
        g.lineWidth = 6;
        g.beginPath();
        g.moveTo(30, 44);
        g.lineTo(64, 70);
        g.lineTo(98, 44);
        g.stroke();
      }),
      icon((g) => {
        // A page with lines.
        roundRect(g, 36, 22, 56, 84, 8);
        g.fill();
        g.fillStyle = "#7b86f5";
        for (let i = 0; i < 4; i++) {
          roundRect(g, 46, 38 + i * 15, i === 3 ? 22 : 36, 6, 3);
          g.fill();
        }
      }),
      icon((g) => {
        // A video call: a camera body and its lens.
        roundRect(g, 22, 40, 60, 48, 10);
        g.fill();
        g.beginPath();
        g.moveTo(86, 56);
        g.lineTo(106, 44);
        g.lineTo(106, 84);
        g.lineTo(86, 72);
        g.closePath();
        g.fill();
      }),
    ];
    const geo = new THREE.PlaneGeometry(0.1, 0.1);
    this.disposables.push(geo, ...textures);
    for (const map of textures) {
      const m = new THREE.MeshBasicMaterial({ map, transparent: true, toneMapped: false, side: THREE.DoubleSide, depthWrite: false });
      const tile = new THREE.Mesh(geo, m);
      f.root.add(tile);
      this.tiles.push(tile);
      this.disposables.push(m);
    }
    f.armL.rotation.z = -2.3;
    f.armR.rotation.z = 2.3;
  }

  /** 0 hidden, 1 all three on the lid. */
  show(t: number) {
    this.shown = t;
    this.group.visible = t > 0.001;
    this.figures.forEach((f, i) => {
      const s = clamp01((t - i * 0.18) / 0.64);
      const k = s <= 0 ? 0.0001 : backOut(s);
      f.root.scale.setScalar(Math.max(k, 0.0001) * SIZE);
      for (const m of f.materials) fade(m, clamp01(s * 2));
      this.badges[i].opacity = clamp01(s * 2) * 0.95;
    });
    // The critter pops up just after Claude.
    const c = clamp01((t - 0.1) / 0.64);
    this.critter.scale.setScalar(Math.max(c <= 0 ? 0.0001 : backOut(c), 0.0001) * SIZE);
    fade(this.critterMaterial, clamp01(c * 2));
  }

  update(time: number) {
    if (!this.group.visible) return;
    const [claude, gpt, gemini] = this.figures;
    // The critter hops in place, squashing a little as it lands.
    const hop = Math.abs(Math.sin(time * 3.4));
    const body = this.critter.children[0];
    body.position.y = hop * 0.035;
    body.scale.set(0.012 * (1 + (1 - hop) * 0.08), 0.012 * (1 - (1 - hop) * 0.1), 0.012);
    for (const [i, f] of this.figures.entries()) {
      f.body.position.y = Math.abs(Math.sin(time * 2.2 + i * 1.7)) * 0.012;
      f.head.rotation.z = Math.sin(time * 1.3 + i) * 0.06;
    }

    // Claude types: both forearms forward over the keys, tapping in turn.
    const tap = time * 13;
    claude.armL.rotation.set(-1.15 + Math.sin(tap) * 0.13, 0, 0.25);
    claude.armR.rotation.set(-1.15 + Math.sin(tap + Math.PI) * 0.13, 0, -0.25);
    claude.head.rotation.x = 0.18 + Math.sin(time * 4) * 0.03;
    this.codeLines.forEach((m, i) => {
      const p = (time * 0.32 + i / this.codeLines.length) % 1;
      m.position.set([-0.17, -0.2, -0.15, -0.22][i], 0.26 + p * 0.24, 0.14);
      (m.material as THREE.MeshBasicMaterial).opacity = Math.sin(p * Math.PI) * 0.9 * clamp01(this.shown * 3 - 2);
    });

    // ChatGPT paints: the brush arm reaches out to the canvas and dabs.
    const stroke = Math.sin(time * 3.1);
    gpt.armR.rotation.set(-0.6 + stroke * 0.18, 0.4, 0.9 + stroke * 0.25);
    gpt.armL.rotation.set(0.1, 0, -0.25 + Math.sin(time * 1.6) * 0.06);
    gpt.body.rotation.z = Math.sin(time * 1.5) * 0.04;
    // It glances back over its shoulder at us, so its mark shows.
    gpt.head.rotation.y = -0.3;

    // Gemini juggles: hands up in turn, three tiles looping overhead.
    gemini.armL.rotation.set(0, 0, -2.3 + Math.sin(time * 4.4) * 0.3);
    gemini.armR.rotation.set(0, 0, 2.3 + Math.sin(time * 4.4 + Math.PI) * 0.3);
    this.tiles.forEach((tile, i) => {
      const a = time * 2.2 + (i * Math.PI * 2) / 3;
      tile.position.set(Math.cos(a) * 0.17, 0.5 + Math.sin(a) * 0.08, 0.2);
      tile.rotation.set(0, 0, Math.sin(a) * 0.25);
    });
  }

  dispose() {
    for (const d of this.disposables) d.dispose();
  }
}
