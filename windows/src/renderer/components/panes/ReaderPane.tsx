import DOMPurify from "dompurify";
import { useMemo } from "react";
import type { AppSnapshot, DocumentPayload, SelectionContext } from "../../../shared/contracts";
import { Icon } from "../Icon";
import { PaneHeader } from "../ThreePaneWorkspace";
import { CanonicalDocumentViewer } from "./CanonicalDocumentViewer";
import { PdfReader } from "./PdfReader";

interface Props {
  snapshot: AppSnapshot;
  document: DocumentPayload | null;
  onOpenItem(courseId: string, itemId: string): void;
  onSelection(value: SelectionContext | null): void;
  onSearch(): void;
  onHeaderDragStart(): void;
  onHeaderDragEnd(): void;
}

export function ReaderPane(props: Props) {
  const course = props.snapshot.activeCourse;
  const materials = course?.items.filter((item) => !item.isNotebookNote || item.appearsInMaterials) ?? [];
  const selected = props.document?.item ?? materials.find((item) => item.id === course?.activeItemId) ?? null;
  return (
    <div className="pane-root">
      <PaneHeader
        eyebrow="READ"
        title={selected?.title ?? "文稿"}
        detail={selected?.subtitle || course?.title}
        onDragStart={props.onHeaderDragStart}
        onDragEnd={props.onHeaderDragEnd}
        actions={
          <>
            <button className="icon-action" title="资料内搜索" onClick={props.onSearch}><Icon name="search" /></button>
            <button className="icon-action" title="更多"><Icon name="more" /></button>
          </>
        }
      />
      {!props.document ? (
        <div className="pane-picker">
          <span className="picker-seal">读</span>
          <h3>选择一篇文稿开始阅读</h3>
          <p>PDF、网页、Markdown 与纯文本都会在这里打开。</p>
          <div className="material-picker-list">
            {materials.map((item) => (
              <button key={item.id} onClick={() => course && props.onOpenItem(course.id, item.id)}>
                <Icon name={item.kind} size={17} />
                <span><strong>{item.title}</strong><small>{item.subtitle}</small></span>
              </button>
            ))}
          </div>
        </div>
      ) : props.document.mediaType === "application/pdf" && props.document.documentGrantUrl ? (
        <PdfReader
          url={props.document.documentGrantUrl}
          title={props.document.item.title}
          itemId={props.document.item.id}
          onSelection={props.onSelection}
        />
      ) : props.document.mediaType === "text/html" ? (
        <SanitizedHTMLFrame title={props.document.item.title} content={props.document.content ?? ""} />
      ) : props.document.mediaType === "text/markdown" ? (
        <CanonicalDocumentViewer
          itemId={props.document.item.id}
          markdown={props.document.content ?? ""}
          preferences={props.snapshot.preferences}
          onSelection={props.onSelection}
        />
      ) : (
        <article className="reader-paper">
          <pre className="plain-document">{props.document.content ?? ""}</pre>
        </article>
      )}
    </div>
  );
}

function SanitizedHTMLFrame({ title, content }: { title: string; content: string }) {
  const srcDoc = useMemo(() => sanitizedHTML(content), [content]);
  return (
    <iframe
      className="reader-html-frame"
      title={title}
      sandbox=""
      srcDoc={srcDoc}
    />
  );
}

function sanitizedHTML(content: string): string {
  return DOMPurify.sanitize(content, {
    WHOLE_DOCUMENT: true,
    FORBID_TAGS: [
      "script", "base", "form", "input", "button", "textarea", "select",
      "object", "embed", "iframe", "frame", "link", "meta", "audio",
      "video", "source",
    ],
    FORBID_ATTR: ["srcset", "formaction"],
  });
}
