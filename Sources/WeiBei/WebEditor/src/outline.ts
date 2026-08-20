export type EditorOutlineItem = {
  id: string;
  index: number;
  level: number;
  title: string;
  position: number;
};

/** Body edits can move a heading without changing the logical outline. */
export const outlineChangeKey = (items: EditorOutlineItem[]) => JSON.stringify(
  items.map(({ level, title }) => [level, title]),
);
