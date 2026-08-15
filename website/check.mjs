import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";

const [html, script, styles, workflow, relations] = await Promise.all([
  readFile(new URL("./index.html", import.meta.url), "utf8"),
  readFile(new URL("./main.js", import.meta.url), "utf8"),
  readFile(new URL("./styles.css", import.meta.url), "utf8"),
  stat(new URL("./assets/workflow-live-scrub.mp4", import.meta.url)),
  stat(new URL("./assets/relations-live-scrub.mp4", import.meta.url)),
]);

assert.match(html, /three-pane-live\.png/);
assert.match(html, /workflow-live-scrub\.mp4/);
assert.match(html, /relations-live-scrub\.mp4/);
assert.doesNotMatch(html, /preload="auto"/);
assert.match(html, /data-download-link/);
assert.match(html, /rel="canonical"/);
assert.match(html, /class="stage-mark"/);
assert.match(html, /class="snap-points"/);
assert.match(html, /styles\.css\?v=13-edge-shadow/);
assert.match(html, /main\.js\?v=13-edge-shadow/);
assert.match(html, /<b>读<\/b>/);
assert.match(html, /<b>问<\/b>/);
assert.match(html, /<b>记<\/b>/);
assert.doesNotMatch(html, /chapter-rail|scroll-cue|workspace-lens|workspace-status|replay/);
assert.doesNotMatch(html, /三栏，刚好是一条路|问题不离开上下文|答案带着|最后一步，仍由你确认|关联会留下/);
assert.doesNotMatch(html, /three-pane-workspace\.png|src="\.\/assets\/workflow\.mp4"|src="\.\/assets\/relations\.mp4"/);
assert.match(script, /function createScrubber/);
assert.match(script, /\{ name: "panes", at: 1 \/ 6 \}/);
assert.match(script, /Number\(button\.dataset\.stop\)/);
assert.match(script, /video\.preload = "auto"/);
assert.match(script, /desktopStory \? workflowVideos\.map\(createScrubber\) : \[\]/);
assert.match(script, /URL\.createObjectURL/);
assert.match(script, /let requestedTime = Number\.NaN/);
assert.match(script, /--stage-mark-opacity/);
assert.match(script, /\{ x: 0, y: 225, scale: 0\.88 \}/);
assert.match(script, /\{ x: -36, y: 94, scale: 0\.96 \}/);
assert.match(script, /\{ x: 78, y: 104, scale: 0\.94 \}/);
assert.match(script, /function resolvePublishedDownload/);
assert.doesNotMatch(script, /gestureLocked|gestureTimer|document\.addEventListener\("wheel"/);
assert.match(script, /addEventListener\("scrollend"/);
assert.match(script, /const nearestIndex = stops\.indexOf\(nearestStop\(progressFromScroll\(\)\)\)/);
assert.doesNotMatch(script, /35\.4|11\.7/);
assert.doesNotMatch(script, /--lens-opacity|--workspace-media-x/);
assert.doesNotMatch(script, /snapToNearest|scheduleSnap|scrollVelocity/);
assert.match(styles, /\.stage-mark/);
assert.match(styles, /\.persistent-canvas \* \{\s*pointer-events: none;/);
assert.match(styles, /--workspace-y: 275px/);
assert.match(styles, /aspect-ratio: 1315 \/ 768/);
assert.match(styles, /border-radius: 30px;/);
assert.match(styles, /object-fit: contain/);
assert.match(styles, /scroll-snap-type: y mandatory/);
assert.match(styles, /scroll-snap-stop: always/);
assert.match(script, /--stage-dark/);
assert.match(styles, /color-mix\(in oklab/);
assert.match(styles, /#1e1a17/);
assert.match(styles, /var\(--paper-deep\)/);
assert.doesNotMatch(styles, /opacity: var\(--stage-dark\)|box-shadow: 0 0 0 3000px/);
assert.ok(workflow.size > 1_000_000);
assert.ok(relations.size > 500_000);

console.log("宣传页检查通过：固定应用窗口、逐页手势、干净媒体切换与精简文案均已接入。");
