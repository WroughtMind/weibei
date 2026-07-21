import type { CSSProperties, PropsWithChildren, ReactNode } from "react";
import "./shared.css";

export function LearningSurface({
  eyebrow,
  title,
  prompt,
  accent,
  children,
  footer,
}: PropsWithChildren<{
  eyebrow: string;
  title: string;
  prompt: string;
  accent: string;
  footer?: ReactNode;
}>) {
  return (
    <section className="learning-surface" style={{ "--scene-accent": accent } as CSSProperties}>
      <header className="learning-surface__intro">
        <span>{eyebrow}</span>
        <h2>{title}</h2>
        <p>{prompt}</p>
      </header>
      {children}
      {footer ? <footer className="learning-surface__footer">{footer}</footer> : null}
    </section>
  );
}

export function EvidenceButton({
  evidenceID,
  label,
  onEvidence,
}: {
  evidenceID: string;
  label: string;
  onEvidence?: (evidenceID: string) => void;
}) {
  return (
    <button className="evidence-button" type="button" onClick={() => onEvidence?.(evidenceID)}>
      <span>↗</span>
      {label}
    </button>
  );
}

export function InlineReadout({ label, value, detail }: { label: string; value: ReactNode; detail?: ReactNode }) {
  return (
    <div className="inline-readout">
      <span>{label}</span>
      <strong>{value}</strong>
      {detail ? <small>{detail}</small> : null}
    </div>
  );
}

export function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(maximum, Math.max(minimum, value));
}
