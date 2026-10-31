// The hero's laptop, a 14-inch MacBook Pro to scale. The page opens inside its
// screen; scrolling pulls the camera back until the whole Mac is in frame,
// then closes the lid. As it closes, the picture holds still in the room and
// frosts and fades from the far edge, sharp at the hinge, as Mac Duo does it.
// The screen's light on the desk narrows to nothing with it.
import * as THREE from "three";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { LidAgents } from "./agents-3d";
import { SCREEN_H, SCREEN_W, drawDeck, drawScreen, drawScreenCat, loadWallpaper } from "./screen";
import { minutesLeft } from "./session";

export type LaptopState = {
  /** 0 the camera inside the screen, 1 the whole open laptop in frame. */
  zoom: number;
  /** 0 open, 1 shut. */
  lid: number;
  /** 0 the open laptop's view, 1 the view from above, over the shut lid. */
  view: number;
  /** 0 none, 1 the three agents at work on the shut lid. */
  agents: number;
};

export type Point = { x: number; y: number };

// 14-inch MacBook Pro: 312.6 × 221.2 × 15.5 mm, a 14.2-inch 3024 × 1964
// display. One unit is 312.6 / 3 mm, so the width is 3.
const MM = 3 / 312.6;
const WIDTH = 312.6 * MM;
const DEPTH = 221.2 * MM;
const BASE = 10.5 * MM;
const LID = 5 * MM;
const CORNER = 11 * MM;
const LID_HEIGHT = 216 * MM;
const DIAGONAL = 14.2 * 25.4;
const SCREEN_WIDTH = (DIAGONAL * 3024) / Math.hypot(3024, 1964) * MM;
const SCREEN_HEIGHT = (SCREEN_WIDTH * 1964) / 3024;
const SIDE_BEZEL = (WIDTH - SCREEN_WIDTH) / 2;
/** The display sits a side bezel's width below the lid's top edge. */
const SCREEN_Y = LID_HEIGHT - SIDE_BEZEL - SCREEN_HEIGHT / 2;
const OPEN = -0.36;
const SHUT = Math.PI / 2;
/** The hinge angle, open: 90° plus the lid's lean back. */
const OPEN_DEGREES = 90 - THREE.MathUtils.radToDeg(OPEN);

// What NoSleep does on the way down, by hinge angle, as the app will: its
// paws come up once the lid passes upright. From 92° the picture is held
// still in the room while the lid folds around it, frosting and darkening
// from the far edge, full strength 58° later (Mac Duo's "Duo" look); it goes
// fully dark only at the very end, before macOS turns the display off.
const PAWS_FROM = 98;
const PAWS_UP = 84;
const FOLD_FROM = 92;
const FOLD_SPAN = 58;
const DARK_FROM = 16;
const DARK_AT = 3;
// The last stretch: from 22° the light of the cat's eyes spreads out over
// the whole screen, there by 10°, so a warm glow leaks from the gap until
// the lid is down. The eyes stay on top of it.
const FLOOD_FROM = 22;
const FLOOD_FULL = 10;
const clamp01 = (t: number) => Math.min(1, Math.max(0, t));
const backOut = (t: number) => 1 + 2.4 * (t - 1) ** 3 + 1.4 * (t - 1) ** 2;
const FOV = 30;

/**
 * Where the frozen picture's corners land on the glass with the lid at
 * `angle`, in screen uv (0–1, y up from the hinge edge): bottom-left,
 * bottom-right, top-right, top-left. The picture was frozen at FOLD_FROM;
 * each corner is what an eye in front of the screen then sees of it through
 * the glass now. Ported from Mac Duo's FoldGeometry (github.com/ninobc/mac-duo,
 * MIT), with its "Duo" eye: 2.4 screen heights out, level with the centre.
 */
function foldCorners(angle: number): [number, number][] {
  const aspect = SCREEN_W / SCREEN_H;
  const rad = THREE.MathUtils.degToRad;
  const separation = Math.min(Math.max(FOLD_FROM - angle, 0), 88);
  const lid = rad(angle);
  const pic = rad(angle + separation);
  const start = rad(FOLD_FROM);
  const eye = {
    x: aspect / 2,
    y: Math.sin(start) / 2 - Math.cos(start) * 2.4,
    z: Math.cos(start) / 2 + Math.sin(start) * 2.4,
  };
  const n = { y: -Math.cos(lid), z: Math.sin(lid) };
  const nDotEye = n.y * eye.y + n.z * eye.z;
  const project = (px: number, ph: number): [number, number] => {
    const d = { x: px - eye.x, y: ph * Math.sin(pic) - eye.y, z: ph * Math.cos(pic) - eye.z };
    const nDotD = n.y * d.y + n.z * d.z;
    const t = Math.abs(nDotD) < 1e-9 ? 1 : Math.max(-nDotEye / nDotD, 1e-3);
    const hit = { x: eye.x + t * d.x, y: eye.y + t * d.y, z: eye.z + t * d.z };
    return [hit.x / aspect, hit.y * Math.sin(lid) + hit.z * Math.cos(lid)];
  };
  return [project(0, 0), project(aspect, 0), project(aspect, 1), project(0, 1)];
}

/** The homography taking the unit square onto a quad (Heckbert's square-to-quad). */
function squareToQuad(q: [number, number][]) {
  const [[x0, y0], [x1, y1], [x2, y2], [x3, y3]] = q;
  const sx = x0 - x1 + x2 - x3;
  const sy = y0 - y1 + y2 - y3;
  const m = new THREE.Matrix3();
  if (Math.abs(sx) < 1e-12 && Math.abs(sy) < 1e-12) {
    return m.set(x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0, 0, 1);
  }
  const dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
  const den = dx1 * dy2 - dx2 * dy1;
  const g = (sx * dy2 - dx2 * sy) / den;
  const h = (dx1 * sy - sx * dy1) / den;
  return m.set(x1 - x0 + g * x1, x3 - x0 + h * x3, x0, y1 - y0 + g * y1, y3 - y0 + h * y3, y0, g, h, 1);
}


const glowVertex = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

// Light from the screen pooling on the desk in front of it. As the lid comes
// down the pool is pressed towards the hinge and fades, the way the real
// light does.
const glowFragment = /* glsl */ `
  uniform float uOpen;
  uniform vec3 uColor;
  varying vec2 vUv;
  void main() {
    float reach = mix(0.04, 0.26, uOpen);
    vec2 p = vec2(vUv.x - 0.5, (vUv.y - (0.66 - reach * 0.55)) / reach);
    p.x /= mix(0.32, 0.5, uOpen);
    float g = smoothstep(1.0, 0.0, length(p));
    g = g * g * uOpen;
    gl_FragColor = vec4(uColor * g * 0.3, g);
  }
`;

// Folded into the screen's MeshBasicMaterial, in place of its plain texture
// read. Blur is mip levels, a ring of taps to round off their blockiness.
const frostUniforms = /* glsl */ `
  uniform mat3 uToPicture;
  uniform float uTopEdge;
  uniform float uBlur;
  uniform float uDim;
  uniform float uDark;
  uniform float uPaws;
  uniform sampler2D uPawMap;
  uniform sampler2D uPawGlass;
  uniform sampler2D uEyeMap;
  uniform vec2 uEyeL;
  uniform vec2 uEyeR;
  uniform float uFlood;
  vec3 frosted(vec2 uv, float lod, float spread) {
    float r = exp2(lod) * spread / ${SCREEN_W}.0;
    vec3 c = textureLod(map, uv, lod).rgb * 2.0;
    for (int i = 0; i < 8; i++) {
      float a = float(i) * 0.7854 + 0.39;
      c += textureLod(map, uv + vec2(cos(a), sin(a) * 1.54) * r, lod).rgb;
    }
    return c / 10.0;
  }
`;

const frostFragment = /* glsl */ `
  vec2 suv = vMapUv;
  vec4 sharp = texture2D(map, suv);
  // Each glass pixel looks up the frozen picture through the fold. Rows
  // above the picture's far edge carry that edge's light, fading out, so
  // there is never a line where the picture ends.
  float above = max(suv.y - uTopEdge, 0.0);
  vec3 m = uToPicture * vec3(suv.x, min(suv.y, uTopEdge), 1.0);
  vec2 q = m.xy / m.z;
  vec2 qc = clamp(q, 0.0, 1.0);
  // Past the picture's sides, as they draw in, its light leaks into the dark.
  float outside = length(q - qc);
  // Height above the hinge in the picture: frost and dark follow it, so the
  // far edge dissolves first and the hinge stays readable.
  float g = qc.y;
  float radius = uBlur * g * ${((125 * SCREEN_W) / 1512).toFixed(1)};
  vec3 c = radius < 0.75 ? texture2D(map, qc).rgb : frosted(qc, clamp(log2(max(radius, 1.0)), 0.0, 8.0), 0.9);
  // Dimming in linear light, so the far edge fades into the dark rather
  // than going grey; the hinge sinks a little too.
  float dim = uDim * (0.18 + 0.82 * smoothstep(0.0, 0.55, g));
  c *= pow(1.0 - dim, 2.1);
  c *= exp(-pow(above / 0.22, 1.4)) * exp(-pow(outside / 0.05, 1.3));
  // And at the very end, dark, the far edge first.
  float dark = 1.0 - smoothstep(0.0, 1.0, uDark * (1.3 + (suv.y - 0.5) * 0.6));
  c *= dark;
  // Grain, so the dark gradient does not band.
  c += (fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * (2.5 / 255.0) * uDim;
  // NoSleep's paws sit on the glass, not under the frost. They are glass
  // themselves: the desktop behind, blurred, brighter and a little richer,
  // dimming with the screen; then their rim and beans on top.
  vec2 puv = vec2(suv.x, suv.y + (1.0 - uPaws));
  bool inPaw = puv.y < 1.0;
  vec4 paw = inPaw ? texture2D(uPawMap, puv) : vec4(0.0);
  float body = inPaw ? texture2D(uPawGlass, puv).a : 0.0;
  float gone = dark;
  // Linear light, so the white haze is a small number.
  vec3 pg = frosted(qc, 5.0, 1.6) * pow(1.0 - dim, 2.1);
  pg = mix(vec3(dot(pg, vec3(0.2126, 0.7152, 0.0722))), pg, 1.5) * 1.7;
  pg = mix(pg, vec3(1.0), 0.012);
  c = mix(c, pg * gone, body);
  c = mix(c, paw.rgb * gone, paw.a);
  // The flood: amber from each eye, deepening to orange at the edges, its
  // front soft, until it fills the screen; then the eyes again, on top.
  if (uFlood > 0.0) {
    vec2 rise = vec2(0.0, 1.0 - uPaws);
    vec2 aspect = vec2(${(SCREEN_W / SCREEN_H).toFixed(4)}, 1.0);
    float d = min(length((suv - uEyeL + rise) * aspect), length((suv - uEyeR + rise) * aspect));
    float r = mix(0.05, 2.3, uFlood);
    float cover = 1.0 - smoothstep(r * 0.45, r, d);
    vec3 warm = mix(vec3(1.0, 0.46, 0.03), vec3(1.0, 0.14, 0.0), smoothstep(0.0, 1.4, d));
    c = mix(c, warm, cover);
    vec4 eye = inPaw ? texture2D(uEyeMap, puv) : vec4(0.0);
    c = mix(c, eye.rgb, eye.a * smoothstep(0.0, 0.3, uFlood));
  }
  diffuseColor *= vec4(c, sharp.a);
`;

const shadowFragment = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vec2 p = (vUv - 0.5) * vec2(1.0, 1.35);
    float a = smoothstep(0.5, 0.18, length(p)) * 0.85;
    gl_FragColor = vec4(0.0, 0.0, 0.0, a);
  }
`;

function roundedRect(w: number, h: number, r: number) {
  const s = new THREE.Shape();
  const x = -w / 2;
  const y = -h / 2;
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y);
  s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + h - r);
  s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  s.lineTo(x + r, y + h);
  s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r);
  s.quadraticCurveTo(x, y, x + r, y);
  return s;
}

/** A slab with rounded corners and softened edges, `thick` deep along +z. */
function slab(w: number, h: number, r: number, thick: number) {
  const bevel = Math.min(0.012, thick / 3);
  const g = new THREE.ExtrudeGeometry(roundedRect(w - bevel * 2, h - bevel * 2, r - bevel), {
    depth: thick - bevel * 2,
    bevelEnabled: true,
    bevelThickness: bevel,
    bevelSize: bevel,
    bevelSegments: 4,
    curveSegments: 18,
  });
  g.translate(0, 0, bevel);
  return g;
}

/** A flat rounded rectangle whose UVs run 0–1 across its bounds, for a texture. */
function panel(w: number, h: number, r: number) {
  const g = new THREE.ShapeGeometry(roundedRect(w, h, r), 18);
  const pos = g.attributes.position;
  const uv = g.attributes.uv;
  for (let i = 0; i < pos.count; i++) uv.setXY(i, pos.getX(i) / w + 0.5, pos.getY(i) / h + 0.5);
  return g;
}

const smooth = (t: number) => t * t * (3 - 2 * t);

export class LaptopScene {
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private camera = new THREE.PerspectiveCamera(FOV, 1, 0.1, 60);
  private laptop = new THREE.Group();
  private hinge = new THREE.Group();
  private screenCanvas = document.createElement("canvas");
  private screenTexture: THREE.CanvasTexture;
  private screenMaterial: THREE.MeshBasicMaterial;
  private frost = {
    uToPicture: { value: new THREE.Matrix3() },
    uTopEdge: { value: 1 },
    uBlur: { value: 0 },
    uDim: { value: 0 },
    uDark: { value: 0 },
    uPaws: { value: 0 },
    uPawMap: { value: null as THREE.Texture | null },
    uPawGlass: { value: null as THREE.Texture | null },
    uEyeMap: { value: null as THREE.Texture | null },
    uEyeL: { value: new THREE.Vector2() },
    uEyeR: { value: new THREE.Vector2() },
    uFlood: { value: 0 },
  };
  private glow: THREE.ShaderMaterial;
  /** The eyes' light leaking out of the front gap as the lid comes down. */
  private leak = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.MeshBasicMaterial({
      color: "#ff9a2e",
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      toneMapped: false,
    }),
  );
  private screenLight = new THREE.PointLight("#9fb3ff", 0, 6, 1.6);
  private state: LaptopState = { zoom: 0, lid: 0, view: 0, agents: 0 };
  private agents = new LidAgents();
  private clock = new THREE.Clock();
  private pointer = { x: 0, y: 0 };
  /** Where the screen cat's pupils point, eased, and where they were last drawn. */
  private gaze = { x: 0, y: 0, drawnX: 0, drawnY: 0 };
  private catLook: (x: number, y: number) => void = () => {};
  private tilt = { x: 0, y: 0 };
  private frame = 0;
  private running = false;
  private shownMinutes = -1;
  private disposables: { dispose(): void }[] = [];

  constructor(private canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    // Clear, so the cat behind it shows through.
    this.renderer.setClearColor("#000000", 0);
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;

    const pmrem = new THREE.PMREMGenerator(this.renderer);
    const room = new RoomEnvironment();
    this.scene.environment = pmrem.fromScene(room, 0.04).texture;
    this.scene.environmentIntensity = 0.45;
    room.dispose();
    pmrem.dispose();

    // Space Black anodised aluminium.
    const metal = new THREE.MeshPhysicalMaterial({
      color: "#222326",
      metalness: 0.7,
      roughness: 0.42,
      clearcoat: 0.2,
      clearcoatRoughness: 0.5,
      envMapIntensity: 0.7,
    });

    const base = new THREE.Mesh(slab(WIDTH, DEPTH, CORNER, BASE), metal);
    base.rotation.x = -Math.PI / 2;

    const deckCanvas = document.createElement("canvas");
    deckCanvas.width = 1024;
    deckCanvas.height = Math.round((1024 * DEPTH) / WIDTH);
    drawDeck(deckCanvas.getContext("2d")!, deckCanvas.width, deckCanvas.height);
    const deckTexture = new THREE.CanvasTexture(deckCanvas);
    deckTexture.colorSpace = THREE.SRGBColorSpace;
    deckTexture.anisotropy = 8;
    const deckMaterial = new THREE.MeshStandardMaterial({ map: deckTexture, metalness: 0.55, roughness: 0.55 });
    const deck = new THREE.Mesh(panel(WIDTH - 0.03, DEPTH - 0.03, CORNER - 0.015), deckMaterial);
    deck.rotation.x = -Math.PI / 2;
    deck.position.y = BASE + 0.0006;

    // Lid, hinged at the back edge of the base, a hair above the deck.
    this.hinge.position.set(0, BASE + 0.003, -DEPTH / 2 + 0.035);
    const lidGeometry = slab(WIDTH, LID_HEIGHT, CORNER, LID);
    lidGeometry.translate(0, LID_HEIGHT / 2, -LID);
    const lid = new THREE.Mesh(lidGeometry, metal);
    // The black glass over the whole front, as on the real one.
    const glassMaterial = new THREE.MeshBasicMaterial({ color: "#040405" });
    const glassFront = new THREE.Mesh(panel(WIDTH - 0.012, LID_HEIGHT - 0.012, CORNER - 0.006), glassMaterial);
    glassFront.position.set(0, LID_HEIGHT / 2, 0.0006);

    this.screenCanvas.width = SCREEN_W;
    this.screenCanvas.height = SCREEN_H;
    this.screenTexture = new THREE.CanvasTexture(this.screenCanvas);
    this.screenTexture.colorSpace = THREE.SRGBColorSpace;
    this.screenTexture.anisotropy = 8;
    this.screenMaterial = new THREE.MeshBasicMaterial({ map: this.screenTexture, toneMapped: false });
    const pawCanvas = document.createElement("canvas");
    pawCanvas.width = 1024;
    pawCanvas.height = Math.round((1024 * SCREEN_H) / SCREEN_W);
    const screenCat = drawScreenCat(pawCanvas.getContext("2d")!, pawCanvas.width, pawCanvas.height);
    const pawShape = screenCat.shape;
    const pawTexture = new THREE.CanvasTexture(pawCanvas);
    pawTexture.colorSpace = THREE.SRGBColorSpace;
    const pawGlass = new THREE.CanvasTexture(pawShape);
    this.frost.uPawMap.value = pawTexture;
    const eyeTexture = new THREE.CanvasTexture(screenCat.eyeMap);
    eyeTexture.colorSpace = THREE.SRGBColorSpace;
    this.frost.uEyeMap.value = eyeTexture;
    this.frost.uEyeL.value.set(...screenCat.eyeCentres[0]);
    this.frost.uEyeR.value.set(...screenCat.eyeCentres[1]);
    this.disposables.push(eyeTexture);
    this.catLook = (x, y) => {
      screenCat.look(x, y);
      pawTexture.needsUpdate = true;
      eyeTexture.needsUpdate = true;
    };
    this.frost.uPawGlass.value = pawGlass;
    this.screenMaterial.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, this.frost);
      shader.fragmentShader = shader.fragmentShader
        .replace("void main() {", `${frostUniforms}\nvoid main() {`)
        .replace("#include <map_fragment>", frostFragment);
    };
    const screen = new THREE.Mesh(new THREE.PlaneGeometry(SCREEN_WIDTH, SCREEN_HEIGHT), this.screenMaterial);
    screen.position.set(0, SCREEN_Y, 0.0025);
    this.screenLight.position.set(0, LID_HEIGHT * 0.5, 0.6);
    this.hinge.add(lid, glassFront, screen, this.screenLight);
    // The agents stand on the lid's outside, which faces up once it is shut:
    // their up is the lid's outward normal, their front its far edge.
    this.agents.group.rotation.x = -Math.PI / 2;
    this.agents.group.position.z = -LID - 0.001;
    this.hinge.add(this.agents.group);

    this.glow = new THREE.ShaderMaterial({
      vertexShader: glowVertex,
      fragmentShader: glowFragment,
      uniforms: { uOpen: { value: 1 }, uColor: { value: new THREE.Color("#8ea2ff") } },
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    const glow = new THREE.Mesh(new THREE.PlaneGeometry(6, 6), this.glow);
    glow.rotation.x = -Math.PI / 2;
    glow.position.set(0, 0.0008, -DEPTH / 2 + 3);

    const shadowMaterial = new THREE.ShaderMaterial({
      vertexShader: glowVertex,
      fragmentShader: shadowFragment,
      transparent: true,
      depthWrite: false,
    });
    const shadow = new THREE.Mesh(new THREE.PlaneGeometry(WIDTH * 1.5, DEPTH * 1.5), shadowMaterial);
    shadow.rotation.x = -Math.PI / 2;
    shadow.position.y = 0.0004;

    // A soft bar of light: bright in the middle, gone at the ends and edges.
    const leakCanvas = document.createElement("canvas");
    leakCanvas.width = 256;
    leakCanvas.height = 64;
    const lg = leakCanvas.getContext("2d")!;
    const across = lg.createLinearGradient(0, 0, 256, 0);
    across.addColorStop(0, "rgba(255,255,255,0)");
    across.addColorStop(0.15, "rgba(255,255,255,1)");
    across.addColorStop(0.85, "rgba(255,255,255,1)");
    across.addColorStop(1, "rgba(255,255,255,0)");
    lg.fillStyle = across;
    lg.fillRect(0, 0, 256, 64);
    lg.globalCompositeOperation = "destination-in";
    const down = lg.createLinearGradient(0, 0, 0, 64);
    down.addColorStop(0, "rgba(0,0,0,0)");
    down.addColorStop(0.5, "rgba(0,0,0,1)");
    down.addColorStop(1, "rgba(0,0,0,0)");
    lg.fillStyle = down;
    lg.fillRect(0, 0, 256, 64);
    const leakMap = new THREE.CanvasTexture(leakCanvas);
    const leakMaterial = this.leak.material as THREE.MeshBasicMaterial;
    leakMaterial.map = leakMap;
    this.leak.visible = false;
    this.disposables.push(this.leak.geometry, leakMaterial, leakMap);

    this.laptop.add(shadow, glow, base, deck, this.hinge, this.leak);
    this.scene.add(this.laptop);

    const key = new THREE.DirectionalLight("#ffffff", 0.7);
    key.position.set(-3, 5, 2);
    const rim = new THREE.DirectionalLight("#ffb46b", 1.1);
    rim.position.set(4, 2, -4);
    this.scene.add(key, rim);

    this.disposables.push(
      base.geometry, lidGeometry, glassFront.geometry, screen.geometry, deck.geometry, glow.geometry,
      shadow.geometry, metal, glassMaterial, deckMaterial, deckTexture, this.screenMaterial, this.screenTexture, pawTexture, pawGlass,
      this.glow, shadowMaterial,
    );

    this.drawScreen();
    loadWallpaper(() => this.drawScreen());
    this.set(this.state);
    this.resize();
  }

  set(state: Partial<LaptopState>) {
    Object.assign(this.state, state);
    const { lid } = this.state;
    this.hinge.rotation.x = OPEN + (SHUT - OPEN) * lid;
    const angle = this.angle();
    const fold = clamp01((FOLD_FROM - angle) / FOLD_SPAN);
    this.frost.uBlur.value = fold ** 1.55;
    this.frost.uDim.value = fold ** 0.75;
    const quad = foldCorners(angle);
    this.frost.uToPicture.value.copy(squareToQuad(quad)).invert();
    this.frost.uTopEdge.value = Math.min(quad[2][1], quad[3][1], 1);
    this.frost.uDark.value = clamp01((DARK_FROM - angle) / (DARK_FROM - DARK_AT));
    this.frost.uPaws.value = backOut(clamp01((PAWS_FROM - angle) / (PAWS_FROM - PAWS_UP)));
    // NoSleep turns the display off when the lid closes, so the light goes too.
    const open = Math.max(0, 1 - lid * 1.08);
    const flood = smooth(clamp01((FLOOD_FROM - angle) / (FLOOD_FROM - FLOOD_FULL)));
    this.frost.uFlood.value = flood;
    // The flood's warm light spills out of the gap onto the desk, until shut.
    const spill = flood * clamp01(angle / 3);
    this.glow.uniforms.uOpen.value = Math.max(open, spill * 0.7) * this.state.zoom;
    this.glow.uniforms.uColor.value.set("#8ea2ff").lerp(new THREE.Color("#ff9a2e"), flood);
    this.agents.show(this.state.agents);
    this.screenLight.intensity = 2.2 * open + 1.6 * spill;
    this.screenLight.color.set("#9fb3ff").lerp(new THREE.Color("#ffa040"), flood);
    // The gap at the front, as the hinge sees it, with its light in it.
    const gap = LID_HEIGHT * Math.sin(THREE.MathUtils.degToRad(angle));
    this.leak.visible = spill > 0.001;
    this.leak.position.set(0, BASE + gap / 2, -DEPTH / 2 + 0.035 + LID_HEIGHT * Math.cos(THREE.MathUtils.degToRad(angle)) + 0.01);
    this.leak.scale.set(WIDTH * 1.05, gap + 0.12, 1);
    (this.leak.material as THREE.MeshBasicMaterial).opacity = spill * 0.9;
    this.placeCamera();
  }

  /** The hinge angle in degrees: about 110 open, 0 shut. */
  angle() {
    return OPEN_DEGREES * (1 - this.state.lid);
  }

  /** Where the screen is: its centre and height on the canvas, in CSS pixels. */
  screenRect() {
    const top = this.project(new THREE.Vector3(0, SCREEN_Y + SCREEN_HEIGHT / 2, 0), this.hinge);
    const bottom = this.project(new THREE.Vector3(0, SCREEN_Y - SCREEN_HEIGHT / 2, 0), this.hinge);
    return { x: (top.x + bottom.x) / 2, y: (top.y + bottom.y) / 2, height: Math.hypot(top.x - bottom.x, top.y - bottom.y) };
  }

  /** The screen's height on the canvas when the camera is inside it. */
  fullScreenHeight() {
    return (this.canvas.clientHeight * SCREEN_HEIGHT) / this.insideCrop().fill;
  }

  /** Where the screen's centre is, from the canvas centre, when the camera is inside it. */
  insideOffset(): Point {
    const { fill, crop, side } = this.insideCrop();
    const px = this.canvas.clientHeight / fill;
    return { x: -side * px, y: crop * px };
  }

  private insideCrop() {
    const aspect = this.camera.aspect || 1;
    const fill = Math.min(SCREEN_HEIGHT, SCREEN_WIDTH / aspect) * 0.985;
    // Cropped from the bottom, so the menu bar stays in view; on a phone,
    // from the left too, so the menu bar cat and its panel stay.
    const crop = Math.max(0, (SCREEN_HEIGHT - fill) / 2);
    const side = aspect < 1 ? Math.max(0, (SCREEN_WIDTH - fill * aspect) / 2) * 0.92 : 0;
    return { fill, crop, side };
  }

  /**
   * Where a cat behind the laptop would be: the line where the desk meets the
   * back of the laptop, the laptop's width there, and two places on the top
   * edge at the back where paws can hang on.
   */
  behind() {
    const top = BASE + LID + 0.006;
    const back = -DEPTH / 2 + 0.05;
    const left = this.project(new THREE.Vector3(-WIDTH / 2, 0, -DEPTH / 2));
    const right = this.project(new THREE.Vector3(WIDTH / 2, 0, -DEPTH / 2));
    return {
      desk: (left.y + right.y) / 2,
      centre: (left.x + right.x) / 2,
      width: right.x - left.x,
      paws: [
        this.project(new THREE.Vector3(-WIDTH * 0.33, top, back)),
        this.project(new THREE.Vector3(WIDTH * 0.33, top, back)),
      ] as [Point, Point],
    };
  }

  private project(p: THREE.Vector3, from: THREE.Object3D = this.laptop): Point {
    this.laptop.updateMatrixWorld(true);
    from.localToWorld(p);
    p.project(this.camera);
    return { x: ((p.x + 1) / 2) * this.canvas.clientWidth, y: ((1 - p.y) / 2) * this.canvas.clientHeight };
  }

  private placeCamera() {
    const { zoom, view } = this.state;
    const aspect = this.camera.aspect || 1;
    const t = Math.tan(THREE.MathUtils.degToRad(FOV / 2));

    // Inside: square on to the open screen, close enough that it fills the
    // window (cropped on whichever side the window is narrower).
    this.laptop.updateMatrixWorld(true);
    const open = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), OPEN);
    const normal = new THREE.Vector3(0, 0, 1).applyQuaternion(open);
    const up = new THREE.Vector3(0, 1, 0).applyQuaternion(open);
    const centre = new THREE.Vector3(0, SCREEN_Y, 0).applyQuaternion(open).add(this.hinge.position);
    const { fill, crop, side } = this.insideCrop();
    const insideLook = centre.clone().addScaledVector(up, crop).add(new THREE.Vector3(side, 0, 0));
    const inside = insideLook.clone().addScaledVector(normal, fill / 2 / t);

    // Wide: the whole open laptop, a little from above. While the lid comes
    // down the camera sinks to the desk and swings round to the front
    // corner, closer in, because the screen turns to face it: the blur on it
    // is only seen from low down, as in a photo across a desk.
    const dip = smooth(Math.min(1, this.state.lid * 1.5)) * (1 - view);
    const wideLook = new THREE.Vector3(-0.15 * dip, 0.82 - 0.16 * dip, -0.1);
    const wideSpan = Math.max(3.6, 3.7 / aspect) * (1 - 0.1 * dip);
    const wide = wideLook.clone().addScaledVector(new THREE.Vector3(0.5 * dip, 0.36 - 0.3 * dip, 1).normalize(), wideSpan / 2 / t);

    // Above: over the shut lid, with room at the back for whoever is there.
    const aboveLook = new THREE.Vector3(0, 1.05, -0.9);
    const aboveSpan = Math.max(5.4, 4.1 / aspect);
    const above = aboveLook.clone().addScaledVector(new THREE.Vector3(0, 0.62, 1).normalize(), aboveSpan / 2 / t);

    const z = smooth(zoom);
    const pos = inside.clone().lerp(wide, z).lerp(above, view);
    const look = insideLook.clone().lerp(wideLook, z).lerp(aboveLook, view);
    const camUp = up.clone().lerp(new THREE.Vector3(0, 1, 0), z).normalize();
    this.camera.position.copy(pos);
    this.camera.up.copy(camUp);
    this.camera.lookAt(look);
  }

  pointTo(x: number, y: number) {
    this.pointer.x = x;
    this.pointer.y = y;
  }

  resize() {
    const { clientWidth: w, clientHeight: h } = this.canvas;
    if (!w || !h) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.placeCamera();
    if (!this.running) this.render();
  }

  start() {
    if (this.running) return;
    this.running = true;
    const tick = () => {
      if (!this.running) return;
      if (minutesLeft() !== this.shownMinutes) this.drawScreen();
      // Eased toward the pointer, so the laptop has a little weight to it.
      // Inside the screen it holds still: a desktop that swims is no desktop.
      const free = smooth(this.state.zoom);
      this.tilt.x += (this.pointer.y * 0.03 * free - this.tilt.x) * 0.06;
      this.tilt.y += (this.pointer.x * 0.06 * free - this.tilt.y) * 0.06;
      this.laptop.rotation.set(this.tilt.x, this.tilt.y, 0);
      // The screen cat watches the pointer, redrawn only while it is up and
      // its pupils have somewhere to go.
      const gz = this.gaze;
      gz.x += (Math.max(-1, Math.min(1, this.pointer.x * 1.4)) - gz.x) * 0.12;
      gz.y += (Math.max(-1, Math.min(1, this.pointer.y * 1.4)) - gz.y) * 0.12;
      if (this.frost.uPaws.value > 0.01 && Math.hypot(gz.x - gz.drawnX, gz.y - gz.drawnY) > 0.01) {
        gz.drawnX = gz.x;
        gz.drawnY = gz.y;
        this.catLook(gz.x, gz.y);
      }
      this.agents.update(this.clock.getElapsedTime());
      this.render();
      this.frame = requestAnimationFrame(tick);
    };
    this.frame = requestAnimationFrame(tick);
  }

  stop() {
    this.running = false;
    cancelAnimationFrame(this.frame);
  }

  render() {
    this.renderer.render(this.scene, this.camera);
  }

  private drawScreen() {
    this.shownMinutes = minutesLeft();
    drawScreen(this.screenCanvas.getContext("2d")!);
    this.screenTexture.needsUpdate = true;
  }

  dispose() {
    this.stop();
    for (const d of this.disposables) d.dispose();
    this.agents.dispose();
    this.scene.environment?.dispose();
    this.renderer.dispose();
  }
}

