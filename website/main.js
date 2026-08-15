const run = document.querySelector(".scroll-run");
const stage = document.querySelector(".stage");
const scenes = [...document.querySelectorAll(".scene")];
const progressButtons = [...document.querySelectorAll("[data-progress], [data-stop]")];
const workflowVideos = [...document.querySelectorAll(".workspace-flow")];
const relationsVideo = document.querySelector(".workspace-relations");
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const desktopStory = matchMedia("(min-width: 761px)").matches;
const captureParams = new URLSearchParams(location.search);
const captureMode = captureParams.has("capture");
const captureStop = captureParams.get("stop");
const releasesUrl = "https://github.com/weibei-app/weibei/releases";

const stops = [
  { name: "hero", at: 0 },
  { name: "panes", at: 1 / 6 },
  { name: "context", at: 2 / 6 },
  { name: "provenance", at: 3 / 6 },
  { name: "writeback", at: 4 / 6 },
  { name: "relations", at: 5 / 6 },
  { name: "finish", at: 1 },
];

const workspaceStates = [
  { x: 540, y: 390, scale: 0.74 },
  { x: 0, y: 225, scale: 0.88 },
  { x: -36, y: 94, scale: 0.96 },
  { x: 560, y: 90, scale: 0.82 },
  { x: -28, y: 110, scale: 0.96 },
  { x: 0, y: 98, scale: 0.95 },
  { x: 84, y: 505, scale: 0.78 },
];

let targetProgress = captureStop === null
  ? 0
  : stops[Math.min(Math.max(Number(captureStop) || 0, 0), stops.length - 1)].at;
let renderedProgress = targetProgress;
let currentStopIndex = 0;
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
  root.setProperty("--stage-mark-opacity", (0.92 * (1 - smoothstep(progress / 0.12))).toFixed(3));

  const workflowIn = smoothstep((progress - 0.19) / 0.11);
  const relationsIn = smoothstep((progress - 0.77) / 0.08);
  const finishIn = smoothstep((progress - 0.94) / 0.06);
  const workflowReady = workflowVideos.every(video => video.dataset.frameReady === "true");
  const relationsReady = relationsVideo?.dataset.frameReady === "true";
  const workflowOpacity = workflowIn * Number(workflowReady) * (1 - finishIn);
  const relationsOpacity = relationsIn * Number(relationsReady) * (1 - finishIn);
  root.setProperty("--workspace-static-opacity", "1");
  root.setProperty("--workspace-flow-opacity", workflowOpacity.toFixed(3));
  root.setProperty("--workspace-relations-opacity", relationsOpacity.toFixed(3));
}

function setActiveScene(index) {
  if (activeSceneIndex === index) return;
  activeSceneIndex = index;
  stage?.classList.toggle("is-dark", index === 3);
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
  const activeIndex = local < 0.5 ? lower : upper;

  scenes.forEach((scene, index) => {
    const opacity = Number(index === activeIndex);
    scene.style.setProperty("--scene-opacity", opacity.toFixed(4));
    scene.style.setProperty("--scene-z", String(opacity > 0 ? 8 : 0));
  });

  setActiveScene(activeIndex);

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

function scrollToStop(index, behavior = reducedMotion ? "auto" : "smooth") {
  if (!run) return;
  currentStopIndex = clamp(index, 0, stops.length - 1);
  const next = stops[currentStopIndex].at;
  scrollTo({
    top: run.offsetTop + next * (run.offsetHeight - innerHeight),
    behavior,
  });
}

function stepStory(direction) {
  const nextIndex = clamp(currentStopIndex + direction, 0, stops.length - 1);
  if (nextIndex !== currentStopIndex) scrollToStop(nextIndex);
}

addEventListener("scroll", () => {
  if (captureStop !== null) return;
  targetProgress = progressFromScroll();
}, { passive: true });

addEventListener("scrollend", () => {
  if (captureStop !== null) return;
  const nearestIndex = stops.indexOf(nearestStop(progressFromScroll()));
  const nearestProgress = stops[nearestIndex].at;
  if (nearestIndex !== currentStopIndex || Math.abs(progressFromScroll() - nearestProgress) > 0.002) {
    scrollToStop(nearestIndex);
  }
}, { passive: true });

addEventListener("resize", () => {
  updateCanvasScale();
  if (captureStop !== null) return;
  targetProgress = progressFromScroll();
}, { passive: true });

progressButtons.forEach(button => {
  button.addEventListener("click", event => {
    event.preventDefault();
    const index = button.dataset.stop === undefined
      ? stops.findIndex(stop => stop.at === Number(button.dataset.progress))
      : Number(button.dataset.stop);
    if (index >= 0) scrollToStop(index);
  });
});

addEventListener("keydown", event => {
  if (!["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp"].includes(event.key)) return;
  const direction = event.key === "ArrowRight" || event.key === "ArrowDown" ? 1 : -1;
  event.preventDefault();
  stepStory(direction);
});

[...workflowVideos, relationsVideo].filter(Boolean).forEach(video => {
  video.addEventListener("loadedmetadata", () => paint(renderedProgress), { once: true });
});

updateCanvasScale();
if (captureStop === null) {
  targetProgress = progressFromScroll();
}
renderedProgress = targetProgress;
currentStopIndex = stops.indexOf(nearestStop(targetProgress));
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
