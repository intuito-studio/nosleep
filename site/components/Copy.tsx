"use client";

import { useRef, useState } from "react";

/** A command with a copy button. The whole block copies, comments and all. */
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
        <span className="copy-label copy-idle">Copy</span>
        <span className="copy-label copy-done" aria-live="polite">
          {copied ? "Copied" : ""}
        </span>
      </button>
    </div>
  );
}
