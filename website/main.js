const run = document.querySelector(".scroll-run");
const stage = document.querySelector(".stage");
const scenes = [...document.querySelectorAll(".scene")];
const railButtons = [...document.querySelectorAll(".chapter-rail [data-progress]")];
const progressButtons = [...document.querySelectorAll("[data-progress]")];
const workflowVideos = [...document.querySelectorAll(".workspace-flow")];
const relationsVideo = document.querySelector(".workspace-relations");
const flowLabel = document.querySelector("[data-flow-label]");
const proofSteps = [...document.querySelectorAll("[data-proof]")];
const workspacePhase = document.querySelector("[data-workspace-phase]");
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const desktopStory = matchMedia("(min-width: 761px)").matches;
const captureMode = new URLSearchParams(location.search).has("capture");
const releasesUrl = "https://github.com/weibei-app/weibei/releases";

const stops = [
  { name: "hero", at: 0 },
  { name: "panes", at: 0.17 },
  { name: "context", at: 0.34 },
  { name: "provenance", at: 0.52 },
  { name: "writeback", at: 0.68 },
  { name: "relations", at: 0.84 },
  { name: "finish", at: 1 },
];

const workspaceStates = [
  { x: 0, y: 540, scale: 0.86, mediaX: 0, lensLeft: 0, lensWidth: 100, lensOpacity: 0, dark: 0 },
  { x: 0, y: 140, scale: 0.96, mediaX: 0, lensLeft: 0, lensWidth: 100, lensOpacity: 0, dark: 0 },
  { x: -120, y: 130, scale: 1.02, mediaX: -90, lensLeft: 31, lensWidth: 38, lensOpacity: 0.72, dark: 0 },
  { x: 520, y: 90, scale: 0.82, mediaX: -520, lensLeft: 27, lensWidth: 48, lensOpacity: 0.58, dark: 1 },
  { x: -80, y: 145, scale: 1, mediaX: -250, lensLeft: 66, lensWidth: 32, lensOpacity: 0.66, dark: 0 },
  { x: 0, y: 100, scale: 0.95, mediaX: 0, lensLeft: 0, lensWidth: 100, lensOpacity: 0, dark: 0 },
  { x: 470, y: 600, scale: 0.72, mediaX: 0, lensLeft: 0, lensWidth: 100, lensOpacity: 0, dark: 0 },
];

const workspaceLabels = [
  "三栏同时在场",
  "原文、Agent、笔记",
  "问题贴着当前材料",
  "回答带着出处回来",
  "等待你确认写入",
  "资料与笔记形成关联",
  "工作流留在一处",
];

let targetProgress = 0;
let renderedProgress = 0;
let lastScrollY = scrollY;
let scrollVelocity = 0;
let snapTimer = 0;
let snappingTo = null;
let activeSceneIndex = -1;

const clamp = (value, min = 0, max = 1) => Math.min(max, Math.max(min, value));
const mix = (a, b, amount) => a + (b - a) * amount;
const smoothstep = value => {
  const x = clamp(value);
  return x * x * (3 - 2 * x);
};

function updateCanvasScale() {
  const scale = Math.min(innerWidth / 2880, innerHeight / 1620);
  document.documentElement.style.setProperty("--canvas-scale", scale.toFixed(5));
}

function progressFromScroll() {
  if (!run) return 0;
  const distance = run.offsetHeight - innerHeight;
  return distance <= 0 ? 0 : clamp((scrollY - run.offsetTop) / distance);
}

function sceneBlend(progress) {
  const upperIndex = stops.findIndex(stop => stop.at >= progress);
  if (upperIndex <= 0) return { lower: 0, upper: 0, local: 0 };
  const upper = stops[upperIndex];
  const lower = stops[upperIndex - 1];
  const local = (progress - lower.at) / (upper.at - lower.at);
  return { lower: upperIndex - 1, upper: upperIndex, local: clamp(local) };
}

function nearestStop(progress) {
  return stops.reduce((nearest, stop) =>
    Math.abs(stop.at - progress) < Math.abs(nearest.at - progress) ? stop : nearest
  );
}

function createScrubber(video) {
  let targetTime = 0;
  let requestedTime = Number.NaN;
  let frameReady = false;
  video.preload = "auto";

  const reveal = () => {
    if (Math.abs(video.currentTime - targetTime) > 0.08) return;
    if (frameReady) return;
    frameReady = true;
    video.dataset.frameReady = "true";
  };

  const commit = () => {
    if (reducedMotion || video.readyState < 1 || !Number.isFinite(video.duration) || video.seeking) {
      return;
    }
    const next = clamp(targetTime, 0, Math.max(0, video.duration - 0.04));
    if (Number.isFinite(requestedTime) && Math.abs(requestedTime - next) <= 0.05) {
      reveal();
      return;
    }
    requestedTime = next;
    video.currentTime = next;
  };

  video.pause();
  video.addEventListener("loadedmetadata", commit);
  video.addEventListener("seeked", reveal);

  fetch(video.currentSrc || video.src)
    .then(response => {
      if (!response.ok) throw new Error(`媒体加载失败：${response.status}`);
      return response.blob();
    })
    .then(blob => {
      requestedTime = Number.NaN;
      video.src = URL.createObjectURL(blob);
      video.load();
    })
    .catch(() => {
      requestedTime = Number.NaN;
      commit();
    });

  return time => {
    video.dataset.targetTime = time.toFixed(3);
    targetTime = time;
    commit();
  };
}

const workflowScrubbers = desktopStory ? workflowVideos.map(createScrubber) : [];
const relationsScrubber = desktopStory && relationsVideo ? createScrubber(relationsVideo) : () => {};

function updateWorkflow(progress) {
  const flowTime = progress <= 0.17
    ? 0.7
    : progress <= 0.34
      ? mix(0.7, 4.2, smoothstep((progress - 0.17) / 0.17))
      : progress <= 0.52
        ? mix(4.2, 7.35, smoothstep((progress - 0.34) / 0.18))
        : progress <= 0.68
          ? mix(7.35, 13.25, smoothstep((progress - 0.52) / 0.16))
          : mix(13.25, 16.4, smoothstep((progress - 0.68) / 0.16));
  workflowScrubbers.forEach(scrub => scrub(flowTime));

  const phase = progress < 0.43 ? "answer" : progress < 0.6 ? "source" : "note";
  const labels = {
    answer: "正在读取当前上下文",
    source: "回答保留材料出处",
    note: "笔记建议等待你确认",
  };
  if (flowLabel) flowLabel.textContent = labels[phase];
  proofSteps.forEach(step => step.classList.toggle("is-active", step.dataset.proof === phase));

  const relationFlow = clamp((progress - 0.77) / 0.07);
  relationsScrubber(mix(0.4, 4.25, smoothstep(relationFlow)));
}

function updatePersistentWorkspace(progress, lower, upper, local) {
  const eased = smoothstep(local);
  const from = workspaceStates[lower];
  const to = workspaceStates[upper];
  const value = key => mix(from[key], to[key], eased);
  const root = document.documentElement.style;

  root.setProperty("--workspace-x", `${value("x").toFixed(2)}px`);
  root.setProperty("--workspace-y", `${value("y").toFixed(2)}px`);
  root.setProperty("--workspace-scale", value("scale").toFixed(4));
  root.setProperty("--workspace-media-x", `${value("mediaX").toFixed(2)}px`);
  root.setProperty("--lens-left", `${value("lensLeft").toFixed(2)}%`);
  root.setProperty("--lens-width", `${value("lensWidth").toFixed(2)}%`);
  root.setProperty("--lens-opacity", value("lensOpacity").toFixed(3));

  const workflowIn = smoothstep((progress - 0.19) / 0.11);
  const relationsIn = smoothstep((progress - 0.77) / 0.08);
  const finishIn = smoothstep((progress - 0.94) / 0.06);
  const workflowReady = workflowVideos.every(video => video.dataset.frameReady === "true");
  const relationsReady = relationsVideo?.dataset.frameReady === "true";
  const workflowOpacity = workflowIn * Number(workflowReady) * (1 - relationsIn) * (1 - finishIn);
  const relationsOpacity = relationsIn * Number(relationsReady) * (1 - finishIn);
  const staticOpacity = clamp(1 - workflowOpacity - relationsOpacity);
  root.setProperty("--workspace-static-opacity", staticOpacity.toFixed(3));
  root.setProperty("--workspace-flow-opacity", workflowOpacity.toFixed(3));
  root.setProperty("--workspace-relations-opacity", relationsOpacity.toFixed(3));

  const dark = value("dark");
  root.setProperty("--stage-dark", dark.toFixed(3));
  stage?.classList.toggle("is-dark", dark > 0.52);

  const active = local < 0.5 ? lower : upper;
  if (workspacePhase) workspacePhase.textContent = workspaceLabels[active];
}

function setActiveScene(index) {
  if (activeSceneIndex === index) return;
  activeSceneIndex = index;
  scenes.forEach((scene, sceneIndex) => {
    const active = sceneIndex === index;
    if (!active && scene.contains(document.activeElement)) document.activeElement.blur();
    scene.classList.toggle("is-interactive", active);
    scene.inert = !active;
    scene.setAttribute("aria-hidden", String(!active));
  });
}

function paint(progress) {
  const { lower, upper, local } = sceneBlend(progress);
  const crossfade = smoothstep((local - 0.31) / 0.38);
  const activeIndex = local < 0.5 ? lower : upper;

  scenes.forEach((scene, index) => {
    const opacity = lower === upper
      ? Number(index === lower)
      : index === lower
        ? 1 - crossfade
        : index === upper
          ? crossfade
          : 0;
    const drift = index === lower
      ? mix(0, -34, crossfade)
      : index === upper
        ? mix(34, 0, crossfade)
        : 0;
    scene.style.setProperty("--scene-opacity", opacity.toFixed(4));
    scene.style.setProperty("--scene-z", String(opacity > 0 ? 8 : 0));
    scene.style.setProperty("--scene-drift-x", `${drift.toFixed(2)}px`);
  });

  setActiveScene(activeIndex);
  document.documentElement.style.setProperty("--scroll-cue-opacity", clamp(1 - progress * 13).toFixed(3));

  const nearest = nearestStop(progress);
  railButtons.forEach(button => {
    button.classList.toggle("is-active", Math.abs(Number(button.dataset.progress) - nearest.at) < 0.035);
  });

  updatePersistentWorkspace(progress, lower, upper, local);
  updateWorkflow(progress);
}

function frame() {
  const response = reducedMotion || captureMode ? 1 : 0.18;
  renderedProgress += (targetProgress - renderedProgress) * response;
  if (Math.abs(targetProgress - renderedProgress) < 0.0001) renderedProgress = targetProgress;
  paint(renderedProgress);
  requestAnimationFrame(frame);
}

function scrollToProgress(progress, behavior = reducedMotion ? "auto" : "smooth") {
  if (!run) return;
  const next = clamp(progress);
  if (behavior === "smooth") snappingTo = next;
  scrollTo({
    top: run.offsetTop + next * (run.offsetHeight - innerHeight),
    behavior,
  });
}

function snapToNearest() {
  if (snappingTo !== null) return;
  const progress = progressFromScroll();
  const nearest = nearestStop(progress);
  const distance = Math.abs(nearest.at - progress);
  if (distance <= 0.003 || distance > 0.055) return;
  snappingTo = nearest.at;
  scrollToProgress(nearest.at);
}

function scheduleSnap() {
  clearTimeout(snapTimer);
  if (reducedMotion || Math.abs(scrollVelocity) > 42) return;
  snapTimer = setTimeout(snapToNearest, 180);
}

addEventListener("scroll", () => {
  const nextScrollY = scrollY;
  scrollVelocity = nextScrollY - lastScrollY;
  lastScrollY = nextScrollY;
  targetProgress = progressFromScroll();
  if (snappingTo !== null) {
    if (Math.abs(targetProgress - snappingTo) < 0.002) snappingTo = null;
    return;
  }
  scheduleSnap();
}, { passive: true });

if ("onscrollend" in window) {
  addEventListener("scrollend", snapToNearest, { passive: true });
}

["wheel", "touchstart", "pointerdown"].forEach(type => {
  addEventListener(type, () => {
    snappingTo = null;
    clearTimeout(snapTimer);
  }, { passive: true });
});

addEventListener("resize", () => {
  updateCanvasScale();
  targetProgress = progressFromScroll();
}, { passive: true });

progressButtons.forEach(button => {
  button.addEventListener("click", event => {
    event.preventDefault();
    scrollToProgress(Number(button.dataset.progress));
  });
});

addEventListener("keydown", event => {
  if (!["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp"].includes(event.key)) return;
  const direction = event.key === "ArrowRight" || event.key === "ArrowDown" ? 1 : -1;
  const currentIndex = stops.indexOf(nearestStop(targetProgress));
  const next = stops[clamp(currentIndex + direction, 0, stops.length - 1)];
  if (!next) return;
  event.preventDefault();
  scrollToProgress(next.at);
});

[...workflowVideos, relationsVideo].filter(Boolean).forEach(video => {
  video.addEventListener("loadedmetadata", () => paint(renderedProgress), { once: true });
});

updateCanvasScale();
targetProgress = progressFromScroll();
renderedProgress = targetProgress;
paint(renderedProgress);
requestAnimationFrame(frame);

async function resolvePublishedDownload() {
  try {
    const response = await fetch("./release.json", { cache: "no-store" });
    if (!response.ok) return;
    const release = await response.json();
    const assets = Array.isArray(release?.assets)
      ? release.assets.filter(asset => asset?.name && asset?.download_url)
      : [];
    const asset = assets.find(item => /universal/i.test(item.name)) || (assets.length === 1 ? assets[0] : null);
    if (!release?.available || !asset) return;
    const downloadUrl = new URL(asset.download_url, document.baseURI);
    document.querySelectorAll("[data-download-link]").forEach(link => {
      link.href = downloadUrl.href;
      link.download = asset.name;
    });
  } catch {
    document.querySelectorAll("[data-download-link]").forEach(link => {
      link.href = releasesUrl;
      link.removeAttribute("download");
    });
  }
}

resolvePublishedDownload();
