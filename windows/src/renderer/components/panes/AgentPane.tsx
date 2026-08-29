import { useMemo, useState } from "react";
import type { AppSnapshot, SelectionContext } from "../../../shared/contracts";
import { Icon } from "../Icon";
import { PaneHeader } from "../ThreePaneWorkspace";

interface Props {
  snapshot: AppSnapshot;
  selection: SelectionContext | null;
  onClearSelection(): void;
  onOpenSource(itemId: string): void;
  onSnapshot(snapshot: AppSnapshot): void;
  onFailure(message: string): void;
  onHeaderDragStart(): void;
  onHeaderDragEnd(): void;
}

export function AgentPane(props: Props) {
  const [question, setQuestion] = useState("");
  const [sending, setSending] = useState(false);
  const [activeRequestId, setActiveRequestId] = useState<string | null>(null);
  const course = props.snapshot.activeCourse;
  const session = course?.sessions.find((candidate) => candidate.id === course.activeSessionId) ?? course?.sessions[0] ?? null;
  const messages = session?.messages ?? [];
  const generating = messages.some((message) => message.completionState === "generating");
  const configured = props.snapshot.provider.hasCredential;
  const title = session?.title || "新 Chat";
  const suggestions = useMemo(() => ["梳理这门课的知识地图", "概括当前文稿的论证", "把关键概念整理成笔记"], []);

  async function ensureSession() {
    if (!course || !window.weiBei) return null;
    if (session) return session;
    const created = await window.weiBei.createSession(course.id);
    const next = await window.weiBei.selectSession(course.id, created.id);
    props.onSnapshot(next);
    return created;
  }

  async function send(value = question) {
    const trimmed = value.trim();
    if (!trimmed || !course || !window.weiBei || sending || generating) return;
    setSending(true);
    try {
      const target = await ensureSession();
      if (!target) return;
      const result = await window.weiBei.startAgent({
        courseId: course.id,
        sessionId: target.id,
        question: trimmed,
        selection: props.selection,
      });
      setActiveRequestId(result.requestId);
      setQuestion("");
    } catch (error) {
      props.onFailure(error instanceof Error ? error.message : "Chat 没有发出");
    } finally {
      setSending(false);
    }
  }

  async function cancel() {
    if (!activeRequestId || !window.weiBei) return;
    setSending(true);
    try {
      await window.weiBei.cancelAgent(activeRequestId);
    } catch (error) {
      props.onFailure(error instanceof Error ? error.message : "无法停止当前回答");
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="pane-root agent-pane-root">
      <PaneHeader
        eyebrow="CHAT"
        title={title}
        detail={course?.title}
        onDragStart={props.onHeaderDragStart}
        onDragEnd={props.onHeaderDragEnd}
        actions={<button className="icon-action" title="更多"><Icon name="more" /></button>}
      />
      <div className="conversation-scroll">
        {messages.length === 0 ? (
          <section className="agent-welcome">
            <span className="agent-seal">魏</span>
            <h3>和课程一起思考</h3>
            <p>{configured ? "我会先阅读课程材料，再给出带出处的回答。" : "在设置里连接模型后，我会基于课程材料回答，并把写入操作交给你确认。"}</p>
            <div className="suggestion-list">
              {suggestions.map((suggestion) => <button key={suggestion} onClick={() => void send(suggestion)}>{suggestion}<span>↗</span></button>)}
            </div>
          </section>
        ) : (
          <div className="message-list">
            {messages.map((message) => (
              <article key={message.id} className={`message-row role-${message.role}`}>
                <header>{message.role === "user" ? "你" : "魏碑"}</header>
                <div className={message.completionState === "generating" ? "is-streaming" : ""}>{message.text || "正在阅读课程材料…"}</div>
                {message.sources.length > 0 && (
                  <footer>{message.sources.map((source) => (
                    <button
                      key={source.id}
                      disabled={!source.itemId}
                      onClick={() => source.itemId && props.onOpenSource(source.itemId)}
                    >
                      〔{source.label}〕
                    </button>
                  ))}</footer>
                )}
              </article>
            ))}
          </div>
        )}
      </div>
      <div className="agent-composer-wrap">
        {!configured && <button className="agent-readiness">尚未连接模型 · 打开设置</button>}
        {props.selection && (
          <div className="selection-context-chip" title={props.selection.text}>
            <span>选区</span>
            <q>{props.selection.text}</q>
            <button aria-label="移除选区" onClick={props.onClearSelection}>×</button>
          </div>
        )}
        <div className="agent-composer">
          <textarea
            rows={1}
            value={question}
            placeholder="问课程、文稿或笔记……"
            onChange={(event) => setQuestion(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter" && !event.shiftKey && !generating) {
                event.preventDefault();
                void send();
              }
            }}
          />
          <button
            className="send-button"
            aria-label={generating ? "停止" : "发送"}
            disabled={sending || (!generating && !question.trim())}
            onClick={() => void (generating ? cancel() : send())}
          >
            <Icon name={generating ? "stop" : "send"} size={17} />
          </button>
        </div>
        <small className="composer-footnote">回答可能有误；引用会定位到你的课程材料。</small>
      </div>
    </div>
  );
}
