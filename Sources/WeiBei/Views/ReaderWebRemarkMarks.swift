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
    /// HTML 材料阅读器的记过标记:整句 wrap + 句末朱砂短棒(::after)+ hover 整句高亮 + 点击回传。
    /// 与 selectionScript 里的问过下划线同构,独立脚本便于单独演进。
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
        .weibei-remark-mark::after {
          content: "";
          display: inline-block;
          width: 3px;
          height: 0.85em;
          margin-left: 3px;
          vertical-align: -0.08em;
          border-radius: 1.5px;
          background-color: rgba(145, 38, 27, 1.0);
        }
        .weibei-remark-mark:hover {
          background-color: rgba(145, 38, 27, 0.14);
        }
      `;
      document.documentElement.appendChild(style);
      window.WeiBeiRemarkMarks = {
        apply: function(marks) {
          try {
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
          } catch (e) {}
        }
      };
    })();
    """
}
