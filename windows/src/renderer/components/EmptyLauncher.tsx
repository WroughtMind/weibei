import { useMemo } from "react";
import type { InterfaceLanguage } from "../../shared/contracts";

const lines = [
  ["读书破万卷，下笔如有神。", "杜甫"],
  ["纸上得来终觉浅，绝知此事要躬行。", "陆游"],
  ["博观而约取，厚积而薄发。", "苏轼"],
  ["知者行之始，行者知之成。", "王阳明"],
] as const;

interface Props {
  language: InterfaceLanguage;
  hasCourses: boolean;
  onLibrary(): void;
  onCreateCourse(): void;
  onAdopt(): void;
}

export function EmptyLauncher(props: Props) {
  const line = useMemo(() => lines[Math.floor(Date.now() / 86_400_000) % lines.length], []);
  const hour = new Date().getHours();
  const greeting = hour < 5 ? "夜深了" : hour < 11 ? "上午好" : hour < 14 ? "中午好" : hour < 18 ? "下午好" : "晚上好";
  return (
    <div className="empty-launcher">
      <div className="empty-watermark" aria-hidden="true">魏</div>
      <section className="empty-entry-cluster">
        <h1>{props.language === "zh-Hans" ? greeting : "Welcome to WeiBei"}</h1>
        <div className="empty-actions">
          <EntryButton seal="库" title={props.hasCourses ? "打开资料库" : "资料库"} detail="课程、文稿与笔记" onClick={props.onLibrary} />
          <EntryButton seal="新" title="新建课程" detail="从一门课开始" onClick={props.onCreateCourse} />
          <EntryButton seal="收" title="收录课程" detail="采用现有文件夹" onClick={props.onAdopt} />
        </div>
      </section>
      <button className="daily-line" aria-label="每日一句">
        <span>“{line[0]}”</span>
        <small>— {line[1]}</small>
      </button>
    </div>
  );
}

function EntryButton(props: { seal: string; title: string; detail: string; onClick(): void }) {
  return (
    <button className="entry-button" onClick={props.onClick}>
      <span className="entry-seal">{props.seal}</span>
      <strong>{props.title}</strong>
      <small>{props.detail}</small>
    </button>
  );
}
