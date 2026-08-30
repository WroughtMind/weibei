import type { Ref } from "react";
import type { AppSnapshot, SaveNoteResult, SelectionContext } from "../../../shared/contracts";
import { Icon } from "../Icon";
import { PaneHeader } from "../ThreePaneWorkspace";
import {
  CanonicalNoteEditor,
  type CanonicalNoteEditorHandle,
} from "./CanonicalNoteEditor";

interface Props {
  snapshot: AppSnapshot;
  draft: string;
  editorGeneration: number | null;
  editorRef: Ref<CanonicalNoteEditorHandle>;
  status: SaveNoteResult["status"] | null;
  conflict: SaveNoteResult | null;
  onSelection(value: SelectionContext | null): void;
  onDraftChange(value: string, itemId: string, documentGeneration: number): void;
  onSave(): void;
  onOverwriteDisk(): void;
  onOpenItem(courseId: string, itemId: string): void;
  onHeaderDragStart(): void;
  onHeaderDragEnd(): void;
}

export function NotePane(props: Props) {
  const course = props.snapshot.activeCourse;
  const notes = course?.items.filter((item) => item.isNotebookNote) ?? [];
  const active = notes.find((item) => item.id === course?.activeNoteId) ?? null;
  return (
    <div className="pane-root">
      <PaneHeader
        eyebrow="NOTE"
        title={active?.title ?? "笔记"}
        detail={active ? saveLabel(props.status) : course?.title}
        onDragStart={props.onHeaderDragStart}
        onDragEnd={props.onHeaderDragEnd}
        actions={
          <>
            <button className="text-action" disabled={!active || props.editorGeneration === null} onClick={props.onSave}>保存</button>
            <button className="icon-action" title="更多"><Icon name="more" /></button>
          </>
        }
      />
      {props.conflict && (
        <div className="note-conflict-strip" role="alert">
          <span>磁盘上的笔记已变化，当前草稿仍保留。</span>
          <button onClick={props.onOverwriteDisk}>
            {props.conflict.diskMarkdown === null ? "重新创建" : "用草稿覆盖"}
          </button>
        </div>
      )}
      {active && props.editorGeneration !== null ? (
        <CanonicalNoteEditor
          ref={props.editorRef}
          key={`${active.id}:${props.editorGeneration}`}
          itemId={active.id}
          markdown={props.draft}
          documentGeneration={props.editorGeneration}
          preferences={props.snapshot.preferences}
          onChange={props.onDraftChange}
          onSelection={props.onSelection}
        />
      ) : active ? (
        <div className="reader-loading" role="status">正在打开《{active.title}》…</div>
      ) : (
        <div className="pane-picker">
          <span className="picker-seal">记</span>
          <h3>选一本笔记继续书写</h3>
          <p>笔记以 Markdown 文件保存在课程的“笔记”目录。</p>
          <div className="material-picker-list">
            {notes.map((item) => (
              <button key={item.id} onClick={() => course && props.onOpenItem(course.id, item.id)}>
                <Icon name="markdown" size={17} />
                <span><strong>{item.title}</strong><small>{item.subtitle}</small></span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function saveLabel(status: SaveNoteResult["status"] | null) {
  if (status === "saved") return "已保存";
  if (status === "conflict") return "外部修改冲突 · 草稿已保留";
  if (status === "unavailable") return "暂时无法写入 · 草稿已保留";
  return "Markdown";
}
