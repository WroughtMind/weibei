import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";

const [html, script, styles, workflow, relations] = await Promise.all([
  readFile(new URL("./index.html", import.meta.url), "utf8"),
  readFile(new URL("./main.js", import.meta.url), "utf8"),
  readFile(new URL("./styles.css", import.meta.url)),
  stat(new URL("./assets/workflow-live-scrub.mp4", import.meta.url)),
  stat(new URL("./assets/relations-live-scrub.mp4", import.meta.url)),
]);

assert.equal(
  createHash("sha256").update(styles).digest("hex"),
  "b57964ce84b9dd0c21c0c957cebf8ddc3b372a622c49151e7a53b6785847d731"
);
assert.match(html, /three-pane-live\.png/);
assert.match(html, /workflow-live-scrub\.mp4/);
assert.match(html, /relations-live-scrub\.mp4/);
assert.doesNotMatch(html, /preload="auto"/);
assert.match(html, /data-download-link/);
assert.match(html, /rel="canonical"/);
assert.doesNotMatch(html, /three-pane-workspace\.png|src="\.\/assets\/workflow\.mp4"|src="\.\/assets\/relations\.mp4"/);
assert.match(script, /function createScrubber/);
assert.match(script, /video\.preload = "auto"/);
assert.match(script, /desktopStory \? workflowVideos\.map\(createScrubber\) : \[\]/);
assert.match(script, /URL\.createObjectURL/);
assert.match(script, /let requestedTime = Number\.NaN/);
assert.match(script, /const crossfade = smoothstep/);
assert.match(script, /function resolvePublishedDownload/);
assert.match(script, /response = reducedMotion \|\| captureMode \? 1 : 0\.18/);
assert.doesNotMatch(script, /35\.4|11\.7/);
assert.ok(workflow.size > 1_000_000);
assert.ok(relations.size > 500_000);

console.log("v7 检查通过：旧版样式零改动，仅替换实机媒体并修复寻帧、交叉淡入与停靠。");
