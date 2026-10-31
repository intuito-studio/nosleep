// Line icons on a 24 grid, drawn to sit beside SF Pro text: 1.6 strokes,
// round caps, the colour from the text around them.

import type { ReactNode } from "react";

function Icon({ children }: { children: ReactNode }) {
  return (
    <svg viewBox="0 0 24 24" className="icon-line" aria-hidden>
      {children}
    </svg>
  );
}

export const Display = () => (
  <Icon>
    <rect x="3" y="4" width="18" height="12" rx="2" />
    <path d="M9 20h6M12 16v4" />
  </Icon>
);

export const Sound = () => (
  <Icon>
    <path d="M4 9.5h3l4.5-4v13L7 14.5H4z" />
    <path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a7.5 7.5 0 0 1 0 11" />
  </Icon>
);

export const LowPower = () => (
  <Icon>
    <rect x="2.5" y="7" width="17" height="10" rx="2.5" />
    <path d="M21.5 10.5v3" />
    <path d="m11.5 9-2 3.2h3l-2 3" />
  </Icon>
);

export const Timer = () => (
  <Icon>
    <circle cx="12" cy="13.5" r="7.5" />
    <path d="M12 13.5V9.5M9.5 3h5" />
  </Icon>
);

export const Moon = () => (
  <Icon>
    <path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z" />
  </Icon>
);

export const Battery = () => (
  <Icon>
    <rect x="2.5" y="7" width="17" height="10" rx="2.5" />
    <path d="M21.5 10.5v3" />
    <rect x="5" y="9.5" width="4" height="5" rx="1" className="icon-fill" />
  </Icon>
);

export const Heat = () => (
  <Icon>
    <path d="M10 14.5V5a2 2 0 0 1 4 0v9.5a4 4 0 1 1-4 0z" />
    <path d="M12 11v6" />
  </Icon>
);

export const Power = () => (
  <Icon>
    <path d="M12 3v8" />
    <path d="M7 6.3a7.5 7.5 0 1 0 10 0" />
  </Icon>
);

export const Backstop = () => (
  <Icon>
    <path d="M12 3 5 6v5.5c0 4.2 3 7.8 7 9.5 4-1.7 7-5.3 7-9.5V6z" />
    <path d="m9 12 2 2 4-4" />
  </Icon>
);

export const Terminal = () => (
  <Icon>
    <rect x="3" y="4.5" width="18" height="15" rx="2.5" />
    <path d="m7 10 3 2.5L7 15M12.5 15H17" />
  </Icon>
);

export const Mug = () => (
  <Icon>
    <path d="M5 8h11v7a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4z" />
    <path d="M16 10h1.5a2.5 2.5 0 0 1 0 5H16M8.5 3.5v2M12 3.5v2" />
  </Icon>
);


