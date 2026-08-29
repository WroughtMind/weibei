import { useMemo, useRef, useState, type DragEvent } from "react";
import type {
  AppSnapshot,
  DocumentPayload,
  PaneRole,
  Preferences,
  SaveNoteResult,
  SelectionContext,
} from "../../shared/contracts";
import { AgentPane } from "./panes/AgentPane";
import { NotePane } from "./panes/NotePane";
import { ReaderPane } from "./panes/ReaderPane";

interface Props {
  snapshot: AppSnapshot;
  document: DocumentPayload | null;
  noteDraft: string;
  noteStatus: SaveNoteResult["status"] | null;
  noteConflict: SaveNoteResult | null;
  selection: SelectionContext | null;
  onDraftChange(value: string): void;
  onSelection(value: SelectionContext | null): void;
  onSaveNote(): void;
  onUseDiskNote(): void;
  onOverwriteDiskNote(): void;
  onOpenItem(courseId: string, itemId: string, target: "reader" | "notes"): void;
  onSnapshot(snapshot: AppSnapshot): void;
  onPreferences(patch: Partial<Preferences>): void;
  onSearch(): void;
  onFailure(message: string): void;
}

export function ThreePaneWorkspace(props: Props) {
  const { preferences } = props.snapshot;
  const [dragging, setDragging] = useState<PaneRole | null>(null);
  const hostRef = useRef<HTMLDivElement>(null);
  const visibleOrder = preferences.paneOrder.filter((pane) => preferences.visiblePanes.includes(pane));
  const gridTemplateColumns = useMemo(
    () =>
      preferences.paneOrder
        .map((pane) => {
          if (!preferences.visiblePanes.includes(pane)) return "0px";
          return `minmax(0, ${preferences.paneWidths[pane]}fr)`;
        })
        .join(" "),
    [preferences],
  );

  function dropPane(event: DragEvent, target: PaneRole) {
    event.preventDefault();
    if (!dragging || dragging === target) return setDragging(null);
    const next = [...preferences.paneOrder];
    const from = next.indexOf(dragging);
    const to = next.indexOf(target);
    next.splice(from, 1);
    next.splice(to, 0, dragging);
    setDragging(null);
    props.onPreferences({ paneOrder: next });
  }

  function resize(left: PaneRole, right: PaneRole, startX: number) {
    const host = hostRef.current;
    if (!host) return;
    const width = host.getBoundingClientRect().width;
    const initial = { ...preferences.paneWidths };
    const total = initial[left] + initial[right];
    const move = (event: PointerEvent) => {
      const delta = ((event.clientX - startX) / Math.max(width, 1)) * visibleOrder.length;
      const nextLeft = Math.max(0.36, Math.min(total - 0.36, initial[left] + delta));
      props.onPreferences({
        paneWidths: { ...initial, [left]: nextLeft, [right]: total - nextLeft },
      });
    };
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up, { once: true });
  }

  return (
    <div
      className="three-pane-workspace"
      ref={hostRef}
      style={{ gridTemplateColumns }}
      data-pane-count={visibleOrder.length}
    >
      {preferences.paneOrder.map((pane, index) => {
        const visible = preferences.visiblePanes.includes(pane);
        const nextVisible = preferences.paneOrder.slice(index + 1).find((candidate) => preferences.visiblePanes.includes(candidate));
        return (
          <section
            key={pane}
            className={`workspace-pane pane-${pane} ${visible ? "is-visible" : "is-hidden"} ${dragging === pane ? "is-dragging" : ""}`}
            onDragOver={(event) => event.preventDefault()}
            onDrop={(event) => dropPane(event, pane)}
          >
            {pane === "reader" && (
              <ReaderPane
                snapshot={props.snapshot}
                document={props.document}
                onOpenItem={(courseId, itemId) => props.onOpenItem(courseId, itemId, "reader")}
                onSelection={props.onSelection}
                onSearch={props.onSearch}
                onHeaderDragStart={() => setDragging("reader")}
                onHeaderDragEnd={() => setDragging(null)}
              />
            )}
            {pane === "agent" && (
              <AgentPane
                snapshot={props.snapshot}
                selection={props.selection}
                onClearSelection={() => props.onSelection(null)}
                onOpenSource={(itemId) => {
                  const courseId = props.snapshot.activeCourse?.id;
                  if (courseId) props.onOpenItem(courseId, itemId, "reader");
                }}
                onSnapshot={props.onSnapshot}
                onFailure={props.onFailure}
                onHeaderDragStart={() => setDragging("agent")}
                onHeaderDragEnd={() => setDragging(null)}
              />
            )}
            {pane === "notes" && (
              <NotePane
                snapshot={props.snapshot}
                draft={props.noteDraft}
                status={props.noteStatus}
                conflict={props.noteConflict}
                onSelection={props.onSelection}
                onDraftChange={props.onDraftChange}
                onSave={props.onSaveNote}
                onUseDisk={props.onUseDiskNote}
                onOverwriteDisk={props.onOverwriteDiskNote}
                onOpenItem={(courseId, itemId) => props.onOpenItem(courseId, itemId, "notes")}
                onHeaderDragStart={() => setDragging("notes")}
                onHeaderDragEnd={() => setDragging(null)}
              />
            )}
            {visible && nextVisible && (
              <div
                className="pane-divider"
                role="separator"
                aria-orientation="vertical"
                onPointerDown={(event) => resize(pane, nextVisible, event.clientX)}
              />
            )}
          </section>
        );
      })}
    </div>
  );
}

export function PaneHeader(props: {
  eyebrow: string;
  title: string;
  detail?: string;
  actions?: React.ReactNode;
  onDragStart(): void;
  onDragEnd(): void;
}) {
  return (
    <header
      className="pane-header"
      draggable
      onDragStart={(event) => {
        event.dataTransfer.effectAllowed = "move";
        props.onDragStart();
      }}
      onDragEnd={props.onDragEnd}
    >
      <div className="pane-heading">
        <span className="pane-eyebrow">{props.eyebrow}</span>
        <div><h2>{props.title}</h2>{props.detail && <small>{props.detail}</small>}</div>
      </div>
      <div className="pane-actions">{props.actions}</div>
    </header>
  );
}
