import { createHash } from "node:crypto";
import { open, readFile } from "node:fs/promises";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";
import {
  courseEvidenceLabel,
  courseHeading,
  courseJumpReference,
  coursePage,
  learningLocationJumpReference,
  searchCourse,
} from "./domains/course-navigation";
import { validateRichAnswerNarrativeFlow } from "./domains/rich-answer-narrative";
import {
  ALLOWED_TOOLS,
  AnswerFormPolicy,
  COMPUTE_ARTIFACT_TOOL,
  CONTEXT_TOOL,
  COURSE_MAP_TOOL,
  COURSE_SEARCH_TOOL,
  ContextToolDetails,
  CourseMapToolDetails,
  CourseSearchToolDetails,
  LEARNING_MEMORY_TOOL,
  LEARNING_UPDATE_TOOL,
  LIMITS,
  LearningMemoryKind,
  LearningMemoryToolDetails,
  LearningUpdateDetails,
  NOTE_PROPOSAL_TOOL,
  NoteProposalDetails,
  READ_TOOL,
  RICH_ANSWER_CATALOG_TOOL,
  RICH_ANSWER_SKILL_BY_PATH,
  RICH_ANSWER_TOOL,
  RichAnswerFaultError,
  RichAnswerToolDetails,
  SkillReadDetails,
  VISUAL_ASSET_TOOL,
  VisualAssetToolDetails,
  canonicalReadPath,
  contextRevisionFromDetails,
  currentTurnEvidenceMatches,
  evidenceLabels,
  readCurrentSnapshot,
  readCurrentVisualAssets,
  resolutionEvidenceMatches,
  rethrowRichAnswerFault,
  richAnswerAllowedAssetIDs,
  richAnswerFault,
  richAnswerFaultMessage,
  richAnswerSourceBindings,
  visualAssetMagicMatches,
} from "./domains/agent-context";
import {
  PYTHON_ARTIFACT_OPERATIONS,
  PYTHON_ARTIFACT_OUTPUT_KINDS,
  registerPythonArtifactTool,
} from "./domains/python-artifact";
import {
  COMPOSABLE_PRIMITIVE_CATALOG,
  OPENUI_ALWAYS_COMPONENTS,
  OPENUI_COMPONENT_CATALOG_SIZE,
  OPENUI_COMPONENT_GROUPS,
  OpenUIComponentName,
  RICH_ANSWER_ASSET_DEPENDENCIES,
  RICH_ANSWER_COMPUTE_NEEDS,
  RICH_ANSWER_COORDINATE_FRAMES,
  RICH_ANSWER_DATA_ORIGINS,
  RICH_ANSWER_FAMILY_CONTRACT,
  RICH_ANSWER_INTERACTION_ACTIONS,
  RICH_ANSWER_KNOWLEDGE_NATURES,
  RICH_ANSWER_KNOWLEDGE_SHAPES,
  RICH_ANSWER_LEARNING_ACTIONS,
  RICH_ANSWER_PRECISION_NEEDS,
  RICH_ANSWER_RENDERER_REGISTRATIONS,
  RICH_ANSWER_RENDERER_REGISTRATION_BY_ID,
  RICH_ANSWER_SPATIAL_DIMENSIONS,
  RICH_ANSWER_TEMPORAL_BEHAVIORS,
  matchingRichAnswerRendererRegistrations,
  openUIComponentCatalog,
  richAnswerEnvelopeSchema,
  richAnswerRendererCapabilityDeclarations,
  richAnswerRendererInteractionCoverage,
  richAnswerRendererNestedFieldContracts,
  richAnswerRendererRepresentationCoverage,
  selectedOpenUIComponentGroups,
} from "./domains/rich-answer-catalog";
import {
  canonicalRichAnswerEvidenceLabel,
  normalizeRichAnswerScene3DSpec,
  normalizedEvidenceText,
  richAnswerEvidenceText,
  validateRichAnswerProgram,
  validateRichAnswerRenderPlan,
  validateRichAnswerUI,
} from "./domains/rich-answer-validation";

export default function weibeiExtension(pi: ExtensionAPI) {
  let requiredContextRevision: string | undefined;
  let lastReadContextRevision: string | undefined;
  let lastReadMemoryRevision: number | undefined;
  let richAnswerAttemptCount = 0;
  let richAnswerCatalogRevision: string | undefined;
  let richAnswerCatalogSelection: Set<OpenUIComponentName> | undefined;
  let richAnswerCatalogRendererSelection: Set<string> | undefined;
  let activeAnswerFormPolicy: AnswerFormPolicy = "automatic";
  const searchedCourseItemIDs = new Set<string>();

  pi.registerTool({
    name: CONTEXT_TOOL,
    label: "读取魏碑上下文",
    description:
      "读取本轮受限的魏碑上下文快照。每轮必须先调用一次，并且只能依据返回的当前材料、笔记和选区回答。",
    promptSnippet: "读取当前魏碑材料、笔记、选区与上下文修订号",
    parameters: Type.Object({}, { additionalProperties: false }),
    executionMode: "sequential",
    async execute() {
      const snapshot = await readCurrentSnapshot();
      const visualAssets = await readCurrentVisualAssets(snapshot);
      requiredContextRevision = snapshot.contextRevision;
      lastReadContextRevision = snapshot.contextRevision;
      richAnswerCatalogRevision = undefined;
      richAnswerCatalogSelection = undefined;
      richAnswerCatalogRendererSelection = undefined;
      activeAnswerFormPolicy = snapshot.answerFormPolicy;

      const details: ContextToolDetails = {
        kind: "weibei_context",
        schemaVersion: 2,
        contextRevision: snapshot.contextRevision,
        snapshot,
      };

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                contextRevision: snapshot.contextRevision,
                richAnswerGrounding: richAnswerSourceBindings(snapshot),
                visualInspection: {
                  availableAssetIDs: [...visualAssets.keys()],
                  tool: VISUAL_ASSET_TOOL,
                },
                material: snapshot.material,
                note: snapshot.note,
                selection: snapshot.selection,
                recentMessages: snapshot.recentMessages,
                course: {
                  title: snapshot.course.title,
                  catalogCount: snapshot.course.catalog.length,
                  searchCandidateCount: snapshot.course.items.length,
                  relationCount: snapshot.course.relations.length,
                  isTruncated: snapshot.course.isTruncated,
                },
                learning: {
                  revision: snapshot.learning.memoryRevision,
                  hasLastLocation: snapshot.learning.lastLocation !== undefined,
                  memoryCount: snapshot.learning.memories.length,
                  session: snapshot.learning.session,
                },
              },
              null,
              2,
            ),
          },
        ],
        details,
      };
    },
  });

  pi.registerTool({
    name: VISUAL_ASSET_TOOL,
    label: "观察当前材料图像",
    description:
      "按当前材料 assetID 读取本轮受控图像像素。只有路线、区域、构图、比例、图中对象或空间位置确实依赖原图时调用；返回给模型的是当前材料图片，不暴露文件路径。",
    promptSnippet: "观察当前材料的真实图像像素，并记录哈希与大小",
    parameters: Type.Object(
      {
        assetID: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallID, params) {
      const current = await readCurrentSnapshot();
      if (lastReadContextRevision !== current.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      const visualAssets = await readCurrentVisualAssets(current);
      const asset = visualAssets.get(params.assetID);
      if (!asset) {
        throw new Error("该 assetID 不是本轮可观察的当前材料图像");
      }
      const file = await open(asset.filePath, "r");
      let data: Buffer;
      try {
        const beforeRead = await file.stat();
        if (!beforeRead.isFile() || beforeRead.size <= 0 || beforeRead.size > LIMITS.visualAssetBytes) {
          throw new Error(`当前材料图像必须是 1 到 ${LIMITS.visualAssetBytes} 字节的普通文件`);
        }
        data = await file.readFile();
        const afterRead = await file.stat();
        if (
          data.byteLength !== beforeRead.size ||
          data.byteLength > LIMITS.visualAssetBytes ||
          afterRead.size !== beforeRead.size ||
          afterRead.mtimeMs !== beforeRead.mtimeMs
        ) {
          throw new Error("当前材料图像在读取期间发生变化；请重新读取当前材料");
        }
      } finally {
        await file.close();
      }
      if (!visualAssetMagicMatches(data, asset.mediaType)) {
        throw new Error("当前材料图像的真实格式与声明不一致");
      }
      const sha256 = createHash("sha256").update(data).digest("hex");
      const details: VisualAssetToolDetails = {
        kind: "visual_asset_read",
        contextRevision: current.contextRevision,
        assetID: asset.id,
        mediaType: asset.mediaType,
        sha256,
        byteCount: data.byteLength,
      };
      return {
        content: [
          {
            type: "text",
            text: `已读取当前材料图像 ${asset.id}；请只依据可见像素和本轮来源判断，不能把近似观察说成精确测量。`,
          },
          {
            type: "image",
            mimeType: asset.mediaType,
            data: data.toString("base64"),
          },
        ],
        details,
      };
    },
  });

  pi.registerTool({
    name: COURSE_MAP_TOOL,
    label: "查看课程地图",
    description:
      "分页返回当前课程的材料、笔记、标签与长期关联。只有需要跨文件理解或导航时才调用。",
    promptSnippet: "查看课程里有哪些材料、笔记和已确认关联",
    parameters: Type.Object(
      {
        offset: Type.Optional(Type.Integer({ minimum: 0 })),
        limit: Type.Optional(
          Type.Integer({ minimum: 1, maximum: LIMITS.courseMapPageItems }),
        ),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const snapshot = await readCurrentSnapshot();
      if (lastReadContextRevision !== snapshot.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      const offset = params.offset ?? 0;
      const limit = params.limit ?? 40;
      const catalog = snapshot.course.catalog.slice(offset, offset + limit).map((item) => ({
        ...item,
        jumpReference: courseJumpReference(snapshot.course, item),
      }));
      const pageCatalogIDs = new Set(catalog.map((item) => item.id));
      const catalogByID = new Map(
        snapshot.course.catalog.map((item) => [item.id, item] as const),
      );
      const relations = snapshot.course.relations
        .filter(
          (relation) =>
            pageCatalogIDs.has(relation.noteItemID) ||
            pageCatalogIDs.has(relation.sourceItemID),
        )
        .map((relation) => ({
          ...relation,
          noteTitle: catalogByID.get(relation.noteItemID)!.title,
          sourceTitle: catalogByID.get(relation.sourceItemID)!.title,
        }));
      const total = snapshot.course.catalog.length;
      const page = {
        title: snapshot.course.title,
        offset,
        limit,
        total,
        hasMore: offset + catalog.length < total,
        catalog,
        relations,
        isTruncated: snapshot.course.isTruncated,
      };
      const details: CourseMapToolDetails = {
        kind: "course_map",
        contextRevision: snapshot.contextRevision,
        ...page,
      };
      return {
        content: [{ type: "text", text: JSON.stringify(page, null, 2) }],
        details,
      };
    },
  });

  pi.registerTool({
    name: COURSE_SEARCH_TOOL,
    label: "搜索课程关联",
    description:
      "在魏碑已建立的课程索引片段中搜索相关材料与笔记，返回可用于说明关联和跳转的精确标题。",
    promptSnippet: "按概念或学习问题搜索课程文件",
    parameters: Type.Object(
      {
        query: Type.String({ minLength: 1, maxLength: 500 }),
        limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 8 })),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const snapshot = await readCurrentSnapshot();
      if (lastReadContextRevision !== snapshot.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      const query = params.query.trim();
      const results = searchCourse(snapshot.course, query, params.limit ?? 5);
      results
        .filter((item) => item.searchText.trim().length > 0)
        .forEach((item) => searchedCourseItemIDs.add(item.id));
      const presentedResults = results.map((item) => {
        const hasEvidence = item.searchText.trim().length > 0;
        const sectionJumpReferences =
          hasEvidence && item.kind === "html"
            ? item.headings
                .slice(0, 5)
                .map((heading) => courseJumpReference(snapshot.course, item, heading))
            : [];
        const pageJumpReferences =
          hasEvidence && item.kind === "pdf"
            ? item.headings
                .filter((heading) => coursePage(heading) !== undefined)
                .slice(0, 5)
                .map((heading) => courseJumpReference(snapshot.course, item, heading))
            : [];
        return {
          ...item,
          headings: item.headings.map((heading) => courseHeading(heading).title),
          evidenceLabel: hasEvidence ? courseEvidenceLabel(snapshot.course, item) : undefined,
          jumpReference: hasEvidence ? courseJumpReference(snapshot.course, item) : undefined,
          sectionJumpReferences,
          pageJumpReferences,
        };
      });
      const evidenceLabels = presentedResults.flatMap((item) =>
        item.evidenceLabel ? [item.evidenceLabel] : [],
      );
      const jumpEvidence = Object.fromEntries(
        presentedResults.flatMap((item) => {
          if (!item.evidenceLabel || !item.jumpReference) return [];
          return [item.jumpReference, ...item.sectionJumpReferences, ...item.pageJumpReferences]
            .map((jumpReference) => [jumpReference, item.evidenceLabel] as const);
        }),
      );
      const jumpReferences = Object.keys(jumpEvidence);
      const details: CourseSearchToolDetails = {
        kind: "course_search",
        contextRevision: snapshot.contextRevision,
        query,
        results,
        evidenceLabels,
        jumpReferences,
        jumpEvidence,
      };
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              presentedResults,
              null,
              2,
            ),
          },
        ],
        details,
      };
    },
  });

  registerPythonArtifactTool(pi, {
    lastReadContextRevision: () => lastReadContextRevision,
    searchedCourseItemIDs,
  });

  pi.registerTool({
    name: RICH_ANSWER_CATALOG_TOOL,
    label: "选择生成式视觉能力",
    description:
      "在提交富回答前，根据本轮学习动作、知识形状、来源媒介、直接操作和呈现表面，检索相关的魏碑深组件、注册专业渲染器与通用原语提示。它返回相关子集，不返回固定场景或标准答案；问题变化时可以重新调用。",
    promptSnippet:
      "先描述学习动作和知识形状，取得相关深组件、专业渲染器和长尾原语提示；不要让完整目录挤进每次生成",
    parameters: Type.Object(
      {
        learningAction: Type.Union(
          RICH_ANSWER_LEARNING_ACTIONS.map((value) => Type.Literal(value)),
        ),
        knowledgeShapes: Type.Array(
          Type.Union(RICH_ANSWER_KNOWLEDGE_SHAPES.map((value) => Type.Literal(value))),
          { minItems: 1, maxItems: 3 },
        ),
        knowledgeNatures: Type.Array(
          Type.Union(RICH_ANSWER_KNOWLEDGE_NATURES.map((value) => Type.Literal(value))),
          { minItems: 1, maxItems: 4 },
        ),
        knowledgeObjects: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 1,
          maxItems: 6,
        }),
        knowledgeRelations: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 6,
        }),
        knowledgeProcesses: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 6,
        }),
        interactions: Type.Array(
          Type.Union(
            RICH_ANSWER_INTERACTION_ACTIONS.map((value) => Type.Literal(value)),
          ),
          { minItems: 1, maxItems: 3 },
        ),
        sourceMedium: Type.Union(
          ["text", "table", "code", "image", "map", "mixed"].map((value) => Type.Literal(value)),
        ),
        surface: Type.Union(
          ["inline", "expanded", "focus"].map((value) => Type.Literal(value)),
        ),
        representationNeeds: Type.Optional(Type.Object(
          {
            spatialDimension: Type.Union(
              RICH_ANSWER_SPATIAL_DIMENSIONS.map((value) => Type.Literal(value)),
            ),
            temporalBehavior: Type.Union(
              RICH_ANSWER_TEMPORAL_BEHAVIORS.map((value) => Type.Literal(value)),
            ),
            dataOrigin: Type.Union(
              RICH_ANSWER_DATA_ORIGINS.map((value) => Type.Literal(value)),
            ),
            coordinateFrame: Type.Union(
              RICH_ANSWER_COORDINATE_FRAMES.map((value) => Type.Literal(value)),
            ),
            computeNeed: Type.Union(
              RICH_ANSWER_COMPUTE_NEEDS.map((value) => Type.Literal(value)),
            ),
            precisionNeed: Type.Union(
              RICH_ANSWER_PRECISION_NEEDS.map((value) => Type.Literal(value)),
            ),
            assetDependency: Type.Union(
              RICH_ANSWER_ASSET_DEPENDENCIES.map((value) => Type.Literal(value)),
            ),
          },
          { additionalProperties: false },
        )),
        reason: Type.String({ minLength: 1, maxLength: 500 }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const current = await readCurrentSnapshot();
      if (lastReadContextRevision !== current.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      const currentAllowedAssetIDs = richAnswerAllowedAssetIDs(
        current,
        searchedCourseItemIDs,
      );
      const selectedGroups = selectedOpenUIComponentGroups(
        params.knowledgeShapes,
        params.interactions,
      );
      const matchingRenderers = matchingRichAnswerRendererRegistrations(
        params.knowledgeShapes,
        params.representationNeeds,
        params.sourceMedium,
        params.knowledgeNatures,
        params.knowledgeObjects,
        params.knowledgeRelations,
        params.knowledgeProcesses,
        currentAllowedAssetIDs.length > 0,
      );
      const representationMatchingRenderers = matchingRenderers.filter((registration) =>
        richAnswerRendererRepresentationCoverage(
          registration,
          params.representationNeeds,
        ).fullySupported
      );
      const fullyMatchingRenderers = representationMatchingRenderers.filter((registration) =>
        richAnswerRendererInteractionCoverage(registration, params.interactions).fullySupported
      );
      const routeRecommendation = {
        decisionOwner: "agent",
        professionalRendererCoverage: fullyMatchingRenderers.length > 0
          ? "complete"
          : representationMatchingRenderers.length > 0
            ? "partial-interaction"
            : matchingRenderers.length > 0
              ? "representation-mismatch"
              : "none",
        fullyCoveredRendererIDs: fullyMatchingRenderers.map((registration) => registration.id),
        partiallyCoveredRendererIDs: representationMatchingRenderers
          .filter((registration) => !fullyMatchingRenderers.includes(registration))
          .map((registration) => registration.id),
        mismatchedRendererIDs: matchingRenderers
          .filter((registration) => !representationMatchingRenderers.includes(registration))
          .map((registration) => registration.id),
        reason: "这里只说明注册专业渲染器的覆盖与缺口，不替 Agent 决定路线。Agent 需比较标准表达质量、独特联动、来源资产、精度、性能和学习价值后自主选择。",
      };
      const selectedComponents = new Set<OpenUIComponentName>(OPENUI_ALWAYS_COMPONENTS);
      selectedGroups.forEach((group) => {
        OPENUI_COMPONENT_GROUPS[group].components.forEach((component) => selectedComponents.add(component));
      });
      richAnswerCatalogRevision = current.contextRevision;
      richAnswerCatalogSelection = selectedComponents;
      richAnswerCatalogRendererSelection = new Set(
        RICH_ANSWER_RENDERER_REGISTRATIONS.map((registration) => registration.id),
      );

      const result = {
        contextRevision: current.contextRevision,
        decision: {
          learningAction: params.learningAction,
          knowledgeShapes: params.knowledgeShapes,
          knowledgeNatures: params.knowledgeNatures,
          knowledgeObjects: params.knowledgeObjects,
          knowledgeRelations: params.knowledgeRelations,
          knowledgeProcesses: params.knowledgeProcesses,
          interactions: params.interactions,
          sourceMedium: params.sourceMedium,
          surface: params.surface,
          representationNeeds: params.representationNeeds,
          reason: params.reason.trim(),
        },
        selectedGroups: selectedGroups.map((group) => ({
          id: group,
          label: OPENUI_COMPONENT_GROUPS[group].label,
        })),
        sourceBindings: richAnswerSourceBindings(current, searchedCourseItemIDs),
        controlledComputation: {
          tool: COMPUTE_ARTIFACT_TOOL,
          adapter: "bundled-fixed-python-worker",
          coverage: params.representationNeeds?.computeNeed === "heavyOrExternal"
            ? "partial-light-deterministic-only"
            : params.representationNeeds?.computeNeed === "lightDeterministic"
              ? "complete-for-allowlisted-operations"
              : "available-when-needed",
          operations: PYTHON_ARTIFACT_OPERATIONS,
          outputKinds: PYTHON_ARTIFACT_OUTPUT_KINDS,
          sourceEvidenceIDs:
            richAnswerSourceBindings(current, searchedCourseItemIDs).readableSourceLabels,
          rules: [
            "只执行固定统计、线性回归、分箱和受限函数采样；不执行模型代码。",
            "无网络、无任意文件访问、无 shell；每次返回长度、哈希、来源和耗时。",
            "产物只提供数据/规格，再由 Agent 选择本轮目录返回的专业 renderer、成熟深组件或长尾组合。",
          ],
        },
        actionBus: {
          learningActions: RICH_ANSWER_LEARNING_ACTIONS,
          interactions: RICH_ANSWER_INTERACTION_ACTIONS,
          rule: "交互只能落到 program 状态、renderPlan interactionBindings 或 ui binding；不得提交 HTML/JS 回调、外部事件或自造 action 类型。",
        },
        routeRecommendation,
        candidateComparison: {
          notRanked: true,
          routes: [
          {
            route: "renderPlan",
            candidates: representationMatchingRenderers.map((registration) => registration.id),
            fullyCovered: fullyMatchingRenderers.map((registration) => registration.id),
            reason: "成熟专业渲染器提供标准表达、统一主题、精度和性能边界；是否采用取决于本题学习价值。",
          },
          {
            route: "program",
            candidates: selectedGroups,
            reason: "保留成熟深组件；当它提供专业渲染器没有的刷选、实验联动、证据阅读或领域机制时，可以成为更优选择。",
          },
          {
            route: "ui",
            candidates: ["restricted-composable-ui"],
            reason: "仅用于前两条都不贴合的真正长尾组合，不用于低级重画标准图表、函数、几何、地图、图像或三维。",
          },
          {
            route: "text",
            candidates: ["source-grounded-text"],
            reason: "可视化没有明确学习增益、能力不足或来源不够时保持正常文本。",
          },
          ],
          rule: "这些是对称候选，不是固定排名；不能按题号或路线标签强迫选择。",
        },
        planningLoop: {
          steps: [
            "判断纯文本是否已经足够；足够则停止，不为装饰生成 UI。",
            "写清用户要看懂的判断、要观察的对象/关系/过程、初始状态、操作后变化和证据。",
            "先声明维度、动态性、数据来源、坐标系、计算、精度和原图依赖，再按知识形状匹配注册专业渲染器并检查交互覆盖。",
            "只有前两者都不贴合且形态本身确属长尾时，才组合 ui；能力不足则保留正文并诚实表达边界。",
            "生成正文与内联体验交错的结果；局部 UI 不重复整篇回答。",
            "提交前核对初始状态可读、操作真实改变目标状态、文案与计算一致、窄宽仍完整。",
          ],
          completionQuestions: [
            "去掉体验块，用户是否会明显更难理解？",
            "初始状态是否已经显示与学习目标有关的对象或差异？",
            "主要操作是否改变了对应图形、读数或知识状态？",
            "局部标题、说明、选区和读数是否与运行时实际状态一致？",
            "缩窄到对话栏后，它是否仍像回答的一部分而不是独立网页？",
          ],
        },
        expressionPriority: [
          "对称比较注册专业渲染器与成熟深组件：前者强调标准表达、精度与性能，后者可能提供不可替代的刷选、实验联动、状态机制或证据阅读。",
          "requestedRepresentationCoverage 核对维度、动态性、数据来源、坐标系、计算、精度和原图依赖；requestedInteractionCoverage 核对交互，但两者都不替 Agent 作最终选择。",
          "标准图表、函数、几何、物理仿真、地图、图像叠层和三维并不因为当前适配器缺少某个互动就自动变成长尾；不要用 ui 的点线、形状和标签重画成熟形态。",
          "最后才看通用原语：只有专业渲染器和成熟深组件都不贴合、且知识形态本身确属长尾组合时才用 ui；否则保留正文并诚实说明当前表达边界。",
        ],
        renderPlan: {
          useWhen:
            "本轮 matchingRenderers 非空时，把它作为与成熟 program 对称比较的候选；完整覆盖不等于强制采用，部分覆盖也不等于必须放弃。提交时 interactionBindings.kind 必须来自对应 renderer 的 interactionBindingKinds，不能把 learning interaction 名称直接当作 binding kind。",
          matchingRenderers: richAnswerRendererCapabilityDeclarations(
            params.knowledgeShapes,
            params.interactions,
            params.representationNeeds,
            params.sourceMedium,
            params.knowledgeNatures,
            params.knowledgeObjects,
            params.knowledgeRelations,
            params.knowledgeProcesses,
            currentAllowedAssetIDs,
          ),
          rendererIndex: RICH_ANSWER_RENDERER_REGISTRATIONS.map((registration) => ({
            id: registration.id,
            label: registration.label,
            specVersion: registration.specVersion,
            knowledgeShapes: registration.knowledgeShapes,
            interactionActions: registration.interactionActions,
            assetDependencies: registration.representationSupport.assetDependencies,
          })),
          sceneContract:
            "scene 三选一时只保留 renderPlan，不同时提交 program 或 ui。renderer/specVersion 必须来自 rendererIndex；matchingRenderers 提供当前请求的详细规格。若目标能力只出现在 rendererIndex，应按真实语义重新调用目录取得详细规格，不要猜 schema。",
        },
        program: {
          catalogSize: OPENUI_COMPONENT_CATALOG_SIZE,
          allowedComponentCount: selectedComponents.size,
          signatures: openUIComponentCatalog(Array.from(selectedComponents)),
          syntaxRules: [
            "每行只声明一个状态或组件；先声明子组件，再由父组件引用。",
            "组件引用数组写 [step1, step2]，引用 id 不加引号；不要在参数中嵌套组件调用。",
            "枚举参数只能写签名或指导中列出的固定值；FunctionPlot.family 当前只能写 \"quadratic\"，不是公式输入框。",
          ],
        },
        ui: {
          useWhen: "返回的深组件与注册专业渲染器都无法诚实表达、且当前知识形态本身确属长尾组合时，才组合通用原语；适配器暂缺、互动未覆盖或想做得更花哨都不是把标准图表、函数、几何、物理、地图、图像叠层、三维硬拆成低级点线树的理由。",
          guidance: COMPOSABLE_PRIMITIVE_CATALOG.split("\n"),
          intentGuidance: [
            "不要按 knowledgeNatures 机械套固定 role 组合；曲线、点、区域、图像、形状、序列、读数都只是可组合的视觉语法。",
            "line/path/point/metric 可以在函数、过程、机制、论证或证据场景中成为主表达，前提是它们真实编码了知识对象、关系或状态，而不是装饰线。",
            "非过程题不要只用 sequence、metric、text、label、grid 变换排版；数量、空间、机制、证据、图像、比较和计算题要让可绑定控件驱动非文字图元或空间编码出现可检查状态变化。",
            "只有当材料和问题确实依赖空间位置、图像局部或对象外形时，才需要选择 image、region、shape、area 等对应图元；不要为通过形式检查而硬凑。",
            "有控件时，控件必须改变与学习目标绑定的可见图元或读数；可以同时协调多个控件、图层和状态。",
            "用户或材料明确指定的观察动作、测量方法和结论边界必须进入可见节点语义；不要只写在 expressionPlan，也不要用不相干的通用控件替代。",
            "knowledgeObjects 要在可见标签里留下关键锨点；knowledgeRelations 可由有标注的曲线、数据、读数或序列结构编码；knowledgeProcesses 若是拖动、切换、观察等互动，可由真实 binding 结构兑现，不必把计划长句逐字复制进 UI。",
            "visualPrimitives 必须列出实际会使用的 ui role，后续 weibei_rich_answer 会校验声明与 UI 节点一致。",
          ],
        },
        guardrails: [
          "返回的是相关能力子集和签名，不是固定模板、场景数量上限或标准答案。",
          "program 只能使用本次返回的签名；renderPlan 只能使用本次返回的 renderer/specVersion；需要另一类能力时重新调用目录。",
          "ui 必须从 rootID 开始形成单父节点树；孤立节点、只在不可达 dataset 里放证据、控件不驱动图元或读数都会被拒绝。",
          "不要引入 Card、Tabs、KPI、Slide、Gallery 这类整页看板组件；要把视觉、控件和读数作为回答流里的内联体验块。",
          "先核对结论、公式、单位、数值、方向和因果边界；不能验证的结果不得交给界面假装计算。",
          "无论 program、renderPlan 或 ui，最终内容、单位、关系与来源都必须由本轮真实材料支撑。",
        ],
      };
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {
          kind: "rich_answer_catalog",
          contextRevision: current.contextRevision,
          selectedGroups,
          allowedComponents: Array.from(selectedComponents),
          allowedRenderers: representationMatchingRenderers.map((registration) => ({
            id: registration.id,
            specVersion: registration.specVersion,
          })),
        },
      };
    },
  });

  pi.registerTool({
    name: RICH_ANSWER_TOOL,
    label: "插入生成式视觉体验",
    description:
      `当可视化或直接操作能明显帮助理解时，在 Agent 回答流中插入受控的生成式视觉体验块。提交前必须先调用 ${RICH_ANSWER_CATALOG_TOOL}；program 只能使用本轮目录返回的签名，renderPlan 只能使用本轮目录返回的注册渲染器，ui 使用受控通用原语。它不是第二篇回答或完整网页。${RICH_ANSWER_FAMILY_CONTRACT}`,
    promptSnippet:
      "先判断文本是否足够；需要时在 program、renderPlan、ui 三条出口里选最贴合的一条，不要画 SVG、套完整网页外壳或从头复述正文",
    parameters: richAnswerEnvelopeSchema,
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      richAnswerAttemptCount += 1;
      const remainingAttempts = Math.max(0, 3 - richAnswerAttemptCount);
      if (richAnswerAttemptCount > 3) {
        throw new Error(richAnswerFaultMessage({
          code: "attempts_exhausted",
          jsonPath: "$",
          message: "本轮富回答最多提交三次；坏 payload 不会被渲染。",
          humanFixHint: "停止调用 weibei_rich_answer，用普通文本诚实降级；正文只回答用户问题和真实限制，不要提富回答校验、协议失败、repair_fault、payload 或内部工具错误。",
        }, 0));
      }
      try {
        const current = await readCurrentSnapshot();
        if (lastReadContextRevision !== current.contextRevision) {
          richAnswerFault({
            code: "context_required",
            jsonPath: "$.contextRevision",
            field: "contextRevision",
            message: `必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`,
            humanFixHint: `先调用 ${CONTEXT_TOOL}，再基于返回的 contextRevision 重新提交完整 RichAnswerUI。`,
          });
        }
        if (params.contextRevision !== current.contextRevision) {
          richAnswerFault({
            code: "stale_context",
            jsonPath: "$.contextRevision",
            field: "contextRevision",
            message: "富回答的 contextRevision 与当前上下文不匹配",
            humanFixHint: "丢弃旧 payload，重新读取上下文并用当前 contextRevision 重发完整 RichAnswerUI。",
          });
        }
        if (
          richAnswerCatalogRevision !== current.contextRevision ||
          richAnswerCatalogSelection === undefined ||
          richAnswerCatalogRendererSelection === undefined
        ) {
          richAnswerFault({
            code: "catalog_required",
            jsonPath: "$.scenes",
            field: "scenes",
            message: `提交富回答前必须先调用 ${RICH_ANSWER_CATALOG_TOOL} 取得本轮相关能力子集`,
            humanFixHint: `先调用 ${RICH_ANSWER_CATALOG_TOOL} 取得本轮 program/renderPlan/ui 能力，再重发完整 RichAnswerUI。`,
          });
        }

      const sceneIDs = params.scenes.map((scene) => scene.id);
      if (new Set(sceneIDs).size !== sceneIDs.length) {
        richAnswerFault({
          code: "duplicate_id",
          jsonPath: "$.scenes[*].id",
          field: "id",
          message: "富回答场景 id 必须唯一",
          humanFixHint: "为每个 scene 重新分配唯一 id，并同步 narrative 中所有场景标记后完整重发。",
        });
      }
      let plainNarrative = "";
      try {
        plainNarrative = validateRichAnswerNarrativeFlow(params.narrative, sceneIDs);
      } catch (error) {
        richAnswerFault({
          code: "narrative_flow",
          jsonPath: "$.narrative",
          field: "narrative",
          message: error instanceof Error ? error.message : String(error),
          humanFixHint: "修正正文中的来源标签或场景标记；若不需要指定插入点，可省略标记让未引用场景顺延到正文末尾，然后完整重发 RichAnswerUI。",
        });
      }
      const evidenceIDs: string[] = params.evidenceLedger.map((entry) => entry.id);
      if (new Set(evidenceIDs).size !== evidenceIDs.length) {
        richAnswerFault({
          code: "duplicate_id",
          jsonPath: "$.evidenceLedger[*].id",
          field: "id",
          message: "富回答证据 id 必须唯一",
          humanFixHint: "为 evidenceLedger 去重并同步 scene.evidenceIDs、program 证据组件、renderPlan sourceBindings 或 ui evidenceIDs 后完整重发。",
        });
      }

      const allowedAssetIDs = new Set<string>(
        richAnswerAllowedAssetIDs(current, searchedCourseItemIDs),
      );
      const evidenceTextByLabel = richAnswerEvidenceText(current, searchedCourseItemIDs);
      const normalizedEvidenceLedger = params.evidenceLedger.map((entry) => {
        const sourceLabel = canonicalRichAnswerEvidenceLabel(
          entry.sourceLabel,
          evidenceTextByLabel.keys(),
        );
        const source = sourceLabel ? evidenceTextByLabel.get(sourceLabel) : undefined;
        if (!source || !sourceLabel) {
          richAnswerFault({
            code: "source_not_available",
            jsonPath: "$.evidenceLedger[*].sourceLabel",
            field: "sourceLabel",
            message: `富回答引用了本轮未读取或无法唯一对应的来源：${entry.sourceLabel}；可用标签：${Array.from(evidenceTextByLabel.keys()).join("、")}`,
            humanFixHint: "只使用本轮 context 或 course_search 返回的真实来源标签，修正 evidenceLedger 后完整重发。",
          });
        }
        const excerpt = normalizedEvidenceText(entry.excerpt);
        if (!excerpt || !normalizedEvidenceText(source.text).includes(excerpt)) {
          richAnswerFault({
            code: "excerpt_mismatch",
            jsonPath: "$.evidenceLedger[*].excerpt",
            field: "excerpt",
            message: `富回答证据摘录不在对应来源中：${sourceLabel}`,
            humanFixHint: "从该来源已读取文本中逐字截取短摘录，并同步相关 scene 证据绑定后完整重发。",
          });
        }
        if ((entry.assetIDs ?? []).some((assetID) => !allowedAssetIDs.has(assetID))) {
          richAnswerFault({
            code: "unauthorized_asset",
            jsonPath: "$.evidenceLedger[*].assetIDs",
            field: "assetIDs",
            message: `富回答证据引用了本轮未开放的本地资源：${sourceLabel}`,
            humanFixHint: "只使用当前材料或本轮搜索开放的 item.id 作为资源，修正 evidenceLedger 后完整重发。",
          });
        }
        return { ...entry, sourceLabel, isTruncated: source.isTruncated, tags: [] };
      });
      const missingNarrativeSources = Array.from(
        new Set<string>(normalizedEvidenceLedger.map((entry) => entry.sourceLabel)),
      ).filter((sourceLabel) => !plainNarrative.includes(sourceLabel));
      if (missingNarrativeSources.length > 0) {
        richAnswerFault({
          code: "missing_evidence",
          jsonPath: "$.narrative",
          field: "narrative",
          message: `富回答 narrative 没有就近标注已使用的真实来源：${missingNarrativeSources.join("、")}`,
          humanFixHint: "在正文相关结论旁加入对应来源标签，并完整重发 RichAnswerUI。",
        });
      }

      const allowedEvidenceIDs = new Set<string>(evidenceIDs);
      let operationCount = 0;
      const renderPlanNormalizations: string[] = [];
      for (const [sceneIndex, scene] of params.scenes.entries()) {
        const scenePath = `$.scenes[${sceneIndex}]`;
        const sceneLayerCount = [
          scene.program,
          scene.renderPlan,
          scene.ui,
        ].filter((layer) => layer !== undefined).length;
        if (sceneLayerCount !== 1) {
          richAnswerFault({
            code: "scene_layer_choice",
            jsonPath: scenePath,
            sceneID: scene.id,
            field: "program/renderPlan/ui",
            message: `富回答场景 ${scene.id} 必须且只能提交 program、renderPlan、ui 之一`,
            humanFixHint: "深组件只保留 program；专业渲染器只保留 renderPlan；通用原语只保留 ui。删除其他出口后完整重发 RichAnswerUI。",
          });
        }
        renderPlanNormalizations.push(
          ...normalizeRichAnswerScene3DSpec(scene).map((message) => `${scene.id}: ${message}`),
        );
        const objects = scene.objects ?? [];
        const objectIDs = objects.map((object) => object.id);
        const relationIDs = (scene.relations ?? []).map((relation) => relation.id);
        const operationIDs = (scene.operations ?? []).map((operation) => operation.id);
        const frameIDs = (scene.frames ?? []).map((frame) => frame.id);
        const localIDs = [...objectIDs, ...relationIDs, ...operationIDs, ...frameIDs];
        if (new Set(localIDs).size !== localIDs.length) {
          richAnswerFault({
            code: "duplicate_id",
            jsonPath: `${scenePath}.id`,
            sceneID: scene.id,
            field: "id",
            message: `富回答场景 ${scene.id} 内的所有 id 必须唯一`,
            humanFixHint: "为本 scene 内对象、关系、操作、坐标框重新分配唯一 id，并同步引用后完整重发。",
          });
        }
        const knownObjects = new Set(objectIDs);
        const knownFrames = new Set(frameIDs);
        const referableIDs = new Set([...objectIDs, ...relationIDs, ...frameIDs]);
        if (
          (scene.relations ?? []).some(
            (relation) =>
              !knownObjects.has(relation.sourceID) || !knownObjects.has(relation.targetID),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.relations`,
            sceneID: scene.id,
            field: "relations",
            message: `富回答场景 ${scene.id} 存在悬空关系`,
            humanFixHint: "让每个 relation.sourceID/targetID 指向本 scene 内真实 object.id，或删除该关系后完整重发。",
          });
        }
        if (
          (scene.operations ?? []).some((operation) =>
            operation.targetIDs.some((targetID) => !referableIDs.has(targetID)) ||
            (operation.frameID !== undefined && !knownFrames.has(operation.frameID)),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.operations`,
            sceneID: scene.id,
            field: "operations",
            message: `富回答场景 ${scene.id} 存在悬空操作目标`,
            humanFixHint: "让 operation.targetIDs/frameID 指向本 scene 内真实对象、关系或坐标框后完整重发。",
          });
        }
        if (
          (scene.frames ?? []).some((frame) =>
            (frame.objectIDs ?? []).some((objectID) => !knownObjects.has(objectID)),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.frames`,
            sceneID: scene.id,
            field: "frames",
            message: `富回答场景 ${scene.id} 存在悬空坐标框对象`,
            humanFixHint: "让 frame.objectIDs 只引用本 scene 内真实 object.id，或删除悬空对象后完整重发。",
          });
        }
        if (
          objects.some(
            (object) =>
              (object.frameID !== undefined && !knownFrames.has(object.frameID)) ||
              ((object.coordinate !== undefined || object.bounds !== undefined) &&
                object.frameID === undefined),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.objects`,
            sceneID: scene.id,
            field: "frameID",
            message: `富回答场景 ${scene.id} 存在缺失坐标框的对象`,
            humanFixHint: "凡是声明 coordinate/bounds 的对象都必须填写有效 frameID；修正对象引用后完整重发。",
          });
        }
        if (
          (scene.frames ?? []).some(
            (frame) =>
              (frame.xAxis !== undefined && frame.xAxis.maximum <= frame.xAxis.minimum) ||
              (frame.yAxis !== undefined && frame.yAxis.maximum <= frame.yAxis.minimum),
          )
        ) {
          richAnswerFault({
            code: "invalid_frame",
            jsonPath: `${scenePath}.frames`,
            sceneID: scene.id,
            field: "xAxis/yAxis",
            message: `富回答场景 ${scene.id} 的坐标范围无效`,
            humanFixHint: "确保每个坐标轴 maximum 大于 minimum，单位和方向符合材料后完整重发。",
          });
        }
        if (
          (scene.frames ?? []).some(
            (frame) => frame.kind === "cartesian" &&
              (frame.xAxis === undefined || frame.yAxis === undefined),
          )
        ) {
          richAnswerFault({
            code: "invalid_frame",
            jsonPath: `${scenePath}.frames`,
            sceneID: scene.id,
            field: "xAxis/yAxis",
            message: `富回答场景 ${scene.id} 的笛卡尔坐标框缺少横轴或纵轴`,
            humanFixHint: "cartesian frame 必须同时提供有效 xAxis 与 yAxis；补齐后完整重发。",
          });
        }
        if (
          (scene.operations ?? []).some((operation) => {
            const parameter = operation.parameter;
            return parameter !== undefined &&
              (parameter.maximum <= parameter.minimum ||
                parameter.initialValue < parameter.minimum ||
                parameter.initialValue > parameter.maximum);
          })
        ) {
          richAnswerFault({
            code: "invalid_binding",
            jsonPath: `${scenePath}.operations`,
            sceneID: scene.id,
            field: "parameter",
            message: `富回答场景 ${scene.id} 的可调参数范围无效`,
            humanFixHint: "让 minimum < maximum、initialValue 落在范围内、step 大于 0，并完整重发。",
          });
        }
        if (
          objects.some(
            (object) => object.assetID !== undefined && !allowedAssetIDs.has(object.assetID),
          ) ||
          (scene.frames ?? []).some(
            (frame) => frame.assetID !== undefined && !allowedAssetIDs.has(frame.assetID),
          )
        ) {
          richAnswerFault({
            code: "unauthorized_asset",
            jsonPath: scenePath,
            sceneID: scene.id,
            field: "assetID",
            message: `富回答场景 ${scene.id} 引用了本轮未开放的本地资源`,
            humanFixHint: "只引用当前材料或本轮搜索开放的 item.id，并在 evidenceLedger.assetIDs 中同步声明后完整重发。",
          });
        }
        if (
          objects.some(
            (object) =>
              object.bounds !== undefined &&
              (object.bounds.x + object.bounds.width > 1 ||
                object.bounds.y + object.bounds.height > 1),
          )
        ) {
          richAnswerFault({
            code: "invalid_frame",
            jsonPath: `${scenePath}.objects`,
            sceneID: scene.id,
            field: "bounds",
            message: `富回答场景 ${scene.id} 的图像区域超出归一化边界`,
            humanFixHint: "把 x/y/width/height 约束在 0–1 且不越界，确认区域含义后完整重发。",
          });
        }
        const referencedEvidenceIDs = [
          ...scene.evidenceIDs,
          ...objects.flatMap((object) => object.evidenceIDs ?? []),
          ...(scene.relations ?? []).flatMap((relation) => relation.evidenceIDs ?? []),
          ...(scene.frames ?? []).flatMap((frame) => frame.evidenceIDs ?? []),
          ...(scene.renderPlan?.sourceBindings ?? []).map((binding) => binding.evidenceID),
        ].filter((evidenceID): evidenceID is string => evidenceID !== undefined);
        if (referencedEvidenceIDs.some((evidenceID) => !allowedEvidenceIDs.has(evidenceID))) {
          richAnswerFault({
            code: "missing_evidence",
            jsonPath: `${scenePath}.evidenceIDs`,
            sceneID: scene.id,
            field: "evidenceIDs",
            message: `富回答场景 ${scene.id} 引用了不存在的证据`,
            humanFixHint: "让 scene、renderPlan sourceBindings、program 证据组件或 ui 可达节点/数据行只引用 evidenceLedger 中已有 id，并把证据真实绑定后完整重发。",
          });
        }
        try {
          operationCount += scene.program !== undefined
            ? validateRichAnswerProgram(scene, richAnswerCatalogSelection)
            : scene.renderPlan !== undefined
              ? validateRichAnswerRenderPlan(
                scene,
                allowedEvidenceIDs,
                allowedAssetIDs,
                richAnswerCatalogRendererSelection,
              )
              : validateRichAnswerUI(scene, allowedEvidenceIDs, allowedAssetIDs);
        } catch (error) {
          if (error instanceof RichAnswerFaultError) throw error;
          const sceneLayer = scene.program !== undefined
            ? "program"
            : scene.renderPlan !== undefined
              ? "renderPlan"
              : "ui";
          richAnswerFault({
            code: scene.program !== undefined
              ? "invalid_openui_program"
              : scene.renderPlan !== undefined
                ? "invalid_render_plan"
                : "invalid_t2_ui",
            jsonPath: `${scenePath}.${sceneLayer}`,
            sceneID: scene.id,
            field: sceneLayer,
            message: error instanceof Error ? error.message : String(error),
            humanFixHint: scene.program !== undefined
              ? "按行列诊断修正 program；不要局部 patch，必须带完整 envelope、完整 scenes 和 evidenceLedger 重发。"
              : scene.renderPlan !== undefined
                ? (() => {
                    const registration = RICH_ANSWER_RENDERER_REGISTRATION_BY_ID.get(
                      scene.renderPlan.renderer,
                    );
                    if (!registration) {
                      return "按注册 renderer、specVersion、高层 spec、interactionBindings、sourceBindings、fallback 和 qualityBudget 诊断修正 renderPlan；不要改成 raw option、脚本、HTML 或 SVG path。";
                    }
                    return [
                      `若当前 renderer ${registration.id}@${registration.specVersion} 仍与本题知识对象和学习动作匹配，就按目录字段形状修正高层规格；若错误暴露的是路线不匹配，返回本轮目录重新对称比较 renderer、program 与 ui，不要机械保留当前路线，也不要直接退回低级通用点线。`,
                      registration.specGuidance,
                      `字段形状：${JSON.stringify({
                        minimalSpecSkeleton: registration.minimalSpecSkeleton,
                        nestedFieldContracts: richAnswerRendererNestedFieldContracts(registration),
                      })}`,
                      "仍需完整重发 envelope、scenes 与 evidenceLedger；禁止 raw option、脚本、HTML 或 SVG path。",
                    ].join(" ");
                  })()
                : "按 UI 节点、数据集、binding 和证据诊断修正 ui 原语树；不要局部 patch，必须完整重发。",
          });
        }
      }

      const details: RichAnswerToolDetails = {
        kind: "rich_answer",
        contextRevision: current.contextRevision,
        normalizations: renderPlanNormalizations,
        envelope: {
          ...params,
          expressionPlan: {
            ...params.expressionPlan,
            directManipulation: operationCount > 0,
          },
          evidenceLedger: normalizedEvidenceLedger,
        },
      };
      return {
        content: [
          {
            type: "text",
            text: "完整 narrative 与生成式视觉体验已通过魏碑的来源、内联位置、program/renderPlan/ui、状态、预算和资源边界校验，并会作为同一篇回答显示。请勿另写或改写第二份正文，只需简短结束本轮。",
          },
        ],
        details,
      };
      } catch (error) {
        rethrowRichAnswerFault(error, remainingAttempts);
      }
    },
  });

  pi.registerTool({
    name: LEARNING_MEMORY_TOOL,
    label: "读取学习记忆",
    description:
      "读取用户上次学到的位置、当前会话摘要、学习目标、理解、困惑和下一步。记忆不是课程事实证据。",
    promptSnippet: "读取用户学习历史与当前会话状态",
    parameters: Type.Object({}, { additionalProperties: false }),
    executionMode: "sequential",
    async execute() {
      const snapshot = await readCurrentSnapshot();
      if (lastReadContextRevision !== snapshot.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      lastReadMemoryRevision = snapshot.learning.memoryRevision;
      const locationJumpReference = learningLocationJumpReference(snapshot);
      const jumpReferences = locationJumpReference ? [locationJumpReference] : [];
      const jumpEvidence = locationJumpReference
        ? { [locationJumpReference]: "[学习记录：上次位置]" }
        : {};
      const details: LearningMemoryToolDetails = {
        kind: "learning_memory",
        contextRevision: snapshot.contextRevision,
        memoryRevision: snapshot.learning.memoryRevision,
        learning: snapshot.learning,
        jumpReferences,
        jumpEvidence,
      };
      const learningForTool = locationJumpReference && snapshot.learning.lastLocation
        ? {
            ...snapshot.learning,
            lastLocation: {
              ...snapshot.learning.lastLocation,
              jumpReference: locationJumpReference,
            },
          }
        : snapshot.learning;
      return {
        content: [{ type: "text", text: JSON.stringify(learningForTool, null, 2) }],
        details,
      };
    },
  });

  pi.registerTool({
    name: LEARNING_UPDATE_TOOL,
    label: "提出学习状态更新",
    description:
      "向魏碑提交带依据的学习记忆和会话状态建议。它不能修改材料或笔记。",
    promptSnippet: "仅在出现可长期复用的目标、理解、困惑或下一步时提交更新",
    parameters: Type.Object(
      {
        contextRevision: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
        memoryRevision: Type.Integer({ minimum: 0 }),
        sessionSummary: Type.Optional(
          Type.String({ minLength: 1, maxLength: LIMITS.sessionSummary }),
        ),
        suggestedPhase: Type.Optional(
          Type.Union(
            ["orient", "explore", "closeRead", "note", "recall", "consolidate", "plan"].map(
              (value) => Type.Literal(value),
            ),
          ),
        ),
        suggestedNext: Type.Array(Type.String({ minLength: 1, maxLength: 300 }), {
          maxItems: 3,
        }),
        entries: Type.Array(
          Type.Object(
            {
              kind: Type.Union(
                ["goal", "understood", "confusion", "nextStep", "preference"].map((value) =>
                  Type.Literal(value),
                ),
              ),
              text: Type.String({ minLength: 1, maxLength: LIMITS.learningText }),
              evidence: Type.String({ minLength: 1, maxLength: LIMITS.learningEvidence }),
              origin: Type.Union([Type.Literal("userStatement"), Type.Literal("agentInference")]),
            },
            { additionalProperties: false },
          ),
          { maxItems: 12 },
        ),
        resolutions: Type.Optional(
          Type.Array(
            Type.Object(
              {
                memoryID: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
                evidence: Type.String({ minLength: 1, maxLength: LIMITS.learningEvidence }),
              },
              { additionalProperties: false },
            ),
            { maxItems: 12 },
          ),
        ),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const current = await readCurrentSnapshot();
      if (
        lastReadContextRevision !== current.contextRevision ||
        lastReadMemoryRevision !== current.learning.memoryRevision
      ) {
        throw new Error(
          `学习状态已变化；请重新调用 ${CONTEXT_TOOL} 和 ${LEARNING_MEMORY_TOOL}`,
        );
      }
      if (
        params.contextRevision !== current.contextRevision ||
        params.memoryRevision !== current.learning.memoryRevision
      ) {
        throw new Error("学习状态建议的上下文或记忆修订号不匹配");
      }
      const entries = params.entries.map((entry) => ({
        kind: entry.kind as LearningMemoryKind,
        text: entry.text.trim(),
        evidence: entry.evidence.trim(),
        origin: entry.origin as "userStatement" | "agentInference",
      }));
      const allowedEvidencePrefixes = [
        "[用户：本轮]",
        "[会话：当前]",
        ...evidenceLabels(current),
        ...current.course.catalog
          .filter((item) => searchedCourseItemIDs.has(item.id))
          .map((item) => courseEvidenceLabel(current.course, item)),
      ];
      if (
        entries.some(
          (entry) =>
            !entry.text ||
            !entry.evidence ||
            !allowedEvidencePrefixes.some((prefix) => entry.evidence.startsWith(prefix)),
        )
      ) {
        throw new Error("每条学习记忆都必须携带当前用户、会话或来源依据标签");
      }
      if (
        entries.some(
          (entry) =>
            (entry.evidence.startsWith("[用户：本轮]") ||
              entry.evidence.startsWith("[会话：当前]")) &&
            !currentTurnEvidenceMatches(current, entry.evidence),
        )
      ) {
        throw new Error("本轮用户或会话依据必须在标签后逐字引用用户本轮真实原话");
      }
      if (
        entries.some(
          (entry) =>
            entry.origin === "userStatement" && !entry.evidence.startsWith("[用户：本轮]"),
        )
      ) {
        throw new Error("用户陈述型记忆必须直接依据本轮用户原话");
      }
      const suggestedNext = params.suggestedNext
        .map((item) => item.trim())
        .filter((item) => item.length > 0);
      const sessionSummary = params.sessionSummary?.trim();
      const activeMemoryByID = new Map(
        current.learning.memories
          .filter(
            (memory) =>
              memory.status === "active" &&
              ["goal", "confusion", "nextStep"].includes(memory.kind),
          )
          .map((memory) => [memory.id, memory] as const),
      );
      const resolutions = (params.resolutions ?? []).map((resolution) => {
        const memory = activeMemoryByID.get(resolution.memoryID);
        const evidence = resolution.evidence.trim();
        if (!memory) {
          throw new Error("只能结案当前学习记忆中仍处于活跃状态的项目");
        }
        if (!resolutionEvidenceMatches(current, evidence)) {
          throw new Error("学习记忆结案必须逐字引用用户本轮的确认或回忆表现");
        }
        return {
          memoryID: memory.id,
          text: memory.text,
          evidence,
        };
      });
      if (
        !sessionSummary &&
        !params.suggestedPhase &&
        suggestedNext.length === 0 &&
        entries.length === 0 &&
        resolutions.length === 0
      ) {
        throw new Error("学习状态建议不能为空");
      }
      const details: LearningUpdateDetails = {
        kind: "learning_update",
        contextRevision: current.contextRevision,
        memoryRevision: current.learning.memoryRevision,
        sessionSummary,
        suggestedPhase: params.suggestedPhase,
        suggestedNext,
        entries,
        resolutions,
      };
      return {
        content: [
          {
            type: "text",
            text: "学习状态建议已校验并交给魏碑；这不会修改课程材料或用户笔记。",
          },
        ],
        details,
      };
    },
  });

  pi.registerTool({
    name: NOTE_PROPOSAL_TOOL,
    label: "提出笔记建议",
    description:
      "向魏碑返回一份待用户确认的 Markdown 笔记建议。它不会写入笔记；调用前必须先读取当前上下文。",
    promptSnippet: "提交有证据、带当前修订号且尚未写回的笔记建议",
    parameters: Type.Object(
      {
        markdown: Type.String({
          minLength: 1,
          maxLength: LIMITS.proposalMarkdown,
          description: "待用户确认的 Markdown 建议正文",
        }),
        evidence: Type.Array(
          Type.String({ minLength: 1, maxLength: LIMITS.proposalEvidenceText }),
          {
            minItems: 1,
            maxItems: LIMITS.proposalEvidenceItems,
            description: "逐项列出可核对的当前材料、笔记或选区证据",
          },
        ),
        contextRevision: Type.String({
          minLength: 1,
          maxLength: LIMITS.identifier,
          description: "最近一次 weibei_context 返回的 contextRevision",
        }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const current = await readCurrentSnapshot();
      if (lastReadContextRevision !== current.contextRevision) {
        lastReadContextRevision = undefined;
        throw new Error("魏碑上下文已变化；请重新调用 weibei_context 后再提出笔记建议");
      }
      if (params.contextRevision !== current.contextRevision) {
        throw new Error(
          `笔记建议的 contextRevision 不匹配；当前修订号为 ${current.contextRevision}，请重新读取上下文`,
        );
      }

      const markdown = params.markdown.trim();
      const evidence = params.evidence.map((item) => item.trim()).filter((item) => item.length > 0);
      if (!markdown || evidence.length === 0) {
        throw new Error("笔记建议必须包含非空 Markdown 和至少一条证据");
      }
      const allowedEvidenceLabels = evidenceLabels(current);
      if (evidence.some((item) => !allowedEvidenceLabels.some((label) => item.startsWith(label)))) {
        throw new Error("笔记建议的每条证据都必须以当前材料、笔记或选区的真实来源标签开头");
      }

      const details: NoteProposalDetails = {
        kind: "note_proposal",
        markdown,
        evidence,
        contextRevision: current.contextRevision,
      };

      return {
        content: [
          {
            type: "text",
            text: "笔记建议格式与上下文修订号已校验；这仍是待确认建议，尚未写回任何笔记。",
          },
        ],
        details,
      };
    },
  });

  pi.on("before_agent_start", async (event) => {
    lastReadContextRevision = undefined;
    lastReadMemoryRevision = undefined;
    richAnswerAttemptCount = 0;
    richAnswerCatalogRevision = undefined;
    richAnswerCatalogSelection = undefined;
    richAnswerCatalogRendererSelection = undefined;
    searchedCourseItemIDs.clear();

    let purpose = "unavailable";
    let revision = "unavailable";
    let answerFormPolicy: AnswerFormPolicy = "automatic";
    let readableSourceLabels: string[] = [];
    let explicitRichAnswerRequested = false;
    try {
      const snapshot = await readCurrentSnapshot();
      purpose = snapshot.purpose;
      revision = snapshot.contextRevision;
      answerFormPolicy = snapshot.answerFormPolicy;
      readableSourceLabels = evidenceLabels(snapshot);
      explicitRichAnswerRequested =
        answerFormPolicy === "automatic" &&
        snapshot.workflow !== "noteMaking" &&
        /(?:富回答|可调|交互|互动|图示|函数图|关系图|时间线|图像叠层|叠层|模拟|实验|rich answer|interactive|adjustable|diagram|function graph|relationship graph|timeline|image overlay|simulation|experiment)/iu.test(
          snapshot.question,
        );
      requiredContextRevision = revision;
      activeAnswerFormPolicy = answerFormPolicy;
    } catch {
      requiredContextRevision = undefined;
      activeAnswerFormPolicy = "automatic";
    }

    const answerFormPolicyInstruction =
      answerFormPolicy === "textOnly"
        ? "本轮 answerFormPolicy=textOnly：即使问题文本出现“富回答、图示、互动、实验、叠层”等词，也必须保持普通文本；不得调用 weibei_ui_catalog 或 weibei_rich_answer；不要向用户暴露这是内部策略。"
        : answerFormPolicy === "partialRichAllowed"
          ? "本轮 answerFormPolicy=partialRichAllowed：允许在证据充分且学习收益明显时使用富回答，但问题文本里的“富回答、图示、互动、实验、叠层”等词不构成强制调用。"
          : explicitRichAnswerRequested
            ? "本轮用户明确指定富回答或互动形态。当前证据足够时必须调用 weibei_rich_answer；不能满足时必须在正文明确说明限制，不得静默退成纯文本。"
            : "本轮没有检测到用户指定富回答形态；由你按学习收益判断是否调用 weibei_rich_answer。";

    const sourceAvailabilityInstruction =
      readableSourceLabels.length === 0
        ? "本轮没有可读材料、笔记或选区来源标签：不得引用空材料/空笔记标签，不得提交富回答；只用普通文本诚实说明当前缺少可读材料证据。"
        : `本轮可读来源标签：${readableSourceLabels.join("、")}；课程事实引用必须逐字使用这些标签或本轮课程搜索返回的 evidenceLabel。`;

    const turnContract = [
      "<weibei_turn>",
      `purpose: ${JSON.stringify(purpose)}`,
      `contextRevision: ${JSON.stringify(revision)}`,
      `answerFormPolicy: ${JSON.stringify(answerFormPolicy)}`,
      "本轮第一次工具调用必须是 weibei_context。调用成功前不得回答事实问题，也不得提出富回答或笔记建议。",
      "当前材料、笔记和选区是本轮直接证据；课程关联需要读课程地图或搜索；学习历史需要读学习记忆。",
      "学习记忆只能说明用户的学习状态，不能作为课程事实证据。",
      sourceAvailabilityInstruction,
      "富回答必须提交 schemaVersion 2，并为每个 scene 在 program、renderPlan、ui 三条表达出口中只选择一条；它作为 Agent 回答流中的生成式视觉体验块，可以组合多个视觉、控件、读数和实验步骤，但不是第二篇回答或完整网页。模型负责提交受控组件程序、注册渲染计划或通用原语数据，魏碑宿主用本地渲染内核呈现。",
      `提交富回答前必须调用 ${RICH_ANSWER_CATALOG_TOOL}，按本轮知识形状取得相关组件子集；不要让完整目录或旧回合组件记忆代替本轮选择。`,
      RICH_ANSWER_FAMILY_CONTRACT,
      answerFormPolicyInstruction,
      "</weibei_turn>",
    ].join("\n");

    return { systemPrompt: `${event.systemPrompt}\n\n${turnContract}` };
  });

  pi.on("tool_call", (event) => {
    if (!ALLOWED_TOOLS.has(event.toolName)) {
      return {
        block: true,
        reason: `魏碑 Agent 只允许读取随 App 打包的 Skill，并调用受控的上下文、课程、记忆、富回答与笔记建议工具`,
      };
    }

    if (event.toolName === READ_TOOL) {
      const requestedPath = (event.input as { path?: unknown }).path;
      const normalizedPath = canonicalReadPath(requestedPath);
      if (!normalizedPath || !RICH_ANSWER_SKILL_BY_PATH.has(normalizedPath)) {
        return {
          block: true,
          reason: "魏碑只允许 Pi 原生 read 读取随 App 打包的富回答 Skill，不能读取其它文件。",
        };
      }
    }

    if (
      activeAnswerFormPolicy === "textOnly" &&
      (event.toolName === RICH_ANSWER_CATALOG_TOOL || event.toolName === RICH_ANSWER_TOOL)
    ) {
      return {
        block: true,
        reason:
          "本轮 answerFormPolicy=textOnly：只能普通文本回答。不要调用富回答目录或富回答工具，也不要向用户暴露内部策略、工具名称或被阻止原因。",
      };
    }

    if (
      event.toolName !== CONTEXT_TOOL &&
      (!requiredContextRevision ||
        !lastReadContextRevision ||
        lastReadContextRevision !== requiredContextRevision)
    ) {
      return {
        block: true,
        reason: `必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`,
      };
    }

    if (event.toolName === LEARNING_UPDATE_TOOL && lastReadMemoryRevision === undefined) {
      return {
        block: true,
        reason: `提出学习状态更新前必须调用 ${LEARNING_MEMORY_TOOL}`,
      };
    }
  });

  pi.on("tool_result", async (event) => {
    if (event.toolName !== READ_TOOL || event.isError) return;
    const requestedPath = (event.input as { path?: unknown }).path;
    const normalizedPath = canonicalReadPath(requestedPath);
    if (!normalizedPath) return;
    const skill = RICH_ANSWER_SKILL_BY_PATH.get(normalizedPath);
    if (!skill) return;

    const current = await readCurrentSnapshot();
    const content = await readFile(normalizedPath, "utf8");
    const details: SkillReadDetails = {
      kind: "weibei_skill_read",
      contextRevision: current.contextRevision,
      loaded: {
        id: skill.id,
        name: skill.name,
        version: skill.version,
        sha256: createHash("sha256").update(content, "utf8").digest("hex"),
        byteCount: new TextEncoder().encode(content).byteLength,
        relativePath: skill.relativePath,
        loadedAtContextRevision: current.contextRevision,
      },
    };
    return { details };
  });

  pi.on("context", async (event) => {
    let currentRevision: string | undefined;
    try {
      currentRevision = (await readCurrentSnapshot()).contextRevision;
    } catch {
      currentRevision = undefined;
    }

    const staleToolCallIDs = new Set<string>();
    for (const message of event.messages) {
      if (
        message.role === "toolResult" &&
        ALLOWED_TOOLS.has(message.toolName) &&
        !message.isError &&
        (currentRevision === undefined ||
          contextRevisionFromDetails(message.details) !== currentRevision)
      ) {
        staleToolCallIDs.add(message.toolCallId);
      }
    }

    if (staleToolCallIDs.size === 0) return;

    const messages: typeof event.messages = [];
    for (const message of event.messages) {
      if (message.role === "toolResult" && staleToolCallIDs.has(message.toolCallId)) {
        continue;
      }

      if (message.role === "assistant") {
        const content = message.content.filter(
          (item) => item.type !== "toolCall" || !staleToolCallIDs.has(item.id),
        );
        if (content.length === 0) continue;
        if (content.length !== message.content.length) {
          messages.push({ ...message, content });
          continue;
        }
      }

      messages.push(message);
    }

    return { messages };
  });
}
