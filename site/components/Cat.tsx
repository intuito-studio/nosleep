import { useId } from "react";
import { CAT_EYES, CAT_HEAD, CAT_VIEWBOX, catLid, catPupil } from "@/lib/cat";

type Props = {
  awake: boolean;
  /** Without colours it is a template, like the menu bar icon: eyes cut out. */
  head?: string;
  eyes?: string;
  pupils?: string;
  className?: string;
  title?: string;
};

export function Cat({ awake, head = "currentColor", eyes, pupils, className, title }: Props) {
  const mask = useId();
  return (
    <svg
      viewBox={CAT_VIEWBOX}
      className={className}
      role={title ? "img" : undefined}
      aria-label={title}
      aria-hidden={title ? undefined : true}
    >
      <mask id={mask}>
        <rect width="230" height="200" fill="white" />
        {awake
          ? !eyes && CAT_EYES.map((e) => <ellipse key={e.cx} {...e} fill="black" />)
          : CAT_EYES.map((e) => (
              <path key={e.cx} d={catLid(e.cx)} fill="none" stroke="black" strokeWidth={14} strokeLinecap="round" />
            ))}
      </mask>
      <path d={CAT_HEAD} fill={head} mask={`url(#${mask})`} />
      {awake &&
        CAT_EYES.map((e) => (
          <g key={e.cx}>
            {eyes && <ellipse {...e} fill={eyes} />}
            <path d={catPupil(e.cx)} fill={pupils ?? head} />
          </g>
        ))}
    </svg>
  );
}
