import { LIMITS, RICH_ANSWER_CATALOG_TOOL } from "./agent-context";
import {
  OPENUI_COMPONENT_ORDER,
  OPENUI_COMPONENT_SIGNATURES,
  OpenUIComponentName,
} from "./rich-answer-catalog";
import {
  RICH_ANSWER_SUPPORTED_OPERATIONS,
  RICH_ANSWER_UI_BINDING_OUTPUT_ROLES,
  RICH_ANSWER_UI_BINDING_ROLES,
  RICH_ANSWER_UI_CANVAS_ROLES,
  RICH_ANSWER_UI_CONTAINER_ROLES,
  RICH_ANSWER_UI_DATASET_ROLES,
  RICH_ANSWER_UI_PRIMARY_CONTROL_ROLES,
  RichAnswerSceneParam,
  RichAnswerUIBindingParam,
  RichAnswerUIDataRowParam,
  RichAnswerUIDatasetParam,
  RichAnswerUINodeParam,
  hasMeaningfulText,
  isNormalizedPoint,
  numericCoordinateSamples,
  operationTargetsAtLeast,
} from "./rich-answer-render-validation";
import {
  OPENUI_CANVAS_COMPONENTS,
  OPENUI_COMPONENT_ARGUMENT_RULES,
  OPENUI_DIRECT_MANIPULATION_COMPONENTS,
  OpenUIComponentDeclaration,
  OpenUIDeclaration,
  OpenUILineParser,
  OpenUIStateDeclaration,
  openUIProgramFailure,
  openUIReferences,
  openUIStateReferences,
  openUIStringValue,
  validateOpenUIArgument,
} from "./openui-parser";
import { validateOpenUIComponentSemantics } from "./openui-component-semantics";


export function validateRichAnswerProgram(
  scene: RichAnswerSceneParam,
  allowedComponents: ReadonlySet<OpenUIComponentName> = new Set(OPENUI_COMPONENT_ORDER),
): number {
  const { program } = scene;
  if (program === undefined) {
    throw new Error(`富回答场景 ${scene.id} 缺少 program OpenUI 程序`);
  }
  const source = program.source.trim();
  const sourceLines = source
    .split(/\r?\n/gu)
    .map((text, index) => ({ text, line: index + 1 }))
    .filter(({ text }) => text.trim().length > 0);
  if (!source || source.length > LIMITS.richAnswerProgramSource || sourceLines.length > 48) {
    openUIProgramFailure(scene.id, "程序为空或超出 10,000 字符 / 48 条声明预算", "删掉无关声明，保留解决当前问题所需的组件组合");
  }
  if (
    new Set(program.capabilities).size !== program.capabilities.length ||
    program.capabilities.length > LIMITS.richAnswerProgramCapabilities
  ) {
    openUIProgramFailure(scene.id, "能力声明重复或超出预算", "去重 capabilities，并控制在 8 项以内");
  }
  if (/<\/?(?:script|svg|iframe)\b/iu.test(source) ||
      /(?:javascript:|https?:\/\/|\bQuery\(|\bMutation\(|\bOpenUrl\()/iu.test(source)) {
    openUIProgramFailure(scene.id, "程序包含标记、网络地址或可执行工具", "只提交状态、白名单组件、字面量和组件引用");
  }
  if ((scene.operations ?? []).length > 0) {
    openUIProgramFailure(scene.id, "program 场景同时提交了旧 operations", "清空 operations，把交互全部放进 OpenUI 状态与组件");
  }

  const declarations: OpenUIDeclaration[] = [];
  const parseErrors: string[] = [];
  for (const { text, line } of sourceLines) {
    try {
      declarations.push(new OpenUILineParser(scene.id, text, line).parse());
    } catch (error) {
      parseErrors.push(error instanceof Error ? error.message : String(error));
    }
  }
  if (parseErrors.length > 0) {
    throw new Error(Array.from(new Set(parseErrors)).slice(0, 12).join("\n"));
  }
  const structuralErrors: string[] = [];
  const captureStructuralError = (validation: () => void): void => {
    try {
      validation();
    } catch (error) {
      structuralErrors.push(error instanceof Error ? error.message : String(error));
    }
  };
  const statesByName = new Map<string, OpenUIStateDeclaration>();
  const componentsByID = new Map<string, OpenUIComponentDeclaration>();
  for (const declaration of declarations) {
    if (declaration.kind === "stateDeclaration") {
      const previous = statesByName.get(declaration.name);
      if (previous) {
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `状态 $${declaration.name} 重复声明；首次在第 ${previous.line} 行`,
            "删除重复声明或改用唯一状态名",
            declaration.line,
            declaration.column,
          )
        );
        continue;
      }
      const value = declaration.value;
      const isSupportedScalar = value.kind === "number" || value.kind === "string";
      const isSupportedArray = value.kind === "array" &&
        value.items.length <= 64 &&
        value.items.every((item) => item.kind === "number" || item.kind === "string");
      if (!isSupportedScalar && !isSupportedArray) {
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `状态 $${declaration.name} 的初值不是受支持的有限状态`,
            "状态默认写有限数字；只有组件签名明确要求时才写字符串、数字数组或字符串数组",
            declaration.line,
            declaration.value.column,
          )
        );
      }
      statesByName.set(declaration.name, declaration);
      continue;
    }

    if (!allowedComponents.has(declaration.component)) {
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 ${declaration.component} 不在本轮目录选择中`,
          `重新调用 ${RICH_ANSWER_CATALOG_TOOL} 选择贴合的知识形状，或只使用本轮返回的组件：${Array.from(allowedComponents).join("、")}`,
          declaration.line,
          declaration.column,
        )
      );
    }

    const previous = componentsByID.get(declaration.id);
    if (previous) {
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 id ${declaration.id} 重复声明；首次在第 ${previous.line} 行`,
          "给每个组件声明唯一 id，并更新引用它的数组",
          declaration.line,
          declaration.column,
        )
      );
      continue;
    }
    componentsByID.set(declaration.id, declaration);
  }

  for (const namespaceCollision of Array.from(statesByName.keys()).filter((name) => componentsByID.has(name))) {
    const declaration = componentsByID.get(namespaceCollision)!;
    captureStructuralError(() =>
      openUIProgramFailure(
        scene.id,
        `状态 $${namespaceCollision} 与组件 id ${namespaceCollision} 撞名`,
        "让状态名和组件 id 使用不同且各自唯一的名称",
        declaration.line,
        declaration.column,
      )
    );
  }

  const root = componentsByID.get("root");
  const rootDeclarations = Array.from(componentsByID.values()).filter(
    (declaration) => declaration.component === "RichAnswerRoot",
  );
  if (!root || root.component !== "RichAnswerRoot" || rootDeclarations.length !== 1) {
    captureStructuralError(() =>
      openUIProgramFailure(
        scene.id,
        "程序必须且只能有一个 id 为 root 的 RichAnswerRoot",
        `保留一条 ${OPENUI_COMPONENT_SIGNATURES.RichAnswerRoot} 声明，并把它的 id 写成 root`,
        root?.line,
        root?.column,
      )
    );
  }

  const argumentErrors: string[] = [];
  for (const declaration of componentsByID.values()) {
    const rules = OPENUI_COMPONENT_ARGUMENT_RULES[declaration.component];
    const minimumArgumentCount = rules.filter((rule) => !(rule.kind === "string" && rule.optional)).length;
    if (declaration.arguments.length < minimumArgumentCount || declaration.arguments.length > rules.length) {
      try {
        openUIProgramFailure(
          scene.id,
          `组件 ${declaration.id}（${declaration.component}）需要 ${minimumArgumentCount}${minimumArgumentCount === rules.length ? "" : `–${rules.length}`} 个参数，实际收到 ${declaration.arguments.length} 个`,
          `按 ${OPENUI_COMPONENT_SIGNATURES[declaration.component]} 重写这一行`,
          declaration.line,
          declaration.column,
        );
      } catch (error) {
        argumentErrors.push(error instanceof Error ? error.message : String(error));
      }
      continue;
    }
    declaration.arguments.forEach((value, index) => {
      try {
        validateOpenUIArgument(scene, declaration, value, rules[index], index, statesByName, componentsByID);
      } catch (error) {
        argumentErrors.push(error instanceof Error ? error.message : String(error));
      }
    });
  }
  if (argumentErrors.length === 0) {
    const componentParentCounts = new Map<string, number>();
    for (const declaration of componentsByID.values()) {
      for (const referencedID of declaration.arguments.flatMap(openUIReferences)) {
        componentParentCounts.set(referencedID, (componentParentCounts.get(referencedID) ?? 0) + 1);
      }
    }
    for (const [componentID, count] of Array.from(componentParentCounts.entries()).filter(([, count]) => count > 1)) {
      const declaration = componentsByID.get(componentID)!;
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 ${componentID} 被引用了 ${count} 次，组件图不再是单父节点树`,
          "每个组件声明只挂到一个父组件；需要重复呈现时创建不同 id 的独立声明",
          declaration.line,
          declaration.column,
        )
      );
    }

    const visited = new Set<string>();
    const active = new Set<string>();
    const visit = (componentID: string, path: string[]): void => {
      if (active.has(componentID)) {
        const declaration = componentsByID.get(componentID)!;
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `组件引用形成循环：${[...path, componentID].join(" → ")}`,
            "让组件只从 root 向下引用，不要反向引用祖先组件",
            declaration.line,
            declaration.column,
          )
        );
        return;
      }
      if (visited.has(componentID)) return;
      active.add(componentID);
      const declaration = componentsByID.get(componentID)!;
      for (const referencedID of declaration.arguments.flatMap(openUIReferences)) {
        visit(referencedID, [...path, componentID]);
      }
      active.delete(componentID);
      visited.add(componentID);
    };
    if (root?.component === "RichAnswerRoot") {
      visit("root", []);
      const orphaned = Array.from(componentsByID.keys()).filter((componentID) => !visited.has(componentID));
      if (orphaned.length > 0) {
        const declaration = componentsByID.get(orphaned[0])!;
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `存在未从 root 引用的孤立组件：${orphaned.slice(0, 6).join("、")}`,
            "把需要的组件接入某个 LearningStage，删除其余孤立声明；不能用孤立组件伪造证据绑定",
            declaration.line,
            declaration.column,
          )
        );
      }
    }

    const usedStateNames = new Set(
      Array.from(componentsByID.values()).flatMap((declaration) =>
        declaration.arguments.flatMap(openUIStateReferences)
      ),
    );
    for (const unusedState of Array.from(statesByName.values()).filter((state) => !usedStateNames.has(state.name))) {
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `状态 $${unusedState.name} 没有被任何组件使用`,
          "删除该状态，或把它作为对应组件的 $状态参数",
          unusedState.line,
          unusedState.column,
        )
      );
    }
  }

  const declarationErrors = Array.from(new Set([...structuralErrors, ...argumentErrors])).slice(0, 24);
  if (declarationErrors.length > 0) {
    throw new Error(declarationErrors.join("\n"));
  }

  const semanticErrors: string[] = [];
  const captureSemanticError = (validation: () => void): void => {
    try {
      validation();
    } catch (error) {
      semanticErrors.push(error instanceof Error ? error.message : String(error));
    }
  };
  for (const declaration of componentsByID.values()) {
    captureSemanticError(() =>
      validateOpenUIComponentSemantics(scene, declaration, statesByName, componentsByID)
    );
  }

  if (new Set(scene.evidenceIDs).size !== scene.evidenceIDs.length) {
    captureSemanticError(() =>
      openUIProgramFailure(scene.id, "scene.evidenceIDs 包含重复 id", "去重 scene.evidenceIDs，并保留每条真实证据一次")
    );
  }
  const sceneEvidenceIDs = new Set(scene.evidenceIDs);
  const boundEvidenceIDs = new Set<string>();
  for (const declaration of componentsByID.values()) {
    const evidenceIndex = declaration.component === "EvidenceSnippet"
      ? 0
      : declaration.component === "ArgumentUnit"
        ? 4
      : declaration.component === "CausalEvent"
          ? 7
          : declaration.component === "SpatialPoint"
            ? 7
          : undefined;
    if (evidenceIndex === undefined) continue;
    if (declaration.arguments[evidenceIndex] === undefined || declaration.arguments[evidenceIndex].kind === "null") continue;
    const evidenceID = openUIStringValue(declaration, evidenceIndex);
    if (!sceneEvidenceIDs.has(evidenceID)) {
      captureSemanticError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 ${declaration.id} 引用了未在 scene.evidenceIDs 声明的证据 ${JSON.stringify(evidenceID)}`,
          "改用本场景 evidenceIDs 中的真实 id，或把经过 evidenceLedger 校验的 id 加入 scene.evidenceIDs",
          declaration.line,
          declaration.arguments[evidenceIndex].column,
        )
      );
    }
    boundEvidenceIDs.add(evidenceID);
  }
  const missingEvidenceIDs = scene.evidenceIDs.filter((evidenceID) => !boundEvidenceIDs.has(evidenceID));
  if (missingEvidenceIDs.length > 0) {
    captureSemanticError(() =>
      openUIProgramFailure(
        scene.id,
        `证据没有绑定到可达的 EvidenceSnippet、ArgumentUnit、CausalEvent 或 SpatialPoint：${missingEvidenceIDs.join("、")}`,
        "把每个 scene.evidenceIDs 真实放进至少一个证据组件；普通字符串出现该 id 不算绑定",
      )
    );
  }
  if (semanticErrors.length > 0) {
    throw new Error(Array.from(new Set(semanticErrors)).slice(0, 12).join("\n"));
  }

  const usedComponents = Array.from(componentsByID.values()).map((declaration) => declaration.component);
  const actualGraphics = usedComponents.some((component) => OPENUI_CANVAS_COMPONENTS.has(component))
    ? "canvas"
    : "dom";
  const actualDirectManipulation = usedComponents.some((component) =>
    OPENUI_DIRECT_MANIPULATION_COMPONENTS.has(component)
  );
  program.graphics = actualGraphics;
  program.directManipulation = actualDirectManipulation;
  return actualDirectManipulation ? 1 : 0;
}


export function validateRichAnswerUI(
  scene: RichAnswerSceneParam,
  allowedEvidenceIDs: ReadonlySet<string>,
  allowedAssetIDs: ReadonlySet<string>,
): number {
  const ui = scene.ui!;
  const validationIssues: string[] = [];
  const issue = (message: string): void => {
    if (!validationIssues.includes(message) && validationIssues.length < 24) {
      validationIssues.push(message);
    }
  };
  if (ui.nodes.length === 0 || ui.nodes.length > LIMITS.richAnswerUINodes) {
    issue(`富回答场景 ${scene.id} 的 UI 节点数量无效`);
  }
  const datasets = ui.datasets ?? [];
  const bindings = ui.bindings ?? [];
  const rows = datasets.flatMap((dataset) => dataset.rows);
  if (rows.length > LIMITS.richAnswerUIRows || bindings.length > LIMITS.richAnswerUIBindings) {
    issue(
      `富回答场景 ${scene.id} 的 UI 数据或绑定超出预算：rows=${rows.length}/${LIMITS.richAnswerUIRows}，bindings=${bindings.length}/${LIMITS.richAnswerUIBindings}`,
    );
  }

  const nodeIDs = ui.nodes.map((node) => node.id);
  const datasetIDs = datasets.map((dataset) => dataset.id);
  const bindingIDs = bindings.map((binding) => binding.id);
  const rowIDs = rows.map((row) => row.id);
  const allIDs = [...nodeIDs, ...datasetIDs, ...bindingIDs, ...rowIDs];
  if (new Set(allIDs).size !== allIDs.length) {
    issue(`富回答场景 ${scene.id} 的 UI 节点、数据行和绑定 id 必须唯一`);
  }

  const nodesByID = new Map(ui.nodes.map((node) => [node.id, node]));
  const datasetsByID = new Map(datasets.map((dataset) => [dataset.id, dataset]));
  const bindingsByID = new Map(bindings.map((binding) => [binding.id, binding]));
  if (!nodesByID.has(ui.rootID)) {
    issue(`富回答场景 ${scene.id} 的 UI 根节点不存在`);
  }

  const parentCounts = new Map<string, number>();
  for (const node of ui.nodes) {
    const children = node.children ?? [];
    if (children.some((childID) => !nodesByID.has(childID))) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 存在悬空子节点`);
    }
    children.forEach((childID) => parentCounts.set(childID, (parentCounts.get(childID) ?? 0) + 1));
    if (RICH_ANSWER_UI_CONTAINER_ROLES.has(node.role)) {
      if (children.length === 0) {
        issue(`富回答场景 ${scene.id} 的 UI 容器 ${node.id} 不能为空`);
      }
    } else if (node.role === "canvas") {
      if (
        children.length === 0 ||
        children.some((childID) => !RICH_ANSWER_UI_CANVAS_ROLES.has(nodesByID.get(childID)?.role ?? ""))
      ) {
        issue(`富回答场景 ${scene.id} 的 canvas 只能包含视觉图元`);
      }
      if (
        (node.xAxis !== undefined && node.xAxis.maximum <= node.xAxis.minimum) ||
        (node.yAxis !== undefined && node.yAxis.maximum <= node.yAxis.minimum)
      ) {
        issue(`富回答场景 ${scene.id} 的 canvas 坐标范围无效`);
      }
    } else if (children.length > 0) {
      issue(`富回答场景 ${scene.id} 的 UI 叶子节点 ${node.id} 不能包含子节点`);
    }

    if (node.role === "grid" && (node.columns === undefined || node.columns < 2 || node.columns > 3)) {
      issue(`富回答场景 ${scene.id} 的 grid 只能使用两列或三列`);
    }
    if (node.role !== "grid" && node.columns !== undefined) {
      issue(`富回答场景 ${scene.id} 的非 grid 节点不能声明 columns`);
    }
    if (node.datasetID !== undefined && !datasetsByID.has(node.datasetID)) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 引用了不存在的数据集`);
    }
    if (RICH_ANSWER_UI_DATASET_ROLES.has(node.role) && node.datasetID === undefined) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 必须引用数据集`);
    }
    if (
      RICH_ANSWER_UI_BINDING_ROLES.has(node.role) &&
      (node.bindingID === undefined || !bindingsByID.has(node.bindingID))
    ) {
      issue(`富回答场景 ${scene.id} 的 UI 控件 ${node.id} 引用了不存在的绑定`);
    }
    if (node.bindingID !== undefined && !bindingsByID.has(node.bindingID)) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 引用了不存在的绑定`);
    }
    if (node.role === "text" && !hasMeaningfulText(node.text) && !hasMeaningfulText(node.label)) {
      issue(`富回答场景 ${scene.id} 的文本节点 ${node.id} 不能为空`);
    }
    if (node.role === "sequence") {
      const dataset = node.datasetID === undefined ? undefined : datasetsByID.get(node.datasetID);
      if (dataset === undefined || dataset.rows.length < 2) {
        issue(`富回答场景 ${scene.id} 的 sequence 节点 ${node.id} 必须引用至少两行数据`);
      } else if (dataset.rows.some((row) => !hasMeaningfulText(row.label))) {
        issue(`富回答场景 ${scene.id} 的 sequence 节点 ${node.id} 每行都必须提供可见 label`);
      }
    }
    if (node.role === "shape") {
      const hasDataset = node.datasetID !== undefined;
      const hasBinding = node.bindingID !== undefined;
      if (node.shape === undefined || node.fill === undefined || node.region === undefined) {
        issue(`富回答场景 ${scene.id} 的 shape 节点 ${node.id} 缺少形状、填充或区域`);
      }
      if (hasBinding && !hasDataset) {
        issue(`富回答场景 ${scene.id} 的可移动 shape 节点 ${node.id} 必须引用 dataset`);
      }
    } else if (node.shape !== undefined) {
      issue(`富回答场景 ${scene.id} 只有 shape 节点可以声明 shape`);
    }
    if (
      node.fill !== undefined &&
      !["shape", "bar", "dotMatrix", "region", "area"].includes(node.role)
    ) {
      issue(`富回答场景 ${scene.id} 的节点 ${node.id} 不能声明 fill`);
    }
    if (node.region !== undefined) {
      if (
        (node.region.x + node.region.width > 1 || node.region.y + node.region.height > 1)
      ) {
        issue(`富回答场景 ${scene.id} 的 UI 区域 ${node.id} 超出归一化边界`);
      }
    }
    if (node.role === "region" && node.region === undefined) {
      issue(`富回答场景 ${scene.id} 的 region 节点 ${node.id} 缺少区域`);
    }
    if (node.role === "image") {
      if (node.assetID === undefined || !allowedAssetIDs.has(node.assetID)) {
        issue(`富回答场景 ${scene.id} 的 image 节点引用了未开放资源`);
      }
    } else if (node.assetID !== undefined) {
      issue(`富回答场景 ${scene.id} 只有 image 节点可以引用资源`);
    }
    if ((node.evidenceIDs ?? []).some((evidenceID) => !allowedEvidenceIDs.has(evidenceID))) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 引用了不存在的证据`);
    }
    if (node.role === "evidence" && (node.evidenceIDs ?? []).length === 0) {
      issue(`富回答场景 ${scene.id} 的 evidence 节点没有来源`);
    }
  }

  for (const labelNode of ui.nodes.filter((node) => node.role === "label" && node.datasetID !== undefined)) {
    const siblingBindings = Array.from(new Set(
      ui.nodes
        .filter((node) =>
          node.id !== labelNode.id &&
          node.datasetID === labelNode.datasetID &&
          node.role !== "label" &&
          node.bindingID !== undefined
        )
        .map((node) => node.bindingID as string),
    ));
    if (siblingBindings.length === 1 && labelNode.bindingID !== siblingBindings[0]) {
      issue(
        `富回答场景 ${scene.id} 的 label 节点 ${labelNode.id} 必须与同数据集图形共享 binding ${siblingBindings[0]}，避免图形隐藏后留下孤立标签`,
      );
    }
  }

  if ((parentCounts.get(ui.rootID) ?? 0) !== 0 || Array.from(parentCounts.values()).some((count) => count > 1)) {
    issue(`富回答场景 ${scene.id} 的 UI 必须是单父节点树`);
  }
  const visited = new Set<string>();
  const active = new Set<string>();
  const visit = (nodeID: string, depth: number): boolean => {
    const node = nodesByID.get(nodeID);
    if (!node || depth > 7 || active.has(nodeID)) return false;
    if (visited.has(nodeID)) return true;
    active.add(nodeID);
    let isValid = true;
    for (const childID of node.children ?? []) {
      if (!visit(childID, depth + 1)) isValid = false;
    }
    active.delete(nodeID);
    if (!isValid) return false;
    visited.add(nodeID);
    return true;
  };
  if (!nodesByID.has(ui.rootID) || !visit(ui.rootID, 1) || visited.size !== ui.nodes.length) {
    issue(`富回答场景 ${scene.id} 的 UI 存在循环、孤立节点或嵌套过深`);
  }
  const reachableNodes = ui.nodes.filter((node) => visited.has(node.id));
  const reachableDatasetIDs = new Set(
    reachableNodes
      .map((node) => node.datasetID)
      .filter((datasetID): datasetID is string => datasetID !== undefined),
  );

  for (const dataset of datasets) {
    if (dataset.rows.length === 0) {
      issue(`富回答场景 ${scene.id} 的数据集 ${dataset.id} 不能为空`);
    }
    for (const row of dataset.rows) {
      const hasSecondPoint = row.x2 !== undefined || row.y2 !== undefined;
      if (hasSecondPoint && (row.x2 === undefined || row.y2 === undefined)) {
        issue(`富回答场景 ${scene.id} 的数据行 ${row.id} 矢量端点不完整`);
      }
      if ((row.evidenceIDs ?? []).some((evidenceID) => !allowedEvidenceIDs.has(evidenceID))) {
        issue(`富回答场景 ${scene.id} 的数据行 ${row.id} 引用了不存在的证据`);
      }
    }
  }
  for (const binding of bindings) {
    if (
      binding.maximum <= binding.minimum ||
      binding.step <= 0 ||
      binding.initialValue < binding.minimum ||
      binding.initialValue > binding.maximum
    ) {
      issue(`富回答场景 ${scene.id} 的 UI 绑定 ${binding.id} 范围无效`);
    }
    const hasControl = reachableNodes.some((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_ROLES.has(node.role)
    );
    const hasDrivenOutput = reachableNodes.some((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_OUTPUT_ROLES.has(node.role)
    );
    if (!hasControl || !hasDrivenOutput) {
      issue(`富回答场景 ${scene.id} 的 UI 绑定 ${binding.id} 必须同时驱动可见控件和图元或读数`);
    } else if (!richAnswerBindingHasChangingOutcome(binding, reachableNodes, datasetsByID)) {
      issue(`富回答场景 ${scene.id} 的 UI 绑定 ${binding.id} 没有产生可验证的语义状态或派生量变化`);
    }
  }

  const boundEvidenceIDs = new Set([
    ...reachableNodes.flatMap((node) => node.evidenceIDs ?? []),
    ...datasets
      .filter((dataset) => reachableDatasetIDs.has(dataset.id))
      .flatMap((dataset) => dataset.rows.flatMap((row) => row.evidenceIDs ?? [])),
  ]);
  const unboundEvidenceIDs = scene.evidenceIDs.filter(
    (evidenceID) => !boundEvidenceIDs.has(evidenceID),
  );
  if (unboundEvidenceIDs.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的证据没有绑定到可达 UI 节点或数据行：${unboundEvidenceIDs.join("、")}`,
    );
  }

  const primaryControlCount = ui.nodes.filter((node) =>
    RICH_ANSWER_UI_PRIMARY_CONTROL_ROLES.has(node.role)
  ).length;
  if (primaryControlCount > 2) {
    issue(`富回答场景 ${scene.id} 最多只能展示两个主要控件`);
  }
  if (validationIssues.length > 0) {
    throw new Error(validationIssues.join("\n"));
  }
  return primaryControlCount + (ui.nodes.some((node) => node.role === "sequence") ? 1 : 0);
}


export function richAnswerBindingHasChangingOutcome(
  binding: RichAnswerUIBindingParam,
  reachableNodes: RichAnswerUINodeParam[],
  datasetsByID: ReadonlyMap<string, RichAnswerUIDatasetParam>,
): boolean {
  return reachableNodes
    .filter((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_OUTPUT_ROLES.has(node.role)
    )
    .some((node) => {
      if (node.datasetID === undefined) return false;
      const dataset = datasetsByID.get(node.datasetID);
      if (dataset === undefined) return false;
      return richAnswerRowsHaveChangingOutcome(dataset.rows, node.role === "sequence");
    });
}


export function richAnswerRowsHaveChangingOutcome(
  rows: RichAnswerUIDataRowParam[],
  acceptsSemanticOnly: boolean,
): boolean {
  if (rows.length < 2) return false;
  const signature = (row: RichAnswerUIDataRowParam): string => [
    row.value ?? "",
    row.result ?? "",
    row.x,
    row.y,
    row.x2 ?? "",
    row.y2 ?? "",
    row.label?.trim().toLocaleLowerCase() ?? "",
  ].join("|");
  const signatures = new Set(rows.map(signature));
  const numericSets = [
    rows.map((row) => row.value).filter((value): value is number => value !== undefined),
    rows.map((row) => row.result).filter((value): value is number => value !== undefined),
    rows.map((row) => row.x),
    rows.map((row) => row.y),
    rows.map((row) => row.x2).filter((value): value is number => value !== undefined),
    rows.map((row) => row.y2).filter((value): value is number => value !== undefined),
  ];
  const hasVaryingNumericState = numericSets.some((values) => new Set(values).size >= 2);
  const hasVaryingSemanticState = new Set(
    rows
      .map((row) => row.label?.trim().toLocaleLowerCase() ?? "")
      .filter((label) => label.length > 0),
  ).size >= 2;
  return signatures.size >= 2 && (hasVaryingNumericState || (acceptsSemanticOnly && hasVaryingSemanticState));
}


export function validateRichAnswerFamilyContract(scene: RichAnswerSceneParam): void {
  const supportedOperations = RICH_ANSWER_SUPPORTED_OPERATIONS[scene.family];
  if (!supportedOperations) {
    throw new Error(`富回答场景 ${scene.id} 的 family 不受支持`);
  }

  const unsupportedOperation = (scene.operations ?? []).find(
    (operation) => !supportedOperations.has(operation.kind),
  );
  if (unsupportedOperation) {
    throw new Error(
      `富回答场景 ${scene.id} 的 ${scene.family} 渲染器不支持 ${unsupportedOperation.kind} 操作`,
    );
  }

  switch (scene.family) {
    case "textAndAlignment": {
      const selectableTextIDs = new Set(
        (scene.objects ?? [])
          .filter((object) => object.kind === "text" && hasMeaningfulText(object.text))
          .map((object) => object.id),
      );
      if (!operationTargetsAtLeast(scene, "select", 1, selectableTextIDs)) {
        throw new Error(`富回答场景 ${scene.id} 的文本族必须提供可选择的文本对象`);
      }
      return;
    }
    case "quantityAndCoordinates": {
      const coordinateFrameIDs = new Set(
        (scene.frames ?? [])
          .filter((frame) => frame.kind === "cartesian")
          .map((frame) => frame.id),
      );
      const plottedObjects = (scene.objects ?? []).filter((object) =>
        (object.kind === "quantity" || object.kind === "dataPoint") &&
          isNormalizedPoint(object.coordinate) &&
          object.frameID !== undefined &&
          coordinateFrameIDs.has(object.frameID),
      );
      if (coordinateFrameIDs.size === 0 || plottedObjects.length < 2) {
        throw new Error(`富回答场景 ${scene.id} 的数量族必须有至少两个坐标点和坐标框`);
      }
      return;
    }
    case "processAndState": {
      const processObjectIDs = new Set(
        (scene.objects ?? [])
          .filter((object) => object.kind === "step" || object.kind === "state")
          .map((object) => object.id),
      );
      if (
        processObjectIDs.size < 2 ||
        !operationTargetsAtLeast(scene, "step", 2, processObjectIDs) ||
        !operationTargetsAtLeast(scene, "playPause", 2, processObjectIDs)
      ) {
        throw new Error(`富回答场景 ${scene.id} 的过程族必须有至少两个步骤/状态，并提供 step 与 playPause`);
      }
      return;
    }
    case "relationAndEvidence": {
      if ((scene.relations ?? []).length === 0) {
        throw new Error(`富回答场景 ${scene.id} 的关系族必须至少有一条关系`);
      }
      return;
    }
    case "timeAndSpace": {
      const navigableFrameIDs = new Set(
        (scene.frames ?? [])
          .filter((frame) => frame.kind === "timeline" || frame.kind === "space")
          .map((frame) => frame.id),
      );
      const navigableObjectIDs = new Set(
        (scene.objects ?? [])
          .filter((object) =>
            isNormalizedPoint(object.coordinate) &&
              object.frameID !== undefined &&
              navigableFrameIDs.has(object.frameID),
          )
          .map((object) => object.id),
      );
      const scrubTargetIDs = new Set([...navigableObjectIDs, ...navigableFrameIDs]);
      if (
        navigableFrameIDs.size === 0 ||
        navigableObjectIDs.size < 2 ||
        !operationTargetsAtLeast(scene, "scrub", 1, scrubTargetIDs)
      ) {
        throw new Error(`富回答场景 ${scene.id} 的时间空间族必须有 timeline/space frame 和 scrub`);
      }
      return;
    }
    case "imageAndOverlay": {
      const imageFrames = (scene.frames ?? []).filter(
        (frame) => frame.kind === "image" && frame.assetID !== undefined,
      );
      const imageFrameIDs = new Set(imageFrames.map((frame) => frame.id));
      const frameAssetIDs = new Set(imageFrames.flatMap((frame) => frame.assetID ?? []));
      const imageObjects = (scene.objects ?? []).filter((object) =>
        object.kind === "image" &&
          object.assetID !== undefined &&
          frameAssetIDs.has(object.assetID) &&
          object.frameID !== undefined &&
          imageFrameIDs.has(object.frameID),
      );
      const regionObjects = (scene.objects ?? []).filter((object) =>
        object.kind === "region" &&
          object.bounds !== undefined &&
          object.frameID !== undefined &&
          imageFrameIDs.has(object.frameID),
      );
      if (imageFrames.length === 0 || imageObjects.length === 0 || regionObjects.length === 0) {
        throw new Error(`富回答场景 ${scene.id} 的图像叠层族必须有 image、region、frame 和 asset`);
      }
      return;
    }
    case "comparisonAndEvaluation": {
      const objectIDs = new Set((scene.objects ?? []).map((object) => object.id));
      if (!operationTargetsAtLeast(scene, "compare", 2, objectIDs)) {
        throw new Error(`富回答场景 ${scene.id} 的比较族必须有至少两个 compare 对象目标`);
      }
      return;
    }
    case "calculationAndConstraints": {
      const hasFormula = (scene.objects ?? []).some(
        (object) => object.kind === "formula" && hasMeaningfulText(object.text),
      );
      const hasConstraint = (scene.objects ?? []).some(
        (object) => object.kind === "constraint" && hasMeaningfulText(object.text),
      );
      const frameIDs = new Set((scene.frames ?? []).map((frame) => frame.id));
      const hasDeterministicAdjust = (scene.operations ?? []).some((operation) => {
        if (operation.kind !== "adjust" || operation.parameter === undefined) return false;
        const samples = numericCoordinateSamples(scene, operation, frameIDs);
        return samples.length >= 2 &&
          new Set(samples.map((sample) => sample.coordinate?.x)).size >= 2;
      });
      if (!hasFormula || !hasConstraint || !hasDeterministicAdjust) {
        throw new Error(`富回答场景 ${scene.id} 的计算族必须有 formula/constraint 和可插值 adjust 样本`);
      }
      return;
    }
    default:
      throw new Error(`富回答场景 ${scene.id} 的 family 不受支持`);
  }
}