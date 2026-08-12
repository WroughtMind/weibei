const run = document.querySelector(".scroll-run");
const stage = document.querySelector(".stage");
const scenes = [...document.querySelectorAll(".scene")];
const progressButtons = [...document.querySelectorAll("[data-progress]")];
const workflowVideos = [...document.querySelectorAll(".workspace-flow")];
const relationsVideo = document.querySelector(".workspace-relations");
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
  { x: 0, y: 380, scale: 0.86 },
  { x: 0, y: 112, scale: 0.96 },
  { x: -36, y: 90, scale: 0.98 },
  { x: 78, y: 104, scale: 0.94 },
  { x: -28, y: 118, scale: 0.98 },
  { x: 0, y: 96, scale: 0.95 },
  { x: 84, y: 430, scale: 0.78 },
];

let targetProgress = 0;
let renderedProgress = 0;
let currentStopIndex = 0;
let gestureLocked = false;
let gestureDirection = 0;
let gestureDelta = 0;
let gestureTimer = 0;
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
  targetProgress = progressFromScroll();
}, { passive: true });

document.addEventListener("wheel", event => {
  if (!desktopStory || event.deltaY === 0) return;
  event.preventDefault();
  if (Math.abs(event.deltaY) < 0.5) return;
  const direction = Math.sign(event.deltaY);
  const delta = Math.abs(event.deltaY) * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? innerHeight : 1);
  clearTimeout(gestureTimer);
  if (!gestureLocked) {
    if (direction !== gestureDirection) gestureDelta = 0;
    gestureDirection = direction;
    gestureDelta += delta;
    if (gestureDelta >= 24) {
      gestureLocked = true;
      gestureDelta = 0;
      stepStory(direction);
    }
  } else if (direction !== gestureDirection) {
    gestureDelta += delta;
    if (gestureDelta >= 80) {
      gestureDirection = direction;
      gestureDelta = 0;
      stepStory(direction);
    }
  } else {
    gestureDelta = 0;
  }
  gestureTimer = setTimeout(() => {
    gestureLocked = false;
    gestureDirection = 0;
    gestureDelta = 0;
  }, 420);
}, { capture: true, passive: false });

addEventListener("scrollend", () => {
  const nearestIndex = stops.indexOf(nearestStop(progressFromScroll()));
  const nearestProgress = stops[nearestIndex].at;
  if (nearestIndex !== currentStopIndex || Math.abs(progressFromScroll() - nearestProgress) > 0.002) {
    scrollToStop(nearestIndex);
  }
}, { passive: true });

addEventListener("resize", () => {
  updateCanvasScale();
  targetProgress = progressFromScroll();
}, { passive: true });

progressButtons.forEach(button => {
  button.addEventListener("click", event => {
    event.preventDefault();
    const index = stops.findIndex(stop => stop.at === Number(button.dataset.progress));
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
targetProgress = progressFromScroll();
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
