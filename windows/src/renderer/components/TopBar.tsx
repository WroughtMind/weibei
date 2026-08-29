import type { AppSnapshot, PaneRole } from "../../shared/contracts";
import { Icon, type IconName } from "./Icon";

interface TopBarProps {
  snapshot: AppSnapshot;
  persistState: "saved" | "unsaved" | "conflict";
  onToggleLibrary(): void;
  onTogglePane(pane: PaneRole): void;
  onCourseSpace(): void;
  onSearch(): void;
  onSettings(): void;
  onToggleTheme(): void;
}

export function TopBar(props: TopBarProps) {
  const { preferences } = props.snapshot;
  return (
    <header className="top-bar" data-testid="top-bar">
      <div className="top-bar-left">
        <ChromeButton label="课程资料库" glyph="library" onClick={props.onToggleLibrary} />
        <ChromeButton label="后退" glyph="back" disabled />
        <ChromeButton label="前进" glyph="forward" disabled />
      </div>
      <div className="pane-toggle-cluster" role="group" aria-label="工作台栏位">
        {(["reader", "agent", "notes"] as const).map((pane) => (
          <ChromeButton
            key={pane}
            label={{ reader: "文稿", agent: "Chat", notes: "笔记" }[pane]}
            glyph={{ reader: "reader", agent: "chat", notes: "note" }[pane] as IconName}
            active={preferences.visiblePanes.includes(pane)}
            onClick={() => props.onTogglePane(pane)}
          />
        ))}
      </div>
      <div className="top-bar-right">
        <button className="course-pill" onClick={props.onCourseSpace} disabled={!props.snapshot.activeCourse}>
          <span className="course-pill-dot" />
          <span>{props.snapshot.activeCourse?.title ?? "课程空间"}</span>
        </button>
        <ChromeButton label="搜索" glyph="search" disabled={!props.snapshot.activeCourse} onClick={props.onSearch} />
        <ChromeButton label="切换深浅外观" glyph="moon" onClick={props.onToggleTheme} />
        <span
          className={`persist-dot is-${props.persistState}`}
          title={{
            saved: "全部更改已保存",
            unsaved: "草稿已在本机暂存",
            conflict: "外部修改冲突",
          }[props.persistState]}
        />
        <ChromeButton label="设置" glyph="settings" onClick={props.onSettings} />
      </div>
    </header>
  );
}

export interface ChromeButtonProps {
  label: string;
  glyph: IconName;
  active?: boolean;
  disabled?: boolean;
  onClick?: () => void;
  className?: string;
}

export function ChromeButton({ label, glyph, active, disabled, onClick, className = "" }: ChromeButtonProps) {
  return (
    <button
      className={`chrome-button ${active ? "is-active" : ""} ${className}`}
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
    >
      <Icon name={glyph} size={15.5} />
    </button>
  );
}
