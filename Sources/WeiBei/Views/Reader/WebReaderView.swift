import AppKit
import PDFKit
import SwiftUI
import WebKit
import WeiBeiCore

struct WebReaderRepresentable: NSViewRepresentable {
    var html: String?
    var url: URL?
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var adaptsDocumentColors: Bool
    var contentRailTarget: WebReaderContentRailTarget?
    /// JSON array of `{id,text}` for selection-ask underline marks.
    var selectionAskMarks: String = "[]"
    var onContentRailChange: ([WebReaderContentRailSection]) -> Void
    var onContentRailActiveChange: (WebReaderContentRailActiveChange) -> Void
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
    var onSelectionChange: (String, CGPoint?) -> Void
    var onSelectionAskMark: (String) -> Void = { _ in }

    private static let scriptMessageNames = [
        "selection",
        "selectionAskMark",
        "appShortcut",
        "contentRailSections",
        "contentRailActive"
    ]

    init(
        html: String,
        searchQuery: String = "",
        appearanceMode: WeiBeiAppearanceMode = .paper,
        adaptsDocumentColors: Bool = true,
        contentRailTarget: WebReaderContentRailTarget? = nil,
        selectionAskMarks: String = "[]",
        onContentRailChange: @escaping ([WebReaderContentRailSection]) -> Void = { _ in },
        onContentRailActiveChange: @escaping (WebReaderContentRailActiveChange) -> Void = { _ in },
        onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false },
        onSelectionAskMark: @escaping (String) -> Void = { _ in },
        onSelectionChange: @escaping (String, CGPoint?) -> Void
    ) {
        self.html = html
        self.url = nil
        self.searchQuery = searchQuery
        self.appearanceMode = appearanceMode
        self.adaptsDocumentColors = adaptsDocumentColors
        self.contentRailTarget = contentRailTarget
        self.selectionAskMarks = selectionAskMarks
        self.onContentRailChange = onContentRailChange
        self.onContentRailActiveChange = onContentRailActiveChange
        self.onAppShortcut = onAppShortcut
        self.onSelectionAskMark = onSelectionAskMark
        self.onSelectionChange = onSelectionChange
    }

    init(
        url: URL,
        searchQuery: String = "",
        appearanceMode: WeiBeiAppearanceMode = .paper,
        adaptsDocumentColors: Bool = true,
        contentRailTarget: WebReaderContentRailTarget? = nil,
        selectionAskMarks: String = "[]",
        onContentRailChange: @escaping ([WebReaderContentRailSection]) -> Void = { _ in },
        onContentRailActiveChange: @escaping (WebReaderContentRailActiveChange) -> Void = { _ in },
        onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false },
        onSelectionAskMark: @escaping (String) -> Void = { _ in },
        onSelectionChange: @escaping (String, CGPoint?) -> Void
    ) {
        self.html = nil
        self.url = url
        self.searchQuery = searchQuery
        self.appearanceMode = appearanceMode
        self.adaptsDocumentColors = adaptsDocumentColors
        self.contentRailTarget = contentRailTarget
        self.selectionAskMarks = selectionAskMarks
        self.onContentRailChange = onContentRailChange
        self.onContentRailActiveChange = onContentRailActiveChange
        self.onAppShortcut = onAppShortcut
        self.onSelectionAskMark = onSelectionAskMark
        self.onSelectionChange = onSelectionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            appearanceMode: appearanceMode,
            adaptsDocumentColors: adaptsDocumentColors,
            contentRailTarget: contentRailTarget,
            onContentRailChange: onContentRailChange,
            onContentRailActiveChange: onContentRailActiveChange,
            onAppShortcut: onAppShortcut,
            onSelectionChange: onSelectionChange,
            onSelectionAskMark: onSelectionAskMark
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        PaneToggleContinuityVerifier.recordWebReaderMake()
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        for name in Self.scriptMessageNames {
            controller.add(context.coordinator, name: name)
        }
        controller.addUserScript(WKUserScript(
            source: Self.appShortcutScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.selectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
        controller.addUserScript(WKUserScript(
            source: Self.readerStyleScript(for: appearanceMode, adaptsDocumentColors: adaptsDocumentColors),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.contentRailScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        view.navigationDelegate = context.coordinator
        context.coordinator.installVerificationScrollObserverIfNeeded()
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.searchQuery = searchQuery
        context.coordinator.onAppShortcut = onAppShortcut
        context.coordinator.onContentRailChange = onContentRailChange
        context.coordinator.onContentRailActiveChange = onContentRailActiveChange
        context.coordinator.onSelectionAskMark = onSelectionAskMark
        context.coordinator.contentRailTarget = contentRailTarget
        context.coordinator.selectionAskMarks = selectionAskMarks
        if context.coordinator.appearanceMode != appearanceMode
            || context.coordinator.adaptsDocumentColors != adaptsDocumentColors {
            context.coordinator.appearanceMode = appearanceMode
            context.coordinator.adaptsDocumentColors = adaptsDocumentColors
            view.evaluateJavaScript(Self.readerStyleScript(for: appearanceMode, adaptsDocumentColors: adaptsDocumentColors))
        }
        if let url {
            let signature = "file:\(url.path)"
            if context.coordinator.loadedSignature != signature {
                context.coordinator.loadedSignature = signature
                context.coordinator.lastAppliedSelectionAskMarks = ""
                view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                context.coordinator.applySearch(in: view)
                context.coordinator.applySelectionAskMarksIfNeeded()
            }
        } else if let html {
            let signature = "html:\(html.hashValue)"
            if context.coordinator.loadedSignature != signature {
                context.coordinator.loadedSignature = signature
                context.coordinator.lastAppliedSelectionAskMarks = ""
                view.loadHTMLString(html, baseURL: nil)
            } else {
                context.coordinator.applySearch(in: view)
                context.coordinator.applySelectionAskMarksIfNeeded()
            }
        }
        context.coordinator.applyContentRailTarget(in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        PaneToggleContinuityVerifier.recordWebReaderDismantle()
        coordinator.removeVerificationScrollObserver()
        unbindScriptMessages(in: view)
        view.navigationDelegate = nil
    }

    private static func unbindScriptMessages(in view: WKWebView) {
        let controller = view.configuration.userContentController
        for name in scriptMessageNames {
            controller.removeScriptMessageHandler(forName: name)
        }
    }

    static let appShortcutScript = """
    (() => {
      const keyName = (event) => {
        if (/^Digit[0-9]$/.test(event.code)) return event.code.slice(5);
        if (/^Key[A-Z]$/.test(event.code)) return event.code.slice(3).toLowerCase();
        return String(event.key || "").toLowerCase();
      };
      const isWeiBeiShortcut = (key, event) => {
        const command = event.metaKey;
        const option = event.altKey;
        const control = event.ctrlKey;
        const shift = event.shiftKey;
        if (command && option && !control && !shift) return ["1", "2", "3", "a", "n", "r", "t"].includes(key);
        if (command && !option && !control && !shift) return ["1", "2", "3", "4", "[", "]", "b", "j", "k", "f"].includes(key);
        if (control && option && !command && !shift) return ["0", "1", "2", "3", "4"].includes(key);
        return false;
      };
      window.addEventListener("keydown", (event) => {
        const key = keyName(event);
        if (!isWeiBeiShortcut(key, event)) return;
        event.preventDefault();
        event.stopPropagation();
        window.webkit.messageHandlers.appShortcut.postMessage({
          key,
          command: event.metaKey,
          option: event.altKey,
          control: event.ctrlKey,
          shift: event.shiftKey
        });
      }, true);
    })();
    """

    static let selectionScript = """
    (() => {
      let frame = 0;
      let lastPayload = { text: "", x: null, y: null };

      function reportSelection() {
        window.cancelAnimationFrame(frame);
        frame = window.requestAnimationFrame(() => {
          if (window.weiBeiSuppressSelectionReport) return;
          const selection = window.getSelection();
          const text = selection ? selection.toString().trim() : "";
          const range = selection && selection.rangeCount ? selection.getRangeAt(0) : null;
          const rect = range ? range.getBoundingClientRect() : null;
          const payload = {
            text,
            x: rect && text ? rect.left + rect.width / 2 : null,
            y: rect && text ? rect.bottom : null
          };
          if (
            payload.text === lastPayload.text &&
            payload.x === lastPayload.x &&
            payload.y === lastPayload.y
          ) {
            return;
          }
          lastPayload = payload;
          window.webkit.messageHandlers.selection.postMessage(payload);
        });
      }

      document.addEventListener("selectionchange", reportSelection);
      document.addEventListener("pointerdown", () => {
        if (window.weiBeiSuppressSelectionReport) return;
        window.cancelAnimationFrame(frame);
        lastPayload = { text: "", x: null, y: null };
        window.webkit.messageHandlers.selection.postMessage(lastPayload);
      }, true);
      document.addEventListener("pointerup", reportSelection);
      document.addEventListener("mouseup", reportSelection);
      document.addEventListener("keyup", reportSelection);
      document.addEventListener("touchend", reportSelection);

      // Underline spans for selection-ask history; click reopens floating Q&A.
      window.WeiBeiSelectionAskMarks = {
        apply: function(marks) {
          try {
            document.querySelectorAll(".weibei-selection-ask-mark").forEach((el) => {
              const parent = el.parentNode;
              if (!parent) return;
              while (el.firstChild) parent.insertBefore(el.firstChild, el);
              parent.removeChild(el);
              parent.normalize();
            });
            const list = Array.isArray(marks) ? marks : [];
            list.forEach((mark) => {
              const needle = String(mark.text || "").trim();
              const id = String(mark.id || "");
              if (!needle || !id || needle.length < 4) return;
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(node) {
                  if (!node.parentElement) return NodeFilter.FILTER_REJECT;
                  if (node.parentElement.closest(".weibei-selection-ask-mark, script, style")) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return node.nodeValue && node.nodeValue.indexOf(needle) >= 0
                    ? NodeFilter.FILTER_ACCEPT
                    : NodeFilter.FILTER_SKIP;
                }
              });
              const hits = [];
              while (walker.nextNode()) hits.push(walker.currentNode);
              hits.slice(0, 3).forEach((textNode) => {
                const value = textNode.nodeValue || "";
                const idx = value.indexOf(needle);
                if (idx < 0) return;
                const range = document.createRange();
                range.setStart(textNode, idx);
                range.setEnd(textNode, idx + needle.length);
                const span = document.createElement("span");
                span.className = "weibei-selection-ask-mark";
                span.dataset.threadId = id;
                span.title = "打开当时的选区问答";
                try {
                  range.surroundContents(span);
                } catch (e) {
                  // ignore partial-node failures
                }
              });
            });
            document.querySelectorAll(".weibei-selection-ask-mark").forEach((el) => {
              el.onclick = function(ev) {
                ev.preventDefault();
                ev.stopPropagation();
                const threadId = el.dataset.threadId || "";
                if (window.webkit?.messageHandlers?.selectionAskMark) {
                  window.webkit.messageHandlers.selectionAskMark.postMessage({
                    threadId,
                    text: el.textContent || ""
                  });
                }
              };
            });
          } catch (e) {}
        }
      };
    })();
    """

    static let contentRailScript = """
    (() => {
      if (window.WeiBeiContentRail?.installed) {
        window.WeiBeiContentRail.scan();
        return;
      }

      const state = {
        items: [],
        activeID: "",
        activeFrame: 0,
        scanTimer: 0,
        pendingScanReason: "initial",
        userScrollUntil: 0
      };
      const clean = (value) => String(value || "").replace(/\\s+/g, " ").trim();
      const clipped = (value, limit) => clean(value).slice(0, limit);
      const visible = (element) => {
        if (!(element instanceof Element)) return false;
        if (element.closest("nav, footer, [aria-hidden='true']")) return false;
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== "none" && style.visibility !== "hidden" && rect.width > 1 && rect.height > 1;
      };
      const absoluteTop = (element) => window.scrollY + element.getBoundingClientRect().top;
      const maximumScroll = () => Math.max(
        1,
        (document.scrollingElement?.scrollHeight || document.documentElement.scrollHeight || document.body.scrollHeight || 1)
          - window.innerHeight
      );
      const normalizedPosition = (element) => Math.max(0, Math.min(1, absoluteTop(element) / maximumScroll()));
      const metadata = (index, count, fallback) => fallback
        ? `HTML · 内容段 ${index + 1} / ${count}`
        : `HTML · ${index + 1} / ${count}`;

      const excerptAfterHeading = (heading) => {
        let cursor = heading.nextElementSibling;
        while (cursor) {
          if (/^H[1-4]$/.test(cursor.tagName) || cursor.getAttribute("role") === "heading") break;
          const candidate = cursor.matches("p, li, blockquote, figcaption, pre")
            ? cursor
            : cursor.querySelector("p, li, blockquote, figcaption, pre");
          const text = clipped(candidate?.textContent, 180);
          if (text) return text;
          cursor = cursor.nextElementSibling;
        }
        return "";
      };

      const sectionFingerprintBody = (heading, nextHeading) => {
        try {
          const range = document.createRange();
          range.setStartAfter(heading);
          if (nextHeading) {
            range.setEndBefore(nextHeading);
          } else if (document.body?.lastChild) {
            range.setEndAfter(document.body.lastChild);
          } else {
            return "";
          }
          const fragment = range.cloneContents();
          fragment.querySelectorAll?.("script, style, noscript, template").forEach((element) => element.remove());
          return clean(fragment.textContent);
        } catch (_) {
          return excerptAfterHeading(heading);
        }
      };

      const sectionLocationID = (title, body) => {
        const normalized = `${title}|${body}`
          .toLocaleLowerCase()
          .match(/[\\p{L}\\p{N}]/gu)?.join("").slice(0, 500) || "";
        const bytes = new TextEncoder().encode(normalized);
        let hash = 0x811c9dc5;
        bytes.forEach((byte) => {
          hash ^= byte;
          hash = Math.imul(hash, 0x01000193) >>> 0;
        });
        return `html-section-${hash.toString(16).padStart(8, "0")}`;
      };

      const headingSections = () => {
        const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4"));
        const locationIDCounts = new Map();
        return headings
        .map((element, index) => {
          const title = clean(element.textContent);
          const baseID = sectionLocationID(title, sectionFingerprintBody(element, headings[index + 1]));
          const count = (locationIDCounts.get(baseID) || 0) + 1;
          locationIDCounts.set(baseID, count);
          const id = count === 1 ? baseID : `${baseID}-dup-${count}`;
          element.dataset.weibeiContentRailID = id;
          return { element, index, id };
        })
        .filter(({ element }) => visible(element) && clean(element.textContent))
        .map(({ element, index, id }) => {
          const explicitLevel = Number(element.getAttribute("aria-level"));
          const tagLevel = /^H[1-4]$/.test(element.tagName) ? Number(element.tagName.slice(1)) : 2;
          const level = Math.max(1, Math.min(4, Number.isFinite(explicitLevel) && explicitLevel > 0 ? explicitLevel : tagLevel));
          return {
            id,
            element,
            level,
            title: clipped(element.textContent, 72),
            excerpt: excerptAfterHeading(element),
            top: absoluteTop(element),
            position: normalizedPosition(element),
            fallback: false
          };
        });
      };

      const fallbackSections = () => {
        const root = document.querySelector("main, article") || document.body;
        const blocks = Array.from(root?.querySelectorAll("p, li, blockquote, figcaption, pre") || [])
          .filter((element) => visible(element) && clean(element.textContent).length >= 24)
          .sort((left, right) => absoluteTop(left) - absoluteTop(right));
        if (blocks.length === 0) return [];
        const desiredCount = Math.max(1, Math.min(24, Math.ceil(maximumScroll() / Math.max(window.innerHeight * 1.35, 640)) + 1));
        const selected = [];
        for (let index = 0; index < desiredCount; index += 1) {
          const blockIndex = desiredCount === 1
            ? 0
            : Math.round((index / (desiredCount - 1)) * (blocks.length - 1));
          const element = blocks[blockIndex];
          if (!element || selected.some((entry) => entry.element === element)) continue;
          const text = clean(element.textContent);
          const id = element.dataset.weibeiContentRailID || `html-block-${blockIndex}`;
          element.dataset.weibeiContentRailID = id;
          selected.push({
            id,
            element,
            level: 4,
            title: clipped(text, 48),
            excerpt: clipped(text, 180),
            top: absoluteTop(element),
            position: normalizedPosition(element),
            fallback: true
          });
        }
        return selected;
      };

      const postSections = () => {
        const count = state.items.length;
        window.webkit?.messageHandlers?.contentRailSections?.postMessage(state.items.map((item, index) => ({
          id: item.id,
          position: item.position,
          level: item.level,
          title: item.title,
          excerpt: item.excerpt,
          metadata: metadata(index, count, item.fallback)
        })));
      };

      const applyActive = (requestedReason = "unknown") => {
        const now = Date.now();
        const reason = requestedReason === "scroll"
          ? (now <= state.userScrollUntil ? "scroll" : "programmatic")
          : requestedReason;
        if (state.items.length === 0) {
          if (state.activeID) {
            state.activeID = "";
            window.webkit?.messageHandlers?.contentRailActive?.postMessage({ id: "", reason });
          }
          return;
        }
        const readingLine = window.scrollY + window.innerHeight * 0.32;
        let active = state.items[0];
        for (const item of state.items) {
          if (item.top <= readingLine) active = item;
          else break;
        }
        if (active.id === state.activeID) return;
        state.activeID = active.id;
        window.webkit?.messageHandlers?.contentRailActive?.postMessage({ id: active.id, reason });
      };

      const updateActive = (requestedReason = "unknown") => {
        window.cancelAnimationFrame(state.activeFrame);
        state.activeFrame = window.requestAnimationFrame(() => applyActive(requestedReason));
      };

      const scan = (reason = "unknown") => {
        const headings = headingSections();
        state.items = (headings.length > 0 ? headings : fallbackSections())
          .sort((left, right) => left.top - right.top);
        postSections();
        updateActive(reason);
      };

      const scheduleScan = (reason) => {
        state.pendingScanReason = reason;
        window.clearTimeout(state.scanTimer);
        state.scanTimer = window.setTimeout(() => scan(state.pendingScanReason), 160);
      };

      const scrollTo = (id) => {
        const item = state.items.find((candidate) => candidate.id === id);
        if (!item?.element) return false;
        item.element.scrollIntoView({ behavior: "smooth", block: "start", inline: "nearest" });
        window.setTimeout(() => window.scrollBy({ top: -44, behavior: "auto" }), 180);
        window.setTimeout(() => {
          state.activeID = id;
          window.webkit?.messageHandlers?.contentRailActive?.postMessage({ id, reason: "jump" });
        }, 240);
        return true;
      };

      const markUserScrollIntent = () => {
        state.userScrollUntil = Date.now() + 900;
      };

      const markKeyboardScrollIntent = (event) => {
        const keys = ["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " "];
        if (keys.includes(event.key)) markUserScrollIntent();
      };

      const simulateUserScrollForVerification = () => {
        const before = window.scrollY;
        const maximum = maximumScroll();
        state.activeID = "";
        window.dispatchEvent(new WheelEvent("wheel", { deltaY: window.innerHeight * 2.4 }));
        window.scrollTo({ top: maximum, behavior: "auto" });
        applyActive("scroll");
        return `before:${before},after:${window.scrollY},max:${maximum},intent:${state.userScrollUntil > Date.now()}`;
      };

      window.WeiBeiContentRail = {
        installed: true,
        scan: () => scan("initial"),
        scrollTo,
        simulateUserScrollForVerification
      };
      window.addEventListener("wheel", markUserScrollIntent, { passive: true });
      window.addEventListener("touchmove", markUserScrollIntent, { passive: true });
      window.addEventListener("keydown", markKeyboardScrollIntent, { passive: true });
      window.addEventListener("scroll", () => updateActive("scroll"), { passive: true });
      window.addEventListener("resize", () => scheduleScan("resize"), { passive: true });
      new MutationObserver(() => scheduleScan("mutation")).observe(document.body || document.documentElement, {
        childList: true,
        characterData: true,
        subtree: true
      });
      if (window.ResizeObserver) {
        new ResizeObserver(() => scheduleScan("resize")).observe(document.body || document.documentElement);
      }
      window.requestAnimationFrame(() => scan("initial"));
    })();
    """

    static func readerStyleScript(for mode: WeiBeiAppearanceMode, adaptsDocumentColors: Bool = true) -> String {
        let tokens = WeiBeiNativePalette.cssHex(for: mode)
        let scheme = mode.isDark ? "dark" : "light"
        let selectionCSS = """
            ::selection { background: \(tokens.selection); color: \(tokens.ink); }
            .weibei-selection-ask-mark {
              text-decoration-line: underline;
              text-decoration-color: \(tokens.cinnabar);
              text-decoration-thickness: 1.5px;
              text-underline-offset: 3px;
              cursor: pointer;
              background: color-mix(in srgb, \(tokens.cinnabar) 12%, transparent);
              border-radius: 2px;
            }
            .weibei-selection-ask-mark:hover {
              background: color-mix(in srgb, \(tokens.cinnabar) 20%, transparent);
            }
            """

        let adaptiveCSS: String
        if !adaptsDocumentColors {
            adaptiveCSS = ""
        } else if mode.isDark {
            adaptiveCSS = """
            html, body { max-width: 100%; overflow-x: hidden; color-scheme: \(scheme); background: transparent !important; }
            body, main, article, section, div, p, li, blockquote, td, th, span { color: \(tokens.ink) !important; background-color: transparent !important; }
            a { color: \(tokens.link) !important; text-decoration-color: color-mix(in srgb, \(tokens.link) 55%, transparent) !important; }
            h1, h2, h3 { color: \(tokens.link) !important; }
            blockquote { border-left: 3px solid color-mix(in srgb, \(tokens.cinnabar) 62%, transparent) !important; background: color-mix(in srgb, \(tokens.cinnabar) 10%, transparent) !important; color: \(tokens.ink) !important; }
            code { background: rgba(255, 255, 255, .05) !important; color: \(tokens.link) !important; }
            pre { background: \(tokens.paperRaised) !important; border: 1px solid color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; color: \(tokens.ink) !important; }
            table { background: rgba(255, 255, 255, .02) !important; }
            th { color: \(tokens.link) !important; background: color-mix(in srgb, \(tokens.link) 10%, transparent) !important; }
            table, th, td { border-color: color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; }
            """
        } else {
            adaptiveCSS = """
            html, body { max-width: 100%; overflow-x: hidden; color-scheme: \(scheme); background: transparent !important; }
            body, main, article, section, div, p, li, blockquote, td, th, span { color: \(tokens.ink) !important; }
            [data-weibei-paper-surface] { background-color: transparent !important; }
            a { color: \(tokens.link) !important; }
            code { background: color-mix(in srgb, \(tokens.ink) 6%, transparent) !important; color: \(tokens.muted) !important; }
            pre { background: color-mix(in srgb, \(tokens.ink) 5%, transparent) !important; border-color: color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; }
            table, th, td { border-color: color-mix(in srgb, \(tokens.ink) 18%, transparent) !important; }
            """
        }

        let css = selectionCSS + "\n" + adaptiveCSS
        return """
        (() => {
          const css = \(Self.json(css));
          const adaptsDocumentColors = \(adaptsDocumentColors ? "true" : "false");
          const appearance = \(Self.json(mode.webThemeName));
          let style = document.getElementById("weibei-reader-style");
          if (!style) {
            style = document.createElement("style");
            style.id = "weibei-reader-style";
            document.head.appendChild(style);
          }
          document.documentElement.dataset.weibeiTheme = adaptsDocumentColors ? appearance : "original";
          style.textContent = `${css}
            body, main, article, section, div { box-sizing: border-box; max-width: 100%; }
            h1, h2, h3, h4, p, li, blockquote { overflow-wrap: anywhere; word-break: normal; }
            pre, code { white-space: pre-wrap; overflow-wrap: anywhere; }
            img, table { max-width: 100%; }
          `;

          document.querySelectorAll("[data-weibei-paper-surface]").forEach((element) => {
            element.removeAttribute("data-weibei-paper-surface");
          });
          if (adaptsDocumentColors && appearance === "paper") {
            const candidates = Array.from(document.querySelectorAll(
              "main, article, section, div, aside, header, footer, table, thead, tbody, tr, td, th"
            )).slice(0, 2500);
            candidates.forEach((element) => {
              const values = (getComputedStyle(element).backgroundColor.match(/[\\d.]+/g) || []).map(Number);
              if (values.length < 3) return;
              const rgb = values.slice(0, 3);
              if (Math.max(...rgb) <= 1.01) {
                rgb[0] *= 255;
                rgb[1] *= 255;
                rgb[2] *= 255;
              }
              const alpha = values.length > 3 ? values[3] : 1;
              const minimum = Math.min(...rgb);
              const spread = Math.max(...rgb) - minimum;
              if (alpha > 0.05 && minimum >= 238 && spread <= 18) {
                element.setAttribute("data-weibei-paper-surface", "");
              }
            });
          }
        })();
        """
    }

    private static func json(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onSelectionChange: (String, CGPoint?) -> Void
        var onSelectionAskMark: (String) -> Void
        var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
        var onContentRailChange: ([WebReaderContentRailSection]) -> Void
        var onContentRailActiveChange: (WebReaderContentRailActiveChange) -> Void
        var contentRailTarget: WebReaderContentRailTarget?
        var loadedSignature: String?
        var searchQuery = ""
        var appearanceMode: WeiBeiAppearanceMode = .paper
        var adaptsDocumentColors = true
        var selectionAskMarks = "[]"
        private var lastAppliedSearchQuery = ""
        var lastAppliedSelectionAskMarks = ""
        private var lastAppliedContentRailTargetRequestID: UUID?
        private var observesVerificationScroll = false
        weak var webView: WKWebView?

        init(
            appearanceMode: WeiBeiAppearanceMode,
            adaptsDocumentColors: Bool,
            contentRailTarget: WebReaderContentRailTarget?,
            onContentRailChange: @escaping ([WebReaderContentRailSection]) -> Void,
            onContentRailActiveChange: @escaping (WebReaderContentRailActiveChange) -> Void,
            onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool,
            onSelectionChange: @escaping (String, CGPoint?) -> Void,
            onSelectionAskMark: @escaping (String) -> Void
        ) {
            self.appearanceMode = appearanceMode
            self.adaptsDocumentColors = adaptsDocumentColors
            self.contentRailTarget = contentRailTarget
            self.onContentRailChange = onContentRailChange
            self.onContentRailActiveChange = onContentRailActiveChange
            self.onAppShortcut = onAppShortcut
            self.onSelectionChange = onSelectionChange
            self.onSelectionAskMark = onSelectionAskMark
        }

        func applySelectionAskMarksIfNeeded() {
            guard let webView, selectionAskMarks != lastAppliedSelectionAskMarks else { return }
            lastAppliedSelectionAskMarks = selectionAskMarks
            let js = "window.WeiBeiSelectionAskMarks && window.WeiBeiSelectionAskMarks.apply(\(selectionAskMarks));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func installVerificationScrollObserverIfNeeded() {
            guard !observesVerificationScroll,
                  ProcessInfo.processInfo.environment["WEIBEI_VERIFY_SCENARIO"] == "reader-scroll-persistence-flow" else { return }
            observesVerificationScroll = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(performVerificationUserScroll),
                name: .weiBeiVerificationUserScroll,
                object: nil
            )
        }

        func removeVerificationScrollObserver() {
            guard observesVerificationScroll else { return }
            NotificationCenter.default.removeObserver(self, name: .weiBeiVerificationUserScroll, object: nil)
            observesVerificationScroll = false
        }

        @objc private func performVerificationUserScroll() {
            guard let webView else { return }
            PaneToggleContinuityVerifier.recordVerificationScrollScheduled()
            webView.evaluateJavaScript(
                "window.WeiBeiContentRail?.simulateUserScrollForVerification()"
            ) { result, error in
                let value = result as? String
                    ?? error.map { "error:\($0.localizedDescription)" }
                    ?? "missing-result"
                PaneToggleContinuityVerifier.recordVerificationScrollResult(value)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "appShortcut" {
                guard let body = message.body as? [String: Any],
                      let key = body["key"] as? String else { return }
                _ = onAppShortcut(key, Self.modifiers(from: body))
                return
            }

            if message.name == "selectionAskMark" {
                let threadID: String
                if let body = message.body as? [String: Any] {
                    threadID = (body["threadId"] as? String) ?? ""
                } else if let body = message.body as? String {
                    threadID = body
                } else {
                    return
                }
                Task { @MainActor in
                    self.onSelectionAskMark(threadID)
                }
                return
            }

            if message.name == "contentRailSections" {
                guard let rows = message.body as? [[String: Any]] else { return }
                let sections = rows.compactMap(Self.contentRailSection(from:))
                PaneToggleContinuityVerifier.recordHTMLSectionEvent(count: sections.count)
                Task { @MainActor in
                    self.onContentRailChange(sections)
                }
                return
            }

            if message.name == "contentRailActive" {
                let body = message.body as? [String: Any]
                let id = body?["id"] as? String
                let reason = (body?["reason"] as? String)
                    .flatMap(WebReaderContentRailEventReason.init(rawValue:)) ?? .unknown
                PaneToggleContinuityVerifier.recordHTMLActiveEvent(reason: reason.rawValue)
                Task { @MainActor in
                    self.onContentRailActiveChange(
                        WebReaderContentRailActiveChange(
                            id: id?.isEmpty == false ? id : nil,
                            reason: reason
                        )
                    )
                }
                return
            }

            let text: String
            let anchor: CGPoint?
            if let body = message.body as? [String: Any],
               let bodyText = body["text"] as? String {
                text = bodyText
                anchor = Self.anchor(from: body, in: webView)
            } else if let bodyText = message.body as? String {
                text = bodyText
                anchor = nil
            } else {
                return
            }
            Task { @MainActor in
                self.onSelectionChange(text, anchor)
            }
        }

        private static func modifiers(from body: [String: Any]) -> NSEvent.ModifierFlags {
            var modifiers: NSEvent.ModifierFlags = []
            if body["command"] as? Bool == true {
                modifiers.insert(.command)
            }
            if body["option"] as? Bool == true {
                modifiers.insert(.option)
            }
            if body["control"] as? Bool == true {
                modifiers.insert(.control)
            }
            if body["shift"] as? Bool == true {
                modifiers.insert(.shift)
            }
            return modifiers
        }

        private static func contentRailSection(from body: [String: Any]) -> WebReaderContentRailSection? {
            guard let id = body["id"] as? String,
                  let title = body["title"] as? String,
                  let position = (body["position"] as? NSNumber)?.doubleValue,
                  let level = (body["level"] as? NSNumber)?.intValue else { return nil }
            return WebReaderContentRailSection(
                id: id,
                position: CGFloat(position),
                level: level,
                title: title,
                excerpt: body["excerpt"] as? String ?? "",
                metadata: body["metadata"] as? String ?? "HTML"
            )
        }

        private static func anchor(from body: [String: Any], in view: WKWebView?) -> CGPoint? {
            guard let view,
                  let x = body["x"] as? Double,
                  let y = body["y"] as? Double else {
                return nil
            }
            return SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastAppliedSearchQuery = ""
            lastAppliedContentRailTargetRequestID = nil
            lastAppliedSelectionAskMarks = ""
            webView.evaluateJavaScript(WebReaderRepresentable.readerStyleScript(for: appearanceMode, adaptsDocumentColors: adaptsDocumentColors))
            applySearch(in: webView)
            applyContentRailTarget(in: webView)
            applySelectionAskMarksIfNeeded()
        }

        func applySearch(in view: WKWebView) {
            let query = ReaderSearch.cleaned(searchQuery)
            guard query != lastAppliedSearchQuery else { return }
            lastAppliedSearchQuery = query
            let script = """
            (() => {
              const query = \(Self.json(query));
              const selection = window.getSelection();
              selection?.removeAllRanges();
              window.webkit?.messageHandlers?.selection?.postMessage({
                text: "",
                x: null,
                y: null
              });
              if (!query) return false;
              window.weiBeiSuppressSelectionReport = true;
              const found = window.find(query, false, false, true, false, true, false);
              window.setTimeout(() => { window.weiBeiSuppressSelectionReport = false; }, 80);
              return found;
            })();
            """
            view.evaluateJavaScript(script)
        }

        func applyContentRailTarget(in view: WKWebView) {
            guard let contentRailTarget,
                  contentRailTarget.requestID != lastAppliedContentRailTargetRequestID else { return }
            lastAppliedContentRailTargetRequestID = contentRailTarget.requestID
            view.evaluateJavaScript("window.WeiBeiContentRail?.scrollTo(\(Self.json(contentRailTarget.id)))")
        }

        private static func json(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
    }
}
