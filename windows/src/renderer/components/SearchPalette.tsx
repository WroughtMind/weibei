import { useEffect, useRef, useState } from "react";
import type { AppSnapshot, SearchResult } from "../../shared/contracts";
import { Icon } from "./Icon";

export interface SearchPaletteProps {
  snapshot: AppSnapshot;
  onClose(): void;
  onOpenItem(itemId: string): void;
}

type SearchState = "idle" | "loading" | "ready" | "error";

const kindLabels: Record<SearchResult["kind"], string> = {
  html: "网页",
  pdf: "PDF",
  markdown: "Markdown",
  text: "文本",
};

/** Search the active course without making the renderer aware of IPC details. */
export function SearchPalette(props: SearchPaletteProps) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [state, setState] = useState<SearchState>("idle");
  const [error, setError] = useState<string | null>(null);
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const requestRef = useRef(0);
  const courseId = props.snapshot.activeCourse?.id ?? null;

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  useEffect(() => {
    const normalizedQuery = query.trim();
    const requestId = ++requestRef.current;
    let cancelled = false;

    setResults([]);
    setActiveIndex(0);
    setError(null);

    if (!courseId || !normalizedQuery) {
      setState("idle");
      return () => {
        cancelled = true;
      };
    }

    const timer = window.setTimeout(() => {
      if (cancelled) return;
      setState("loading");
      Promise.resolve()
        .then(() => {
          if (!window.weiBei?.search) throw new Error("search-unavailable");
          return window.weiBei.search({ courseId, query: normalizedQuery, limit: 30 });
        })
        .then((nextResults) => {
          if (cancelled || requestRef.current !== requestId) return;
          setResults(nextResults);
          setState("ready");
        })
        .catch(() => {
          if (cancelled || requestRef.current !== requestId) return;
          setResults([]);
          setState("error");
          setError("搜索暂时不可用，请稍后重试。");
        });
    }, 150);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [courseId, query]);

  const selectResult = (result: SearchResult | undefined) => {
    if (!result) return;
    props.onOpenItem(result.itemId);
    props.onClose();
  };

  const handleKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Escape") {
      event.preventDefault();
      props.onClose();
      return;
    }
    if (!results.length) return;
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveIndex((index) => (index + 1) % results.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((index) => (index - 1 + results.length) % results.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      selectResult(results[activeIndex]);
    }
  };

  const activeResultId = results[activeIndex] ? resultId(results[activeIndex], activeIndex) : undefined;

  return (
    <div className="search-palette-scrim" role="presentation" onMouseDown={(event) => {
      if (event.target === event.currentTarget) props.onClose();
    }}>
      <section
        className="search-palette"
        role="dialog"
        aria-modal="true"
        aria-labelledby="search-palette-title"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <header className="search-palette-header">
          <div className="search-palette-heading">
            <Icon name="search" size={18} />
            <div>
              <span className="overline">SEARCH</span>
              <h2 id="search-palette-title">搜索课程资料</h2>
            </div>
          </div>
          <button className="search-palette-close" type="button" aria-label="关闭搜索" onClick={props.onClose}>
            <Icon name="close" size={17} />
          </button>
        </header>

        <div className="search-palette-input-wrap">
          <Icon name="search" size={16} />
          <input
            ref={inputRef}
            type="search"
            value={query}
            placeholder={courseId ? "搜索标题、正文或笔记" : "请先选择课程"}
            disabled={!courseId}
            aria-label="搜索课程资料"
            aria-controls="search-palette-results"
            aria-activedescendant={activeResultId}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={handleKeyDown}
          />
          <kbd>Esc</kbd>
        </div>

        <div className="search-palette-body" id="search-palette-results" role="listbox" aria-label="搜索结果" aria-busy={state === "loading"}>
          {state === "loading" && <p className="search-palette-status">正在搜索…</p>}
          {state === "error" && <p className="search-palette-status is-error" role="alert">{error}</p>}
          {state === "idle" && <p className="search-palette-status">输入关键词，搜索当前课程中的资料。</p>}
          {state === "ready" && results.length === 0 && <p className="search-palette-status">没有找到匹配的资料。</p>}
          {results.length > 0 && (
            <ul className="search-palette-results">
              {results.map((result, index) => (
                <li key={`${result.itemId}-${index}`}>
                  <button
                    id={resultId(result, index)}
                    type="button"
                    role="option"
                    aria-selected={index === activeIndex}
                    className={index === activeIndex ? "is-active" : ""}
                    onMouseEnter={() => setActiveIndex(index)}
                    onClick={() => selectResult(result)}
                  >
                    <span className="search-result-icon"><Icon name={result.kind === "pdf" ? "reader" : result.kind === "markdown" ? "note" : "reader"} size={16} /></span>
                    <span className="search-result-copy">
                      <strong>{result.title}</strong>
                      <small>{result.excerpt || "无摘要"}</small>
                    </span>
                    <span className="search-result-kind">{kindLabels[result.kind]}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
        <footer className="search-palette-footer"><span>↑↓ 选择</span><span>Enter 打开</span><span>Esc 关闭</span></footer>
      </section>
    </div>
  );
}

function resultId(result: SearchResult, index: number): string {
  return `search-result-${result.itemId.replace(/[^a-zA-Z0-9_-]/g, "-")}-${index}`;
}
