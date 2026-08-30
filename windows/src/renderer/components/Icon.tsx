import { useId, type SVGProps } from "react";

type IconPart = Readonly<{
  d: string;
  fill?: boolean;
  strokeWidth?: number;
}>;

type IconDefinition = Readonly<{
  paths: readonly IconPart[];
}>;

/**
 * WeiBei-owned line icons. These paths intentionally express the same
 * metaphors as the macOS controls without bundling or tracing SF Symbols.
 * Geometry is drawn on a 24 × 24 optical grid with round 1.5 px strokes.
 */
export const iconManifest = {
  library: {
    paths: [
      { d: "M4.75 4.75h14.5a1.5 1.5 0 0 1 1.5 1.5v11.5a1.5 1.5 0 0 1-1.5 1.5H4.75a1.5 1.5 0 0 1-1.5-1.5V6.25a1.5 1.5 0 0 1 1.5-1.5Z" },
      { d: "M9 4.75v14.5M6.25 8h.01M6.25 11h.01" },
    ],
  },
  back: {
    paths: [{ d: "M19.25 12H5.5m5-5-5 5 5 5" }],
  },
  forward: {
    paths: [{ d: "M4.75 12H18.5m-5-5 5 5-5 5" }],
  },
  reader: {
    paths: [
      { d: "M7 3.75h7.25L18.5 8v12.25H7a1.5 1.5 0 0 1-1.5-1.5V5.25A1.5 1.5 0 0 1 7 3.75Z" },
      { d: "M14.25 3.75V8h4.25M8.5 11h7M8.5 14h7M8.5 17h4.5" },
    ],
  },
  chat: {
    paths: [
      { d: "M5.25 5.25h9.25A2.25 2.25 0 0 1 16.75 7.5v3A2.25 2.25 0 0 1 14.5 12.75H9.25L6.5 15v-2.25H5.25A2.25 2.25 0 0 1 3 10.5v-3a2.25 2.25 0 0 1 2.25-2.25Z" },
      { d: "M10.25 15.5h4.5l2.75 2.25V15.5h1.25A2.25 2.25 0 0 0 21 13.25v-3A2.25 2.25 0 0 0 18.75 8h-2M7 8.75h5.75" },
    ],
  },
  note: {
    paths: [
      { d: "M7 3.75h7.25L18.5 8v12.25H7a1.5 1.5 0 0 1-1.5-1.5V5.25A1.5 1.5 0 0 1 7 3.75Z" },
      { d: "M14.25 3.75V8h4.25M8.5 10.75v6.5M11 11h4.75M11 14h4.75M11 17h3" },
    ],
  },
  search: {
    paths: [{ d: "M10.75 4.25a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13Zm4.75 11.25 4.25 4.25" }],
  },
  "theme-light": {
    paths: [
      { d: "M12 7.25a4.75 4.75 0 1 1 0 9.5 4.75 4.75 0 0 1 0-9.5Z" },
      { d: "M12 2.75v2M12 19.25v2M2.75 12h2M19.25 12h2M5.45 5.45l1.42 1.42M17.13 17.13l1.42 1.42M18.55 5.45l-1.42 1.42M6.87 17.13l-1.42 1.42" },
    ],
  },
  sun: {
    paths: [
      { d: "M12 7.25a4.75 4.75 0 1 1 0 9.5 4.75 4.75 0 0 1 0-9.5Z" },
      { d: "M12 2.75v2M12 19.25v2M2.75 12h2M19.25 12h2M5.45 5.45l1.42 1.42M17.13 17.13l1.42 1.42M18.55 5.45l-1.42 1.42M6.87 17.13l-1.42 1.42" },
    ],
  },
  moon: {
    paths: [{ d: "M19.5 15.1A7.75 7.75 0 0 1 8.9 4.5 7.75 7.75 0 1 0 19.5 15.1Z" }],
  },
  settings: {
    paths: [
      { d: "M4 6.5h7M15.5 6.5H20M4 12h3M11 12h9M4 17.5h9M17 17.5h3" },
      { d: "M13.5 4.5v4M9 10v4M15 15.5v4" },
    ],
  },
  close: {
    paths: [{ d: "m6.5 6.5 11 11m0-11-11 11" }],
  },
  more: {
    paths: [{ d: "M6 12h.01M12 12h.01M18 12h.01", strokeWidth: 2.5 }],
  },
  add: {
    paths: [{ d: "M12 4.5v15M4.5 12h15" }],
  },
  import: {
    paths: [
      { d: "M12 3.5v10m-4-4 4 4 4-4" },
      { d: "M5 15.5v2.75a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V15.5" },
    ],
  },
  send: {
    paths: [
      { d: "M3.75 4.5 21 12 3.75 19.5l2-6.25L15.5 12l-9.75-1.25-2-6.25Z" },
      { d: "M6 12h9.5" },
    ],
  },
  stop: {
    paths: [{ d: "M8.25 8.25h7.5v7.5h-7.5z" }],
  },
  html: {
    paths: [
      { d: "M12 3.5a8.5 8.5 0 1 1 0 17 8.5 8.5 0 0 1 0-17Z" },
      { d: "M3.75 12h16.5M12 3.5c2.1 2.3 3.2 5.15 3.2 8.5S14.1 18.2 12 20.5C9.9 18.2 8.8 15.35 8.8 12S9.9 5.8 12 3.5Z" },
    ],
  },
  pdf: {
    paths: [
      { d: "M7 3.75h7.25L18.5 8v12.25H7a1.5 1.5 0 0 1-1.5-1.5V5.25A1.5 1.5 0 0 1 7 3.75Z" },
      { d: "M14.25 3.75V8h4.25M8 16v-4h1.25a1.25 1.25 0 0 1 0 2.5H8m4.25 1.5v-4h1a2 2 0 0 1 0 4h-1Zm4 0v-4H19m-2.75 2H19" },
    ],
  },
  markdown: {
    paths: [
      { d: "M7 3.75h7.25L18.5 8v12.25H7a1.5 1.5 0 0 1-1.5-1.5V5.25A1.5 1.5 0 0 1 7 3.75Z" },
      { d: "M14.25 3.75V8h4.25M8 16v-4l2 2 2-2v4m3-4v4m-1.5-1.5L15 16l1.5-1.5" },
    ],
  },
  text: {
    paths: [
      { d: "M7 3.75h7.25L18.5 8v12.25H7a1.5 1.5 0 0 1-1.5-1.5V5.25A1.5 1.5 0 0 1 7 3.75Z" },
      { d: "M14.25 3.75V8h4.25M8.5 11h7M8.5 14h7M8.5 17h5" },
    ],
  },
  folder: {
    paths: [{ d: "M3.5 7.25A1.75 1.75 0 0 1 5.25 5.5h4l1.75 2h7.75a1.75 1.75 0 0 1 1.75 1.75v8.5a1.75 1.75 0 0 1-1.75 1.75H5.25a1.75 1.75 0 0 1-1.75-1.75V7.25Z" }],
  },
  link: {
    paths: [
      { d: "m9.5 14.5 5-5" },
      { d: "M7.8 17.65 6.35 19.1a3.15 3.15 0 0 1-4.45-4.45l3.25-3.25A3.15 3.15 0 0 1 9.6 11" },
      { d: "m14.4 13 3.25-3.25A3.15 3.15 0 0 0 13.2 5.3l-1.45 1.45" },
    ],
  },
  warning: {
    paths: [
      { d: "M10.35 4.5 2.9 17.35a1.65 1.65 0 0 0 1.43 2.48h15.34a1.65 1.65 0 0 0 1.43-2.48L13.65 4.5a1.9 1.9 0 0 0-3.3 0Z" },
      { d: "M12 9v4.5M12 17h.01", strokeWidth: 2 },
    ],
  },
  check: {
    paths: [{ d: "m5 12.5 4.25 4.25L19 7" }],
  },
  "chevron-down": {
    paths: [{ d: "m6.5 9 5.5 5.5L17.5 9" }],
  },
} as const satisfies Record<string, IconDefinition>;

export type IconName = keyof typeof iconManifest;

export const iconNames = Object.freeze(
  Object.keys(iconManifest) as IconName[],
) as readonly IconName[];

export interface IconProps
  extends Omit<SVGProps<SVGSVGElement>, "aria-hidden" | "children" | "name"> {
  name: IconName;
  size?: number | string;
  strokeWidth?: number;
  title?: string;
  /** Defaults to true unless title or aria-label supplies an accessible name. */
  ariaHidden?: boolean;
}

export function Icon({
  name,
  size = 16,
  strokeWidth = 1.5,
  title,
  ariaHidden,
  ...svgProps
}: IconProps) {
  const generatedTitleId = useId();
  const hasAccessibleName = Boolean(title || svgProps["aria-label"]);
  const hidden = ariaHidden ?? !hasAccessibleName;
  const definition = iconManifest[name];
  const paths: readonly IconPart[] = definition.paths;

  return (
    <svg
      {...svgProps}
      aria-hidden={hidden ? true : undefined}
      aria-labelledby={!hidden && title ? generatedTitleId : undefined}
      fill="none"
      focusable="false"
      height={size}
      role={hidden ? undefined : (svgProps.role ?? "img")}
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth={strokeWidth}
      viewBox="0 0 24 24"
      width={size}
      xmlns="http://www.w3.org/2000/svg"
    >
      {!hidden && title ? <title id={generatedTitleId}>{title}</title> : null}
      {paths.map((part, index) => (
        <path
          d={part.d}
          fill={part.fill ? "currentColor" : "none"}
          key={`${name}-${index}`}
          stroke={part.fill ? "none" : "currentColor"}
          strokeWidth={part.strokeWidth ?? strokeWidth}
          vectorEffect="non-scaling-stroke"
        />
      ))}
    </svg>
  );
}
