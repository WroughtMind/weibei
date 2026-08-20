declare global {
  interface Window {
    WeiBeiKaTeX?: any;
    WeiBeiMermaid?: any;
    WeiBeiPrism?: any;
  }
}

const scripts = new Map<string, Promise<void>>();

const loadScript = (name: string) => {
  const existing = scripts.get(name);
  if (existing) return existing;
  const promise = new Promise<void>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = new URL(name, document.baseURI).href;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Unable to load local editor runtime: ${name}`));
    document.head.appendChild(script);
  });
  scripts.set(name, promise);
  return promise;
};

export const loadKaTeX = () => loadScript('katex-runtime.js').then(() => window.WeiBeiKaTeX);
export const loadedKaTeX = () => window.WeiBeiKaTeX;
export const loadMermaid = () => loadScript('mermaid-runtime.js').then(() => window.WeiBeiMermaid);
export const loadPrism = () => loadScript('prism-runtime.js').then(() => window.WeiBeiPrism);
