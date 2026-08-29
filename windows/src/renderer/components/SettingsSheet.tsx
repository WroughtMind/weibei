import { useState } from "react";
import type { AppSnapshot, Preferences, ThemeMode } from "../../shared/contracts";
import { Icon } from "./Icon";

type Section = "appearance" | "agent" | "data" | "about";
const themes: Array<[ThemeMode, string, string]> = [
  ["paper", "纸本", "暖色古籍纸"], ["xuan", "宣纸", "清亮中性纸"], ["inkstone", "砚台", "温润墨黑"], ["stele", "碑石", "冷灰深色"],
  ["glassLight", "晴玻", "明亮半透明"], ["glassDark", "夜玻", "深色半透明"], ["glassMist", "雾玻", "柔和淡玻璃"], ["glassSlate", "石玻", "冷灰玻璃"],
];

interface Props {
  snapshot: AppSnapshot;
  onClose(): void;
  onPreferences(patch: Partial<Preferences>): void;
  onSnapshot(value: AppSnapshot): void;
}

export function SettingsSheet(props: Props) {
  const [section, setSection] = useState<Section>("appearance");
  const [providerId, setProviderId] = useState(props.snapshot.provider.providerId);
  const [model, setModel] = useState(props.snapshot.provider.model);
  const [baseUrl, setBaseUrl] = useState(props.snapshot.provider.baseUrl);
  const [apiKey, setApiKey] = useState("");
  const [saved, setSaved] = useState(false);
  return (
    <div className="settings-scrim" role="presentation">
      <section className="settings-sheet" role="dialog" aria-modal="true" aria-label="设置">
        <aside className="settings-sidebar">
          <header><span className="settings-seal">魏</span><div><span className="overline">WEI BEI</span><h2>设置</h2></div></header>
          <nav>
            <SettingsNav id="appearance" current={section} label="外观与阅读" glyph="theme-light" onClick={setSection} />
            <SettingsNav id="agent" current={section} label="模型与 Agent" glyph="chat" onClick={setSection} />
            <SettingsNav id="data" current={section} label="资料与安全" glyph="folder" onClick={setSection} />
            <SettingsNav id="about" current={section} label="关于魏碑" glyph="reader" onClick={setSection} />
          </nav>
          <small>魏碑 {props.snapshot.appVersion} · Windows</small>
        </aside>
        <div className="settings-content">
          <header className="settings-content-header"><div><span className="overline">SETTINGS</span><h1>{sectionTitle(section)}</h1></div><button className="icon-action" onClick={props.onClose} aria-label="关闭设置"><Icon name="close" size={19} /></button></header>
          {section === "appearance" && (
            <div className="settings-page">
              <SettingsGroup title="主题" detail="界面与编辑器会一起切换，内容本身不受影响。">
                <div className="theme-grid">{themes.map(([id, title, detail]) => (
                  <button key={id} className={props.snapshot.preferences.theme === id ? "is-selected" : ""} onClick={() => props.onPreferences({ theme: id })}>
                    <span className={`theme-swatch swatch-${id}`}><i /><i /><i /></span>
                    <span><strong>{title}</strong><small>{detail}</small></span>
                    {props.snapshot.preferences.theme === id && <Icon name="check" size={15} />}
                  </button>
                ))}</div>
              </SettingsGroup>
              <SettingsGroup title="界面文字" detail="独立于 Windows 显示缩放，在 90% 至 160% 之间调整。">
                <div className="scale-row"><span>小</span><input type="range" min="0.9" max="1.6" step="0.05" value={props.snapshot.preferences.textScale} onChange={(event) => props.onPreferences({ textScale: Number(event.target.value) })} /><span>大</span><output>{Math.round(props.snapshot.preferences.textScale * 100)}%</output></div>
              </SettingsGroup>
              <SettingsGroup title="语言与动效">
                <label className="setting-row"><span><strong>界面语言</strong><small>重新打开窗口后仍会保留。</small></span><select value={props.snapshot.preferences.language} onChange={(event) => props.onPreferences({ language: event.target.value as Preferences["language"] })}><option value="zh-Hans">简体中文</option><option value="en">English</option></select></label>
                <label className="setting-row"><span><strong>减少动态效果</strong><small>保留必要的状态反馈。</small></span><input type="checkbox" checked={props.snapshot.preferences.reduceMotion} onChange={(event) => props.onPreferences({ reduceMotion: event.target.checked })} /></label>
              </SettingsGroup>
            </div>
          )}
          {section === "agent" && (
            <div className="settings-page">
              <SettingsGroup title="模型连接" detail="密钥由 Windows DPAPI 加密，永远不会写入课程或 workspace.json。">
                <label className="field-label">供应商<select value={providerId} onChange={(event) => setProviderId(event.target.value)}><option value="openai">OpenAI</option><option value="anthropic">Anthropic</option><option value="google">Google</option><option value="custom">OpenAI 兼容接口</option></select></label>
                <label className="field-label">模型<input value={model} onChange={(event) => setModel(event.target.value)} placeholder="模型名称" /></label>
                <label className="field-label">接口地址<input value={baseUrl} onChange={(event) => setBaseUrl(event.target.value)} spellCheck={false} /></label>
                <label className="field-label">API 密钥<input type="password" value={apiKey} onChange={(event) => setApiKey(event.target.value)} placeholder={props.snapshot.provider.hasCredential ? "已安全保存；留空则不更改" : "输入 API 密钥"} /></label>
                <button className="primary-paper-button" onClick={async () => {
                  if (!window.weiBei) return;
                  const provider = await window.weiBei.saveProvider({ providerId, model, baseUrl, apiKey: apiKey || undefined });
                  props.onSnapshot({ ...props.snapshot, provider });
                  setApiKey(""); setSaved(true); setTimeout(() => setSaved(false), 1800);
                }}>{saved ? "已保存" : "保存连接"}</button>
              </SettingsGroup>
              <SettingsGroup title="写入确认" detail="Agent 不会直接更改笔记。每次修改都先形成建议，并在应用时重新校验磁盘基线。">
                <div className="safety-callout"><Icon name="check" size={18} /><span><strong>唯一写入闸门已启用</strong><small>外部修改、撤销与 Agent 建议共用同一套冲突保护。</small></span></div>
              </SettingsGroup>
            </div>
          )}
          {section === "data" && <DataPage snapshot={props.snapshot} />}
          {section === "about" && <AboutPage version={props.snapshot.appVersion} />}
        </div>
      </section>
    </div>
  );
}

function SettingsNav(props: { id: Section; current: Section; label: string; glyph: "theme-light" | "chat" | "folder" | "reader"; onClick(value: Section): void }) {
  return <button className={props.current === props.id ? "is-current" : ""} onClick={() => props.onClick(props.id)}><Icon name={props.glyph} size={17} /><span>{props.label}</span></button>;
}
function SettingsGroup(props: { title: string; detail?: string; children: React.ReactNode }) {
  return <section className="settings-group"><header><h2>{props.title}</h2>{props.detail && <p>{props.detail}</p>}</header><div className="settings-group-body">{props.children}</div></section>;
}
function DataPage({ snapshot }: { snapshot: AppSnapshot }) {
  return <div className="settings-page"><SettingsGroup title="课程资料库" detail="课程目录是事实来源；索引和缓存可随时重建。"><div className="path-card"><Icon name="folder" /><span><strong>{snapshot.libraryRootPath || "尚未选择"}</strong><small>文稿、笔记与 portable state 保存在这里</small></span></div></SettingsGroup><SettingsGroup title="文件安全"><div className="safety-callout"><Icon name="check" size={18} /><span><strong>保存前校验外部修改</strong><small>只有磁盘摘要仍与打开时一致，魏碑才会原子替换文件。</small></span></div><div className="safety-callout"><Icon name="check" size={18} /><span><strong>写后重读验证</strong><small>OneDrive 或网络盘暂时不可用时会保留草稿，不会报告假成功。</small></span></div></SettingsGroup></div>;
}
function AboutPage({ version }: { version: string }) {
  return <div className="about-page"><span className="about-seal">魏</span><h2>魏碑</h2><p>专注于课程阅读、笔记与思考的本地工作台。</p><small>Windows 版本 {version}</small><div><button>隐私说明</button><button>第三方许可</button><button>素材归属</button></div></div>;
}
function sectionTitle(section: Section) { return { appearance: "外观与阅读", agent: "模型与 Agent", data: "资料与安全", about: "关于魏碑" }[section]; }
