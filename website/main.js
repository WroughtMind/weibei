const REPOSITORY = "weibei-app/weibei";
const RELEASES_URL = `https://github.com/${REPOSITORY}/releases`;
const RELEASE_MANIFEST = "./release.json";
const LOCAL_DMG = "./downloads/WeiBei-latest.dmg";

const root = document.documentElement;
const themeColor = document.querySelector('meta[name="theme-color"]');
const themeLabel = document.querySelector("[data-theme-label]");
const themeToggles = document.querySelectorAll("[data-theme-toggle], [data-theme-toggle-secondary]");

function preferredTheme() {
  const saved = localStorage.getItem("weibei-theme");
  if (saved === "paper" || saved === "inkstone") return saved;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "inkstone" : "paper";
}

function setTheme(theme, persist = false) {
  root.dataset.theme = theme;
  if (themeLabel) themeLabel.textContent = theme === "paper" ? "墨石" : "纸面";
  if (themeColor) themeColor.content = theme === "paper" ? "#f2e2ca" : "#0f0f0f";
  if (persist) localStorage.setItem("weibei-theme", theme);
}

setTheme(preferredTheme());

themeToggles.forEach((button) => {
  button.addEventListener("click", () => {
    setTheme(root.dataset.theme === "paper" ? "inkstone" : "paper", true);
  });
});

const header = document.querySelector("[data-header]");
function updateHeader() {
  header?.classList.toggle("is-scrolled", window.scrollY > 24);
}

updateHeader();
window.addEventListener("scroll", updateHeader, { passive: true });

const revealItems = [...document.querySelectorAll(".reveal")];
revealItems.forEach((item) => item.classList.add("is-visible"));

function fileSize(bytes) {
  const value = Number(bytes);
  if (!Number.isFinite(value) || value <= 0) return "";
  const megabytes = value / (1024 * 1024);
  return `${megabytes >= 100 ? megabytes.toFixed(0) : megabytes.toFixed(1)} MB`;
}

function cleanVersion(version) {
  return String(version || "").trim().replace(/^v/i, "");
}

function releaseDate(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(date);
}

function setFallbackRelease() {
  document.querySelectorAll("[data-download-link]").forEach((link) => {
    link.href = RELEASES_URL;
    link.removeAttribute("download");
  });
  document.querySelectorAll("[data-download-label]").forEach((label) => {
    label.textContent = "查看最新版本";
  });
}

function architectureLabel(name) {
  if (/universal/i.test(name)) return "Universal";
  if (/arm64|aarch64|apple[-_ ]?silicon/i.test(name)) return "Apple Silicon";
  if (/x86_64|x64|intel/i.test(name)) return "Intel";
  return "macOS";
}

function normalizedAssets(release) {
  if (Array.isArray(release?.assets)) {
    return release.assets.filter((asset) => asset?.name && asset?.download_url);
  }
  if (release?.asset_name && release?.download_url) {
    return [{ name: release.asset_name, size: release.size, download_url: release.download_url }];
  }
  return [];
}

function renderDownloadOptions(assets) {
  const options = document.querySelector("[data-download-options]");
  if (!options) return;
  options.replaceChildren();

  assets.forEach((asset) => {
    const link = document.createElement("a");
    const title = document.createElement("strong");
    const detail = document.createElement("span");
    link.href = new URL(asset.download_url, document.baseURI).href;
    link.download = asset.name;
    title.textContent = architectureLabel(asset.name);
    detail.textContent = `${asset.name}${asset.size ? ` · ${fileSize(asset.size)}` : ""}`;
    link.append(title, detail);
    options.append(link);
  });
  options.hidden = assets.length < 2;
}

function applyRelease(release) {
  if (!release?.available) {
    setFallbackRelease();
    return;
  }

  const version = cleanVersion(release.version || release.tag_name);
  const published = releaseDate(release.published_at);
  const assets = normalizedAssets(release);
  const primary = assets.find((asset) => /universal/i.test(asset.name)) || (assets.length === 1 ? assets[0] : null);

  if (!assets.length) {
    setFallbackRelease();
    return;
  }

  renderDownloadOptions(assets);

  document.querySelectorAll("[data-download-link]").forEach((link) => {
    link.href = primary ? new URL(primary.download_url || LOCAL_DMG, document.baseURI).href : "#download";
    if (primary) link.setAttribute("download", primary.name);
    else link.removeAttribute("download");
  });
  document.querySelectorAll("[data-download-label]").forEach((label, index) => {
    if (!primary) {
      label.textContent = "选择 macOS 版本";
    } else {
      label.textContent = index === 0 && version ? `下载 v${version}` : `下载${version ? ` v${version}` : "最新版"} DMG`;
    }
  });

  const versionLabel = document.querySelector("[data-release-version]");
  if (versionLabel && version) versionLabel.textContent = `v${version}`;

  const meta = document.querySelector("[data-release-meta]");
  if (meta) {
    meta.textContent = ["macOS 14 及以上", version && `v${version}`, primary && fileSize(primary.size), published]
      .filter(Boolean)
      .join(" · ");
  }

  const assetLabel = document.querySelector("[data-asset-name]");
  if (assetLabel) {
    assetLabel.textContent = primary
      ? [primary.name, fileSize(primary.size)].filter(Boolean).join(" · ")
      : `${assets.length} 个安装包可选`;
  }
}

async function resolveLatestRelease() {
  try {
    const response = await fetch(RELEASE_MANIFEST, { cache: "no-store" });
    if (!response.ok) throw new Error(`release manifest unavailable: ${response.status}`);
    applyRelease(await response.json());
  } catch {
    setFallbackRelease();
  }
}

resolveLatestRelease();
