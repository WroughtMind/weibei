import { useMemo, useState } from "react";
import type { AppSnapshot } from "../../shared/contracts";
import { Icon } from "./Icon";

type Page = "hub" | "map" | "records" | "memory";

interface Props {
  snapshot: AppSnapshot;
  onClose(): void;
  onSnapshot(snapshot: AppSnapshot): void;
  onOpenItem(courseId: string, itemId: string): void;
}

const pages: Array<[Page, string]> = [
  ["hub", "概览"],
  ["map", "文稿与笔记"],
  ["records", "对话"],
  ["memory", "课程记忆"],
];

export function CourseSpace(props: Props) {
  const [page, setPage] = useState<Page>("hub");
  const [query, setQuery] = useState("");
  const course = props.snapshot.activeCourse;
  const materials = course?.items.filter((item) => !item.isNotebookNote || item.appearsInMaterials) ?? [];
  const notes = course?.items.filter((item) => item.isNotebookNote) ?? [];
  const filtered = useMemo(() => {
    const needle = query.trim().toLocaleLowerCase();
    if (!needle) return course?.items ?? [];
    return (course?.items ?? []).filter((item) => `${item.title}\n${item.subtitle}`.toLocaleLowerCase().includes(needle));
  }, [course?.items, query]);

  return (
    <section className="course-space-overlay" role="dialog" aria-modal="true" aria-label="课程空间">
      <header className="course-space-header">
        <div className="course-space-title">
          <span className="course-seal large">{course?.title.slice(0, 1) ?? "课"}</span>
          <div><span className="overline">COURSE SPACE</span><h1>{course?.title ?? "课程空间"}</h1></div>
        </div>
        <nav className="course-tabs" aria-label="课程空间页面">
          {pages.map(([id, label]) => <button key={id} className={page === id ? "is-current" : ""} onClick={() => setPage(id)}>{label}</button>)}
        </nav>
        <div className="course-space-tools">
          <label className="course-search"><Icon name="search" size={15} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="搜索课程" /></label>
          <button className="icon-action" aria-label="关闭课程空间" onClick={props.onClose}><Icon name="close" size={19} /></button>
        </div>
      </header>
      <div className="course-space-body">
        {!course ? <EmptyCourse /> : page === "hub" ? (
          <CourseHub course={course} materials={materials} notes={notes} onOpen={props.onOpenItem} />
        ) : page === "map" ? (
          <DocsAndNotes courseId={course.id} items={filtered} onOpen={props.onOpenItem} />
        ) : page === "records" ? (
          <Records snapshot={props.snapshot} onSnapshot={props.onSnapshot} />
        ) : (
          <Memory />
        )}
      </div>
    </section>
  );
}

function CourseHub(props: {
  course: NonNullable<AppSnapshot["activeCourse"]>;
  materials: NonNullable<AppSnapshot["activeCourse"]>["items"];
  notes: NonNullable<AppSnapshot["activeCourse"]>["items"];
  onOpen(courseId: string, itemId: string): void;
}) {
  const recent = [...props.course.items].slice(0, 6);
  return (
    <div className="course-hub-grid">
      <section className="hub-welcome">
        <span className="overline">继续学习</span>
        <h2>{props.course.title}</h2>
        <p>把文稿、笔记和 Chat 放在同一个课程语境里。魏碑会保留你的阅读位置与学习脉络。</p>
        {recent[0] && <button className="primary-paper-button" onClick={() => props.onOpen(props.course.id, recent[0].id)}>继续上次学习 <span>→</span></button>}
      </section>
      <section className="hub-stat-grid">
        <Stat value={props.materials.length} label="篇文稿" seal="文" />
        <Stat value={props.notes.length} label="本笔记" seal="记" />
        <Stat value={props.course.sessions.length} label="个 Chat" seal="问" />
      </section>
      <section className="hub-card recent-card">
        <header><div><span className="overline">RECENT</span><h3>最近内容</h3></div><button>查看全部</button></header>
        <div className="recent-grid">
          {recent.map((item) => (
            <button key={item.id} onClick={() => props.onOpen(props.course.id, item.id)}>
              <Icon name={item.kind} size={18} />
              <span><strong>{item.title}</strong><small>{item.isNotebookNote ? "笔记" : "文稿"} · {item.subtitle}</small></span>
              <span>›</span>
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}

function Stat({ value, label, seal }: { value: number; label: string; seal: string }) {
  return <article className="hub-stat"><span>{seal}</span><div><strong>{value}</strong><small>{label}</small></div></article>;
}

function DocsAndNotes(props: {
  courseId: string;
  items: NonNullable<AppSnapshot["activeCourse"]>["items"];
  onOpen(courseId: string, itemId: string): void;
}) {
  const materials = props.items.filter((item) => !item.isNotebookNote || item.appearsInMaterials);
  const notes = props.items.filter((item) => item.isNotebookNote);
  return (
    <div className="relations-layout">
      <Column title="文稿" caption="DOCS" items={materials} courseId={props.courseId} onOpen={props.onOpen} />
      <div className="relation-thread"><span /><span /><span /><span /></div>
      <Column title="笔记" caption="NOTES" items={notes} courseId={props.courseId} onOpen={props.onOpen} />
    </div>
  );
}

function Column(props: { title: string; caption: string; items: NonNullable<AppSnapshot["activeCourse"]>["items"]; courseId: string; onOpen(courseId: string, itemId: string): void }) {
  return (
    <section className="relation-column">
      <header><span className="overline">{props.caption}</span><h2>{props.title}</h2></header>
      {props.items.length === 0 ? <p className="drawer-empty">尚无内容</p> : props.items.map((item) => (
        <button key={item.id} onClick={() => props.onOpen(props.courseId, item.id)}>
          <span className="relation-icon"><Icon name={item.kind} size={18} /></span>
          <span><strong>{item.title}</strong><small>{item.subtitle || item.relativePath}</small></span>
          <span>›</span>
        </button>
      ))}
    </section>
  );
}

function Records({ snapshot, onSnapshot }: { snapshot: AppSnapshot; onSnapshot(value: AppSnapshot): void }) {
  const course = snapshot.activeCourse;
  if (!course) return <EmptyCourse />;
  return (
    <section className="records-page">
      <header><div><span className="overline">CONVERSATIONS</span><h2>对话</h2></div><button className="primary-paper-button" onClick={async () => {
        if (!window.weiBei) return;
        const session = await window.weiBei.createSession(course.id);
        onSnapshot(await window.weiBei.selectSession(course.id, session.id));
      }}>＋ 新 Chat</button></header>
      <div className="records-list">
        {course.sessions.length === 0 ? <p className="drawer-empty">课程还没有 Chat。</p> : course.sessions.map((session) => (
          <button key={session.id} onClick={async () => window.weiBei && onSnapshot(await window.weiBei.selectSession(course.id, session.id))}>
            <span className="agent-seal small">问</span>
            <span><strong>{session.title}</strong><small>{session.messages.length} 条消息 · {new Date(session.updatedAt).toLocaleString()}</small></span>
            <span>›</span>
          </button>
        ))}
      </div>
    </section>
  );
}

function Memory() {
  return (
    <section className="memory-page">
      <span className="memory-watermark">忆</span>
      <span className="overline">COURSE MEMORY</span>
      <h2>课程记忆</h2>
      <p>魏碑会在得到你确认后，记住课程中的稳定偏好、学习目标和已经掌握的概念。记忆有来源、可查看，也可以随时撤销。</p>
      <div className="memory-empty"><span>尚无课程记忆</span><small>继续阅读和对话后，经过确认的记忆会出现在这里。</small></div>
    </section>
  );
}

function EmptyCourse() {
  return <div className="pane-picker"><span className="picker-seal">课</span><h3>先从资料库选择一门课程</h3></div>;
}
