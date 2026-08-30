import { useEffect, useRef, useState } from "react";
import * as pdfjs from "pdfjs-dist";
import workerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import type { SelectionContext } from "../../../shared/contracts";
import { Icon } from "../Icon";

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

type PdfSearchMatch = {
  pageNumber: number;
  occurrenceOnPage: number;
};

type SearchRun = {
  cancelled: boolean;
};

export function PdfReader({
  url,
  title,
  itemId,
  onSelection,
}: {
  url: string;
  title: string;
  itemId: string;
  onSelection(value: SelectionContext | null): void;
}) {
  const [pages, setPages] = useState<Array<{ pageNumber: number }>>([]);
  const [pdfDocument, setPdfDocument] = useState<pdfjs.PDFDocumentProxy | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [availableWidth, setAvailableWidth] = useState(720);
  const [currentPage, setCurrentPage] = useState(1);
  const [zoom, setZoom] = useState(1);
  const [continuousScroll, setContinuousScroll] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");
  const [searchMatches, setSearchMatches] = useState<PdfSearchMatch[]>([]);
  const [activeMatchIndex, setActiveMatchIndex] = useState(0);
  const [searching, setSearching] = useState(false);
  const loadingTaskRef = useRef<ReturnType<typeof pdfjs.getDocument> | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const currentPageRef = useRef(1);
  const pageTextCacheRef = useRef(new Map<number, string>());
  const searchRunRef = useRef<SearchRun | null>(null);

  useEffect(() => {
    const task = pdfjs.getDocument({ url, rangeChunkSize: 256 * 1024 });
    let cancelled = false;
    loadingTaskRef.current = task;
    if (searchRunRef.current) searchRunRef.current.cancelled = true;
    pageTextCacheRef.current.clear();
    setError(null);
    setPdfDocument(null);
    setPages([]);
    setCurrentPage(1);
    currentPageRef.current = 1;
    setZoom(1);
    setSearchQuery("");
    setSearchMatches([]);
    setActiveMatchIndex(0);
    setSearching(false);

    void task.promise.then(
      (pdf) => {
        if (cancelled) return;
        setPdfDocument(pdf);
        setPages(Array.from({ length: pdf.numPages }, (_, pageNumber) => ({ pageNumber: pageNumber + 1 })));
      },
      (reason: unknown) => {
        if (!cancelled) setError(reason instanceof Error ? reason.message : "PDF 无法打开");
      },
    );
    return () => {
      cancelled = true;
      if (searchRunRef.current) searchRunRef.current.cancelled = true;
      if (loadingTaskRef.current === task) loadingTaskRef.current = null;
      void task.destroy();
    };
  }, [url]);

  useEffect(() => {
    const target = scrollRef.current;
    if (!target) return;
    const observer = new ResizeObserver(([entry]) => {
      if (entry) setAvailableWidth(Math.max(220, entry.contentRect.width - 40));
    });
    observer.observe(target);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const target = scrollRef.current;
    if (!target || pages.length === 0) return;
    let frame: number | null = null;

    const updateCurrentPage = () => {
      frame = null;
      const rootRect = target.getBoundingClientRect();
      const readingLine = rootRect.top + Math.min(rootRect.height * 0.38, 180);
      let candidate: { pageNumber: number; distance: number } | null = null;
      for (const page of target.querySelectorAll<HTMLElement>(".pdf-page[data-page-index]")) {
        const rect = page.getBoundingClientRect();
        if (rect.bottom <= rootRect.top || rect.top >= rootRect.bottom) continue;
        const distance = Math.abs((rect.top + rect.bottom) / 2 - readingLine);
        const pageNumber = Number(page.dataset.pageIndex) + 1;
        if (Number.isInteger(pageNumber) && (!candidate || distance < candidate.distance)) {
          candidate = { pageNumber, distance };
        }
      }
      if (candidate && candidate.pageNumber !== currentPageRef.current) {
        currentPageRef.current = candidate.pageNumber;
        setCurrentPage(candidate.pageNumber);
      }
    };

    const scheduleUpdate = () => {
      if (frame === null) frame = window.requestAnimationFrame(updateCurrentPage);
    };
    const observer = new IntersectionObserver(scheduleUpdate, {
      root: target,
      rootMargin: "80px 0px",
      threshold: [0, 0.25, 0.5, 0.75, 1],
    });
    target.querySelectorAll<HTMLElement>(".pdf-page[data-page-index]").forEach((page) => observer.observe(page));
    target.addEventListener("scroll", scheduleUpdate, { passive: true });
    scheduleUpdate();
    return () => {
      observer.disconnect();
      target.removeEventListener("scroll", scheduleUpdate);
      if (frame !== null) window.cancelAnimationFrame(frame);
    };
  }, [pages.length, continuousScroll]);

  useEffect(() => {
    if (searchRunRef.current) searchRunRef.current.cancelled = true;
    const run: SearchRun = { cancelled: false };
    searchRunRef.current = run;
    const query = normalizeSearchText(searchQuery);
    setSearchMatches([]);
    setActiveMatchIndex(0);
    if (!query || !pdfDocument || pages.length === 0) {
      setSearching(false);
      return () => {
        run.cancelled = true;
      };
    }

    setSearching(true);
    const timer = window.setTimeout(() => {
      const matches: PdfSearchMatch[] = [];
      let nextPageNumber = 1;

      const scanPage = async () => {
        while (!run.cancelled) {
          const pageNumber = nextPageNumber;
          nextPageNumber += 1;
          if (pageNumber > pages.length) return;
          let pageHandle: pdfjs.PDFPageProxy | null = null;
          try {
            let text = pageTextCacheRef.current.get(pageNumber);
            if (text === undefined) {
              pageHandle = await pdfDocument.getPage(pageNumber);
              const textContent = await pageHandle.getTextContent();
              text = normalizeSearchText(
                textContent.items.map((item) => ("str" in item ? item.str : "")).join(" "),
              );
              if (!run.cancelled) pageTextCacheRef.current.set(pageNumber, text);
            }
            if (run.cancelled) return;
            const occurrenceCount = countMatches(text, query);
            for (let occurrenceOnPage = 0; occurrenceOnPage < occurrenceCount; occurrenceOnPage += 1) {
              matches.push({ pageNumber, occurrenceOnPage });
            }
            if (occurrenceCount > 0 && !run.cancelled) {
              matches.sort(compareSearchMatches);
              setSearchMatches(matches.slice());
            }
          } catch (reason: unknown) {
            if (!run.cancelled) console.warn(`PDF page ${pageNumber} search failed`, reason);
          } finally {
            pageHandle?.cleanup();
          }
        }
      };

      const workerCount = Math.min(3, pages.length);
      void Promise.all(Array.from({ length: workerCount }, () => scanPage())).then(() => {
        if (run.cancelled) return;
        matches.sort(compareSearchMatches);
        setSearchMatches(matches.slice());
        setSearching(false);
      });
    }, 140);

    return () => {
      run.cancelled = true;
      window.clearTimeout(timer);
    };
  }, [pages.length, pdfDocument, searchQuery]);

  useEffect(() => {
    if (searchMatches.length === 0) {
      if (activeMatchIndex !== 0) setActiveMatchIndex(0);
    } else if (activeMatchIndex >= searchMatches.length) {
      setActiveMatchIndex(0);
    }
  }, [activeMatchIndex, searchMatches.length]);

  const activeMatch = searchMatches[activeMatchIndex] ?? null;

  useEffect(() => {
    if (!activeMatch || !normalizeSearchText(searchQuery) || !scrollRef.current) return;
    if (!continuousScroll && currentPageRef.current !== activeMatch.pageNumber) {
      currentPageRef.current = activeMatch.pageNumber;
      setCurrentPage(activeMatch.pageNumber);
    }
    const frame = window.requestAnimationFrame(() => {
      const page = scrollRef.current?.querySelector<HTMLElement>(
        `.pdf-page[data-page-index="${activeMatch.pageNumber - 1}"]`,
      );
      page?.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
    });
    return () => window.cancelAnimationFrame(frame);
  }, [activeMatch?.occurrenceOnPage, activeMatch?.pageNumber, searchQuery, continuousScroll]);

  if (error) return <div className="reader-error">{error}</div>;
  if (!loadingTaskRef.current || !pdfDocument || pages.length === 0) {
    return <div className="reader-loading">正在整理《{title}》…</div>;
  }

  function updatePage(pageNumber: number) {
    const boundedPage = Math.max(1, Math.min(pages.length, pageNumber));
    currentPageRef.current = boundedPage;
    setCurrentPage(boundedPage);
    window.requestAnimationFrame(() => {
      const page = scrollRef.current?.querySelector<HTMLElement>(
        `.pdf-page[data-page-index="${boundedPage - 1}"]`,
      );
      page?.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
    });
  }

  function updateMatch(delta: number) {
    if (searchMatches.length === 0) return;
    const nextIndex = (activeMatchIndex + delta + searchMatches.length) % searchMatches.length;
    setActiveMatchIndex(nextIndex);
    updatePage(searchMatches[nextIndex].pageNumber);
  }

  const queryIsActive = Boolean(normalizeSearchText(searchQuery));
  const searchSummary = !queryIsActive
    ? ""
    : searching
      ? `${searchMatches.length}…`
      : `${searchMatches.length > 0 ? activeMatchIndex + 1 : 0}/${searchMatches.length}`;

  function captureSelection() {
    const selection = window.getSelection();
    const text = selection?.toString().trim() ?? "";
    if (!selection || selection.rangeCount === 0 || !text || !scrollRef.current) {
      return;
    }
    const common = selection.getRangeAt(0).commonAncestorContainer;
    const element = common instanceof Element ? common : common.parentElement;
    const page = element?.closest<HTMLElement>(".pdf-page[data-page-index]");
    if (!page || !scrollRef.current.contains(page)) {
      return;
    }
    const pageIndex = Number(page.dataset.pageIndex);
    onSelection({
      itemId,
      text,
      pageIndex: Number.isInteger(pageIndex) && pageIndex >= 0 ? pageIndex : null,
      sectionTitle: null,
      sectionLocationId: null,
    });
  }

  return (
    <div
      ref={scrollRef}
      className="pdf-scroll"
      aria-label={title}
      onPointerUp={captureSelection}
      onKeyUp={captureSelection}
    >
      <div className="pdf-toolbar" role="toolbar" aria-label="PDF 工具栏">
        <div className="pdf-toolbar-group">
          <button
            className="pdf-toolbar-button"
            type="button"
            aria-label="上一页"
            title="上一页"
            disabled={currentPage <= 1}
            onClick={() => updatePage(currentPage - 1)}
          >
            <Icon name="back" size={14} />
          </button>
          <span className="pdf-page-indicator" aria-live="polite" aria-label={`第 ${currentPage} 页，共 ${pages.length} 页`}>
            <strong>{currentPage}</strong><span aria-hidden="true"> / </span>{pages.length}
          </span>
          <button
            className="pdf-toolbar-button"
            type="button"
            aria-label="下一页"
            title="下一页"
            disabled={currentPage >= pages.length}
            onClick={() => updatePage(currentPage + 1)}
          >
            <Icon name="forward" size={14} />
          </button>
          <span className="pdf-toolbar-separator" aria-hidden="true" />
          <button
            className="pdf-toolbar-button pdf-zoom-glyph"
            type="button"
            aria-label="缩小"
            title="缩小"
            disabled={zoom <= 0.5}
            onClick={() => setZoom((value) => clampZoom(value - 0.1))}
          >
            −
          </button>
          <button
            className="pdf-toolbar-button pdf-zoom-value"
            type="button"
            aria-label="重置缩放"
            title="重置缩放"
            onClick={() => setZoom(1)}
          >
            {Math.round(zoom * 100)}%
          </button>
          <button
            className="pdf-toolbar-button pdf-zoom-glyph"
            type="button"
            aria-label="放大"
            title="放大"
            disabled={zoom >= 2.4}
            onClick={() => setZoom((value) => clampZoom(value + 0.1))}
          >
            +
          </button>
          <button
            className={`pdf-continuous-toggle${continuousScroll ? " is-active" : ""}`}
            type="button"
            aria-pressed={continuousScroll}
            title={continuousScroll ? "连续滚动（已开启）" : "连续滚动（已关闭）"}
            onClick={() => setContinuousScroll((value) => !value)}
          >
            <span aria-hidden="true">↕</span><span>连续</span>
          </button>
        </div>
        <div className="pdf-search-controls">
          <label className="pdf-search-field">
            <Icon name="search" size={14} />
            <input
              type="search"
              value={searchQuery}
              aria-label="在 PDF 中查找"
              placeholder="查找文档"
              spellCheck={false}
              onChange={(event) => setSearchQuery(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                  updateMatch(event.shiftKey ? -1 : 1);
                }
              }}
            />
          </label>
          <span className="pdf-search-count" aria-live="polite" aria-atomic="true" title="匹配数量">
            {searchSummary}
          </span>
          <button
            className="pdf-toolbar-button pdf-search-nav"
            type="button"
            aria-label="上一个匹配"
            title="上一个匹配"
            disabled={searchMatches.length === 0}
            onClick={() => updateMatch(-1)}
          >
            ↑
          </button>
          <button
            className="pdf-toolbar-button pdf-search-nav"
            type="button"
            aria-label="下一个匹配"
            title="下一个匹配"
            disabled={searchMatches.length === 0}
            onClick={() => updateMatch(1)}
          >
            ↓
          </button>
        </div>
      </div>
      {pages.map(({ pageNumber }) => (
        <PdfPage
          key={pageNumber}
          task={loadingTaskRef.current!}
          pageNumber={pageNumber}
          availableWidth={availableWidth}
          zoom={zoom}
          isHidden={!continuousScroll && pageNumber !== currentPage}
          searchQuery={searchQuery}
          currentMatchOnPage={activeMatch?.pageNumber === pageNumber ? activeMatch.occurrenceOnPage : null}
        />
      ))}
    </div>
  );
}

function PdfPage({
  task,
  pageNumber,
  availableWidth,
  zoom,
  isHidden,
  searchQuery,
  currentMatchOnPage,
}: {
  task: ReturnType<typeof pdfjs.getDocument>;
  pageNumber: number;
  availableWidth: number;
  zoom: number;
  isHidden: boolean;
  searchQuery: string;
  currentMatchOnPage: number | null;
}) {
  const figureRef = useRef<HTMLElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const textLayerRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(false);
  const [rendered, setRendered] = useState(false);

  useEffect(() => {
    const target = figureRef.current;
    if (!target) return;
    const observer = new IntersectionObserver(
      ([entry]) => setActive(Boolean(entry?.isIntersecting)),
      { rootMargin: "1000px 0px" },
    );
    observer.observe(target);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!active || isHidden) return;
    let renderTask: pdfjs.RenderTask | null = null;
    let textLayer: pdfjs.TextLayer | null = null;
    let pageHandle: pdfjs.PDFPageProxy | null = null;
    let cancelled = false;
    setRendered(false);
    void task.promise.then(async (pdf) => {
      const page = await pdf.getPage(pageNumber);
      pageHandle = page;
      if (cancelled || !canvasRef.current || !textLayerRef.current || !figureRef.current) return;
      const base = page.getViewport({ scale: 1 });
      const fitScale = Math.min(1.65, 760 / base.width, availableWidth / base.width);
      const cssScale = Math.max(0.25, Math.min(4, fitScale * zoom));
      const cssViewport = page.getViewport({ scale: cssScale });
      const outputViewport = page.getViewport({ scale: cssScale * window.devicePixelRatio });
      const figure = figureRef.current;
      const canvas = canvasRef.current;
      const textContainer = textLayerRef.current;
      figure.style.width = `${cssViewport.width}px`;
      figure.style.height = `${cssViewport.height}px`;
      figure.style.setProperty("--total-scale-factor", String(cssScale));
      canvas.width = outputViewport.width;
      canvas.height = outputViewport.height;
      canvas.style.width = `${cssViewport.width}px`;
      canvas.style.height = `${cssViewport.height}px`;
      const context = canvas.getContext("2d");
      if (!context) return;
      textContainer.replaceChildren();
      renderTask = page.render({ canvas, canvasContext: context, viewport: outputViewport });
      textLayer = new pdfjs.TextLayer({
        textContentSource: page.streamTextContent({ includeMarkedContent: true }),
        container: textContainer,
        viewport: cssViewport,
      });
      await Promise.all([renderTask.promise, textLayer.render()]);
      if (!cancelled) setRendered(true);
    }).catch((reason: unknown) => {
      if (!cancelled) console.warn(`PDF page ${pageNumber} render failed`, reason);
    });
    return () => {
      cancelled = true;
      renderTask?.cancel();
      textLayer?.cancel();
      pageHandle?.cleanup();
      textLayerRef.current?.replaceChildren();
      setRendered(false);
    };
  }, [active, availableWidth, isHidden, pageNumber, task, zoom]);

  useEffect(() => {
    if (!rendered || !textLayerRef.current) return;
    applySearchHighlights(textLayerRef.current, searchQuery, currentMatchOnPage);
  }, [currentMatchOnPage, rendered, searchQuery]);

  return (
    <figure
      ref={figureRef}
      className={`pdf-page${isHidden ? " is-hidden" : ""}`}
      data-page-index={pageNumber - 1}
      aria-hidden={isHidden ? true : undefined}
    >
      <canvas ref={canvasRef} />
      <div ref={textLayerRef} className="textLayer" />
      <figcaption>{pageNumber}</figcaption>
    </figure>
  );
}

function normalizeSearchText(value: string): string {
  return value.replace(/\s+/g, " ").trim().toLocaleLowerCase();
}

function countMatches(value: string, query: string): number {
  if (!query) return 0;
  let count = 0;
  let index = 0;
  while (index <= value.length - query.length) {
    const found = value.indexOf(query, index);
    if (found < 0) break;
    count += 1;
    index = found + Math.max(query.length, 1);
  }
  return count;
}

function compareSearchMatches(left: PdfSearchMatch, right: PdfSearchMatch): number {
  return left.pageNumber - right.pageNumber || left.occurrenceOnPage - right.occurrenceOnPage;
}

function clampZoom(value: number): number {
  return Math.round(Math.max(0.5, Math.min(2.4, value)) * 10) / 10;
}

function applySearchHighlights(container: HTMLElement, query: string, currentMatchOnPage: number | null): void {
  const normalizedQuery = normalizeSearchText(query);
  let occurrence = 0;
  container.querySelectorAll<HTMLElement>("span").forEach((span) => {
    span.classList.remove("pdf-search-hit", "pdf-search-hit-current");
    if (!normalizedQuery) return;
    const spanText = normalizeSearchText(span.textContent ?? "");
    const spanMatchCount = countMatches(spanText, normalizedQuery);
    if (spanMatchCount === 0) return;
    span.classList.add("pdf-search-hit");
    if (
      currentMatchOnPage !== null
      && currentMatchOnPage >= occurrence
      && currentMatchOnPage < occurrence + spanMatchCount
    ) {
      span.classList.add("pdf-search-hit-current");
    }
    occurrence += spanMatchCount;
  });
}
