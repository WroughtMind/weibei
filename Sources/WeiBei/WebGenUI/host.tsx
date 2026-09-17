import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import {
  ErrorBoundary, GenuiActionContext, GenuiBlock, isRenderableProcess,
  processGenuiSpec, setGenuiAssetBase, type BlockInteractionState, type GenuiSpec,
} from '@changfenhuang/dsh-genui/embed';
import './host.css';

type Payload = {
  id?: string;
  renderToken?: string;
  spec: unknown;
  state?: BlockInteractionState;
  appearance?: string;
  theme?: Record<string, string>;
  actionStatus?: string;
  actionUnavailableReason?: string;
};
type ActionResult = { requestID: number; accepted: boolean; reason?: string };
declare global {
  interface Window {
    webkit?: { messageHandlers?: { weibeiGenUI?: { postMessage(body: unknown): void } } };
    WeiBeiGenUIHost: { render(payload: Payload): void; actionResult(result: ActionResult): void; snapshot(): BlockInteractionState };
  }
}

const container = document.getElementById('genui-root')!;
const content = document.getElementById('genui-content')!;
const status = document.getElementById('genui-status')!;
const root = createRoot(content);
const post = (body: unknown) => window.webkit?.messageHandlers?.weibeiGenUI?.postMessage(body);
let payload: Payload;
let spec: GenuiSpec;
let state: BlockInteractionState = {};
let pending: number | undefined;
let nextRequestID = 0;

setGenuiAssetBase('./');
const saveState = (value: BlockInteractionState) => {
  state = value;
  post({ type: 'state', state });
};
const showStatus = (message = '') => {
  status.textContent = message;
  status.hidden = message === '';
};
const sendAction = (action: string, data: Record<string, unknown>) => {
  if (pending !== undefined || payload.actionStatus === 'processing' || payload.actionUnavailableReason) return;
  pending = ++nextRequestID;
  showStatus('正在提交…');
  draw();
  post({ type: 'action', requestID: pending, action, payload: data });
};
function draw() {
  const available = pending === undefined && payload.actionStatus !== 'processing' && !payload.actionUnavailableReason;
  flushSync(() => root.render(
    <ErrorBoundary key={`${payload.id ?? 'inline'}:${payload.renderToken ?? ''}`} label="互动界面">
      <GenuiActionContext.Provider value={available ? sendAction : undefined}>
        <GenuiBlock spec={spec} stateKey={payload.id ?? 'inline'} initialState={state}
          onStateChange={saveState} animateEntrance={false} />
      </GenuiActionContext.Provider>
    </ErrorBoundary>,
  ));
}
function reportHeight() {
  requestAnimationFrame(() => post({
    type: 'height',
    height: Math.ceil(Math.max(container.scrollHeight, container.getBoundingClientRect().height)),
  }));
}
new ResizeObserver(reportHeight).observe(container);

window.WeiBeiGenUIHost = {
  render(next) {
    const result = processGenuiSpec(next.spec);
    const unsupported = result.renderedTotalCount !== result.renderedNativeCount;
    if (!isRenderableProcess(result) || result.spec === null || unsupported) {
      showStatus(`互动界面无法显示：${unsupported ? '包含未支持的组件' : result.errors.join('；')}`);
      post({ type: 'error', renderToken: next.renderToken, message: status.textContent });
      return;
    }
    if (payload === undefined || payload.id !== next.id) {
      state = next.state ?? {};
      pending = undefined;
    }
    payload = next;
    spec = result.spec;
    for (const [name, value] of Object.entries(next.theme ?? {})) {
      document.body.style.setProperty(`--weibei-${name}`, value);
    }
    document.body.toggleAttribute('data-ds-dark-theme', next.appearance === 'dark');
    document.documentElement.style.colorScheme = next.appearance === 'dark' ? 'dark' : 'light';
    showStatus(next.actionUnavailableReason || (next.actionStatus === 'processing' ? '正在生成回答…' : ''));
    draw();
    reportHeight();
    requestAnimationFrame(() => {
      if (payload !== next) return;
      const failure = content.querySelector('[data-genui-error]');
      post(failure
        ? { type: 'error', renderToken: next.renderToken, message: failure.textContent }
        : { type: 'rendered', renderToken: next.renderToken });
    });
  },
  actionResult(result) {
    if (result.requestID !== pending) return;
    pending = undefined;
    showStatus(result.accepted ? '已提交' : result.reason || '互动操作未被受理。');
    draw();
  },
  snapshot: () => state,
};
post({ type: 'ready' });
