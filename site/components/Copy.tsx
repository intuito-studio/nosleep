"use client";

import { useRef, useState } from "react";

/** A command with a copy icon at the end of its row. The whole block copies. */
export function Copy({ lines, label }: { lines: string[]; label: string }) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(lines.join("\n"));
    } catch {
      return;
    }
    setCopied(true);
    clearTimeout(timer.current);
    timer.current = setTimeout(() => setCopied(false), 1600);
  };

  return (
    <div className="command">
      <pre>
        <code>
          {lines.map((line) => (
            <span key={line} className="command-line">
              {line}
            </span>
          ))}
        </code>
      </pre>
      <button type="button" className="copy" onClick={copy} aria-label={`Copy ${label}`} data-copied={copied}>
        <svg className="copy-icon copy-idle" viewBox="0 0 24 24" aria-hidden>
          <rect x="8.5" y="8.5" width="11" height="11" rx="2.5" />
          <path d="M15.5 5.5v-.5a2 2 0 0 0-2-2h-8.5a2 2 0 0 0-2 2v8.5a2 2 0 0 0 2 2h.5" />
        </svg>
        <svg className="copy-icon copy-done" viewBox="0 0 24 24" aria-hidden>
          <path d="m5 12.5 4.5 4.5 9.5-10" />
        </svg>
        <span className="visually-hidden" aria-live="polite">
          {copied ? "Copied" : ""}
        </span>
      </button>
    </div>
  );
}
