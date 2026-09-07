import Foundation
import WeiBeiCore

/// 记过标记 JSON:`[{id, text}]`(与 selectionAskMarksJSON 同构,排序稳定防 WebKit IPC 抖动)。
func selectionRemarkMarksJSON(_ records: [SelectionRemarkRecord], activeID: UUID? = nil, revealRequest: ExcerptRevealRequest? = nil) -> String {
    let marks = records.map { record -> [String: Any] in
        var mark: [String: Any] = [
            "id": record.id.uuidString,
            "text": record.selectionText,
            "active": record.id == activeID,
        ]
        if revealRequest?.recordID == record.id { mark["reveal"] = revealRequest?.id.uuidString }
        if let anchor = record.documentAnchor?.text {
            mark["anchor"] = ["startOffset": anchor.startOffset, "endOffset": anchor.endOffset]
        }
        return mark
    }
    guard let data = try? JSONSerialization.data(withJSONObject: Array(marks), options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return json
}

extension WebReaderRepresentable {
    /// HTML 材料阅读器的记过标记:整句 wrap + **行右缘朱砂圆点**(绝对定位,不用 float——满行时 float 会掉到下一行看不见)。
    /// hover 圆点或整句 → 整句高亮;点击回传 remarkMark。
    static let readerRemarkMarksScript = """
    (() => {
      if (window.WeiBeiRemarkMarks) return;
      const style = document.createElement("style");
      style.textContent = `
        .weibei-remark-mark {
          cursor: pointer;
          border-radius: 2px;
          transition: background-color 120ms ease;
        }
        .weibei-remark-mark:hover,
        .weibei-remark-mark.weibei-remark-hover,
        .weibei-remark-mark.weibei-remark-active {
          background-color: rgba(145, 38, 27, 0.14);
        }
        .weibei-remark-dot {
          position: absolute;
          width: 24px;
          height: 24px;
          margin-left: 5px;
          border-radius: 50%;
          background: radial-gradient(circle, rgba(145, 38, 27, 1) 4.5px, transparent 5px);
          cursor: pointer;
          z-index: 3;
        }
      `;
      document.documentElement.appendChild(style);

      const placeDots = function() {
        document.querySelectorAll(".weibei-remark-dot").forEach((dot) => dot.remove());
        const placedByLine = new Map();
        document.querySelectorAll(".weibei-remark-end").forEach((span) => {
          const recordId = span.dataset.recordId || "";
          if (!recordId) return;
          const rects = span.getClientRects();
          if (!rects || rects.length === 0) return;
          const last = rects[rects.length - 1];
          // 圆点挂在句子末行:同一文本行(top 相近)堆叠,从行右缘向左排
          const lineKey = Math.round(last.top / 4);
          const host = span.closest("p, div, li, blockquote, td, section, article") || span.parentElement;
          if (!host) return;
          const hostRect = host.getBoundingClientRect();
          const relativeTop = last.top - hostRect.top + (last.height - 24) / 2;
          const slot = placedByLine.get(lineKey) || 0;
          placedByLine.set(lineKey, slot + 1);
          // 行右缘=宿主段落右缘;同行多条从右缘向左堆叠
          const rightOffset = slot * 24;
          const dot = document.createElement("span");
          dot.className = "weibei-remark-dot";
          dot.dataset.weibeiAnnotationUi = "true";
          dot.dataset.recordId = recordId;
          dot.style.top = `${relativeTop}px`;
          dot.style.right = `${rightOffset}px`;
          if (getComputedStyle(host).position === "static") host.style.position = "relative";
          host.appendChild(dot);
          const fragments = Array.from(document.querySelectorAll(".weibei-remark-mark")).filter(el => el.dataset.recordId === recordId);
          dot.onmouseenter = function() { fragments.forEach(el => el.classList.add("weibei-remark-hover")); };
          dot.onmouseleave = function() { fragments.forEach(el => el.classList.remove("weibei-remark-hover")); };
          dot.onclick = function(ev) {
            ev.preventDefault();
            ev.stopPropagation();
            if (window.webkit?.messageHandlers?.remarkMark) {
              window.webkit.messageHandlers.remarkMark.postMessage({
                recordId,
                rect: { x: ev.clientX, y: ev.clientY }
              });
            }
          };
        });
      };

      let placementFrame = 0;
      const scheduleDots = () => {
        cancelAnimationFrame(placementFrame);
        placementFrame = requestAnimationFrame(placeDots);
      };
      window.addEventListener("resize", scheduleDots);
      document.fonts?.ready.then(scheduleDots);

      window.WeiBeiRemarkMarks = {
        apply: function(marks) {
          try {
            document.querySelectorAll(".weibei-remark-dot").forEach((dot) => dot.remove());
            WeiBeiSelection.applyDOMSelectionMarks(document.body, marks, "weibei-remark-mark", "data-record-id");
            document.querySelectorAll(".weibei-remark-mark").forEach((el) => {
              el.onclick = function(ev) {
                if (window.getSelection()?.toString().trim()) return;
                ev.preventDefault();
                ev.stopPropagation();
                const recordId = el.dataset.recordId || "";
                if (window.webkit?.messageHandlers?.remarkMark) {
                  window.webkit.messageHandlers.remarkMark.postMessage({
                    recordId,
                    rect: { x: ev.clientX, y: ev.clientY }
                  });
                }
              };
            });
            // 字体加载/布局稳定后再定点位
            window.requestAnimationFrame(placeDots);
            window.setTimeout(placeDots, 350);
          } catch (e) {}
        }
      };
    })();
    """
}
