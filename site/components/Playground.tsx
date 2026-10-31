"use client";

import { useGSAP } from "@gsap/react";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useEffect, useRef, useState } from "react";
import { Cat } from "@/components/Cat";
import { HOURS, LOW_POWER_BELOW, START, ending, levelAt } from "@/lib/battery";
import { CAT_BROWN, CAT_YELLOW } from "@/lib/cat";

gsap.registerPlugin(ScrollTrigger, useGSAP);

// The app's own stops, from Controller.swift. null is "No limit" / "Off".
const DURATIONS: (number | null)[] = [15, 30, 60, 120, 180, 240, 360, 480, null];
const FLOORS: (number | null)[] = [null, 5, 10, 15, 20, 25, 30, 40, 50];

function durationName(minutes: number | null) {
  if (minutes === null) return "No limit";
  if (minutes < 60) return `${minutes} minutes`;
  return minutes === 60 ? "1 hour" : `${minutes / 60} hours`;
}

function compact(minutes: number) {
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

export function Playground() {
  const [awake, setAwake] = useState(true);
  const [duration, setDuration] = useState(3);
  const [floor, setFloor] = useState(4);
  const minutes = DURATIONS[duration];
  const stop = FLOORS[floor];

  return (
    <div className="playground">
      <div className="desktop">
        <div className="menubar" aria-hidden>
          <span className="menubar-left">
            <b>Finder</b>
            <span>File</span>
            <span>Edit</span>
            <span>View</span>
          </span>
          <span className="menubar-right">
            <span className="menubar-item is-open">
              <Cat awake={awake} className="menubar-cat" />
              {awake && minutes !== null && <span className="num">{compact(minutes)}</span>}
            </span>
            <span className="num">11:48 PM</span>
          </span>
        </div>

        <div className="panel glass" role="group" aria-label="NoSleep panel, interactive">
          <button
            type="button"
            className="tile switch"
            aria-pressed={awake}
            onClick={() => setAwake((a) => !a)}
          >
            <Ring awake={awake} />
            <span className="switch-text">
              <strong>{awake ? "Awake" : "Normal sleep"}</strong>
              <span>
                {awake
                  ? minutes === null
                    ? "Until you switch it off"
                    : `${durationName(minutes)} left`
                  : "Click to keep the Mac awake"}
              </span>
            </span>
          </button>

          <div className="tile sliders">
            <Stop
              label="Keep awake for"
              value={durationName(minutes)}
              index={duration}
              count={DURATIONS.length}
              onChange={setDuration}
              icon="timer"
            />
            <Stop
              label="Stop at battery"
              detail={`now ${START}%`}
              value={stop === null ? "Off" : `${stop}%`}
              index={floor}
              count={FLOORS.length}
              onChange={setFloor}
              icon="battery"
            />
          </div>
        </div>
      </div>

      <BatteryChart stop={stop ?? 0} timer={minutes === null ? HOURS + 4 : minutes / 60} awake={awake} />
    </div>
  );
}

function Ring({ awake }: { awake: boolean }) {
  return (
    <span className="badge-ring" data-awake={awake}>
      <svg viewBox="0 0 64 64" aria-hidden>
        <circle cx="32" cy="32" r="29" className="ring-track" />
        <circle cx="32" cy="32" r="29" className="ring-fill" pathLength={100} />
      </svg>
      <span className="badge-face">
        {awake ? (
          <Cat awake head={CAT_BROWN} eyes={CAT_YELLOW} pupils={CAT_BROWN} />
        ) : (
          <Cat awake={false} />
        )}
      </span>
    </span>
  );
}

function Stop(props: {
  label: string;
  value: string;
  detail?: string;
  index: number;
  count: number;
  icon: "timer" | "battery";
  onChange: (i: number) => void;
}) {
  const id = `stop-${props.icon}`;
  return (
    <div className="stop">
      <div className="stop-head">
        <label htmlFor={id}>{props.label}</label>
        <span className="stop-value">
          {props.detail && <span className="stop-detail">{props.detail}</span>}
          <span className="num">{props.value}</span>
        </span>
      </div>
      <div className="stop-track">
        {props.icon === "timer" ? <TimerIcon /> : <BatteryIcon />}
        <span className="range">
          <span className="ticks" aria-hidden>
            {Array.from({ length: props.count }, (_, i) => (
              <i key={i} />
            ))}
          </span>
          <input
            id={id}
            type="range"
            min={0}
            max={props.count - 1}
            step={1}
            value={props.index}
            aria-valuetext={props.value}
            onChange={(e) => props.onChange(Number(e.target.value))}
          />
        </span>
      </div>
    </div>
  );
}

function TimerIcon() {
  return (
    <svg viewBox="0 0 20 20" className="icon" aria-hidden>
      <circle cx="10" cy="11" r="7" />
      <path d="M10 11 7 8M8 2.5h4" />
    </svg>
  );
}

function BatteryIcon() {
  return (
    <svg viewBox="0 0 20 20" className="icon" aria-hidden>
      <rect x="1.5" y="6" width="15" height="8" rx="2" />
      <path d="M18.5 8.5v3" />
      <rect x="3.5" y="8" width="3" height="4" rx="0.5" className="icon-fill" />
    </svg>
  );
}

/** One evening on battery, drawn on a 2D canvas, redrawn as the sliders move. */
function BatteryChart({ stop, timer, awake }: { stop: number; timer: number; awake: boolean }) {
  const wrap = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  // Tweened copies of the props, so the line glides to its new ending.
  const shown = useRef({ stop, timer, reveal: 0 });
  const draw = useRef<() => void>(() => {});
  const end = ending(stop, timer);

  useEffect(() => {
    const c = canvas.current!;
    const g = c.getContext("2d")!;

    draw.current = () => {
      const css = getComputedStyle(c);
      const ink = css.getPropertyValue("--ink").trim();
      const muted = css.getPropertyValue("--ink-3").trim();
      const hair = css.getPropertyValue("--hair").trim();
      const accent = css.getPropertyValue("--accent").trim();
      const font = css.getPropertyValue("font-family");

      const dpr = Math.min(window.devicePixelRatio, 2);
      const W = c.clientWidth;
      const H = c.clientHeight;
      if (c.width !== W * dpr || c.height !== H * dpr) {
        c.width = W * dpr;
        c.height = H * dpr;
      }
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      g.clearRect(0, 0, W, H);

      const left = 44;
      const right = 16;
      const top = 16;
      const bottom = 30;
      const x = (t: number) => left + (t / HOURS) * (W - left - right);
      const y = (level: number) => top + (1 - level / 100) * (H - top - bottom);

      g.font = `12px ${font}`;
      g.textBaseline = "middle";
      g.lineWidth = 1;
      for (const level of [0, 50, 100]) {
        g.strokeStyle = hair;
        g.beginPath();
        g.moveTo(left, Math.round(y(level)) + 0.5);
        g.lineTo(W - right, Math.round(y(level)) + 0.5);
        g.stroke();
        g.fillStyle = muted;
        g.textAlign = "right";
        g.fillText(`${level}%`, left - 10, y(level));
      }
      g.textAlign = "center";
      g.textBaseline = "top";
      for (let h = 0; h <= HOURS; h++) g.fillText(h === 0 ? "now" : `${h}h`, x(h), H - bottom + 10);

      const s = shown.current;
      const e = ending(s.stop, s.timer);

      // The rules, as lines across the chart.
      g.setLineDash([3, 4]);
      g.strokeStyle = muted;
      g.beginPath();
      g.moveTo(left, y(LOW_POWER_BELOW));
      g.lineTo(W - right, y(LOW_POWER_BELOW));
      g.stroke();
      if (s.stop > 0.5) {
        g.strokeStyle = accent;
        g.beginPath();
        g.moveTo(left, y(s.stop));
        g.lineTo(W - right, y(s.stop));
        g.stroke();
      }
      g.setLineDash([]);
      g.textAlign = "right";
      g.textBaseline = "bottom";
      g.fillStyle = muted;
      g.fillText("Low Power Mode below 40%", W - right, y(LOW_POWER_BELOW) - 5);
      if (s.stop > 0.5) {
        g.fillStyle = accent;
        g.fillText(`Stop at ${Math.round(s.stop)}%`, W - right, y(s.stop) - 5);
      }

      // The session, revealed left to right.
      const until = Math.min(e.at, HOURS) * s.reveal;
      g.strokeStyle = ink;
      g.lineWidth = 2.25;
      g.lineJoin = "round";
      g.beginPath();
      for (let t = 0; t <= until; t += 0.02) {
        const px = x(t);
        const py = y(levelAt(t));
        if (t === 0) g.moveTo(px, py);
        else g.lineTo(px, py);
      }
      g.lineTo(x(until), y(levelAt(until)));
      g.stroke();

      if (s.reveal >= 1 && e.at < HOURS) {
        // Asleep: the battery holds where the session left it.
        const level = levelAt(e.at);
        g.strokeStyle = muted;
        g.lineWidth = 1.5;
        g.setLineDash([2, 5]);
        g.beginPath();
        g.moveTo(x(e.at), y(level));
        g.lineTo(W - right, y(level));
        g.stroke();
        g.setLineDash([]);
        g.fillStyle = accent;
        g.beginPath();
        g.arc(x(e.at), y(level), 5, 0, Math.PI * 2);
        g.fill();
      }
    };
    draw.current();

    const redraw = () => draw.current();
    const ro = new ResizeObserver(redraw);
    ro.observe(c);
    return () => ro.disconnect();
  }, []);

  useGSAP(
    () => {
      const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
      if (reduce) {
        shown.current.reveal = 1;
        draw.current();
        return;
      }
      gsap.to(shown.current, {
        reveal: 1,
        duration: 1.6,
        ease: "power2.out",
        onUpdate: () => draw.current(),
        scrollTrigger: { trigger: wrap.current, start: "top 75%", once: true },
      });
    },
    { scope: wrap },
  );

  useEffect(() => {
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    gsap.to(shown.current, {
      stop,
      timer,
      duration: reduce ? 0 : 0.5,
      ease: "expo.out",
      overwrite: "auto",
      onUpdate: () => draw.current(),
    });
  }, [stop, timer]);

  const hours = (h: number) => {
    const m = Math.round(h * 60);
    return m < 60 ? `${m} minutes` : `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, "0")}m`;
  };
  const summary = !awake
    ? "Switched off, the Mac sleeps as usual when you close the lid."
    : end.reason === "timer"
      ? `The timer ends first: after ${hours(end.at)}, at ${Math.round(levelAt(end.at))}%, the Mac goes to sleep.`
      : end.reason === "battery"
        ? `The battery stop comes first: at ${stop}%, after ${hours(end.at)}, the Mac goes to sleep.`
        : "No timer and no battery stop: it runs until the battery is flat.";

  return (
    <figure ref={wrap} className="chart" data-off={!awake}>
      <canvas
        ref={canvas}
        role="img"
        aria-label={`Battery level over ${HOURS} hours on battery, starting at ${START}%. ${summary}`}
      />
      <figcaption>
        <span className="chart-summary" aria-live="polite">
          {summary}
        </span>
        <span className="chart-note">Illustration: a Mac at {START}% on battery, under load. Move the sliders above.</span>
      </figcaption>
    </figure>
  );
}
