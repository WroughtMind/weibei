import Foundation
import WebKit

@MainActor
final class ReaderWebTranslation: NSObject, WKScriptMessageHandler {
    private struct Paragraph: Hashable {
        let id: Int
        let text: String
    }

    private static let world = WKContentWorld.world(name: "WeiBei.ReaderTranslation")
    private static let handler = "readerTranslationViewport"
    private var context: ReaderTranslationContext?
    private var token: String?
    private var viewport: [Paragraph]?
    private var requested: [Paragraph] = []
    private var rendered: [Int: String] = [:]
    private var task: Task<Void, Never>?
    private var status: ReaderTranslationStatus?
    private var onStatus: (ReaderTranslationStatus) -> Void = { _ in }

    func update(
        in view: WKWebView,
        context: ReaderTranslationContext?,
        rootSelector: String,
        snapshotImportedHTML: Bool,
        onStatus: @escaping (ReaderTranslationStatus) -> Void
    ) {
        self.onStatus = onStatus
        guard self.context != context else { return }
        stop(in: view)
        guard let context else { return }
        self.context = context
        let token = UUID().uuidString
        self.token = token
        view.configuration.userContentController.add(self, contentWorld: Self.world, name: Self.handler)
        publish(.idle)
        view.callAsyncJavaScript(
            Self.startScript,
            arguments: ["token": token, "rootSelector": rootSelector, "snapshotImportedHTML": snapshotImportedHTML],
            in: nil,
            in: Self.world
        ) { [weak self] result in
            guard let self, self.token == token, case .failure = result else { return }
            self.publish(.failed(.failed))
        }
    }

    func stop(in view: WKWebView) {
        guard let token else { return }
        self.token = nil
        context = nil
        viewport = nil
        requested = []
        rendered.removeAll()
        status = nil
        task?.cancel()
        task = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: Self.handler, contentWorld: Self.world)
        view.callAsyncJavaScript(
            "globalThis.weiBeiReaderTranslation?.stop(token);",
            arguments: ["token": token], in: nil, in: Self.world, completionHandler: nil
        )
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handler, message.frameInfo.isMainFrame, let view = message.webView,
              let token, let body = message.body as? [String: Any], body["token"] as? String == token,
              let values = body["paragraphs"] as? [[String: Any]] else { return }
        let next = values.compactMap { value -> Paragraph? in
            guard let id = value["id"] as? Int, let text = value["text"] as? String, !text.isEmpty else { return nil }
            return Paragraph(id: id, text: text)
        }
        guard next != viewport else { return }
        viewport = next
        translateVisibleParagraphs(in: view)
    }

    private func translateVisibleParagraphs(in view: WKWebView) {
        guard let context, let token, let viewport else { return }
        let missing = viewport.filter { rendered[$0.id] != $0.text }
        if let task {
            let relevant = missing.isEmpty ? viewport : missing
            guard Set(relevant).isDisjoint(with: requested) else { return }
            task.cancel()
            self.task = nil
            requested = []
        }
        guard !missing.isEmpty else {
            publish(viewport.isEmpty ? .noText : .ready)
            return
        }
        publish(.translating)
        requested = missing
        task = Task { [weak self, weak view] in
            do {
                _ = try await context.service.translate(missing.map(\.text)) { [weak self, weak view] index, translation in
                    guard let self, let view else { return }
                    await self.render(translation, for: missing[index], token: token, in: view)
                }
                guard let self, let view, self.token == token, !Task.isCancelled else { return }
                self.task = nil
                self.requested = []
                if self.viewport == viewport, missing.contains(where: { self.rendered[$0.id] != $0.text }) {
                    self.publish(.failed(.failed))
                } else {
                    self.translateVisibleParagraphs(in: view)
                }
            } catch {
                guard let self, self.token == token, !Task.isCancelled else { return }
                self.task = nil
                self.requested = []
                if let view, self.viewport != viewport {
                    self.translateVisibleParagraphs(in: view)
                } else {
                    self.publish(.failed(ReaderTranslationProblem(error)))
                }
            }
        }
    }

    private func render(_ translation: String, for paragraph: Paragraph, token: String, in view: WKWebView) async {
        guard self.token == token, !Task.isCancelled else { return }
        let update: [String: Any] = ["id": paragraph.id, "source": paragraph.text, "translation": translation]
        let appliedIDs = try? await view.callAsyncJavaScript(
            "return globalThis.weiBeiReaderTranslation?.render(token, updates) ?? [];",
            arguments: ["token": token, "updates": [update]],
            in: nil, contentWorld: Self.world
        )
        guard self.token == token, !Task.isCancelled, (appliedIDs as? [Int]) == [paragraph.id] else { return }
        rendered[paragraph.id] = paragraph.text
        translateVisibleParagraphs(in: view)
    }

    private func publish(_ status: ReaderTranslationStatus) {
        guard self.status != status else { return }
        self.status = status
        let token = self.token
        // A representable may change the session during its SwiftUI update.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.token == token, self.status == status else { return }
            self.onStatus(status)
        }
    }

    // The shadow tree keeps translated text out of source search and selection ranges.
    static let startScript = #"""
    globalThis.weiBeiReaderTranslation?.stop();
    const translationSelector = '[data-weibei-reader-translation]';
    const slideSelector = '[data-slide-index]';
    const office = rootSelector === '#office-document';
    const blocks = 'p,h1,h2,h3,h4,h5,h6,li,dt,dd,figcaption,blockquote,td,th,caption'
      + (office ? ',' + slideSelector : rootSelector === 'body' ? ',div,main,article,section' : '');
    const excluded = 'nav,footer,aside:not(.office-note),pre,code,form,[hidden],[aria-hidden="true"],'
      + '[role="status"],[role="alert"],[data-weibei-annotation-ui]';
    const ids = new WeakMap();
    const slideText = new WeakMap();
    const translations = new Map();
    const translationHosts = new WeakSet();
    const elements = new Map();
    const observed = new Set();
    const intersecting = new Set();
    let nextID = 0;
    let lastReport;
    let timer;
    let needsRefresh = true;

    function nestedList(element) {
      return element.matches('li') ? element.querySelector(':scope > ul, :scope > ol') : null;
    }

    function isSlide(element) {
      return office && element.matches(slideSelector);
    }

    function textOf(element) {
      if (isSlide(element)) {
        const source = element.firstElementChild?.querySelector('[data-weibei-location$=".xml"]');
        if (source) slideText.set(element, source.innerText.trim());
        // Slide wrappers persist when the renderer unloads offscreen artwork.
        return slideText.get(element) || '';
      }
      if (nestedList(element)) {
        return Array.from(element.childNodes).map(node => {
          if (node.nodeType === Node.TEXT_NODE) return node.textContent;
          if (node instanceof HTMLElement && !node.matches('ul,ol,' + translationSelector)) return node.innerText;
          return '';
        }).join('').trim();
      }
      return element.innerText?.trim() || '';
    }

    function isParagraph(element) {
      if (element.closest(excluded)) return false;
      if (isSlide(element)) return true;
      if (office && element.closest(slideSelector) && !element.closest('.office-note-body')) return false;
      if (!nestedList(element)) return !element.querySelector(blocks);
      return !Array.from(element.children).some(child =>
        !child.matches('ul,ol') && (child.matches(blocks) || child.querySelector(blocks)));
    }

    function sourceBlocks() {
      const root = document.querySelector(rootSelector);
      if (!root) return [];
      const paragraphs = Array.from(root.querySelectorAll(blocks)).filter(isParagraph);
      if (!paragraphs.length && root.matches('body') && !root.querySelector(excluded)) return [root];
      return paragraphs;
    }

    // An imported page can run its own scripts. Only translate the prose present
    // when this reading session starts, even if the page later rewrites its DOM.
    const approvedSource = snapshotImportedHTML
      ? new WeakMap(sourceBlocks().map(element => [element, textOf(element)]))
      : null;

    function assignID(element) {
      const id = ++nextID;
      ids.set(element, id);
      elements.set(id, element);
    }

    function removeTranslation(element) {
      translations.get(element)?.host.remove();
      translations.delete(element);
    }

    function invalidateTranslation(element) {
      const entry = translations.get(element);
      if (!entry || (entry.host.isConnected && textOf(element) === entry.source)) return;
      removeTranslation(element);
      elements.delete(ids.get(element));
      assignID(element);
    }

    function schedule() {
      if (!timer) timer = setTimeout(report, 140);
    }

    const intersection = new IntersectionObserver(entries => {
      for (const entry of entries) {
        if (entry.isIntersecting) intersecting.add(entry.target);
        else intersecting.delete(entry.target);
      }
      schedule();
    });

    function refresh() {
      const leafBlocks = new Set(sourceBlocks().filter(element => !approvedSource || approvedSource.has(element)));
      for (const element of observed) {
        if (leafBlocks.has(element)) continue;
        intersection.unobserve(element);
        intersecting.delete(element);
        observed.delete(element);
        elements.delete(ids.get(element));
        removeTranslation(element);
      }
      for (const element of leafBlocks) {
        if (observed.has(element)) continue;
        assignID(element);
        observed.add(element);
        intersection.observe(element);
      }
      needsRefresh = false;
    }

    function report() {
      timer = undefined;
      if (needsRefresh) refresh();
      const paragraphs = Array.from(intersecting)
        .filter(element => {
          if (!element.isConnected || element.closest(excluded)) return false;
          const rect = element.getBoundingClientRect();
          const bottom = nestedList(element)?.getBoundingClientRect().top ?? rect.bottom;
          const appearance = getComputedStyle(element);
          return bottom > 0 && rect.top < innerHeight && rect.right > 0 && rect.left < innerWidth
            && rect.height > 0 && rect.width > 0 && appearance.visibility === 'visible' && appearance.opacity !== '0';
        })
        .sort((a, b) => a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1)
        .map(element => ({ id: ids.get(element), text: textOf(element) }))
        .filter(paragraph => !approvedSource || approvedSource.get(elements.get(paragraph.id)) === paragraph.text)
        .filter(paragraph => /\p{L}/u.test(paragraph.text));
      const signature = JSON.stringify(paragraphs);
      if (signature === lastReport) return;
      lastReport = signature;
      window.webkit.messageHandlers.readerTranslationViewport.postMessage({ token, paragraphs });
    }

    const changes = new MutationObserver(records => {
      let sourceChanged = false;
      for (const record of records) {
        if (record.type === 'childList' && !record.removedNodes.length && record.addedNodes.length
            && Array.from(record.addedNodes).every(node => translationHosts.has(node))) continue;
        sourceChanged = true;
        const node = record.target;
        const element = (node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement)?.closest(blocks);
        invalidateTranslation(element);
        for (const removed of record.removedNodes) {
          if (translationHosts.has(removed)) {
            for (const [original, entry] of translations) {
              if (entry.host === removed) invalidateTranslation(original);
            }
          }
        }
      }
      if (!sourceChanged) return;
      needsRefresh = true;
      schedule();
    });
    changes.observe(document.body, {
      childList: true, characterData: true, subtree: true,
      attributes: true, attributeFilter: ['class', 'hidden', 'aria-hidden', 'style']
    });
    document.addEventListener('scroll', schedule, { capture: true, passive: true });
    globalThis.weiBeiReaderTranslation = {
      stop(expected) {
        if (expected && expected !== token) return;
        clearTimeout(timer);
        changes.disconnect();
        intersection.disconnect();
        document.removeEventListener('scroll', schedule, true);
        for (const entry of translations.values()) entry.host.remove();
        translations.clear();
        delete globalThis.weiBeiReaderTranslation;
      },
      render(expected, updates) {
        const applied = [];
        if (expected !== token) return applied;
        for (const { id, source, translation } of updates) {
          const element = elements.get(id);
          if (element?.isConnected && textOf(element) === source) {
            removeTranslation(element);
            const host = document.createElement('span');
            host.setAttribute('data-weibei-reader-translation', '');
            translationHosts.add(host);
            host.contentEditable = 'false';
            Object.assign(host.style, {
              color: 'inherit', opacity: '.8', fontSize: '.93em', fontWeight: 'normal',
              lineHeight: '1.6', marginBlock: '.35em .55em', whiteSpace: 'pre-wrap', overflowWrap: 'anywhere'
            });
            host.style.setProperty('display', 'block', 'important');
            host.attachShadow({ mode: 'closed' }).append(document.createTextNode(translation));
            translations.set(element, { source, host });
            if (isSlide(element)) {
              host.style.contain = 'inline-size';
              host.style.paddingInline = 'min(4vw, 24px)';
              element.append(host);
            } else if (element.matches('li,td,th,caption,body')) element.insertBefore(host, nestedList(element));
            else element.after(host);
            applied.push(id);
          }
        }
        return applied;
      }
    };
    refresh();
    schedule();
    """#
}
