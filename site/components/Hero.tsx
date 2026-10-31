"use client";

import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useEffect, useRef, useState } from "react";
import { Cat } from "@/components/Cat";
import { DownloadButtons } from "@/components/Download";
import { CAT_BROWN, CAT_YELLOW } from "@/lib/cat";
import { CatCanvas } from "@/lib/cat-canvas";
import type { LaptopScene } from "@/lib/laptop-scene";
import { clock, minutesLeft } from "@/lib/session";

gsap.registerPlugin(ScrollTrigger, useGSAP);

// The hero is one scroll: inside the Mac's screen, out to the whole Mac, the
// lid down, NoSleep's paws coming up in the screen's corners and the picture
// frosting over as it goes, and the cat up from behind it, waking as the lid shuts. Then
// three AI agents get to work on the shut lid.
export function Hero() {
  const root = useRef<HTMLElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const catBack = useRef<HTMLCanvasElement>(null);
  const catFront = useRef<HTMLCanvasElement>(null);
  const screenCopy = useRef<HTMLDivElement>(null);
  const angle = useRef<HTMLSpanElement>(null);
  const [noWebGL, setNoWebGL] = useState(false);

  useGSAP(
    () => {
      let scene: LaptopScene | null = null;
      let cancelled = false;
      const cleanups: (() => void)[] = [];
      const hero = root.current!;
      const nav = document.documentElement;

      // Inside the hero's Mac, its menu bar is the only bar; set before the
      // scene loads so the nav never flashes in.
      nav.dataset.inHero = "";
      const cat = new CatCanvas(catBack.current!, catFront.current!);
      cat.follow(() => scene?.behind() ?? null);

      // The copy sits on the screen, so it shrinks and travels with it.
      const pinCopy = () => {
        const el = screenCopy.current;
        if (!scene || !el) return;
        const r = scene.screenRect();
        const o = scene.insideOffset();
        const s = r.height / scene.fullScreenHeight();
        // The point of the screen the copy covered at the start, wherever it is now.
        const x = r.x - o.x * s - hero.clientWidth / 2;
        const y = r.y - o.y * s - hero.clientHeight / 2;
        el.style.transform = `translate(${x}px, ${y}px) scale(${s})`;
      };

      const sized = new ResizeObserver(() => {
        scene?.resize();
        cat.resize();
        pinCopy();
      });
      sized.observe(hero);
      cleanups.push(() => sized.disconnect());

      // Only draw while the hero is on screen.
      const seen = new IntersectionObserver(([entry]) => {
        if (entry.isIntersecting) {
          cat.start();
          scene?.start();
        } else {
          cat.stop();
          scene?.stop();
        }
      });
      seen.observe(hero);
      cleanups.push(() => seen.disconnect());

      const move = (e: PointerEvent) => {
        cat.look(e.clientX, e.clientY);
        if (e.pointerType === "mouse") hero.style.cursor = cat.hits(e.clientX, e.clientY) ? "pointer" : "";
      };
      const poke = (e: MouseEvent) => {
        if ((e.target as Element).closest("a, button")) return;
        if (cat.hits(e.clientX, e.clientY)) cat.poke();
      };
      window.addEventListener("pointermove", move);
      hero.addEventListener("click", poke);
      cleanups.push(() => {
        window.removeEventListener("pointermove", move);
        hero.removeEventListener("click", poke);
        cat.stop();
        delete nav.dataset.inHero;
      });

      import("@/lib/laptop-scene").then(({ LaptopScene }) => {
        if (cancelled || !canvas.current) return;
        try {
          scene = new LaptopScene(canvas.current);
        } catch {
          delete nav.dataset.inHero;
          setNoWebGL(true);
          return;
        }
        const s = scene;
        s.start();
        pinCopy();
        gsap.to(canvas.current, { opacity: 1, duration: 0.9, ease: "power2.out" });

        const mm = gsap.matchMedia();
        cleanups.push(() => mm.revert());

        mm.add("(hover: hover) and (pointer: fine)", () => {
          const tilt = (e: PointerEvent) =>
            s.pointTo((e.clientX / window.innerWidth) * 2 - 1, (e.clientY / window.innerHeight) * 2 - 1);
          window.addEventListener("pointermove", tilt);
          return () => window.removeEventListener("pointermove", tilt);
        });

        mm.add("(prefers-reduced-motion: no-preference)", () => {
          const state = { zoom: 0, lid: 0, view: 0, agents: 0, rise: 0, wake: 0, night: 0 };
          const apply = () => {
            s.set(state);
            cat.set(state);
            pinCopy();
            if (angle.current) angle.current.textContent = `${Math.round(s.angle())}°`;
          };
          // The site's own nav waits until we are out of the Mac's screen,
          // where the Mac's menu bar is the only bar.
          nav.dataset.inHero = "";
          gsap
            .timeline({
              defaults: { ease: "none" },
              scrollTrigger: {
                trigger: hero,
                start: "top top",
                end: "+=320%",
                pin: true,
                scrub: 0.8,
                onUpdate: (st) => {
                  if (st.progress > 0.22) delete nav.dataset.inHero;
                  else nav.dataset.inHero = "";
                },
              },
              onUpdate: apply,
            })
            .to(".hero-open", { autoAlpha: 0, filter: "blur(8px)", duration: 0.12 }, 0.14)
            .to(state, { zoom: 1, duration: 0.3, ease: "power2.inOut" }, 0.04)
            .to(state, { night: 1, duration: 0.2 }, 0.28)
            // The lid comes down at an even pace, so the paws and the frost,
            // which follow the hinge angle, get their time.
            .to(state, { lid: 1, duration: 0.4, ease: "sine.inOut" }, 0.34)
            .fromTo(".hero-angle", { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: 0.04 }, 0.34)
            .to(".hero-angle", { opacity: 0, duration: 0.03 }, 0.74)
            .to(state, { view: 1, duration: 0.22, ease: "power1.inOut" }, 0.69)
            .to(state, { rise: 1, duration: 0.12, ease: "back.out(1.6)" }, 0.74)
            .to(state, { wake: 1, duration: 0.04 }, 0.86)
            .fromTo(
              ".hero-shut",
              { opacity: 0, y: 24, filter: "blur(10px)" },
              { opacity: 1, y: 0, filter: "blur(0px)", duration: 0.05 },
              0.87,
            )
            .to(state, { agents: 1, duration: 0.08 }, 0.9)
            .fromTo(".hero-status", { opacity: 0, y: 16, scale: 0.96 }, { opacity: 1, y: 0, scale: 1, duration: 0.04 }, 0.93)
            .to({}, { duration: 0.04 });
          return () => {
            delete nav.dataset.inHero;
            s.set({ zoom: 0, lid: 0, view: 0, agents: 0 });
            cat.set({ rise: 0, wake: 0, night: 0 });
          };
        });

        // Reduced motion: no scroll story. The page stays on the Mac's
        // desktop, copy and all, and the nav waits until it scrolls away.
        mm.add("(prefers-reduced-motion: reduce)", () => {
          if (window.scrollY < hero.offsetHeight * 0.4) nav.dataset.inHero = "";
          const st = ScrollTrigger.create({
            trigger: hero,
            start: "top top",
            end: "bottom 60%",
            onLeave: () => delete nav.dataset.inHero,
            onEnterBack: () => (nav.dataset.inHero = ""),
          });
          return () => st.kill();
        });
      });

      return () => {
        cancelled = true;
        cleanups.forEach((c) => c());
        scene?.dispose();
      };
    },
    { scope: root },
  );

  return (
    <section ref={root} className="hero" aria-labelledby="hero-title">
      <canvas ref={catBack} className="hero-layer" aria-hidden />
      <div className="hero-stage">
        <canvas ref={canvas} className="hero-canvas" aria-hidden hidden={noWebGL} />
      </div>
      <canvas ref={catFront} className="hero-layer front" aria-hidden />

      <div className="hero-open">
        <div ref={screenCopy} className="hero-screen-copy">
          <h1 id="hero-title">
            Close the lid.
            <br />
            Keep it running.
          </h1>
          <p className="lede">A menu bar switch that keeps your Mac awake with the lid shut.</p>
          <DownloadButtons />
          <p className="fine">Free · macOS 14 or later · Apple silicon and Intel</p>
        </div>
      </div>

      <div className="hero-shut" aria-hidden>
        <p className="display">Lid shut.</p>
        <p className="display accent">Still awake.</p>
      </div>

      <div className="hero-angle glass" aria-hidden>
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M4 19h16M4 19 15 6" />
          <path d="M10 19a6 6 0 0 0-1.6-4.1" />
        </svg>
        <span ref={angle}>110°</span>
      </div>

      <Status />
    </section>
  );
}

/** The little banner under the cat: the same countdown as the Mac's menu bar. */
function Status() {
  const [minutes, setMinutes] = useState(102);
  useEffect(() => {
    const tick = () => setMinutes(minutesLeft());
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, []);
  return (
    <div className="hero-status glass" aria-hidden>
      <span className="badge">
        <Cat awake head={CAT_BROWN} eyes={CAT_YELLOW} pupils={CAT_BROWN} />
      </span>
      <span>
        <strong>Awake</strong>, {clock(minutes)} left
      </span>
    </div>
  );
}
