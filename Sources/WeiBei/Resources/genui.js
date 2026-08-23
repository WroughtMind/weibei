(() => {
  'use strict';

  const root = document.getElementById('genui-root');
  const svgNS = 'http://www.w3.org/2000/svg';
  const palette = ['var(--series-1)', 'var(--series-2)', 'var(--series-3)', 'var(--series-4)', 'var(--series-5)'];
  const timers = new Map();
  let spec = { items: [] };
  let state = {};
  let nodeCount = 0;
  let actionStatus = 'ready';
  let actionUnavailableReason = '';
  let queuedActionKey = null;
  let pendingAction = null;
  let actionRejection = null;
  let nextActionRequestID = 0;
  let nodeLimitNoticeShown = false;

  const post = body => window.webkit?.messageHandlers?.weibeiGenUI?.postMessage(body);
  const clamp = (value, min, max) => Math.min(max, Math.max(min, Number(value) || 0));
  const array = (value, cap = 50) => {
    if (!Array.isArray(value)) return [];
    return value.slice(0, cap);
  };
  const string = (value, cap = Infinity) => {
    if (typeof value !== 'string') return '';
    return value.slice(0, cap);
  };
  const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const color = (value, index = 0) => /^#[0-9a-f]{3,8}$/i.test(value || '') ? value : palette[index % palette.length];
  const keyFor = (node, path) => string(node?.id, 128) || path;
  const read = (key, fallback) => Object.prototype.hasOwnProperty.call(state, key) ? state[key] : fallback;
  const write = (key, value, redraw = false) => {
    state[key] = value;
    post({ type: 'state', state });
    if (redraw) render();
  };
  const action = (node, key, payload = {}) => {
    if (!node.action || actionStatus !== 'ready' || actionUnavailableReason || pendingAction) return;
    pendingAction = { requestID: ++nextActionRequestID, key };
    actionRejection = null;
    post({ type: 'action', requestID: pendingAction.requestID, action: typeof node.action === 'string' ? node.action : '', payload: { component: key, ...payload, state } });
    render();
  };
  const el = (tag, className, content) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (content !== undefined) node.textContent = string(content);
    return node;
  };
  const svg = (tag, attrs = {}) => {
    const node = document.createElementNS(svgNS, tag);
    for (const [name, value] of Object.entries(attrs)) node.setAttribute(name, String(value));
    return node;
  };
  const append = (parent, children) => children.forEach(child => child && parent.append(child));
  const revealInBatches = (parent, items, appendItem, batchSize = 50) => {
    let shown = 0;
    const controls = el('div', 'data-progress');
    const status = el('span');
    const more = el('button', 'control-button', '继续显示');
    const reveal = () => {
      const end = Math.min(items.length, shown + batchSize);
      items.slice(shown, end).forEach(appendItem);
      shown = end;
      status.textContent = `已显示 ${shown}/${items.length}`;
      more.hidden = shown >= items.length;
      reportHeight();
    };
    more.onclick = reveal;
    reveal();
    if (shown < items.length) { controls.append(status, more); parent.append(controls); }
  };

  function renderItems(items, path, depth) {
    const fragment = document.createDocumentFragment();
    const values = Array.isArray(items) ? items : [];
    let shown = 0;
    const controls = el('div', 'data-progress');
    const status = el('span');
    const more = el('button', 'control-button', '继续显示');
    const reveal = () => {
      const end = Math.min(values.length, shown + 100);
      const children = document.createDocumentFragment();
      let next = shown;
      for (; next < end; next += 1) {
        const child = renderNode(values[next], `${path}.${next}`, depth + 1);
        if (child) children.append(child);
        if (nodeLimitNoticeShown) break;
      }
      shown = next;
      if (controls.parentNode) controls.before(children); else fragment.append(children);
      status.textContent = nodeLimitNoticeShown
        ? `已显示 ${shown}/${values.length}；剩余内容因本地资源限制未显示`
        : `已显示 ${shown}/${values.length}`;
      more.hidden = nodeLimitNoticeShown || shown >= values.length;
      reportHeight();
    };
    more.onclick = reveal;
    reveal();
    if (shown < values.length) { controls.append(status, more); fragment.append(controls); }
    return fragment;
  }

  function container(node, path, depth, className) {
    const box = el('div', className);
    if (node.type === 'grid') box.style.gridTemplateColumns = `repeat(${clamp(node.cols || 1, 1, 6)}, minmax(0, 1fr))`;
    if (node.type === 'col' && node.gap !== undefined) box.style.gap = `${clamp(node.gap, 0, 64)}px`;
    if (node.wrap) box.classList.add('wrap');
    box.append(renderItems(node.items, path, depth));
    if (node.spacer) box.append(el('div', 'spacer'));
    return box;
  }

  function field(node, key, multiline = false) {
    const label = el('label', 'field');
    if (node.label) label.append(el('span', '', node.label));
    const control = multiline ? document.createElement('textarea') : document.createElement('input');
    if (multiline) control.rows = clamp(node.rows || 4, 1, 16);
    else control.type = ['text', 'email', 'password'].includes(node.inputType) ? node.inputType : 'text';
    control.placeholder = string(node.placeholder, 500);
    control.value = string(read(key, node.value || ''), 4000);
    control.addEventListener('input', () => write(key, control.value));
    label.append(control);
    return label;
  }

  function chartNode(node) {
    const data = array(node.data, 60).map(item => ({ label: string(item?.label, 80), value: number(item?.value), color: item?.color }));
    const wrap = el('div', 'chart');
    if (!data.length) return wrap;
    if (node.kind === 'donut') {
      const body = el('div', 'donut-wrap');
      const total = data.reduce((sum, item) => sum + Math.max(0, item.value), 0) || 1;
      let cursor = 0;
      const stops = data.map((item, index) => {
        const start = cursor;
        cursor += Math.max(0, item.value) / total * 360;
        return `${color(item.color, index)} ${start}deg ${cursor}deg`;
      });
      const ring = el('div', 'donut');
      ring.style.background = `conic-gradient(${stops.join(',')})`;
      body.append(ring, legend(data));
      wrap.append(body);
      return wrap;
    }
    const width = 640, height = 240, left = 42, right = 16, top = 14, bottom = 38;
    const figure = svg('svg', { viewBox: `0 0 ${width} ${height}`, role: 'img' });
    const values = data.map(item => item.value);
    const min = Math.min(0, ...values), max = Math.max(0, ...values);
    const span = max - min || 1;
    const x = index => left + (width - left - right) * (data.length === 1 ? .5 : index / (data.length - 1));
    const y = value => top + (height - top - bottom) * (1 - (value - min) / span);
    figure.append(svg('rect', { x: left, y: top, width: width - left - right, height: height - top - bottom, class: 'chart-frame' }));
    if (node.kind === 'line') {
      const points = data.map((item, index) => `${x(index)},${y(item.value)}`).join(' ');
      figure.append(svg('polyline', { points, fill: 'none', stroke: color(data[0]?.color, 0), 'stroke-width': 2.5, 'stroke-linejoin': 'round' }));
      data.forEach((item, index) => figure.append(svg('circle', { cx: x(index), cy: y(item.value), r: 3.2, fill: color(item.color, index) })));
    } else {
      const gap = 8;
      const barWidth = Math.max(8, (width - left - right) / Math.max(1, data.length) - gap);
      data.forEach((item, index) => {
        const xPos = left + index * ((width - left - right) / data.length) + gap / 2;
        const zero = y(0), valueY = y(item.value);
        figure.append(svg('rect', { x: xPos, y: Math.min(zero, valueY), width: barWidth, height: Math.max(2, Math.abs(zero - valueY)), rx: 3, fill: color(item.color, index) }));
      });
    }
    data.forEach((item, index) => {
      const label = svg('text', { x: x(index), y: height - 15, 'text-anchor': 'middle', class: 'chart-label' });
      label.textContent = item.label;
      figure.append(label);
    });
    wrap.append(figure, legend(data));
    return wrap;
  }

  function legend(items) {
    const box = el('div', 'legend');
    items.forEach((item, index) => {
      const row = el('span');
      const swatch = el('i');
      swatch.style.background = color(item.color, index);
      row.append(swatch, document.createTextNode(`${item.label} · ${item.value ?? ''}`));
      box.append(row);
    });
    return box;
  }

  function plotNode(node, key) {
    const definitions = array(node.series, 8);
    const wrap = el('div', 'plot');
    if (node.title) wrap.append(el('div', 'learning-title', node.title));
    const explicitPoints = definitions.flatMap(entry => array(entry?.points, 240))
      .filter(point => Array.isArray(point) && point.length >= 2 && Number.isFinite(Number(point[0])) && Number.isFinite(Number(point[1])))
      .map(point => [Number(point[0]), Number(point[1])]);
    let xMin = node.xMin === undefined ? (explicitPoints.length ? Math.min(...explicitPoints.map(point => point[0])) : -5) : number(node.xMin, -5);
    let xMax = node.xMax === undefined ? (explicitPoints.length ? Math.max(...explicitPoints.map(point => point[0])) : 5) : number(node.xMax, 5);
    if (xMax < xMin) { xMin = -5; xMax = 5; }
    else if (xMax === xMin) { xMin -= 1; xMax += 1; }

    const parameters = array(definitions.flatMap((entry, seriesIndex) => array(entry?.params, 8).flatMap(raw => {
      const name = string(raw?.name, 24);
      if (!/^[a-z]$/.test(name)) return [];
      const min = number(raw?.min, 0);
      const proposedMax = number(raw?.max, 10);
      const max = proposedMax > min ? proposedMax : min + 1;
      return [{
        seriesIndex,
        name,
        label: string(raw?.label, 80) || `${string(entry?.label, 80) || string(entry?.expr, 80)} · ${name}`,
        min,
        max,
        step: Math.max(number(raw?.step, (max - min) / 100), Number.EPSILON),
        value: clamp(number(raw?.value, 1), min, max),
        stateKey: `${key}:plot:${seriesIndex}:${name}`,
      }];
    })), 16);

    const resolveSeries = useDefaults => definitions.map((entry, seriesIndex) => {
      const expr = string(entry?.expr, 500);
      const params = {};
      parameters.filter(parameter => parameter.seriesIndex === seriesIndex).forEach(parameter => {
        params[parameter.name] = useDefaults ? parameter.value : clamp(read(parameter.stateKey, parameter.value), parameter.min, parameter.max);
      });
      const points = expr && globalThis.WeiBeiSafeMath
        ? globalThis.WeiBeiSafeMath.sampleExpr(expr, xMin, xMax, 180, params)
        : array(entry?.points, 240)
          .filter(point => Array.isArray(point) && point.length >= 2 && Number.isFinite(Number(point[0])) && Number.isFinite(Number(point[1])))
          .map(point => [Number(point[0]), Number(point[1])]);
      return {
        label: string(entry?.label, 80) || expr || `系列 ${seriesIndex + 1}`,
        color: color(entry?.color, seriesIndex),
        points,
      };
    }).filter(entry => entry.points.length > 1);

    const initial = resolveSeries(true);
    if (!initial.length) {
      wrap.append(el('div', 'error', '函数或数据无法绘制。'));
      return wrap;
    }
    const initialY = initial.flatMap(entry => entry.points.map(point => point[1]));
    let yMin = node.yMin === undefined ? Math.min(...initialY) : number(node.yMin);
    let yMax = node.yMax === undefined ? Math.max(...initialY) : number(node.yMax);
    if (yMax < yMin) { yMin = -1; yMax = 1; }
    if (yMin === yMax) { yMin -= 1; yMax += 1; }
    if (node.yMin === undefined && node.yMax === undefined) {
      const margin = (yMax - yMin) * .08;
      yMin -= margin;
      yMax += margin;
    }

    const width = 640, height = 270, left = 52, right = 18, top = 14, bottom = 46;
    const x = value => left + (value - xMin) / (xMax - xMin) * (width - left - right);
    const y = value => top + (1 - (value - yMin) / (yMax - yMin)) * (height - top - bottom);
    const chart = el('div');
    const draw = () => {
      const series = resolveSeries(false);
      const figure = svg('svg', { viewBox: `0 0 ${width} ${height}`, role: 'img' });
      figure.append(svg('rect', { x: left, y: top, width: width - left - right, height: height - top - bottom, class: 'chart-frame' }));
      if (xMin <= 0 && xMax >= 0) figure.append(svg('line', { x1: x(0), x2: x(0), y1: top, y2: height - bottom, class: 'axis-line' }));
      if (yMin <= 0 && yMax >= 0) figure.append(svg('line', { x1: left, x2: width - right, y1: y(0), y2: y(0), class: 'axis-line' }));
      series.forEach(entry => figure.append(svg('polyline', { points: entry.points.map(point => `${x(point[0])},${y(point[1])}`).join(' '), fill: 'none', stroke: entry.color, 'stroke-width': 2.2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round' })));
      const xLabel = svg('text', { x: (left + width - right) / 2, y: height - 10, 'text-anchor': 'middle', class: 'axis-label' }); xLabel.textContent = string(node.xLabel, 80);
      const yLabel = svg('text', { x: 13, y: (top + height - bottom) / 2, transform: `rotate(-90 13 ${(top + height - bottom) / 2})`, 'text-anchor': 'middle', class: 'axis-label' }); yLabel.textContent = string(node.yLabel, 80);
      figure.append(xLabel, yLabel);
      chart.replaceChildren(figure);
    };
    draw();
    const main = el('div', 'plot-main');
    main.append(chart, legend(initial.map(entry => ({ label: entry.label, color: entry.color, value: '' }))));
    const workspace = el('div', `plot-workspace${parameters.length ? ' has-params' : ''}`);
    workspace.append(main);
    if (parameters.length) {
      const controls = el('div', 'plot-params');
      parameters.forEach(parameter => {
        const row = el('label', 'plot-param-row');
        const name = el('span', 'plot-param-name', parameter.label);
        const input = document.createElement('input');
        const output = el('output', 'plot-param-value');
        input.type = 'range';
        input.min = parameter.min;
        input.max = parameter.max;
        input.step = parameter.step;
        input.value = clamp(read(parameter.stateKey, parameter.value), parameter.min, parameter.max);
        output.textContent = String(Math.round(Number(input.value) * 100) / 100);
        input.oninput = () => {
          state[parameter.stateKey] = Number(input.value);
          output.textContent = String(Math.round(Number(input.value) * 100) / 100);
          post({ type: 'state', state });
          draw();
        };
        row.append(name, input, output);
        controls.append(row);
      });
      workspace.append(controls);
    }
    wrap.append(workspace);
    return wrap;
  }

  function sceneNode(node, key) {
    const scene = el('div', 'learning');
    if (node.title) scene.append(el('div', 'learning-title', node.title));
    const viewport = el('div', 'scene3d');
    const world = el('div', 'scene3d-world');
    const initial = read(key, { x: -12, y: 24 });
    const apply = value => { world.style.transform = `rotateX(${value.x}deg) rotateY(${value.y}deg)`; };
    apply(initial);
    array(node.objects, 12).forEach((object, index) => {
      const shape = ['box', 'sphere', 'cone', 'cylinder'].includes(object?.shape) ? object.shape : 'box';
      const part = el('div', `scene3d-object ${shape}`);
      const c = color(object?.color, index); part.style.backgroundColor = c; part.style.setProperty('--object-color', c);
      const position = array(object?.position, 3), scale = array(object?.scale, 3);
      part.style.transform = `translate3d(${number(position[0]) * 46}px, ${-number(position[1]) * 36}px, ${number(position[2]) * 46}px) scale3d(${number(scale[0], 1)},${number(scale[1], 1)},${number(scale[2], 1)})`;
      if (object?.label) part.append(el('span', 'scene3d-label', object.label));
      world.append(part);
    });
    let drag = null;
    viewport.addEventListener('pointerdown', event => { drag = { x: event.clientX, y: event.clientY, value: read(key, initial) }; viewport.setPointerCapture(event.pointerId); });
    viewport.addEventListener('pointermove', event => { if (!drag) return; const value = { x: drag.value.x - (event.clientY - drag.y) * .35, y: drag.value.y + (event.clientX - drag.x) * .45 }; state[key] = value; apply(value); });
    viewport.addEventListener('pointerup', event => { if (!drag) return; drag = null; viewport.releasePointerCapture(event.pointerId); write(key, state[key]); });
    viewport.append(world); scene.append(viewport); return scene;
  }

  function sortNode(node, key) {
    const box = el('div', 'learning'); if (node.prompt) box.append(el('div', 'learning-title', node.prompt));
    const fallback = array(node.items, 24).map(item => string(item, 500));
    const items = array(read(key, fallback), 24); const list = el('div', 'practice-list');
    const move = (from, to) => { if (to < 0 || to >= items.length || from === to) return; const next = [...items]; next.splice(to, 0, next.splice(from, 1)[0]); write(key, next, true); };
    items.forEach((item, index) => {
      const row = el('div', 'practice-item'); row.draggable = true; row.dataset.index = index;
      row.addEventListener('dragstart', event => event.dataTransfer.setData('text/plain', String(index)));
      row.addEventListener('dragover', event => event.preventDefault()); row.addEventListener('drop', event => move(Number(event.dataTransfer.getData('text/plain')), index));
      const buttons = el('span', 'move'); const up = el('button', 'control-button', '↑'); const down = el('button', 'control-button', '↓'); up.disabled = index === 0; down.disabled = index === items.length - 1; up.onclick = () => move(index, index - 1); down.onclick = () => move(index, index + 1);
      buttons.append(up, down); row.append(el('span', 'drag', '≡'), el('span', '', item), buttons); list.append(row);
    });
    box.append(list, practiceFooter(key, () => items.every((item, index) => item === array(node.answer, 24)[index]))); return box;
  }

  function matchNode(node, key) {
    const box = el('div', 'learning'); if (node.prompt) box.append(el('div', 'learning-title', node.prompt));
    const pairs = array(node.pairs, 24).map(pair => ({ left: string(pair?.left, 500), right: string(pair?.right, 500) })).filter(pair => pair.left && pair.right);
    const value = read(key, { matches: {}, selected: null }); const grid = el('div', 'match-grid'), left = el('div', 'match-column'), right = el('div', 'match-column');
    const pair = target => { if (!value.selected) return; value.matches[value.selected] = target; value.selected = null; write(key, value, true); };
    pairs.forEach(item => { const button = el('button', `match-button ${value.selected === item.left ? 'selected' : ''}`, item.left); button.draggable = true; button.onclick = () => { value.selected = item.left; write(key, value, true); }; button.ondragstart = event => event.dataTransfer.setData('text/plain', item.left); left.append(button); });
    [...pairs].reverse().forEach(item => { const button = el('button', 'match-button', item.right); const source = Object.entries(value.matches).find(([, target]) => target === item.right)?.[0]; if (source) button.append(el('small', 'match-paired', source)); button.ondragover = event => event.preventDefault(); button.ondrop = event => { value.selected = event.dataTransfer.getData('text/plain'); pair(item.right); }; button.onclick = () => pair(item.right); right.append(button); });
    grid.append(left, right); box.append(grid, practiceFooter(key, () => pairs.every(item => value.matches[item.left] === item.right))); return box;
  }

  function classifyNode(node, key) {
    const box = el('div', 'learning'); if (node.prompt) box.append(el('div', 'learning-title', node.prompt));
    const groups = array(node.groups, 8).map(group => ({ label: string(group?.label, 200), items: array(group?.items, 24).map(item => string(item, 500)) })).filter(group => group.label);
    const all = groups.flatMap(group => group.items); const value = read(key, { placed: {}, selected: null }); const bank = el('div', 'bank');
    const select = item => { value.selected = item; write(key, value, true); }; const place = group => { if (!value.selected) return; value.placed[value.selected] = group; value.selected = null; write(key, value, true); };
    all.filter(item => !value.placed[item]).forEach(item => { const button = el('button', `bank-button ${value.selected === item ? 'selected' : ''}`, item); button.draggable = true; button.onclick = () => select(item); button.ondragstart = event => event.dataTransfer.setData('text/plain', item); bank.append(button); });
    const buckets = el('div', 'classify-grid'); groups.forEach(group => { const bucket = el('div', 'bucket'); bucket.append(el('div', 'bucket-title', group.label)); bucket.ondragover = event => event.preventDefault(); bucket.ondrop = event => { value.selected = event.dataTransfer.getData('text/plain'); place(group.label); }; bucket.onclick = () => place(group.label); Object.entries(value.placed).filter(([, label]) => label === group.label).forEach(([item]) => { const button = el('button', 'bank-button', item); button.onclick = event => { event.stopPropagation(); delete value.placed[item]; write(key, value, true); }; bucket.append(button); }); buckets.append(bucket); });
    box.append(bank, buckets, practiceFooter(key, () => groups.every(group => group.items.every(item => value.placed[item] === group.label)))); return box;
  }

  function practiceFooter(key, check) {
    const footer = el('div', 'practice-footer'); const button = el('button', 'control-button', '检查');
    button.onclick = () => write(`${key}:result`, check(), true);
    footer.append(button); const result = read(`${key}:result`, null); if (result !== null) footer.append(el('span', result ? 'correct' : 'incorrect', result ? '正确' : '再调整一下')); return footer;
  }

  function formulaNode(node, key) {
    const box = el('div', 'learning'); if (node.label) box.append(el('div', 'learning-title', node.label)); box.append(el('div', 'formula-expression', node.expression));
    const steps = array(node.steps, 24), visible = clamp(read(key, steps.length), 0, steps.length), list = el('ol', 'formula-steps');
    steps.slice(0, visible).forEach(step => { const item = el('li', 'formula-step'); item.append(el('div', 'formula-expression', step?.expression)); if (step?.explanation) item.append(el('div', 'formula-explain', step.explanation)); list.append(item); }); box.append(list);
    if (steps.length) { const controls = el('div', 'learning-controls'), previous = el('button', 'control-button', '上一步'), next = el('button', 'control-button', '下一步'); previous.disabled = visible === 0; next.disabled = visible === steps.length; previous.onclick = () => write(key, visible - 1, true); next.onclick = () => write(key, visible + 1, true); controls.append(previous, next); box.append(controls); } return box;
  }

  function quizNode(node, key) {
    const box = el('div', 'learning'); box.append(el('div', 'learning-title', node.question)); const options = array(node.options, 12), selected = read(key, null);
    options.forEach((option, index) => { let className = 'quiz-option'; if (selected !== null) className += option?.correct ? ' correct' : selected === index ? ' wrong' : ''; const button = el('button', className, option?.label); button.disabled = selected !== null; button.onclick = () => write(key, index, true); box.append(button); });
    if (selected !== null) { const chosen = options[selected], result = el('div', 'quiz-result'); result.append(el('strong', chosen?.correct ? 'correct' : 'incorrect', chosen?.correct ? '回答正确' : '再想想看')); if (chosen?.feedback) result.append(el('div', 'quiz-explanation', chosen.feedback)); if (node.explanation) result.append(el('div', 'quiz-explanation', node.explanation)); const retry = el('button', 'control-button', '重新作答'); retry.onclick = () => write(key, null, true); result.append(retry); box.append(result); } return box;
  }

  function simulationNode(node, key) {
    const box = el('div', 'learning'); if (node.title) box.append(el('div', 'learning-title', node.title)); const steps = array(node.steps, 60); if (!steps.length) return box;
    const value = read(key, { current: clamp(node.current || 0, 0, steps.length - 1), playing: false }); value.current = clamp(value.current, 0, steps.length - 1); const current = steps[value.current];
    const stage = el('div', 'simulation-stage'); stage.append(el('strong', '', current?.label), el('p', '', current?.content)); box.append(stage);
    const track = el('div', 'simulation-track'); steps.forEach((_, index) => { const button = el('button', index === value.current ? 'active' : ''); button.onclick = () => { value.current = index; write(key, value, true); }; track.append(button); }); box.append(track);
    const controls = el('div', 'learning-controls'), previous = el('button', 'control-button', '上一步'), play = el('button', 'control-button', value.playing ? '暂停' : '播放'), next = el('button', 'control-button', '下一步'); previous.disabled = value.current === 0; next.disabled = value.current === steps.length - 1; previous.onclick = () => { value.current -= 1; write(key, value, true); }; next.onclick = () => { value.current += 1; write(key, value, true); }; play.onclick = () => { value.playing = !value.playing; write(key, value, true); }; controls.append(previous, play, next); box.append(controls);
    if (value.playing) { const timer = setTimeout(() => { if (value.current < steps.length - 1) value.current += 1; else if (node.loop) value.current = 0; else value.playing = false; write(key, value, true); }, clamp(node.intervalMs || 1200, 250, 60000)); timers.set(key, timer); } return box;
  }

  function renderNode(node, path, depth) {
    if (!node || typeof node !== 'object') return null;
    if (depth > 8) return el('div', 'error content-limit', '这一部分过大，未显示。');
    if (nodeCount++ > 200) {
      if (nodeLimitNoticeShown) return null;
      nodeLimitNoticeShown = true;
      return el('div', 'error content-limit', '这一部分过大，未显示。');
    }
    const key = keyFor(node, path);
    switch (node.type) {
      case 'text': { const item = el('div', `text ${['h1','h2','h3','body','muted','caption'].includes(node.size) ? node.size : 'body'}${node.center ? ' center' : ''}`, node.content); return item; }
      case 'row': return container(node, path, depth, 'row'); case 'col': return container(node, path, depth, 'col'); case 'grid': return container(node, path, depth, 'grid');
      case 'card': { const box = el('section', 'card'); if (node.title) box.append(el('div', 'card-title', node.title)); box.append(renderItems(node.items, path, depth)); return box; }
      case 'divider': return el('hr', 'divider'); case 'spacer': return el('div', 'spacer');
      case 'badge': return el('span', `badge ${['success','warn','danger','accent'].includes(node.tone) ? node.tone : ''}`, node.label);
      case 'progress': { const box = el('div'); const head = el('div', 'progress-head'); head.append(el('span', '', node.label), el('span', '', node.valueLabel || `${clamp(node.value,0,100)}%`)); const track = el('div', 'progress-track'), fill = el('div', 'progress-fill'); fill.style.width = `${clamp(node.value,0,100)}%`; track.append(fill); box.append(head, track); return box; }
      case 'list': { const wrap = el('div'), box = el('div', 'list'), items = Array.isArray(node.items) ? node.items : []; wrap.append(box); revealInBatches(wrap, items, item => { const row = el('div', 'list-item', typeof item === 'string' ? item : item?.title); if (typeof item === 'object' && item?.desc) row.append(el('span', 'list-desc', item.desc)); box.append(row); }); return wrap; }
      case 'table': { const wrap = el('div', 'table-wrap'), table = el('table'), thead = el('thead'), header = el('tr'), columns = Array.isArray(node.columns) ? node.columns : []; columns.forEach(column => header.append(el('th','',column))); thead.append(header); const tbody = el('tbody'), rows = Array.isArray(node.rows) ? node.rows : []; table.append(thead,tbody); wrap.append(table); revealInBatches(wrap, rows, row => { const tr = el('tr'), cells = Array.isArray(row) ? row : []; cells.forEach(cell => tr.append(el('td','',String(cell)))); tbody.append(tr); }); return wrap; }
      case 'keyvalue': { const box = el('dl', 'kv'); array(node.pairs,24).forEach(pair => box.append(el('dt','kv-key',pair?.key), el('dd','kv-value',pair?.value))); return box; }
      case 'callout': { const box = el('aside', `callout ${node.tone || ''}`); if (node.title) box.append(el('div','callout-title',node.title)); box.append(el('div','',node.content)); return box; }
      case 'steps': { const box = el('div','steps'), current = clamp(node.current ?? array(node.steps).length,0,array(node.steps).length); array(node.steps,24).forEach((step,index) => { const row = el('div',`step ${index < current ? 'done' : index === current ? 'active' : ''}`), body=el('div'); body.append(el('div','',step?.title)); if(step?.desc) body.append(el('div','step-desc',step.desc)); row.append(el('span','step-mark',index < current ? '✓' : index+1),body); box.append(row); }); return box; }
      case 'timeline': { const box=el('div','timeline'); array(node.items,24).forEach(item=>{const row=el('div','timeline-item'),body=el('div'); body.append(el('div','',item?.title)); if(item?.time) body.append(el('div','timeline-time',item.time)); if(item?.desc) body.append(el('div','timeline-desc',item.desc)); row.append(el('span','timeline-mark','·'),body); box.append(row);}); return box; }
      case 'button': {
        const box=el('div'), label=string(node.label,200), button=el('button',`button ${node.tone || ''}`,label);
        const reason=!node.action?'此按钮没有配置继续回答操作。':actionUnavailableReason;
        const rejection=actionRejection?.key===key?actionRejection.reason:'';
        const status=reason?'':actionStatus==='processing'?'处理中':pendingAction?.key===key?'已按下':queuedActionKey===key?'已排队':'';
        button.disabled=Boolean(reason||status);
        if(status) button.textContent=`${label} · ${status}`;
        button.onclick=()=>action(node,key,{type:'button',label});
        box.append(button);
        if(reason||rejection){button.title=reason||rejection; box.append(el('div','text caption',reason||rejection));}
        return box;
      }
      case 'input': return field(node,key,false); case 'textarea': return field(node,key,true);
      case 'select': { const label=el('label','field'); if(node.label) label.append(el('span','',node.label)); const select=el('select'), options=array(node.options,50); options.forEach((option,index)=>{const item=el('option','',option); item.value=String(index); select.append(item);}); select.value=String(read(key,clamp(node.selected||0,0,options.length-1))); select.onchange=()=>write(key,Number(select.value)); label.append(select); return label; }
      case 'checkbox': { const label=el('label','choice'),input=document.createElement('input'); input.type='checkbox'; input.checked=Boolean(read(key,node.checked===true)); input.onchange=()=>write(key,input.checked); label.append(input,document.createTextNode(string(node.label))); return label; }
      case 'radio': { const box=el('div','field'); if(node.label) box.append(el('span','',node.label)); const selected=read(key,clamp(node.selected||0,0,array(node.options).length-1)); array(node.options,50).forEach((option,index)=>{const label=el('label','choice'),input=document.createElement('input'); input.type='radio'; input.name=`radio-${key}`; input.checked=index===selected; input.onchange=()=>write(key,index,true); label.append(input,document.createTextNode(string(option))); box.append(label);}); return box; }
      case 'switch': { const button=el('button',`button ${read(key,node.checked===true) ? 'primary' : 'ghost'}`,`${node.label} · ${read(key,node.checked===true) ? '开' : '关'}`); button.setAttribute('role','switch'); button.setAttribute('aria-checked',String(Boolean(read(key,node.checked===true)))); button.onclick=()=>{const value=!read(key,node.checked===true); write(key,value,true);}; return button; }
      case 'slider': { const label=el('label','field'),head=el('span','slider-head'),value=number(read(key,node.value),number(node.value)); head.append(el('span','',node.label),el('output','',`${value}${string(node.unit,30)}`)); const input=document.createElement('input'); input.type='range'; input.min=number(node.min); input.max=number(node.max,100); input.step=number(node.step,(input.max-input.min)/100); input.value=value; input.oninput=()=>{state[key]=Number(input.value); head.querySelector('output').textContent=`${input.value}${string(node.unit,30)}`; post({type:'state',state});}; label.append(head,input); return label; }
      case 'tabs': { const box=el('div','tabs'),tabs=array(node.tabs,12),active=clamp(read(key,0),0,tabs.length-1),bar=el('div','tabbar'); tabs.forEach((tab,index)=>{const button=el('button',`tab ${index===active?'active':''}`,tab?.label); button.onclick=()=>write(key,index,true); bar.append(button);}); box.append(bar); if(tabs[active]) box.append(renderItems(tabs[active].items,`${path}.tab${active}`,depth)); return box; }
      case 'accordion': { const box=el('div'),items=array(node.items,24),open=read(key,0); items.forEach((item,index)=>{const head=el('button','accordion-head'); head.append(el('span','',item?.title),el('span','',open===index?'−':'+')); head.onclick=()=>write(key,open===index?null:index,true); box.append(head); if(open===index){const body=el('div','accordion-body'); body.append(renderItems(item.items,`${path}.acc${index}`,depth)); box.append(body);}}); return box; }
      case 'copy': { const button=el('button','button',node.label||'复制'); button.onclick=()=>navigator.clipboard?.writeText(string(node.text,12000)).then(()=>{button.textContent='已复制'; setTimeout(()=>button.textContent=node.label||'复制',1200);}).catch(()=>{}); return button; }
      case 'chart': return chartNode(node); case 'plot': return plotNode(node,key); case 'scene3d': return sceneNode(node,key);
      case 'formula': return formulaNode(node,key); case 'quiz': return quizNode(node,key); case 'sort': return sortNode(node,key); case 'match': return matchNode(node,key); case 'classify': return classifyNode(node,key); case 'simulation': return simulationNode(node,key);
      default: return null;
    }
  }

  function render() {
    timers.forEach(timer => clearTimeout(timer)); timers.clear(); nodeCount = 0; nodeLimitNoticeShown = false; root.replaceChildren();
    document.body.classList.toggle('dark', spec.appearance === 'dark');
    const block = el('section','genui'); block.style.gap=`${clamp(spec.gap ?? 12,0,64)}px`; if(spec.title) block.append(el('div','banner',spec.title)); block.append(renderItems(spec.items,'root',0));
    if (!block.children.length) block.append(el('div','error','这个互动界面没有可显示的组件。')); root.append(block); reportHeight();
  }
  function reportHeight() { requestAnimationFrame(() => post({ type: 'height', height: Math.ceil(Math.max(root.scrollHeight, root.getBoundingClientRect().height)) })); }
  new ResizeObserver(reportHeight).observe(root);

  window.WeiBeiGenUIHost = {
    render(payload) {
      if (!payload || typeof payload.spec !== 'object' || !Array.isArray(payload.spec.items)) return;
      spec = { ...payload.spec, appearance: payload.appearance === 'dark' ? 'dark' : 'light' };
      state = payload.state && typeof payload.state === 'object' && !Array.isArray(payload.state) ? payload.state : {};
      if (actionStatus === 'processing' && payload.actionStatus === 'ready') queuedActionKey = null;
      actionStatus = payload.actionStatus === 'processing' ? 'processing' : 'ready';
      actionUnavailableReason = string(payload.actionUnavailableReason, 500);
      render();
    },
    actionResult(result) {
      if (!pendingAction || Number(result?.requestID) !== pendingAction.requestID) return;
      if (result.accepted === true) queuedActionKey = pendingAction.key;
      else actionRejection = { key: pendingAction.key, reason: string(result?.reason, 500) || '互动操作未被受理。' };
      pendingAction = null;
      render();
    },
    snapshot() { return state; },
  };
  post({ type: 'ready' });
})();
