import { DMG_URL, REPO_URL } from "./links";

// What the page says about itself to search engines and AI answer engines:
// one place for the name, the address and the plain facts, so the
// metadata, the structured data, the FAQ on the page and llms.txt agree.

/**
 * The page's own address. On Vercel the production domain is known at build
 * time; NEXT_PUBLIC_SITE_URL overrides it anywhere else.
 */
export const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : "http://localhost:3344");

export const NAME = "NoSleep";
export const TITLE = "NoSleep: keep your Mac awake with the lid closed";
export const DESCRIPTION =
  "Free macOS menu bar app that keeps a MacBook running with the lid closed, no external display needed. " +
  "Timer, battery stop and heat safety put sleep back on their own. macOS 14+, Apple silicon and Intel.";
export const PUBLISHER = "Intuito Studio";
export const VERSION = "1.0.0";

export const FAQ: [string, string][] = [
  [
    "Can a MacBook stay awake with the lid closed without an external display?",
    "Yes. NoSleep switches macOS's own sleep setting (pmset disablesleep), so a MacBook keeps running with the lid shut: no external display, keyboard or power adapter needed. Downloads, renders, builds and AI agents carry on.",
  ],
  [
    "Is it safe to keep a closed MacBook awake?",
    "NoSleep turns on Low Power Mode below 40% battery and when the Mac runs hot, stops at 20% battery (or a level you pick), and puts sleep back when you quit. If it crashes, a backstop restores sleep within a minute, so it is never left awake in a bag.",
  ],
  [
    "Is NoSleep free?",
    "Yes, free, with the source on GitHub. It updates itself in one click.",
  ],
  [
    "Which Macs does NoSleep work on?",
    "Any Mac on macOS 14 Sonoma or later, Apple silicon or Intel.",
  ],
  [
    "Why does NoSleep ask for my password?",
    "Once, the first time you switch it on, to allow exactly the power commands it uses and nothing else. After that it never asks again.",
  ],
  [
    "How do I install NoSleep?",
    "Download NoSleep.dmg and drag it to Applications, or run brew install --cask intuito-studio/tap/nosleep after tapping intuito-studio/tap, or the one-line installer on the page.",
  ],
];

/** Structured data: the app, its maker, and the FAQ, as schema.org JSON-LD. */
export function jsonLd() {
  return [
    {
      "@context": "https://schema.org",
      "@type": "SoftwareApplication",
      name: NAME,
      description: DESCRIPTION,
      url: SITE_URL,
      applicationCategory: "UtilitiesApplication",
      operatingSystem: "macOS 14 or later",
      softwareVersion: VERSION,
      downloadUrl: DMG_URL,
      installUrl: `${SITE_URL}/#install`,
      codeRepository: REPO_URL,
      image: `${SITE_URL}/app-icon.png`,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
      publisher: { "@type": "Organization", name: PUBLISHER, url: "https://intuitostudio.com" },
    },
    {
      "@context": "https://schema.org",
      "@type": "FAQPage",
      mainEntity: FAQ.map(([q, a]) => ({ "@type": "Question", name: q, acceptedAnswer: { "@type": "Answer", text: a } })),
    },
  ];
}
