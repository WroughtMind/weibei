import {
  LIMITS,
  RICH_ANSWER_CATALOG_TOOL,
  isRecord,
} from "./agent-context";
import { RICH_ANSWER_RENDERER_REGISTRATION_BY_ID, RichAnswerRendererRegistration } from "./rich-answer-catalog";
import {
  RICH_ANSWER_RENDER_ARTIFACT_FIELDS,
  RICH_ANSWER_RENDER_ARTIFACT_KINDS,
  RICH_ANSWER_RENDER_FALLBACK_FIELDS,
  RICH_ANSWER_RENDER_FALLBACK_MODES,
  RICH_ANSWER_RENDER_INTERACTION_FIELDS,
  RICH_ANSWER_RENDER_INTERACTION_KINDS,
  RICH_ANSWER_RENDER_PLAN_FIELDS,
  RICH_ANSWER_RENDER_QUALITY_BUDGET_FIELDS,
  RICH_ANSWER_RENDER_SOURCE_BINDING_FIELDS,
  RICH_ANSWER_RENDER_SOURCE_BINDING_ROLES,
  RichAnswerSceneParam,
  rendererFieldList,
  richAnswerRenderPlanByteLength,
  richAnswerRenderPlanContainsUnsafeText,
  richAnswerRenderPlanIntegerInRange,
  richAnswerRenderPlanSpecEvidenceIDs,
  richAnswerRenderPlanStringArray,
  richAnswerRenderPlanUnknownFields,
  richAnswerRenderPlanValidActionName,
  richAnswerRenderPlanValidIdentifier,
} from "./rich-answer-validation-models";
import {
  richAnswerRenderPlanEstimatedNodes,
  richAnswerRenderPlanFiniteNumber,
  richAnswerValidateNestedFields,
  validateRichAnswerChartSpec,
  validateRichAnswerGenericRenderSpec,
  validateRichAnswerMathFunctionSpec,
} from "./rich-answer-chart-validation";
import {
  richAnswerValidateIdentifier,
  richAnswerValidateRange,
  richAnswerValidateVector3,
  validateRichAnswerGeometry2DSpec,
  validateRichAnswerImageOverlaySpec,
  validateRichAnswerSpatialMapSpec,
} from "./rich-answer-spatial-validation";


export function validateRichAnswerScene3DSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  allowedEvidenceIDs: ReadonlySet<string>,
  issue: (message: string) => void,
  validateStateCollections = true,
): number {
  validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  if (richAnswerValidateNestedFields(
    scene,
    spec.camera,
    ["yaw", "pitch", "distance", "lookAt", "fov"],
    "spec.camera",
    issue,
  )) {
    richAnswerValidateVector3(scene, spec.camera.lookAt, "spec.camera.lookAt", issue);
    if (![spec.camera.yaw, spec.camera.pitch, spec.camera.distance].every(richAnswerRenderPlanFiniteNumber)) {
      issue(`富回答场景 ${scene.id} 的 spec.camera 数值必须是有限数字`);
    }
  }
  if (spec.coordinateUnits !== undefined) {
    richAnswerValidateNestedFields(scene, spec.coordinateUnits, ["x", "y", "z"], "spec.coordinateUnits", issue);
  }
  if (spec.bounds !== undefined && richAnswerValidateNestedFields(scene, spec.bounds, ["x", "y", "z"], "spec.bounds", issue)) {
    richAnswerValidateRange(scene, spec.bounds.x, "spec.bounds.x", issue);
    richAnswerValidateRange(scene, spec.bounds.y, "spec.bounds.y", issue);
    richAnswerValidateRange(scene, spec.bounds.z, "spec.bounds.z", issue);
  }
  if (spec.controls !== undefined) {
    richAnswerValidateNestedFields(
      scene,
      spec.controls,
      ["allowLayerToggle", "allowSlice", "allowCameraDrag", "allowReset", "allowProbe"],
      "spec.controls",
      issue,
    );
  }
  const layers = Array.isArray(spec.layers) ? spec.layers : [];
  if (spec.layers !== undefined && !Array.isArray(spec.layers)) issue(`富回答场景 ${scene.id} 的 spec.layers 必须是数组`);
  const layerIDs = new Set<string>();
  for (const [layerIndex, rawLayer] of layers.entries()) {
    const layerPath = `spec.layers[${layerIndex}]`;
    if (!richAnswerValidateNestedFields(scene, rawLayer, ["id", "title", "visibleDefault"], layerPath, issue)) continue;
    if (richAnswerValidateIdentifier(scene, rawLayer.id, `${layerPath}.id`, issue)) {
      if (layerIDs.has(rawLayer.id)) issue(`富回答场景 ${scene.id} 的三维图层 id 重复：${rawLayer.id}`);
      layerIDs.add(rawLayer.id);
    }
  }
  const states = Array.isArray(spec.states) ? spec.states : [];
  if (spec.states !== undefined && !Array.isArray(spec.states)) issue(`富回答场景 ${scene.id} 的 spec.states 必须是数组`);
  const objects = Array.isArray(spec.objects) ? spec.objects : [];
  if (spec.objects !== undefined && !Array.isArray(spec.objects)) issue(`富回答场景 ${scene.id} 的 spec.objects 必须是数组`);
  if (objects.length === 0 && states.length === 0) issue(`富回答场景 ${scene.id} 至少需要一个共享对象或状态对象`);
  const objectIDs = new Set<string>();
  let dataPointCount = 0;
  for (const [objectIndex, rawObject] of objects.entries()) {
    const objectPath = `spec.objects[${objectIndex}]`;
    if (!isRecord(rawObject)) {
      issue(`富回答场景 ${scene.id} 的 ${objectPath} 必须是对象`);
      continue;
    }
    const baseFields = ["id", "kind", "layer", "label", "visible", "color", "alpha"];
    const fields = rawObject.kind === "point"
      ? [...baseFields, "position", "radius"]
      : rawObject.kind === "polyline"
        ? [...baseFields, "points", "closed", "strokeWidth"]
        : rawObject.kind === "wireframe-grid"
          ? [...baseFields, "xRange", "zRange", "cellSize", "y"]
          : rawObject.kind === "surface"
            ? [...baseFields, "yValues", "xRange", "zRange", "wireColor"]
            : rawObject.kind === "molecule"
              ? [...baseFields, "atoms", "bonds", "electronDomains", "angleMarkers", "showAtomLabels", "showBondLabels", "showElectronDomains"]
              : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawObject, fields, objectPath, issue);
    if (!["point", "polyline", "wireframe-grid", "surface", "molecule"].includes(String(rawObject.kind))) {
      issue(`富回答场景 ${scene.id} 的 ${objectPath}.kind 无效`);
      continue;
    }
    if (richAnswerValidateIdentifier(scene, rawObject.id, `${objectPath}.id`, issue)) {
      if (objectIDs.has(rawObject.id)) issue(`富回答场景 ${scene.id} 的三维对象 id 重复：${rawObject.id}`);
      objectIDs.add(rawObject.id);
    }
    if (rawObject.layer !== undefined && !layerIDs.has(String(rawObject.layer))) {
      issue(`富回答场景 ${scene.id} 的 ${objectPath}.layer 引用了不存在的图层`);
    }
    if (rawObject.kind === "point") {
      richAnswerValidateVector3(scene, rawObject.position, `${objectPath}.position`, issue);
      dataPointCount += 1;
    } else if (rawObject.kind === "polyline") {
      const points = Array.isArray(rawObject.points) ? rawObject.points : [];
      if (points.length < 2) issue(`富回答场景 ${scene.id} 的 ${objectPath}.points 至少需要两个点`);
      points.forEach((point, pointIndex) => richAnswerValidateVector3(scene, point, `${objectPath}.points[${pointIndex}]`, issue));
      dataPointCount += points.length;
    } else if (rawObject.kind === "wireframe-grid") {
      richAnswerValidateRange(scene, rawObject.xRange, `${objectPath}.xRange`, issue);
      richAnswerValidateRange(scene, rawObject.zRange, `${objectPath}.zRange`, issue);
      if (!richAnswerRenderPlanFiniteNumber(rawObject.cellSize) || rawObject.cellSize <= 0) issue(`富回答场景 ${scene.id} 的 ${objectPath}.cellSize 必须大于 0`);
      dataPointCount += 4;
    } else if (rawObject.kind === "surface") {
      richAnswerValidateRange(scene, rawObject.xRange, `${objectPath}.xRange`, issue);
      richAnswerValidateRange(scene, rawObject.zRange, `${objectPath}.zRange`, issue);
      const rows = Array.isArray(rawObject.yValues) ? rawObject.yValues : [];
      const width = Array.isArray(rows[0]) ? rows[0].length : 0;
      if (rows.length < 2 || width < 2) issue(`富回答场景 ${scene.id} 的 ${objectPath}.yValues 必须是至少 2×2 的规则有限数矩阵`);
      rows.forEach((row, rowIndex) => {
        if (!Array.isArray(row) || row.length !== width || !row.every(richAnswerRenderPlanFiniteNumber)) {
          issue(`富回答场景 ${scene.id} 的 ${objectPath}.yValues[${rowIndex}] 必须与首行等长且只含有限数`);
        }
      });
      dataPointCount += rows.length * width;
    } else {
      const atoms = Array.isArray(rawObject.atoms) ? rawObject.atoms : [];
      if (atoms.length === 0) issue(`富回答场景 ${scene.id} 的 ${objectPath}.atoms 必须是非空数组`);
      const atomIDs = new Set<string>();
      for (const [atomIndex, rawAtom] of atoms.entries()) {
        const atomPath = `${objectPath}.atoms[${atomIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawAtom,
          ["id", "element", "label", "position", "radius", "color", "role", "charge"],
          atomPath,
          issue,
        )) continue;
        if (richAnswerValidateIdentifier(scene, rawAtom.id, `${atomPath}.id`, issue)) {
          if (atomIDs.has(rawAtom.id)) issue(`富回答场景 ${scene.id} 的分子原子 id 重复：${rawAtom.id}`);
          atomIDs.add(rawAtom.id);
        }
        richAnswerValidateVector3(scene, rawAtom.position, `${atomPath}.position`, issue);
      }
      const bonds = Array.isArray(rawObject.bonds) ? rawObject.bonds : [];
      for (const [bondIndex, rawBond] of bonds.entries()) {
        const bondPath = `${objectPath}.bonds[${bondIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawBond,
          ["id", "from", "to", "order", "style", "label", "color", "radius"],
          bondPath,
          issue,
        )) continue;
        if (!atomIDs.has(String(rawBond.from)) || !atomIDs.has(String(rawBond.to)) || rawBond.from === rawBond.to) {
          issue(`富回答场景 ${scene.id} 的 ${bondPath} 必须连接两个不同且存在的原子`);
        }
      }
      const domains = Array.isArray(rawObject.electronDomains) ? rawObject.electronDomains : [];
      for (const [domainIndex, rawDomain] of domains.entries()) {
        const domainPath = `${objectPath}.electronDomains[${domainIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawDomain,
          ["id", "kind", "atom", "label", "direction", "position", "distance", "radius", "color", "alpha"],
          domainPath,
          issue,
        )) continue;
        if (!atomIDs.has(String(rawDomain.atom))) issue(`富回答场景 ${scene.id} 的 ${domainPath}.atom 不存在`);
        if (rawDomain.direction === undefined && rawDomain.position === undefined) issue(`富回答场景 ${scene.id} 的 ${domainPath} 必须提供 direction 或 position`);
        if (rawDomain.direction !== undefined) richAnswerValidateVector3(scene, rawDomain.direction, `${domainPath}.direction`, issue);
        if (rawDomain.position !== undefined) richAnswerValidateVector3(scene, rawDomain.position, `${domainPath}.position`, issue);
      }
      const markers = Array.isArray(rawObject.angleMarkers) ? rawObject.angleMarkers : [];
      for (const [markerIndex, rawMarker] of markers.entries()) {
        const markerPath = `${objectPath}.angleMarkers[${markerIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawMarker,
          ["id", "from", "via", "to", "degrees", "label", "color"],
          markerPath,
          issue,
        )) continue;
        const refs = [rawMarker.from, rawMarker.via, rawMarker.to].map(String);
        if (new Set(refs).size !== 3 || refs.some((atomID) => !atomIDs.has(atomID))) {
          issue(`富回答场景 ${scene.id} 的 ${markerPath} 必须引用三个不同且存在的原子`);
        }
      }
      dataPointCount += atoms.length + bonds.length * 2 + domains.length + markers.length * 3;
    }
  }
  let totalObjectCount = objects.length;
  if (validateStateCollections) {
    const stateBinding = spec.stateBinding;
    if (states.length > 12) issue(`富回答场景 ${scene.id} 的 spec.states 最多支持 12 个状态`);
    if (states.length > 0 && !isRecord(stateBinding)) {
      issue(`富回答场景 ${scene.id} 的 spec.states 存在时必须提交 stateBinding`);
    } else if (states.length === 0 && stateBinding !== undefined) {
      issue(`富回答场景 ${scene.id} 的 spec.stateBinding 不能脱离 states 单独存在`);
    } else if (isRecord(stateBinding)) {
      richAnswerValidateNestedFields(scene, stateBinding, ["initial", "control", "label"], "spec.stateBinding", issue);
      richAnswerValidateIdentifier(scene, stateBinding.initial, "spec.stateBinding.initial", issue);
      if (stateBinding.control !== undefined && !["segmented", "slider"].includes(String(stateBinding.control))) {
        issue(`富回答场景 ${scene.id} 的 spec.stateBinding.control 只能是 segmented 或 slider`);
      }
      if (stateBinding.label !== undefined && (typeof stateBinding.label !== "string" || stateBinding.label.trim().length === 0)) {
        issue(`富回答场景 ${scene.id} 的 spec.stateBinding.label 必须是非空文本`);
      }
    }

    const stateIDs = new Set<string>();
    const sceneEvidenceIDs = new Set(scene.evidenceIDs);
    const validateStateEvidenceIDs = (value: unknown, path: string, maximum: number): void => {
      const evidenceIDs = value === undefined ? [] : richAnswerRenderPlanStringArray(value);
      if (evidenceIDs === undefined) {
        issue(`富回答场景 ${scene.id} 的 ${path} 必须是证据 id 数组`);
        return;
      }
      if (evidenceIDs.length > maximum) issue(`富回答场景 ${scene.id} 的 ${path} 最多包含 ${maximum} 个证据 id`);
      for (const evidenceID of evidenceIDs) {
        if (!allowedEvidenceIDs.has(evidenceID)) issue(`富回答场景 ${scene.id} 的 ${path} 引用了不存在的证据：${evidenceID}`);
        if (!sceneEvidenceIDs.has(evidenceID)) issue(`富回答场景 ${scene.id} 的 ${path} 必须引用 scene.evidenceIDs 中的证据：${evidenceID}`);
      }
    };

    for (const [stateIndex, rawState] of states.entries()) {
      const statePath = `spec.states[${stateIndex}]`;
      if (!richAnswerValidateNestedFields(
        scene,
        rawState,
        ["id", "title", "description", "objectIds", "objects", "readouts", "evidenceIDs"],
        statePath,
        issue,
      )) continue;
      if (richAnswerValidateIdentifier(scene, rawState.id, `${statePath}.id`, issue)) {
        if (stateIDs.has(rawState.id)) issue(`富回答场景 ${scene.id} 的三维状态 id 重复：${rawState.id}`);
        stateIDs.add(rawState.id);
      }
      const objectRefs = rawState.objectIds === undefined ? [] : richAnswerRenderPlanStringArray(rawState.objectIds);
      if (objectRefs === undefined) {
        issue(`富回答场景 ${scene.id} 的 ${statePath}.objectIds 必须是对象 id 数组`);
      } else {
        objectRefs.forEach((objectID) => {
          if (!objectIDs.has(objectID)) issue(`富回答场景 ${scene.id} 的 ${statePath}.objectIds 引用了不存在的共享对象：${objectID}`);
        });
      }

      const stateObjects = Array.isArray(rawState.objects) ? rawState.objects : [];
      if (rawState.objects !== undefined && !Array.isArray(rawState.objects)) issue(`富回答场景 ${scene.id} 的 ${statePath}.objects 必须是数组`);
      totalObjectCount += stateObjects.length;
      for (const [stateObjectIndex, rawStateObject] of stateObjects.entries()) {
        if (!isRecord(rawStateObject)) continue;
        const stateObjectPath = `${statePath}.objects[${stateObjectIndex}]`;
        if (richAnswerValidateIdentifier(scene, rawStateObject.id, `${stateObjectPath}.id`, issue)) {
          if (objectIDs.has(rawStateObject.id)) issue(`富回答场景 ${scene.id} 的三维对象 id 重复：${rawStateObject.id}`);
          objectIDs.add(rawStateObject.id);
        }
      }
      if (stateObjects.length > 0) {
        dataPointCount += validateRichAnswerScene3DSpec(
          scene,
          {
            title: rawState.title ?? spec.title,
            camera: spec.camera,
            layers: spec.layers ?? [],
            objects: stateObjects,
            coordinateUnits: spec.coordinateUnits,
            bounds: spec.bounds,
            slices: [],
            controls: spec.controls,
            focusEnabled: spec.focusEnabled,
          },
          registration,
          allowedEvidenceIDs,
          issue,
          false,
        );
      }

      const readouts = Array.isArray(rawState.readouts) ? rawState.readouts : [];
      if (rawState.readouts !== undefined && !Array.isArray(rawState.readouts)) issue(`富回答场景 ${scene.id} 的 ${statePath}.readouts 必须是数组`);
      if (readouts.length > 12) issue(`富回答场景 ${scene.id} 的 ${statePath}.readouts 最多支持 12 项`);
      const readoutIDs = new Set<string>();
      for (const [readoutIndex, rawReadout] of readouts.entries()) {
        const readoutPath = `${statePath}.readouts[${readoutIndex}]`;
        if (!richAnswerValidateNestedFields(scene, rawReadout, ["id", "label", "value", "unit", "evidenceIDs"], readoutPath, issue)) continue;
        if (richAnswerValidateIdentifier(scene, rawReadout.id, `${readoutPath}.id`, issue)) {
          if (readoutIDs.has(rawReadout.id)) issue(`富回答场景 ${scene.id} 的状态读数 id 重复：${rawReadout.id}`);
          readoutIDs.add(rawReadout.id);
        }
        if (typeof rawReadout.label !== "string" || rawReadout.label.trim().length === 0) issue(`富回答场景 ${scene.id} 的 ${readoutPath}.label 必须是非空文本`);
        if (!richAnswerRenderPlanFiniteNumber(rawReadout.value) && (typeof rawReadout.value !== "string" || rawReadout.value.trim().length === 0)) {
          issue(`富回答场景 ${scene.id} 的 ${readoutPath}.value 必须是有限数字或非空文本`);
        }
        validateStateEvidenceIDs(rawReadout.evidenceIDs, `${readoutPath}.evidenceIDs`, 8);
      }
      validateStateEvidenceIDs(rawState.evidenceIDs, `${statePath}.evidenceIDs`, 12);
    }

    if (isRecord(stateBinding) && typeof stateBinding.initial === "string" && !stateIDs.has(stateBinding.initial)) {
      issue(`富回答场景 ${scene.id} 的 spec.stateBinding.initial 引用了不存在的状态：${stateBinding.initial}`);
    }
    if (totalObjectCount === 0) {
      issue(`富回答场景 ${scene.id} 至少需要一个共享对象或状态对象`);
    }
    if (totalObjectCount > registration.budgets.maxNodes) {
      issue(`富回答场景 ${scene.id} 的三维对象总数超出预算：${totalObjectCount}/${registration.budgets.maxNodes}`);
    }
  }
  const slices = Array.isArray(spec.slices) ? spec.slices : [];
  if (spec.slices !== undefined && !Array.isArray(spec.slices)) issue(`富回答场景 ${scene.id} 的 spec.slices 必须是数组`);
  for (const [sliceIndex, rawSlice] of slices.entries()) {
    const slicePath = `spec.slices[${sliceIndex}]`;
    if (!richAnswerValidateNestedFields(scene, rawSlice, ["axis", "value", "thickness", "label", "color"], slicePath, issue)) continue;
    if (!["x", "y", "z"].includes(String(rawSlice.axis)) || !richAnswerRenderPlanFiniteNumber(rawSlice.value)) {
      issue(`富回答场景 ${scene.id} 的 ${slicePath} 轴或数值无效`);
    }
  }
  if (dataPointCount > registration.budgets.maxDataPoints) {
    issue(`富回答场景 ${scene.id} 的三维数据点超出预算：${dataPointCount}/${registration.budgets.maxDataPoints}`);
  }
  return dataPointCount;
}


export function validateRichAnswerRenderPlan(
  scene: RichAnswerSceneParam,
  allowedEvidenceIDs: ReadonlySet<string>,
  allowedAssetIDs: ReadonlySet<string>,
  catalogRendererSelection: ReadonlySet<string> | undefined,
): number {
  const plan = scene.renderPlan;
  const validationIssues: string[] = [];
  const issue = (message: string): void => {
    if (!validationIssues.includes(message) && validationIssues.length < 24) {
      validationIssues.push(message);
    }
  };

  if (!plan || !isRecord(plan)) {
    throw new Error(`富回答场景 ${scene.id} 缺少 renderPlan 对象`);
  }

  const unknownPlanFields = richAnswerRenderPlanUnknownFields(plan, RICH_ANSWER_RENDER_PLAN_FIELDS);
  if (unknownPlanFields.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 renderPlan 只能包含 ${rendererFieldList(RICH_ANSWER_RENDER_PLAN_FIELDS)}，不能包含 ${unknownPlanFields.join("、")}`,
    );
  }

  const renderer = plan.renderer;
  const registration = typeof renderer === "string"
    ? RICH_ANSWER_RENDERER_REGISTRATION_BY_ID.get(renderer)
    : undefined;
  if (typeof renderer !== "string" || renderer.trim().length === 0) {
    issue(`富回答场景 ${scene.id} 的 renderPlan.renderer 不能为空`);
  } else if (registration === undefined) {
    issue(`富回答场景 ${scene.id} 的 renderer 未注册：${renderer}`);
  } else if (!catalogRendererSelection?.has(renderer)) {
    issue(`富回答场景 ${scene.id} 的 renderer ${renderer} 不是本轮 ${RICH_ANSWER_CATALOG_TOOL} 返回的能力`);
  }

  if (registration !== undefined && plan.specVersion !== registration.specVersion) {
    issue(
      `富回答场景 ${scene.id} 的 specVersion 必须是 ${registration.specVersion}，当前为 ${String(plan.specVersion)}`,
    );
  }

  if (richAnswerRenderPlanContainsUnsafeText(plan)) {
    issue(`富回答场景 ${scene.id} 的 renderPlan 含脚本、网页、外链或事件处理文本；只能提交本地高层 JSON`);
  }

  const spec = isRecord(plan.spec) ? plan.spec : undefined;
  if (spec === undefined) {
    issue(`富回答场景 ${scene.id} 的 renderPlan.spec 必须是对象`);
  }
  let dataPointCount = 0;
  if (spec !== undefined && registration !== undefined) {
    switch (registration.validatorKind) {
      case "mathFunction":
        dataPointCount = validateRichAnswerMathFunctionSpec(scene, spec, registration, issue);
        break;
      case "chart":
        dataPointCount = validateRichAnswerChartSpec(scene, spec, registration, issue);
        break;
      case "geometry2D":
        dataPointCount = validateRichAnswerGeometry2DSpec(scene, spec, registration, issue);
        break;
      case "scene3D":
        dataPointCount = validateRichAnswerScene3DSpec(scene, spec, registration, allowedEvidenceIDs, issue);
        break;
      case "spatialMap":
        dataPointCount = validateRichAnswerSpatialMapSpec(scene, spec, registration, allowedAssetIDs, issue);
        break;
      case "imageOverlay":
        dataPointCount = validateRichAnswerImageOverlaySpec(scene, spec, registration, allowedAssetIDs, issue);
        break;
    }
  }

  const interactionBindings = Array.isArray(plan.interactionBindings)
    ? plan.interactionBindings
    : [];
  if (!Array.isArray(plan.interactionBindings)) {
    issue(`富回答场景 ${scene.id} 的 interactionBindings 必须是数组`);
  }
  const interactionIDs = new Set<string>();
  for (const [bindingIndex, binding] of interactionBindings.entries()) {
    if (!isRecord(binding)) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}] 必须是对象`);
      continue;
    }
    const unknownBindingFields = richAnswerRenderPlanUnknownFields(
      binding,
      RICH_ANSWER_RENDER_INTERACTION_FIELDS,
    );
    if (unknownBindingFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}] 包含未知字段：${unknownBindingFields.join("、")}`,
      );
    }
    if (!richAnswerRenderPlanValidIdentifier(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].id 无效`);
    } else if (interactionIDs.has(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 interactionBinding id 重复：${binding.id}`);
    } else {
      interactionIDs.add(binding.id);
    }
    if (typeof binding.kind !== "string" || !RICH_ANSWER_RENDER_INTERACTION_KINDS.has(binding.kind)) {
      issue(
        `富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].kind 必须是 ${rendererFieldList(RICH_ANSWER_RENDER_INTERACTION_KINDS)} 之一`,
      );
    } else if (
      registration !== undefined &&
      !registration.interactionBindingKinds.includes(binding.kind)
    ) {
      issue(
        `富回答场景 ${scene.id} 的 renderer ${registration.id} 只接受 interactionBindings.kind=${registration.interactionBindingKinds.join("、")}；当前 ${binding.kind} 不受支持`,
      );
    }
    if (typeof binding.target !== "string" || binding.target.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].target 不能为空`);
    }
    if (
      binding.actionName !== undefined &&
      (typeof binding.actionName !== "string" || !richAnswerRenderPlanValidActionName(binding.actionName))
    ) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].actionName 只能是本地动作名，不得是代码或 URL`);
    }
  }

  const sourceBindings = Array.isArray(plan.sourceBindings) ? plan.sourceBindings : [];
  if (!Array.isArray(plan.sourceBindings)) {
    issue(`富回答场景 ${scene.id} 的 sourceBindings 必须是数组`);
  }
  const sceneEvidenceIDs = new Set(scene.evidenceIDs);
  const specEvidenceIDs = richAnswerRenderPlanSpecEvidenceIDs(spec);
  for (const evidenceID of specEvidenceIDs) {
    if (!allowedEvidenceIDs.has(evidenceID)) {
      issue(`富回答场景 ${scene.id} 的 renderPlan.spec 引用了不存在的证据：${evidenceID}`);
    }
    if (!sceneEvidenceIDs.has(evidenceID)) {
      issue(`富回答场景 ${scene.id} 的 renderPlan.spec evidenceID 必须列入 scene.evidenceIDs：${evidenceID}`);
    }
  }
  if (sceneEvidenceIDs.size !== scene.evidenceIDs.length) {
    issue(`富回答场景 ${scene.id} 的 scene.evidenceIDs 不能重复`);
  }
  const sourceBindingIDs = new Set<string>();
  const boundSceneEvidenceIDs = new Set<string>();
  const requiresSourcePreservingFallback = sourceBindings.some((binding) =>
    isRecord(binding) && binding.requiredForFallback === true
  );
  for (const [bindingIndex, binding] of sourceBindings.entries()) {
    if (!isRecord(binding)) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}] 必须是对象`);
      continue;
    }
    const unknownBindingFields = richAnswerRenderPlanUnknownFields(
      binding,
      RICH_ANSWER_RENDER_SOURCE_BINDING_FIELDS,
    );
    if (unknownBindingFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}] 包含未知字段：${unknownBindingFields.join("、")}`,
      );
    }
    if (!richAnswerRenderPlanValidIdentifier(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].id 无效`);
    } else if (sourceBindingIDs.has(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 sourceBinding id 重复：${binding.id}`);
    } else {
      sourceBindingIDs.add(binding.id);
    }
    if (!richAnswerRenderPlanValidIdentifier(binding.evidenceID)) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].evidenceID 无效`);
    } else {
      if (!allowedEvidenceIDs.has(binding.evidenceID)) {
        issue(`富回答场景 ${scene.id} 的 sourceBinding 引用了不存在的证据：${binding.evidenceID}`);
      }
      if (!sceneEvidenceIDs.has(binding.evidenceID)) {
        issue(`富回答场景 ${scene.id} 的 sourceBinding 证据必须同时列入 scene.evidenceIDs：${binding.evidenceID}`);
      } else {
        boundSceneEvidenceIDs.add(binding.evidenceID);
      }
    }
    if (typeof binding.target !== "string" || binding.target.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].target 不能为空`);
    }
    if (typeof binding.role !== "string" || !RICH_ANSWER_RENDER_SOURCE_BINDING_ROLES.has(binding.role)) {
      issue(
        `富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].role 必须是 ${rendererFieldList(RICH_ANSWER_RENDER_SOURCE_BINDING_ROLES)} 之一`,
      );
    }
  }
  const missingSourceBindings = scene.evidenceIDs.filter((evidenceID) => !boundSceneEvidenceIDs.has(evidenceID));
  if (missingSourceBindings.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 scene.evidenceIDs 没有被 sourceBindings 覆盖：${missingSourceBindings.join("、")}`,
    );
  }

  const artifactRefs = Array.isArray(plan.artifactRefs) ? plan.artifactRefs : [];
  if (!Array.isArray(plan.artifactRefs)) {
    issue(`富回答场景 ${scene.id} 的 artifactRefs 必须是数组`);
  }
  const artifactIDs = new Set<string>();
  for (const [artifactIndex, artifact] of artifactRefs.entries()) {
    if (!isRecord(artifact)) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}] 必须是对象`);
      continue;
    }
    const unknownArtifactFields = richAnswerRenderPlanUnknownFields(
      artifact,
      RICH_ANSWER_RENDER_ARTIFACT_FIELDS,
    );
    if (unknownArtifactFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}] 包含未知字段：${unknownArtifactFields.join("、")}`,
      );
    }
    if (!richAnswerRenderPlanValidIdentifier(artifact.id)) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].id 无效`);
    } else if (artifactIDs.has(artifact.id)) {
      issue(`富回答场景 ${scene.id} 的 artifactRef id 重复：${artifact.id}`);
    } else {
      artifactIDs.add(artifact.id);
    }
    if (typeof artifact.mimeType !== "string" || artifact.mimeType.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].mimeType 不能为空`);
    }
    if (typeof artifact.role !== "string" || artifact.role.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].role 不能为空`);
    }
    if (typeof artifact.kind !== "string" || !RICH_ANSWER_RENDER_ARTIFACT_KINDS.has(artifact.kind)) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].kind 无效`);
    }
    if (
      artifact.checksum !== undefined &&
      (typeof artifact.checksum !== "string" || !/^[0-9a-f]{64}$/i.test(artifact.checksum))
    ) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].checksum 必须是 64 位 sha256`);
    }
  }
  if (registration !== undefined && artifactRefs.length > registration.budgets.maxArtifacts) {
    issue(
      `富回答场景 ${scene.id} 的 artifactRefs 超出预算：${artifactRefs.length}/${registration.budgets.maxArtifacts}`,
    );
  }

  const fallback = isRecord(plan.fallback) ? plan.fallback : undefined;
  if (fallback === undefined) {
    issue(`富回答场景 ${scene.id} 的 fallback 必须是对象`);
  } else {
    const unknownFallbackFields = richAnswerRenderPlanUnknownFields(
      fallback,
      RICH_ANSWER_RENDER_FALLBACK_FIELDS,
    );
    if (unknownFallbackFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 fallback 包含未知字段：${unknownFallbackFields.join("、")}`,
      );
    }
    if (typeof fallback.mode !== "string" || !RICH_ANSWER_RENDER_FALLBACK_MODES.has(fallback.mode)) {
      issue(
        `富回答场景 ${scene.id} 的 fallback.mode 必须是 ${rendererFieldList(RICH_ANSWER_RENDER_FALLBACK_MODES)} 之一`,
      );
    }
    if (typeof fallback.reason !== "string" || fallback.reason.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 fallback.reason 不能为空`);
    }
    if (typeof fallback.text !== "string" || fallback.text.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 fallback.text 不能为空`);
    }
    if (
      fallback.renderer !== undefined &&
      (typeof fallback.renderer !== "string" ||
        !RICH_ANSWER_RENDERER_REGISTRATION_BY_ID.has(fallback.renderer))
    ) {
      issue(`富回答场景 ${scene.id} 的 fallback.renderer 必须是已注册 renderer`);
    }
    if (
      fallback.artifactID !== undefined &&
      (typeof fallback.artifactID !== "string" || !artifactIDs.has(fallback.artifactID))
    ) {
      issue(`富回答场景 ${scene.id} 的 fallback.artifactID 必须来自 artifactRefs`);
    }
    if (requiresSourcePreservingFallback && fallback.preservesSourceBinding !== true) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings 要求 fallback 保留来源绑定，fallback.preservesSourceBinding 必须为 true`);
    }
  }

  const qualityBudget = isRecord(plan.qualityBudget) ? plan.qualityBudget : undefined;
  if (qualityBudget === undefined) {
    issue(`富回答场景 ${scene.id} 的 qualityBudget 必须是对象`);
  } else {
    const unknownBudgetFields = richAnswerRenderPlanUnknownFields(
      qualityBudget,
      RICH_ANSWER_RENDER_QUALITY_BUDGET_FIELDS,
    );
    if (unknownBudgetFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget 包含未知字段：${unknownBudgetFields.join("、")}`,
      );
    }
    if (typeof qualityBudget.allowAnimation !== "boolean") {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.allowAnimation 必须是布尔值`);
    }
    if (qualityBudget.allowWebGL !== false) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.allowWebGL 必须为 false`);
    }
    if (qualityBudget.allowNetwork !== false) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.allowNetwork 必须为 false`);
    }
    const estimatedNodes = spec === undefined
      ? 1 + interactionBindings.length + sourceBindings.length
      : richAnswerRenderPlanEstimatedNodes(spec, interactionBindings.length, sourceBindings.length);
    if (
      qualityBudget.maxNodes !== undefined &&
      (!richAnswerRenderPlanIntegerInRange(qualityBudget.maxNodes, estimatedNodes, registration?.budgets.maxNodes ?? LIMITS.richAnswerRenderPlanNodes))
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxNodes 必须覆盖估算节点数 ${estimatedNodes}，且不超过 ${registration?.budgets.maxNodes ?? LIMITS.richAnswerRenderPlanNodes}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxDataPoints !== undefined &&
      !richAnswerRenderPlanIntegerInRange(
        qualityBudget.maxDataPoints,
        dataPointCount,
        registration.budgets.maxDataPoints,
      )
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxDataPoints 必须覆盖实际数据点 ${dataPointCount}，且不超过 ${registration.budgets.maxDataPoints}`,
      );
    }
    if (
      registration !== undefined &&
      qualityBudget.maxArtifacts !== undefined &&
      !richAnswerRenderPlanIntegerInRange(
        qualityBudget.maxArtifacts,
        artifactRefs.length,
        registration.budgets.maxArtifacts,
      )
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxArtifacts 必须覆盖 artifactRefs 数量 ${artifactRefs.length}，且不超过 ${registration.budgets.maxArtifacts}`,
      );
    }
    const byteLength = richAnswerRenderPlanByteLength(plan);
    if (
      registration !== undefined &&
      qualityBudget.maxBytes !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxBytes, byteLength, registration.budgets.maxBytes)
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxBytes 必须覆盖 renderPlan ${byteLength} bytes，且不超过 ${registration.budgets.maxBytes}`,
      );
    }
    if (registration !== undefined && byteLength > registration.budgets.maxBytes) {
      issue(
        `富回答场景 ${scene.id} 的 renderPlan 超出字节预算：${byteLength}/${registration.budgets.maxBytes}`,
      );
    }
    if (
      registration !== undefined &&
      qualityBudget.maxWidth !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxWidth, 240, registration.budgets.maxWidth)
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxWidth 超出 renderer 上限 ${registration.budgets.maxWidth}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxHeight !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxHeight, 160, registration.budgets.maxHeight)
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxHeight 超出 renderer 上限 ${registration.budgets.maxHeight}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxAnimationFPS !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxAnimationFPS, 0, registration.budgets.maxAnimationFPS)
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxAnimationFPS 超出 renderer 上限 ${registration.budgets.maxAnimationFPS}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxInteractionLatencyMS !== undefined &&
      !richAnswerRenderPlanIntegerInRange(
        qualityBudget.maxInteractionLatencyMS,
        1,
        registration.budgets.maxInteractionLatencyMS,
      )
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxInteractionLatencyMS 超出 renderer 上限 ${registration.budgets.maxInteractionLatencyMS}`,
      );
    }
  }

  if (validationIssues.length > 0) {
    throw new Error(validationIssues.join("\n"));
  }
  return interactionBindings.length > 0 ? 1 : 0;
}