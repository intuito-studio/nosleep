"use client";

import { useEffect } from "react";

// Edge refraction for `.glass`, after Apple's Liquid Glass: the backdrop is
// bent outward near the rim and left alone in the middle, a little more for
// blue than for red, so the rim picks up a hint of colour. The map is two
// gradients (red across, green down) with a neutral grey middle; SVG filters
// in backdrop-filter only work in Chromium, so only there is the class set.
const MAP =
  "data:image/svg+xml," +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="none">
      <defs>
        <linearGradient id="r" x1="0" x2="1"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#f00"/></linearGradient>
        <linearGradient id="g" y1="0" y2="1" x1="0" x2="0"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#0f0"/></linearGradient>
        <filter id="b"><feGaussianBlur stdDeviation="5"/></filter>
      </defs>
      <rect width="100" height="100" fill="url(#r)"/>
      <rect width="100" height="100" fill="url(#g)" style="mix-blend-mode:screen"/>
      <rect x="10" y="12" width="80" height="76" rx="18" fill="rgb(128,128,0)" filter="url(#b)"/>
    </svg>`,
  );

export function GlassFilter() {
  useEffect(() => {
    const brands = (navigator as Navigator & { userAgentData?: { brands: { brand: string }[] } }).userAgentData?.brands;
    if (brands?.some((b) => b.brand === "Chromium")) document.documentElement.classList.add("refracts");
  }, []);

  return (
    <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden>
      <filter id="liquid-glass" x="0" y="0" width="100%" height="100%" colorInterpolationFilters="sRGB">
        <feImage href={MAP} x="0" y="0" width="100%" height="100%" preserveAspectRatio="none" result="map" />
        <feDisplacementMap in="SourceGraphic" in2="map" scale="-20" xChannelSelector="R" yChannelSelector="G" result="r0" />
        <feColorMatrix in="r0" type="matrix" values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0" result="red" />
        <feDisplacementMap in="SourceGraphic" in2="map" scale="-23" xChannelSelector="R" yChannelSelector="G" result="g0" />
        <feColorMatrix in="g0" type="matrix" values="0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0" result="green" />
        <feDisplacementMap in="SourceGraphic" in2="map" scale="-26" xChannelSelector="R" yChannelSelector="G" result="b0" />
        <feColorMatrix in="b0" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0" result="blue" />
        <feBlend in="red" in2="green" mode="screen" result="rg" />
        <feBlend in="rg" in2="blue" mode="screen" />
      </filter>
    </svg>
  );
}
