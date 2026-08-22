import Foundation
import WeiBeiCore

/// 记过标记 JSON:`[{id, text}]`(与 selectionAskMarksJSON 同构,排序稳定防 WebKit IPC 抖动)。
func selectionRemarkMarksJSON(_ records: [SelectionRemarkRecord]) -> String {
    let marks = records.prefix(60).map { record -> [String: String] in
        [
            "id": record.id.uuidString,
            "text": String(record.selectionText.prefix(240)),
        ]
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
        .weibei-remark-mark.weibei-remark-hover {
          background-color: rgba(145, 38, 27, 0.14);
        }
        .weibei-remark-dot {
          position: absolute;
          width: 9px;
          height: 9px;
          margin-left: 5px;
          border-radius: 50%;
          background-color: rgba(145, 38, 27, 1.0);
          cursor: pointer;
          z-index: 3;
        }
      `;
      document.documentElement.appendChild(style);

      const placeDots = function() {
        document.querySelectorAll(".weibei-remark-dot").forEach((dot) => dot.remove());
        const placedByLine = new Map();
        document.querySelectorAll(".weibei-remark-mark").forEach((span) => {
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
          const relativeTop = last.top - hostRect.top + (last.height - 9) / 2;
          const slot = placedByLine.get(lineKey) || 0;
          placedByLine.set(lineKey, slot + 1);
          // 行右缘=宿主段落右缘;同行多条从右缘向左堆叠
          const rightOffset = 6 + slot * 13;
          const dot = document.createElement("span");
          dot.className = "weibei-remark-dot";
          dot.dataset.recordId = recordId;
          dot.style.top = `${relativeTop}px`;
          dot.style.right = `${rightOffset}px`;
          host.style.position = "relative";
          host.appendChild(dot);
          dot.onmouseenter = function() { span.classList.add("weibei-remark-hover"); };
          dot.onmouseleave = function() { span.classList.remove("weibei-remark-hover"); };
          dot.onclick = function(ev) {
            ev.preventDefault();
            ev.stopPropagation();
            if (window.webkit?.messageHandlers?.remarkMark) {
              window.webkit.messageHandlers.remarkMark.postMessage({
                recordId,
                text: span.textContent || ""
              });
            }
          };
        });
      };

      window.WeiBeiRemarkMarks = {
        apply: function(marks) {
          try {
            document.querySelectorAll(".weibei-remark-dot").forEach((dot) => dot.remove());
            document.querySelectorAll(".weibei-remark-mark").forEach((el) => {
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
              if (!needle || !id || needle.length < 2) return;
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(node) {
                  if (!node.parentElement) return NodeFilter.FILTER_REJECT;
                  if (node.parentElement.closest(".weibei-remark-mark, .weibei-selection-ask-mark, script, style")) {
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
                span.className = "weibei-remark-mark";
                span.dataset.recordId = id;
                span.title = "回访这句的札记";
                try {
                  range.surroundContents(span);
                } catch (e) {
                  // ignore partial-node failures
                }
              });
            });
            document.querySelectorAll(".weibei-remark-mark").forEach((el) => {
              el.onclick = function(ev) {
                ev.preventDefault();
                ev.stopPropagation();
                const recordId = el.dataset.recordId || "";
                if (window.webkit?.messageHandlers?.remarkMark) {
                  window.webkit.messageHandlers.remarkMark.postMessage({
                    recordId,
                    text: el.textContent || ""
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
