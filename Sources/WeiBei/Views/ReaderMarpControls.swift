import Foundation

/// Owns the reader chrome while Marp keeps navigation, fragments and keyboard handling.
enum ReaderMarpControls {
    static let styleScript = #"""
    (() => {
      const style = document.createElement('style');
      style.id = 'weibei-marp-controls-style';
      style.textContent = `
        body:has(svg[data-marpit-svg]) .bespoke-marp-osc { visibility: hidden !important; }
        body .weibei-slide-controls {
          position: fixed; inset: auto 12px 12px auto; z-index: 2147483000;
          display: flex; align-items: center; gap: 6px; box-sizing: border-box;
          margin: 0; padding: 3px; border-radius: 8px;
          border: 1px solid color-mix(in srgb, var(--weibei-note-ink) 16%, transparent);
          background: color-mix(in srgb, var(--weibei-note-fill) 86%, transparent) !important;
          color: var(--weibei-note-ink) !important;
          box-shadow: 0 3px 7px color-mix(in srgb, var(--weibei-note-ink) 5%, transparent);
          backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px);
          font: 500 12px/1 -apple-system, BlinkMacSystemFont, sans-serif;
          user-select: none; -webkit-user-select: none; cursor: default;
        }
        body .weibei-slide-controls > button {
          appearance: none; -webkit-appearance: none; display: grid; place-items: center;
          flex: 0 0 26px; width: 26px; height: 26px; box-sizing: border-box;
          padding: 0; margin: 0; border: 1px solid transparent; border-radius: 6px;
          background: transparent !important; color: var(--weibei-note-ink) !important;
          cursor: pointer; opacity: .8;
        }
        body .weibei-slide-controls > button:hover:enabled {
          opacity: 1;
          background: color-mix(in srgb, var(--weibei-note-ink) 7%, transparent) !important;
          border-color: color-mix(in srgb, var(--weibei-note-ink) 14%, transparent);
          box-shadow: inset 0 1px 0 #ffffff12, 0 1px 2px #00000012;
        }
        body .weibei-slide-controls > button:active:enabled {
          background: color-mix(in srgb, var(--weibei-note-ink) 12%, transparent) !important;
          box-shadow: inset 0 1px 2px #00000018;
        }
        body .weibei-slide-controls > button:focus-visible {
          outline: 2px solid var(--weibei-note-accent); outline-offset: 2px; opacity: 1;
        }
        body .weibei-slide-controls > button:disabled { opacity: .28; cursor: not-allowed; }
        body .weibei-slide-controls > button > svg {
          width: 13px; height: 13px; fill: none; stroke: currentColor;
          stroke-width: 1.6; stroke-linecap: round; stroke-linejoin: round;
          pointer-events: none;
        }
        body .weibei-slide-controls > span {
          min-width: 50px; text-align: center; white-space: nowrap;
          font: 500 12px/26px ui-monospace, monospace; font-variant-numeric: tabular-nums;
          color: var(--weibei-note-muted) !important;
        }
      `;
      document.documentElement.appendChild(style);
    })();
    """#

    static func script(isEnglish: Bool) -> String {
        #"""
        (() => {
          if (window.WeiBeiMarpControls) {
            window.WeiBeiMarpControls.setLanguage('\#(isEnglish ? "english" : "chinese")');
            return;
          }
          let english = \#(isEnglish);
          const controls = new Set();
          const refresh = control => {
            // Marp's activity timer still targets this container. Reader navigation
            // stays discoverable and keyboard accessible, like the PDF controls.
            control.removeAttribute('aria-hidden');
            control.removeAttribute('inert');
            control.setAttribute('aria-label', english ? 'Slide navigation' : '课件翻页');
            for (const [direction, chinese, translated] of [
              ['prev', '上一页', 'Previous page'], ['next', '下一页', 'Next page']
            ]) {
              const button = control.querySelector(`[data-bespoke-marp-osc="${direction}"]`);
              const label = english ? translated : chinese;
              button.setAttribute('aria-label', label);
              button.title = label;
            }
            const page = control.querySelector('[data-bespoke-marp-osc="page"]');
            const match = page.textContent.trim().match(/^(?:Page (\d+) of (\d+)|(\d+)\s*\/\s*(\d+))$/);
            if (!match) return;
            const current = match[1] || match[3], total = match[2] || match[4];
            const text = `${current} / ${total}`;
            if (page.textContent !== text) page.textContent = text;
            page.setAttribute('aria-label', english ? `Page ${current} of ${total}` : `第 ${current} 页，共 ${total} 页`);
          };
          const install = control => {
            const previous = control.querySelector('button[data-bespoke-marp-osc="prev"]');
            const next = control.querySelector('button[data-bespoke-marp-osc="next"]');
            const page = control.querySelector('[data-bespoke-marp-osc="page"]');
            if (!previous || !next || !page) return;
            // Keep the delegated Marp navigation handlers on the same container;
            // remove the exported presentation UI instead of adding a second bar.
            control.replaceChildren(previous, page, next);
            control.classList.replace('bespoke-marp-osc', 'weibei-slide-controls');
            control.setAttribute('data-weibei-annotation-ui', '');
            control.setAttribute('role', 'group');
            for (const [button, path] of [[previous, 'm10 3-5 5 5 5'], [next, 'm6 3 5 5-5 5']]) {
              button.type = 'button';
              button.removeAttribute('tabindex');
              button.innerHTML = `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="${path}"/></svg>`;
            }
            page.setAttribute('aria-live', 'polite');
            page.setAttribute('aria-atomic', 'true');
            controls.add(control);
            const observer = new MutationObserver(() => refresh(control));
            observer.observe(control, {
              childList: true, subtree: true, characterData: true,
              attributes: true, attributeFilter: ['aria-hidden', 'inert']
            });
            refresh(control);
          };
          const scan = () => {
            if (!document.querySelector('svg[data-marpit-svg]')) return;
            document.querySelectorAll('.bespoke-marp-osc').forEach(install);
          };
          window.WeiBeiMarpControls = {
            setLanguage(language) {
              english = language === 'english';
              controls.forEach(refresh);
            }
          };
          scan();
          new MutationObserver(records => {
            if (records.some(record => Array.from(record.addedNodes).some(node =>
              node.nodeType === 1 && (node.matches('.bespoke-marp-osc') || node.querySelector('.bespoke-marp-osc'))
            ))) scan();
          }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """#
    }
}
