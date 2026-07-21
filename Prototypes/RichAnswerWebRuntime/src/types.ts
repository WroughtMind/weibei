import type { ComponentType } from "react";

export type SubjectGroup = "stem" | "humanities" | "society";

export type SceneKey =
  | "math-line"
  | "physics-force"
  | "chem-equilibrium"
  | "biology-meiosis"
  | "text-argument"
  | "history-causality"
  | "geography-map"
  | "art-observation"
  | "statistics-sampling"
  | "finance-cashflow"
  | "economics-policy"
  | "code-sort";

export interface LearningSceneProps {
  title: string;
  prompt: string;
  onEvidence?: (evidenceID: string) => void;
}

export interface SceneDescriptor {
  key: SceneKey;
  group: SubjectGroup;
  subject: string;
  label: string;
  interaction: string;
  componentName: string;
  prompt: string;
  component: ComponentType<LearningSceneProps>;
}

