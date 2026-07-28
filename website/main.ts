const REPOSITORY = "weibei-app/weibei";
const RELEASES_URL = `https://github.com/${REPOSITORY}/releases`;
const RELEASE_MANIFEST = "./release.json";
const LOCAL_DMG = "./downloads/WeiBei-latest.dmg";

type Theme = "paper" | "inkstone";

interface ReleaseAsset {
  download_url: string;
  name: string;
  size?: number | string;
}

interface ReleaseManifest {
  asset_name?: string;
  assets?: ReleaseAsset[];
  available?: boolean;
  download_url?: string;
  published_at?: string;
  size?: number | string;
  tag_name?: string;
  version?: string;
}

const root = document.documentElement;
const themeColor = document.querySelector<HTMLMetaElement>(
  'meta[name="theme-color"]',
);
const themeLabel = document.querySelector<HTMLElement>("[data-theme-label]");
const themeToggles = document.querySelectorAll<HTMLElement>(
  "[data-theme-toggle], [data-theme-toggle-secondary]",
);

/**
 * 读取访客保存的主题；尚未选择时跟随系统配色。
 *
 * @returns 当前页面应使用的主题
 */
function preferredTheme(): Theme {
  const saved = localStorage.getItem("weibei-theme");
  if (saved === "paper" || saved === "inkstone") return saved;
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "inkstone"
    : "paper";
}

/**
 * 更新页面主题以及浏览器标题栏颜色。
 *
 * @param theme - 要应用的主题
 * @param persist - 是否保存访客的主动选择
 */
function setTheme(theme: Theme, persist = false): void {
  root.dataset.theme = theme;
  if (themeLabel) themeLabel.textContent = theme === "paper" ? "墨石" : "纸面";
  if (themeColor)
    themeColor.content = theme === "paper" ? "#f2e2ca" : "#0f0f0f";
  if (persist) localStorage.setItem("weibei-theme", theme);
}

/**
 * 在纸面与墨石主题之间切换，并保存访客选择。
 */
function toggleTheme(): void {
  setTheme(root.dataset.theme === "paper" ? "inkstone" : "paper", true);
}

setTheme(preferredTheme());

for (const button of themeToggles) {
  button.addEventListener("click", toggleTheme);
}

const header = document.querySelector<HTMLElement>("[data-header]");

/**
 * 根据滚动位置同步页头的紧凑样式。
 */
function updateHeader(): void {
  header?.classList.toggle("is-scrolled", window.scrollY > 24);
}

updateHeader();
window.addEventListener("scroll", updateHeader, { passive: true });

const revealItems = document.querySelectorAll<HTMLElement>(".reveal");
for (const item of revealItems) {
  item.classList.add("is-visible");
}

/**
 * 将安装包字节数格式化为适合下载区域展示的 MB 文本。
 *
 * @param bytes - 发布清单中的安装包字节数
 * @returns 可展示的文件大小；无效值返回空字符串
 */
function fileSize(bytes: number | string | null | undefined): string {
  const value = Number(bytes);
  if (!Number.isFinite(value) || value <= 0) return "";
  const megabytes = value / (1024 * 1024);
  return `${megabytes >= 100 ? megabytes.toFixed(0) : megabytes.toFixed(1)} MB`;
}

/**
 * 规范发布版本号，避免页面重复展示 Git 标签的 v 前缀。
 *
 * @param version - 发布清单中的版本号
 * @returns 去除 v 前缀后的版本号
 */
function cleanVersion(version: string | null | undefined): string {
  return String(version || "")
    .trim()
    .replace(/^v/i, "");
}

/**
 * 将发布时间格式化为中文短日期。
 *
 * @param value - 发布清单中的 ISO 日期
 * @returns 可展示的发布日期；无效值返回空字符串
 */
function releaseDate(value: string | null | undefined): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "short",
    day: "numeric",
  }).format(date);
}

/**
 * 在发布清单不可用时，把下载入口统一指向 GitHub Releases。
 */
function setFallbackRelease(): void {
  const downloadLinks = document.querySelectorAll<HTMLAnchorElement>(
    "[data-download-link]",
  );
  for (const link of downloadLinks) {
    link.href = RELEASES_URL;
    link.removeAttribute("download");
  }

  const downloadLabels = document.querySelectorAll<HTMLElement>(
    "[data-download-label]",
  );
  for (const label of downloadLabels) {
    label.textContent = "查看最新版本";
  }
}

/**
 * 根据安装包文件名推断面向访客展示的处理器架构。
 *
 * @param name - 安装包文件名
 * @returns 架构展示名称
 */
function architectureLabel(name: string): string {
  if (/universal/i.test(name)) return "Universal";
  if (/arm64|aarch64|apple[-_ ]?silicon/i.test(name)) return "Apple Silicon";
  if (/x86_64|x64|intel/i.test(name)) return "Intel";
  return "macOS";
}

/**
 * 将新版多资源和旧版单资源发布清单统一为资源数组。
 *
 * @param release - 网站发布清单
 * @returns 具备名称和下载地址的安装包资源
 */
function normalizedAssets(release: ReleaseManifest): ReleaseAsset[] {
  if (Array.isArray(release.assets)) {
    return release.assets.filter((asset) =>
      Boolean(asset?.name && asset.download_url),
    );
  }
  if (release.asset_name && release.download_url) {
    return [
      {
        name: release.asset_name,
        size: release.size,
        download_url: release.download_url,
      },
    ];
  }
  return [];
}

/**
 * 渲染多架构安装包选择入口。
 *
 * @param assets - 可下载的安装包资源
 */
function renderDownloadOptions(assets: ReleaseAsset[]): void {
  const options = document.querySelector<HTMLElement>(
    "[data-download-options]",
  );
  if (!options) return;
  options.replaceChildren();

  for (const asset of assets) {
    const link = document.createElement("a");
    const title = document.createElement("strong");
    const detail = document.createElement("span");
    link.href = new URL(asset.download_url, document.baseURI).href;
    link.download = asset.name;
    title.textContent = architectureLabel(asset.name);
    detail.textContent = `${asset.name}${asset.size ? ` · ${fileSize(asset.size)}` : ""}`;
    link.append(title, detail);
    options.append(link);
  }
  options.hidden = assets.length < 2;
}

/**
 * 将发布清单同步到下载按钮、版本信息与安装包说明。
 *
 * @param release - 网站发布清单
 */
function applyRelease(release: ReleaseManifest): void {
  if (!release.available) {
    setFallbackRelease();
    return;
  }

  const version = cleanVersion(release.version || release.tag_name);
  const published = releaseDate(release.published_at);
  const assets = normalizedAssets(release);
  let primary: ReleaseAsset | undefined;
  for (const asset of assets) {
    if (/universal/i.test(asset.name)) {
      primary = asset;
      break;
    }
  }
  if (!primary && assets.length === 1) primary = assets[0];

  if (!assets.length) {
    setFallbackRelease();
    return;
  }

  renderDownloadOptions(assets);

  const downloadLinks = document.querySelectorAll<HTMLAnchorElement>(
    "[data-download-link]",
  );
  for (const link of downloadLinks) {
    link.href = primary
      ? new URL(primary.download_url || LOCAL_DMG, document.baseURI).href
      : "#download";
    if (primary) link.setAttribute("download", primary.name);
    else link.removeAttribute("download");
  }

  const downloadLabels = document.querySelectorAll<HTMLElement>(
    "[data-download-label]",
  );
  for (const [index, label] of downloadLabels.entries()) {
    if (!primary) {
      label.textContent = "选择 macOS 版本";
    } else {
      label.textContent =
        index === 0 && version
          ? `下载 v${version}`
          : `下载${version ? ` v${version}` : "最新版"} DMG`;
    }
  }

  const versionLabel = document.querySelector<HTMLElement>(
    "[data-release-version]",
  );
  if (versionLabel && version) versionLabel.textContent = `v${version}`;

  const meta = document.querySelector<HTMLElement>("[data-release-meta]");
  if (meta) {
    meta.textContent = [
      "macOS 14 及以上",
      version && `v${version}`,
      primary && fileSize(primary.size),
      published,
    ]
      .filter(Boolean)
      .join(" · ");
  }

  const assetLabel = document.querySelector<HTMLElement>("[data-asset-name]");
  if (assetLabel) {
    assetLabel.textContent = primary
      ? [primary.name, fileSize(primary.size)].filter(Boolean).join(" · ")
      : `${assets.length} 个安装包可选`;
  }
}

/**
 * 加载最新发布清单；网络或清单异常时回退到 Releases 页面。
 */
async function resolveLatestRelease(): Promise<void> {
  try {
    const response = await fetch(RELEASE_MANIFEST, { cache: "no-store" });
    if (!response.ok)
      throw new Error(`release manifest unavailable: ${response.status}`);
    applyRelease((await response.json()) as ReleaseManifest);
  } catch {
    setFallbackRelease();
  }
}

void resolveLatestRelease();
