import { useEffect, useMemo, useState } from "react";
import { Renderer } from "@openuidev/react-lang";
import type { OpenUIError } from "@openuidev/react-lang";
import { sceneDescriptors, sceneForKey, sceneResponse, weiBeiLearningLibrary } from "./catalog";
import type { SceneDescriptor, SubjectGroup } from "./types";

const groupLabels: Record<SubjectGroup, string> = {
  stem: "自然科学",
  humanities: "文史与图像",
  society: "数据与社会",
};

function readScene() {
  const scene = sceneForKey(new URLSearchParams(window.location.search).get("case"));
  if (!scene) throw new Error("旧版场景目录不能为空。");
  return scene;
}

function navigate(scene: SceneDescriptor) {
  const url = new URL(window.location.href);
  url.searchParams.set("case", scene.key);
  url.searchParams.set("legacy", "1");
  window.history.pushState({}, "", url);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

export function LegacyGallery() {
  const [activeScene, setActiveScene] = useState(readScene);
  const [activeGroup, setActiveGroup] = useState<SubjectGroup>(activeScene.group);
  const [evidenceNotice, setEvidenceNotice] = useState<string | null>(null);
  const [errors, setErrors] = useState<OpenUIError[]>([]);
  const response = useMemo(() => sceneResponse(activeScene), [activeScene]);
  const visibleScenes = sceneDescriptors.filter((scene) => scene.group === activeGroup);

  useEffect(() => {
    const onPopState = () => {
      const scene = readScene();
      setActiveScene(scene);
      setActiveGroup(scene.group);
    };
    const onEvidence = (event: Event) => {
      const detail = (event as CustomEvent<{ evidenceID: string }>).detail;
      setEvidenceNotice(detail.evidenceID);
      window.setTimeout(() => setEvidenceNotice(null), 2200);
    };
    window.addEventListener("popstate", onPopState);
    window.addEventListener("weibei:evidence", onEvidence);
    return () => {
      window.removeEventListener("popstate", onPopState);
      window.removeEventListener("weibei:evidence", onEvidence);
    };
  }, []);

  return (
    <main className="prototype-shell">
      <header className="prototype-toolbar">
        <div>
          <strong>旧版固定场景对照</strong>
          <span>仅保留取证，不再作为默认生成链路</span>
        </div>
        <div className="group-tabs" aria-label="学科分组">
          {(Object.keys(groupLabels) as SubjectGroup[]).map((group) => (
            <button
              key={group}
              type="button"
              className={activeGroup === group ? "is-active" : ""}
              onClick={() => {
                setActiveGroup(group);
                const first = sceneDescriptors.find((scene) => scene.group === group);
                if (first) navigate(first);
              }}
            >
              {groupLabels[group]}
            </button>
          ))}
        </div>
      </header>

      <nav className="scene-tabs" aria-label={`${groupLabels[activeGroup]}场景`}>
        {visibleScenes.map((scene) => (
          <button key={scene.key} type="button" className={activeScene.key === scene.key ? "is-active" : ""} onClick={() => navigate(scene)}>
            <span>{scene.subject}</span>
            <strong>{scene.label}</strong>
          </button>
        ))}
      </nav>

      <section className="agent-turn">
        <div className="agent-answer">
          <div className="agent-answer__meta">
            <strong>{activeScene.subject}</strong>
            <span>{activeScene.interaction}</span>
          </div>
          <div className="renderer-shell">
            <Renderer response={response} library={weiBeiLearningLibrary} isStreaming={false} onError={setErrors} />
          </div>
          {errors.length ? <p className="runtime-error">协议渲染失败：{errors.map((error) => error.message).join("；")}</p> : null}
        </div>
      </section>

      {evidenceNotice ? <div className="evidence-toast">已定位材料证据·{evidenceNotice}</div> : null}
    </main>
  );
}
