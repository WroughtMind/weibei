import type { ComponentType } from "react";
import { createLibrary, defineComponent } from "@openuidev/react-lang";
import { z } from "zod/v4";
import type { LearningSceneProps, SceneDescriptor, SceneKey } from "./types";
import { MathLineScene, PhysicsForceScene, ChemEquilibriumScene, BiologyMeiosisScene } from "./scenes/stem-scenes";
import { TextArgumentScene, HistoryCausalityScene, GeographyMapScene, ArtObservationScene } from "./scenes/humanities-scenes";
import { StatisticsSamplingScene, FinanceCashflowScene, EconomicsPolicyScene, CodeSortScene } from "./scenes/data-scenes";

const sceneInputs: Array<Omit<SceneDescriptor, "component"> & { component: ComponentType<LearningSceneProps> }> = [
  {
    key: "math-line",
    group: "stem",
    subject: "数学",
    label: "两点决定直线",
    interaction: "拖两个点",
    componentName: "MathLineExplorer",
    prompt: "直接拖动 A、B 两点，观察变化率如何同时改变直线、斜率三角形、方程和取值表。",
    component: MathLineScene,
  },
  {
    key: "physics-force",
    group: "stem",
    subject: "物理",
    label: "受力与运动",
    interaction: "拖力矢量",
    componentName: "ForceMotionLab",
    prompt: "拖动合力箭头的端点，区分速度方向和加速度方向，并观察零合力时的惯性。",
    component: PhysicsForceScene,
  },
  {
    key: "chem-equilibrium",
    group: "stem",
    subject: "化学",
    label: "动态平衡",
    interaction: "投入扰动",
    componentName: "EquilibriumPerturbationLab",
    prompt: "把一种扰动投入反应池，看正逆反应速率先分离、再在新的条件下接近平衡。",
    component: ChemEquilibriumScene,
  },
  {
    key: "biology-meiosis",
    group: "stem",
    subject: "生物",
    label: "染色体分离",
    interaction: "编排阶段",
    componentName: "MeiosisComposer",
    prompt: "把染色体拖进正确的减数分裂阶段，观察等位基因如何进入配子并形成比例。",
    component: BiologyMeiosisScene,
  },
  {
    key: "text-argument",
    group: "humanities",
    subject: "文本",
    label: "论证剖面",
    interaction: "逐句点读",
    componentName: "ArgumentCloseReader",
    prompt: "点选原文句子，区分主张、理由、证据、反驳与回应，并始终保留回到原文的路径。",
    component: TextArgumentScene,
  },
  {
    key: "history-causality",
    group: "humanities",
    subject: "历史",
    label: "因果时间河",
    interaction: "聚焦路径",
    componentName: "CausalHistoryRiver",
    prompt: "选择历史节点，只保留它能支持的背景条件、直接推动与长期传导，避免把先后误当因果。",
    component: HistoryCausalityScene,
  },
  {
    key: "geography-map",
    group: "humanities",
    subject: "地理",
    label: "空间图层",
    interaction: "切层定位",
    componentName: "LayeredSpatialReader",
    prompt: "切换地形、洪泛区和运输路线，点选地点，理解位置、路线与尺度如何共同形成解释。",
    component: GeographyMapScene,
  },
  {
    key: "art-observation",
    group: "humanities",
    subject: "艺术",
    label: "图像观察镜",
    interaction: "移动观察镜",
    componentName: "ArtworkObservationLens",
    prompt: "拖动观察镜或点选编号，把构图、笔势、材质和拓片残损绑定到具体图像局部。",
    component: ArtObservationScene,
  },
  {
    key: "statistics-sampling",
    group: "society",
    subject: "统计",
    label: "抽样分布",
    interaction: "刷选样本窗",
    componentName: "SamplingBrushLab",
    prompt: "在总体分布上刷选不同样本窗，观察样本均值、中位数和异常值怎样随选择而摆动。",
    component: StatisticsSamplingScene,
  },
  {
    key: "finance-cashflow",
    group: "society",
    subject: "金融",
    label: "现金流传导",
    interaction: "编辑假设",
    componentName: "CashflowDependencyModel",
    prompt: "直接编辑增长、现金流率和折现率单元格，沿传导路径观察每期现金流、终值与估值。",
    component: FinanceCashflowScene,
  },
  {
    key: "economics-policy",
    group: "society",
    subject: "经济",
    label: "政策证据链",
    interaction: "追因果路径",
    componentName: "PolicyEvidenceTimeline",
    prompt: "选择政策事件，分开观察时间顺序、直接机制、滞后指标和证据不足的部分。",
    component: EconomicsPolicyScene,
  },
  {
    key: "code-sort",
    group: "society",
    subject: "代码",
    label: "算法执行轨道",
    interaction: "前后步进",
    componentName: "AlgorithmStateTrack",
    prompt: "逐步执行冒泡排序，让当前代码行、比较对象、数组状态、循环轮次与最终输出同时变化。",
    component: CodeSortScene,
  },
];

export const sceneDescriptors: SceneDescriptor[] = sceneInputs;

const openUIComponents = sceneDescriptors.map((descriptor) => {
  const Scene = descriptor.component;
  return defineComponent({
    name: descriptor.componentName,
    description: `${descriptor.subject}学习深组件。主互动：${descriptor.interaction}。组件内部保证知识对象与输出真实联动。`,
    props: z.object({
      title: z.string(),
      prompt: z.string(),
    }),
    component: ({ props: { title, prompt } }) => (
      <Scene
        title={title}
        prompt={prompt}
        onEvidence={(evidenceID) => {
          window.dispatchEvent(new CustomEvent("weibei:evidence", { detail: { evidenceID } }));
        }}
      />
    ),
  });
});

export const weiBeiLearningLibrary = createLibrary({ components: openUIComponents });

export function sceneResponse(descriptor: SceneDescriptor) {
  return `root = ${descriptor.componentName}(${JSON.stringify(descriptor.label)}, ${JSON.stringify(descriptor.prompt)})`;
}

export function sceneForKey(key: string | null) {
  return sceneDescriptors.find((scene) => scene.key === key) ?? sceneDescriptors[0];
}

export function isSceneKey(value: string): value is SceneKey {
  return sceneDescriptors.some((scene) => scene.key === value);
}
