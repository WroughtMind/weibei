import type { AppSnapshot } from "../../shared/contracts";
import { ChromeButton } from "./TopBar";

interface Props {
  open: boolean;
  snapshot: AppSnapshot;
  onClose(): void;
  onSelectCourse(id: string): void;
  onCreateCourse(): void;
  onImport(): void;
  onCreateNote(): void;
}

export function LibraryDrawer(props: Props) {
  return (
    <>
      <button
        className={`drawer-scrim ${props.open ? "is-open" : ""}`}
        aria-label="关闭资料库"
        tabIndex={props.open ? 0 : -1}
        onClick={props.onClose}
      />
      <aside className={`library-drawer ${props.open ? "is-open" : ""}`} aria-hidden={!props.open}>
        <header className="drawer-header">
          <div><span className="overline">WEI BEI</span><h2>课程资料库</h2></div>
          <ChromeButton label="关闭" glyph="close" onClick={props.onClose} />
        </header>
        <div className="drawer-actions">
          <button onClick={props.onCreateCourse}><span>＋</span> 新建课程</button>
          <button onClick={props.onImport} disabled={!props.snapshot.activeCourse}><span>↥</span> 导入文稿</button>
          <button onClick={props.onCreateNote} disabled={!props.snapshot.activeCourse}><span>✎</span> 新建笔记</button>
        </div>
        <section className="drawer-section">
          <h3>课程</h3>
          {props.snapshot.courses.length === 0 ? (
            <p className="drawer-empty">尚无课程。创建课程后，文稿与笔记都会留在你选择的资料库中。</p>
          ) : (
            <ul className="course-list">
              {props.snapshot.courses.map((course) => (
                <li key={course.id}>
                  <button
                    className={props.snapshot.activeCourse?.id === course.id ? "is-current" : ""}
                    onClick={() => props.onSelectCourse(course.id)}
                  >
                    <span className={`course-seal color-${course.colorIndex % 6}`}>{course.title.slice(0, 1)}</span>
                    <span><strong>{course.title}</strong><small>{course.itemCount} 项资料</small></span>
                    <span className="row-chevron">›</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>
        <footer className="drawer-footer" title={props.snapshot.libraryRootPath}>
          <span className="persist-dot" />
          <span>{props.snapshot.libraryRootPath || "尚未选择资料库位置"}</span>
        </footer>
      </aside>
    </>
  );
}
