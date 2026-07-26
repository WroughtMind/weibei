import { isRecord } from "./agent-context";
import { RichAnswerRendererRegistration } from "./rich-answer-catalog";
import {
  RichAnswerSceneParam,
  richAnswerRenderPlanIntegerInRange,
  richAnswerRenderPlanValidIdentifier,
} from "./rich-answer-validation-models";
import {
  richAnswerRenderPlanControlValue,
  richAnswerRenderPlanFiniteNumber,
  richAnswerValidateNestedFields,
  validateRichAnswerGenericRenderSpec,
} from "./rich-answer-chart-validation";


export function richAnswerValidateIdentifier(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
): value is string {
  if (!richAnswerRenderPlanValidIdentifier(value)) {
    issue(`富回答场景 ${scene.id} 的 ${path} 必须是非空 id`);
    return false;
  }
  return true;
}


export function richAnswerValidateCoordinate2D(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
  normalized = false,
): value is Record<string, unknown> {
  if (!richAnswerValidateNestedFields(scene, value, ["x", "y"], path, issue)) return false;
  if (!richAnswerRenderPlanFiniteNumber(value.x) || !richAnswerRenderPlanFiniteNumber(value.y)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.x/y 必须是有限数字`);
    return false;
  }
  if (normalized && (value.x < 0 || value.x > 1 || value.y < 0 || value.y > 1)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.x/y 必须落在 0–1`);
    return false;
  }
  return true;
}


export function richAnswerValidateVector3(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
): value is [number, number, number] {
  if (
    !Array.isArray(value) ||
    value.length !== 3 ||
    !value.every(richAnswerRenderPlanFiniteNumber)
  ) {
    issue(`富回答场景 ${scene.id} 的 ${path} 必须是三个有限数字组成的三维向量`);
    return false;
  }
  return true;
}


export function richAnswerValidateRange(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
): value is Record<string, unknown> {
  if (!richAnswerValidateNestedFields(scene, value, ["min", "max"], path, issue)) return false;
  if (
    !richAnswerRenderPlanFiniteNumber(value.min) ||
    !richAnswerRenderPlanFiniteNumber(value.max) ||
    value.min >= value.max
  ) {
    issue(`富回答场景 ${scene.id} 的 ${path} 必须满足有限数 min < max`);
    return false;
  }
  return true;
}


export function richAnswerValidateStyle(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
  fields: readonly string[],
): void {
  if (value === undefined) return;
  richAnswerValidateNestedFields(scene, value, fields, path, issue);
}


export function richAnswerValidateRasterSource(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  allowedAssetIDs: ReadonlySet<string>,
  issue: (message: string) => void,
  allowNone: boolean,
): void {
  if (!richAnswerValidateNestedFields(
    scene,
    value,
    ["kind", "source", "label", "width", "height"],
    path,
    issue,
  )) return;
  const kind = value.kind;
  const allowedKinds = allowNone ? ["none", "dataUrl", "assetRef"] : ["dataUrl", "assetRef"];
  if (typeof kind !== "string" || !allowedKinds.includes(kind)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.kind 必须是 ${allowedKinds.join("、")}`);
    return;
  }
  if (kind === "none") {
    if (value.source !== undefined) {
      issue(`富回答场景 ${scene.id} 的 ${path}.kind=none 时不能提交 source`);
    }
    return;
  }
  const source = typeof value.source === "string" ? value.source.trim() : "";
  if (!source) {
    issue(`富回答场景 ${scene.id} 的 ${path}.source 不能为空`);
    return;
  }
  if (kind === "assetRef") {
    if (!allowedAssetIDs.has(source)) {
      issue(`富回答场景 ${scene.id} 的 ${path}.source 必须引用 sourceBindings.allowedAssetIDs 中的真实材料资产：${source}`);
    }
  } else if (!/^data:image\/(?:png|jpe?g|webp|gif);base64,/iu.test(source)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.source 只接受安全 raster data URL`);
  }
  for (const dimension of ["width", "height"] as const) {
    if (
      value[dimension] !== undefined &&
      (!Number.isInteger(value[dimension]) || (value[dimension] as number) < 16)
    ) {
      issue(`富回答场景 ${scene.id} 的 ${path}.${dimension} 必须是至少 16 的整数`);
    }
  }
}


export function validateRichAnswerImageOverlaySpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  allowedAssetIDs: ReadonlySet<string>,
  issue: (message: string) => void,
): number {
  const dataPointCount = validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  richAnswerValidateRasterSource(scene, spec.image, "spec.image", allowedAssetIDs, issue, false);
  if (spec.objectFit !== undefined && !["contain", "cover", "fill", "none"].includes(String(spec.objectFit))) {
    issue(`富回答场景 ${scene.id} 的 spec.objectFit 必须是 contain、cover、fill 或 none`);
  }
  if (spec.measurement !== undefined && richAnswerValidateNestedFields(
    scene,
    spec.measurement,
    ["unit", "pxPerUnit", "precision"],
    "spec.measurement",
    issue,
  )) {
    if (spec.measurement.pxPerUnit !== undefined && (!richAnswerRenderPlanFiniteNumber(spec.measurement.pxPerUnit) || spec.measurement.pxPerUnit <= 0)) {
      issue(`富回答场景 ${scene.id} 的 spec.measurement.pxPerUnit 必须大于 0`);
    }
    if (spec.measurement.precision !== undefined && !richAnswerRenderPlanIntegerInRange(spec.measurement.precision, 0, 8)) {
      issue(`富回答场景 ${scene.id} 的 spec.measurement.precision 必须是 0–8 的整数`);
    }
  }

  const layers = Array.isArray(spec.layers) ? spec.layers : [];
  if (!Array.isArray(spec.layers)) issue(`富回答场景 ${scene.id} 的 spec.layers 必须是数组`);
  const layerIDs = new Set<string>();
  let visibleFeatureCount = 0;
  for (const [layerIndex, rawLayer] of layers.entries()) {
    const layerPath = `spec.layers[${layerIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawLayer,
      ["id", "title", "visibleDefault", "features", "annotation"],
      layerPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawLayer.id, `${layerPath}.id`, issue)) {
      if (layerIDs.has(rawLayer.id)) issue(`富回答场景 ${scene.id} 的图层 id 重复：${rawLayer.id}`);
      layerIDs.add(rawLayer.id);
    }
    const features = Array.isArray(rawLayer.features) ? rawLayer.features : [];
    if (!Array.isArray(rawLayer.features) || features.length === 0) {
      issue(`富回答场景 ${scene.id} 的 ${layerPath}.features 必须是非空数组`);
    }
    const featureIDs = new Set<string>();
    for (const [featureIndex, rawFeature] of features.entries()) {
      const featurePath = `${layerPath}.features[${featureIndex}]`;
      if (!isRecord(rawFeature)) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath} 必须是对象`);
        continue;
      }
      const kind = rawFeature.kind;
      const allowedFeatureFields = kind === "point"
        ? ["id", "kind", "label", "point", "emphasis", "tone", "style", "value"]
        : kind === "line"
          ? ["id", "kind", "label", "start", "end", "points", "emphasis", "tone", "style", "value"]
          : kind === "rect"
            ? ["id", "kind", "label", "box", "emphasis", "tone", "style", "value"]
            : kind === "polygon"
              ? ["id", "kind", "label", "points", "emphasis", "tone", "style", "value"]
              : ["id", "kind"];
      richAnswerValidateNestedFields(scene, rawFeature, allowedFeatureFields, featurePath, issue);
      if (!["point", "line", "rect", "polygon"].includes(String(kind))) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.kind 只能是 point、line、rect 或 polygon`);
        continue;
      }
      if (richAnswerValidateIdentifier(scene, rawFeature.id, `${featurePath}.id`, issue)) {
        if (featureIDs.has(rawFeature.id)) issue(`富回答场景 ${scene.id} 的图形 id 重复：${rawFeature.id}`);
        featureIDs.add(rawFeature.id);
      }
      if (rawFeature.emphasis !== undefined && !["subtle", "normal", "strong"].includes(String(rawFeature.emphasis))) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.emphasis 只能是 subtle、normal 或 strong`);
      }
      if (rawFeature.tone !== undefined && !["earth", "neutral", "accent", "caution"].includes(String(rawFeature.tone))) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.tone 只能是 earth、neutral、accent 或 caution`);
      }
      if (kind === "point") {
        richAnswerValidateCoordinate2D(scene, rawFeature.point, `${featurePath}.point`, issue, true);
        visibleFeatureCount += 1;
      } else if (kind === "line") {
        const points = Array.isArray(rawFeature.points) ? rawFeature.points : [];
        const hasSegment = rawFeature.start !== undefined || rawFeature.end !== undefined;
        if (points.length > 0 && hasSegment) {
          issue(`富回答场景 ${scene.id} 的 ${featurePath} 不能同时提交 start/end 与 points`);
        } else if (points.length > 0) {
          if (points.length < 2 || points.length > 64) {
            issue(`富回答场景 ${scene.id} 的 ${featurePath}.points 必须包含 2–64 个点`);
          }
          points.forEach((point, pointIndex) => richAnswerValidateCoordinate2D(
            scene,
            point,
            `${featurePath}.points[${pointIndex}]`,
            issue,
            true,
          ));
          visibleFeatureCount += points.length;
        } else {
          richAnswerValidateCoordinate2D(scene, rawFeature.start, `${featurePath}.start`, issue, true);
          richAnswerValidateCoordinate2D(scene, rawFeature.end, `${featurePath}.end`, issue, true);
          visibleFeatureCount += 2;
        }
      } else if (kind === "rect") {
        if (richAnswerValidateNestedFields(
          scene,
          rawFeature.box,
          ["x", "y", "width", "height"],
          `${featurePath}.box`,
          issue,
        )) {
          const box = rawFeature.box;
          if (
            ![box.x, box.y, box.width, box.height].every(richAnswerRenderPlanFiniteNumber) ||
            box.x < 0 || box.y < 0 || box.width <= 0 || box.height <= 0 ||
            box.x + box.width > 1 || box.y + box.height > 1
          ) issue(`富回答场景 ${scene.id} 的 ${featurePath}.box 必须是 0–1 内的正面积矩形`);
        }
        visibleFeatureCount += 2;
      } else {
        const points = Array.isArray(rawFeature.points) ? rawFeature.points : [];
        if (points.length < 3 || points.length > 64) {
          issue(`富回答场景 ${scene.id} 的 ${featurePath}.points 必须包含 3–64 个点`);
        }
        points.forEach((point, pointIndex) => richAnswerValidateCoordinate2D(
          scene,
          point,
          `${featurePath}.points[${pointIndex}]`,
          issue,
          true,
        ));
        visibleFeatureCount += points.length;
      }
      richAnswerValidateStyle(
        scene,
        rawFeature.style,
        `${featurePath}.style`,
        issue,
        ["stroke", "strokeWidth", "fill", "opacity", "dash"],
      );
    }
  }

  const annotations = Array.isArray(spec.annotations) ? spec.annotations : [];
  if (spec.annotations !== undefined && !Array.isArray(spec.annotations)) {
    issue(`富回答场景 ${scene.id} 的 spec.annotations 必须是数组`);
  }
  for (const [annotationIndex, rawAnnotation] of annotations.entries()) {
    const annotationPath = `spec.annotations[${annotationIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawAnnotation,
      ["id", "point", "text", "color", "layer"],
      annotationPath,
      issue,
    )) continue;
    richAnswerValidateIdentifier(scene, rawAnnotation.id, `${annotationPath}.id`, issue);
    richAnswerValidateCoordinate2D(scene, rawAnnotation.point, `${annotationPath}.point`, issue, true);
    if (rawAnnotation.layer !== undefined && !layerIDs.has(String(rawAnnotation.layer))) {
      issue(`富回答场景 ${scene.id} 的 ${annotationPath}.layer 引用了不存在的图层`);
    }
  }

  if (spec.comparison !== undefined && richAnswerValidateNestedFields(
    scene,
    spec.comparison,
    ["enabled", "image", "ratio", "axis", "leftLabel", "rightLabel"],
    "spec.comparison",
    issue,
  )) {
    richAnswerValidateRasterSource(
      scene,
      spec.comparison.image,
      "spec.comparison.image",
      allowedAssetIDs,
      issue,
      false,
    );
    if (spec.comparison.ratio !== undefined && (!richAnswerRenderPlanFiniteNumber(spec.comparison.ratio) || spec.comparison.ratio < 0.1 || spec.comparison.ratio > 0.9)) {
      issue(`富回答场景 ${scene.id} 的 spec.comparison.ratio 必须在 0.1–0.9`);
    }
    if (spec.comparison.axis !== undefined && !["vertical", "horizontal"].includes(String(spec.comparison.axis))) {
      issue(`富回答场景 ${scene.id} 的 spec.comparison.axis 必须是 vertical 或 horizontal`);
    }
  }
  if (visibleFeatureCount === 0 && annotations.length === 0) {
    issue(`富回答场景 ${scene.id} 的图像叠层至少需要一个图形或批注`);
  }
  return Math.max(dataPointCount, visibleFeatureCount + annotations.length);
}


export function validateRichAnswerSpatialMapSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  allowedAssetIDs: ReadonlySet<string>,
  issue: (message: string) => void,
): number {
  validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  const coordinateMode = spec.coordinateMode;
  if (coordinateMode !== "schematic" && coordinateMode !== "geographic") {
    issue(`富回答场景 ${scene.id} 的 spec.coordinateMode 必须是 schematic 或 geographic`);
  }
  if (spec.mapAsset !== undefined) {
    richAnswerValidateRasterSource(scene, spec.mapAsset, "spec.mapAsset", allowedAssetIDs, issue, true);
  }
  if (spec.bounds !== undefined && richAnswerValidateNestedFields(
    scene,
    spec.bounds,
    ["xMin", "xMax", "yMin", "yMax"],
    "spec.bounds",
    issue,
  )) {
    const bounds = spec.bounds;
    if (
      ![bounds.xMin, bounds.xMax, bounds.yMin, bounds.yMax].every(richAnswerRenderPlanFiniteNumber) ||
      bounds.xMin >= bounds.xMax || bounds.yMin >= bounds.yMax
    ) issue(`富回答场景 ${scene.id} 的 spec.bounds 必须满足有限数 xMin<xMax、yMin<yMax`);
  }
  if (spec.scaleBar !== undefined) {
    richAnswerValidateNestedFields(
      scene,
      spec.scaleBar,
      ["enabled", "label", "targetPixels"],
      "spec.scaleBar",
      issue,
    );
  }
  if (spec.controls !== undefined) {
    richAnswerValidateNestedFields(
      scene,
      spec.controls,
      ["allowPan", "allowZoom", "allowLayerToggle", "allowReset", "probeEnabled"],
      "spec.controls",
      issue,
    );
  }
  const layers = Array.isArray(spec.layers) ? spec.layers : [];
  if (spec.layers !== undefined && !Array.isArray(spec.layers)) issue(`富回答场景 ${scene.id} 的 spec.layers 必须是数组`);
  const layerIDs = new Set<string>();
  for (const [layerIndex, rawLayer] of layers.entries()) {
    const layerPath = `spec.layers[${layerIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawLayer,
      ["id", "title", "visibleDefault", "note"],
      layerPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawLayer.id, `${layerPath}.id`, issue)) {
      if (layerIDs.has(rawLayer.id)) issue(`富回答场景 ${scene.id} 的地图图层 id 重复：${rawLayer.id}`);
      layerIDs.add(rawLayer.id);
    }
  }
  const features = Array.isArray(spec.features) ? spec.features : [];
  if (!Array.isArray(spec.features) || features.length === 0) {
    issue(`富回答场景 ${scene.id} 的 spec.features 必须是非空数组`);
  }
  const featureIDs = new Set<string>();
  const geometryIDs = new Set<string>();
  let pointCount = 0;
  for (const [featureIndex, rawFeature] of features.entries()) {
    const featurePath = `spec.features[${featureIndex}]`;
    if (!isRecord(rawFeature)) {
      issue(`富回答场景 ${scene.id} 的 ${featurePath} 必须是对象`);
      continue;
    }
    const kind = rawFeature.kind;
    const commonFields = ["id", "kind", "layer", "visibilityGroup", "visible", "label", "style", "value"];
    const allowedFields = kind === "point"
      ? [...commonFields, "x", "y", "radius"]
      : kind === "line"
        ? [...commonFields, "points", "closed"]
        : kind === "polygon"
          ? [...commonFields, "points", "fillMode"]
          : kind === "label"
            ? ["id", "kind", "x", "y", "text", "layer", "visibilityGroup", "bindTo", "visible", "style"]
            : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawFeature, allowedFields, featurePath, issue);
    if (!["point", "line", "polygon", "label"].includes(String(kind))) {
      issue(`富回答场景 ${scene.id} 的 ${featurePath}.kind 只能是 point、line、polygon 或 label`);
      continue;
    }
    if (richAnswerValidateIdentifier(scene, rawFeature.id, `${featurePath}.id`, issue)) {
      if (featureIDs.has(rawFeature.id)) issue(`富回答场景 ${scene.id} 的地图元素 id 重复：${rawFeature.id}`);
      featureIDs.add(rawFeature.id);
      if (kind !== "label") geometryIDs.add(rawFeature.id);
    }
    if (rawFeature.layer !== undefined && !layerIDs.has(String(rawFeature.layer))) {
      issue(`富回答场景 ${scene.id} 的 ${featurePath}.layer 引用了不存在的图层`);
    }
    if (kind === "point" || kind === "label") {
      if (!richAnswerRenderPlanFiniteNumber(rawFeature.x) || !richAnswerRenderPlanFiniteNumber(rawFeature.y)) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.x/y 必须是有限数字`);
      } else if (
        coordinateMode === "geographic" &&
        (rawFeature.x < -180 || rawFeature.x > 180 || rawFeature.y < -90 || rawFeature.y > 90)
      ) issue(`富回答场景 ${scene.id} 的 ${featurePath} 经纬度越界`);
      pointCount += 1;
    } else {
      const points = Array.isArray(rawFeature.points) ? rawFeature.points : [];
      const minimum = kind === "polygon" ? 3 : 2;
      if (points.length < minimum) issue(`富回答场景 ${scene.id} 的 ${featurePath}.points 至少需要 ${minimum} 个点`);
      points.forEach((point, pointIndex) => {
        if (richAnswerValidateCoordinate2D(scene, point, `${featurePath}.points[${pointIndex}]`, issue) && coordinateMode === "geographic") {
          if (point.x < -180 || point.x > 180 || point.y < -90 || point.y > 90) {
            issue(`富回答场景 ${scene.id} 的 ${featurePath}.points[${pointIndex}] 经纬度越界`);
          }
        }
      });
      pointCount += points.length;
    }
    richAnswerValidateStyle(
      scene,
      rawFeature.style,
      `${featurePath}.style`,
      issue,
      kind === "label"
        ? ["color", "size", "weight", "shadow"]
        : ["stroke", "strokeWidth", "fill", "opacity", "dash"],
    );
  }
  for (const [featureIndex, rawFeature] of features.entries()) {
    if (isRecord(rawFeature) && rawFeature.kind === "label" && rawFeature.bindTo !== undefined && !geometryIDs.has(String(rawFeature.bindTo))) {
      issue(`富回答场景 ${scene.id} 的 spec.features[${featureIndex}].bindTo 引用了不存在的图形`);
    }
  }
  if (pointCount > registration.budgets.maxDataPoints) {
    issue(`富回答场景 ${scene.id} 的地图数据点超出预算：${pointCount}/${registration.budgets.maxDataPoints}`);
  }
  return pointCount;
}


export function validateRichAnswerGeometry2DSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  issue: (message: string) => void,
): number {
  validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  if (!richAnswerValidateNestedFields(
    scene,
    spec.coordinateSpace,
    ["xMin", "xMax", "yMin", "yMax", "preserveAspectRatio", "gridStep"],
    "spec.coordinateSpace",
    issue,
  )) return 0;
  const coordinateSpace = spec.coordinateSpace;
  if (
    ![coordinateSpace.xMin, coordinateSpace.xMax, coordinateSpace.yMin, coordinateSpace.yMax].every(richAnswerRenderPlanFiniteNumber) ||
    coordinateSpace.xMin >= coordinateSpace.xMax || coordinateSpace.yMin >= coordinateSpace.yMax
  ) issue(`富回答场景 ${scene.id} 的 spec.coordinateSpace 范围无效`);

  const points = Array.isArray(spec.points) ? spec.points : [];
  if (!Array.isArray(spec.points) || points.length === 0) issue(`富回答场景 ${scene.id} 的 spec.points 必须是非空数组`);
  const pointIDs = new Set<string>();
  let dataPointCount = points.length;
  for (const [pointIndex, rawPoint] of points.entries()) {
    const pointPath = `spec.points[${pointIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawPoint,
      ["id", "label", "x", "y", "draggable", "constraint", "style"],
      pointPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawPoint.id, `${pointPath}.id`, issue)) {
      if (pointIDs.has(rawPoint.id)) issue(`富回答场景 ${scene.id} 的点 id 重复：${rawPoint.id}`);
      pointIDs.add(rawPoint.id);
    }
    if (!richAnswerRenderPlanFiniteNumber(rawPoint.x) || !richAnswerRenderPlanFiniteNumber(rawPoint.y)) {
      issue(`富回答场景 ${scene.id} 的 ${pointPath}.x/y 必须是有限数字`);
    }
    richAnswerValidateStyle(scene, rawPoint.style, `${pointPath}.style`, issue, ["stroke", "fill", "radius"]);
    if (rawPoint.constraint !== undefined && isRecord(rawPoint.constraint)) {
      const constraint = rawPoint.constraint;
      const fields = constraint.kind === "free"
        ? ["kind"]
        : constraint.kind === "axis"
          ? ["kind", "axis", "value", "showTrack"]
          : constraint.kind === "lineSegment"
            ? ["kind", "start", "end", "showTrack"]
            : constraint.kind === "circle"
              ? ["kind", "center", "radius", "showTrack"]
              : constraint.kind === "roundedBoxTrack"
                ? ["kind", "box", "cornerRadius", "showTrack"]
                : ["kind"];
      richAnswerValidateNestedFields(scene, constraint, fields, `${pointPath}.constraint`, issue);
      if (!["free", "axis", "lineSegment", "circle", "roundedBoxTrack"].includes(String(constraint.kind))) {
        issue(`富回答场景 ${scene.id} 的 ${pointPath}.constraint.kind 无效`);
      }
      if (constraint.kind === "lineSegment") {
        richAnswerValidateCoordinate2D(scene, constraint.start, `${pointPath}.constraint.start`, issue);
        richAnswerValidateCoordinate2D(scene, constraint.end, `${pointPath}.constraint.end`, issue);
      } else if (constraint.kind === "circle") {
        richAnswerValidateCoordinate2D(scene, constraint.center, `${pointPath}.constraint.center`, issue);
      }
    } else if (rawPoint.constraint !== undefined) {
      issue(`富回答场景 ${scene.id} 的 ${pointPath}.constraint 必须是对象`);
    }
  }

  const shapes = Array.isArray(spec.shapes) ? spec.shapes : [];
  if (spec.shapes !== undefined && !Array.isArray(spec.shapes)) issue(`富回答场景 ${scene.id} 的 spec.shapes 必须是数组`);
  const shapeIDs = new Set<string>();
  const visibilityControlRefs: Array<{ path: string; controlID: string }> = [];
  const validateVisibility = (value: unknown, path: string) => {
    if (value === undefined) return;
    if (!richAnswerValidateNestedFields(scene, value, ["controlID", "equals"], path, issue)) return;
    if (richAnswerValidateIdentifier(scene, value.controlID, `${path}.controlID`, issue)) {
      visibilityControlRefs.push({ path, controlID: value.controlID });
    }
    if (!richAnswerRenderPlanControlValue(value.equals)) {
      issue(`富回答场景 ${scene.id} 的 ${path}.equals 必须是有限数字或短状态值`);
    }
  };
  for (const [shapeIndex, rawShape] of shapes.entries()) {
    const shapePath = `spec.shapes[${shapeIndex}]`;
    if (!isRecord(rawShape)) {
      issue(`富回答场景 ${scene.id} 的 ${shapePath} 必须是对象`);
      continue;
    }
    const kind = rawShape.kind;
    const fields = kind === "segment"
      ? ["id", "kind", "from", "to", "label", "style", "visibleWhen"]
      : kind === "vector"
        ? ["id", "kind", "from", "to", "label", "style", "visibleWhen"]
      : kind === "circle"
        ? ["id", "kind", "center", "radius", "through", "label", "style", "visibleWhen"]
        : kind === "angle"
          ? ["id", "kind", "vertex", "from", "to", "radius", "label", "style", "visibleWhen"]
          : kind === "roundedBox"
            ? ["id", "kind", "box", "cornerRadius", "label", "style", "visibleWhen"]
            : kind === "locus"
              ? ["id", "kind", "points", "label", "style", "visibleWhen"]
              : kind === "polygon"
                ? ["id", "kind", "points", "label", "style", "visibleWhen"]
                : kind === "orientedBox"
                  ? ["id", "kind", "center", "width", "height", "rotationDegrees", "label", "style", "visibleWhen"]
              : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawShape, fields, shapePath, issue);
    if (!["segment", "vector", "circle", "angle", "roundedBox", "locus", "polygon", "orientedBox"].includes(String(kind))) {
      issue(`富回答场景 ${scene.id} 的 ${shapePath}.kind 无效`);
      continue;
    }
    validateVisibility(rawShape.visibleWhen, `${shapePath}.visibleWhen`);
    if (richAnswerValidateIdentifier(scene, rawShape.id, `${shapePath}.id`, issue)) {
      if (shapeIDs.has(rawShape.id) || pointIDs.has(rawShape.id)) issue(`富回答场景 ${scene.id} 的几何对象 id 重复：${rawShape.id}`);
      shapeIDs.add(rawShape.id);
    }
    const pointRefs = kind === "segment" || kind === "vector"
      ? [rawShape.from, rawShape.to]
      : kind === "circle"
        ? [rawShape.center, rawShape.through].filter((value) => value !== undefined)
        : kind === "angle"
          ? [rawShape.vertex, rawShape.from, rawShape.to]
          : kind === "polygon"
            ? (Array.isArray(rawShape.points) ? rawShape.points : [])
            : kind === "orientedBox"
              ? [rawShape.center]
          : [];
    pointRefs.forEach((pointRef) => {
      if (!pointIDs.has(String(pointRef))) issue(`富回答场景 ${scene.id} 的 ${shapePath} 引用了不存在的点 ${String(pointRef)}`);
    });
    if (kind === "circle" && rawShape.radius === undefined && rawShape.through === undefined) {
      issue(`富回答场景 ${scene.id} 的圆 ${String(rawShape.id)} 必须提供 radius 或 through`);
    }
    if (kind === "locus") {
      const locusPoints = Array.isArray(rawShape.points) ? rawShape.points : [];
      if (locusPoints.length < 2) issue(`富回答场景 ${scene.id} 的 ${shapePath}.points 至少需要两个点`);
      locusPoints.forEach((point, pointIndex) => richAnswerValidateCoordinate2D(scene, point, `${shapePath}.points[${pointIndex}]`, issue));
      dataPointCount += locusPoints.length;
    }
    if (kind === "polygon") {
      const polygonPoints = Array.isArray(rawShape.points) ? rawShape.points : [];
      if (polygonPoints.length < 3) issue(`富回答场景 ${scene.id} 的 ${shapePath}.points 至少需要三个点 id`);
    }
    if (kind === "orientedBox") {
      if (!richAnswerRenderPlanFiniteNumber(rawShape.width) || rawShape.width <= 0) {
        issue(`富回答场景 ${scene.id} 的 ${shapePath}.width 必须大于 0`);
      }
      if (!richAnswerRenderPlanFiniteNumber(rawShape.height) || rawShape.height <= 0) {
        issue(`富回答场景 ${scene.id} 的 ${shapePath}.height 必须大于 0`);
      }
      if (!richAnswerRenderPlanFiniteNumber(rawShape.rotationDegrees)) {
        issue(`富回答场景 ${scene.id} 的 ${shapePath}.rotationDegrees 必须是有限数字`);
      }
    }
    richAnswerValidateStyle(scene, rawShape.style, `${shapePath}.style`, issue, ["stroke", "strokeWidth", "fill", "opacity", "dash"]);
  }

  const controls = Array.isArray(spec.controls) ? spec.controls : [];
  if (spec.controls !== undefined && !Array.isArray(spec.controls)) issue(`富回答场景 ${scene.id} 的 spec.controls 必须是数组`);
  const controlIDs = new Set<string>();
  const controlsWithoutBindings: Array<{ path: string; id: string }> = [];
  for (const [controlIndex, rawControl] of controls.entries()) {
    const controlPath = `spec.controls[${controlIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawControl,
      ["id", "label", "value", "minimum", "maximum", "step", "unit", "options", "presentation", "bindings"],
      controlPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawControl.id, `${controlPath}.id`, issue)) {
      if (controlIDs.has(rawControl.id)) issue(`富回答场景 ${scene.id} 的控件 id 重复：${rawControl.id}`);
      controlIDs.add(rawControl.id);
    }
    const presentation = rawControl.presentation === undefined ? "slider" : String(rawControl.presentation);
    if (!richAnswerRenderPlanControlValue(rawControl.value)) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath}.value 必须是有限数字或短状态值`);
    }
    if (presentation === "slider") {
      if (
        ![rawControl.value, rawControl.minimum, rawControl.maximum, rawControl.step].every(richAnswerRenderPlanFiniteNumber) ||
        rawControl.minimum >= rawControl.maximum || rawControl.step <= 0 ||
        rawControl.value < rawControl.minimum || rawControl.value > rawControl.maximum
      ) issue(`富回答场景 ${scene.id} 的 ${controlPath} 滑杆范围或初值无效`);
    }
    const bindings = Array.isArray(rawControl.bindings) ? rawControl.bindings : [];
    if (!Array.isArray(rawControl.bindings)) issue(`富回答场景 ${scene.id} 的 ${controlPath}.bindings 必须是数组`);
    if (bindings.length === 0 && typeof rawControl.id === "string") {
      controlsWithoutBindings.push({ path: controlPath, id: rawControl.id });
    }
    const options = Array.isArray(rawControl.options) ? rawControl.options : [];
    if (rawControl.options !== undefined && (options.length < 2 || options.length > 12)) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath}.options 必须有 2–12 项`);
    }
    const optionValues = new Set<number | string>();
    for (const [optionIndex, rawOption] of options.entries()) {
      const optionPath = `${controlPath}.options[${optionIndex}]`;
      if (!richAnswerValidateNestedFields(scene, rawOption, ["value", "label"], optionPath, issue)) continue;
      if (!richAnswerRenderPlanControlValue(rawOption.value)) {
        issue(`富回答场景 ${scene.id} 的 ${optionPath}.value 必须是有限数字或短状态值`);
      } else {
        if (optionValues.has(rawOption.value)) issue(`富回答场景 ${scene.id} 的 ${controlPath}.options value 不能重复`);
        optionValues.add(rawOption.value);
      }
      if (typeof rawOption.label !== "string" || rawOption.label.trim().length === 0) {
        issue(`富回答场景 ${scene.id} 的 ${optionPath}.label 不能为空`);
      }
    }
    if (rawControl.presentation !== undefined && !["slider", "segmented"].includes(String(rawControl.presentation))) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath}.presentation 必须是 slider 或 segmented`);
    }
    if (presentation === "segmented") {
      const selectedValue = rawControl.value;
      if (!options.some((option) => isRecord(option) && option.value === selectedValue)) {
        issue(`富回答场景 ${scene.id} 的 ${controlPath}.value 必须命中一个分段选项`);
      }
    }
    if (bindings.length > 0 && !richAnswerRenderPlanFiniteNumber(rawControl.value)) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath} 有几何绑定时 value 必须是有限数字`);
    }
    for (const [bindingIndex, rawBinding] of bindings.entries()) {
      const bindingPath = `${controlPath}.bindings[${bindingIndex}]`;
      if (!isRecord(rawBinding)) {
        issue(`富回答场景 ${scene.id} 的 ${bindingPath} 必须是对象`);
        continue;
      }
      const fields = rawBinding.kind === "pointCoordinate"
        ? ["kind", "pointID", "axis", "multiplier", "offset", "minimum", "maximum"]
        : rawBinding.kind === "pointOnConstraint"
          ? ["kind", "pointID", "multiplier", "offset"]
          : rawBinding.kind === "circleRadius"
            ? ["kind", "shapeID", "multiplier", "offset", "minimum", "maximum"]
            : ["kind"];
      richAnswerValidateNestedFields(scene, rawBinding, fields, bindingPath, issue);
      if (rawBinding.kind === "circleRadius") {
        if (!shapeIDs.has(String(rawBinding.shapeID))) issue(`富回答场景 ${scene.id} 的 ${bindingPath}.shapeID 不存在`);
      } else if (["pointCoordinate", "pointOnConstraint"].includes(String(rawBinding.kind))) {
        if (!pointIDs.has(String(rawBinding.pointID))) issue(`富回答场景 ${scene.id} 的 ${bindingPath}.pointID 不存在`);
      } else {
        issue(`富回答场景 ${scene.id} 的 ${bindingPath}.kind 无效`);
      }
    }
  }

  const readouts = Array.isArray(spec.readouts) ? spec.readouts : [];
  if (spec.readouts !== undefined && !Array.isArray(spec.readouts)) issue(`富回答场景 ${scene.id} 的 spec.readouts 必须是数组`);
  const stateReadoutControlRefs: Array<{ path: string; controlID: string }> = [];
  for (const [readoutIndex, rawReadout] of readouts.entries()) {
    const readoutPath = `spec.readouts[${readoutIndex}]`;
    if (!isRecord(rawReadout)) {
      issue(`富回答场景 ${scene.id} 的 ${readoutPath} 必须是对象`);
      continue;
    }
    const fields = rawReadout.kind === "point"
      ? ["id", "kind", "label", "pointID"]
      : rawReadout.kind === "distance"
        ? ["id", "kind", "label", "from", "to", "unit"]
        : rawReadout.kind === "angle"
          ? ["id", "kind", "label", "vertex", "from", "to", "unit"]
          : rawReadout.kind === "state"
            ? ["id", "kind", "label", "controlID", "options"]
          : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawReadout, fields, readoutPath, issue);
    const refs = rawReadout.kind === "point"
      ? [rawReadout.pointID]
      : rawReadout.kind === "distance"
        ? [rawReadout.from, rawReadout.to]
        : rawReadout.kind === "angle"
          ? [rawReadout.vertex, rawReadout.from, rawReadout.to]
          : [];
    refs.forEach((pointRef) => {
      if (!pointIDs.has(String(pointRef))) issue(`富回答场景 ${scene.id} 的 ${readoutPath} 引用了不存在的点`);
    });
    if (rawReadout.kind === "state") {
      if (richAnswerValidateIdentifier(scene, rawReadout.controlID, `${readoutPath}.controlID`, issue)) {
        stateReadoutControlRefs.push({ path: readoutPath, controlID: rawReadout.controlID });
      }
      const options = Array.isArray(rawReadout.options) ? rawReadout.options : [];
      if (options.length < 2 || options.length > 12) issue(`富回答场景 ${scene.id} 的 ${readoutPath}.options 必须有 2–12 项`);
      options.forEach((rawOption, optionIndex) => {
        const optionPath = `${readoutPath}.options[${optionIndex}]`;
        if (!richAnswerValidateNestedFields(scene, rawOption, ["value", "label"], optionPath, issue)) return;
        if (!richAnswerRenderPlanControlValue(rawOption.value)) issue(`富回答场景 ${scene.id} 的 ${optionPath}.value 必须是有限数字或短状态值`);
        if (typeof rawOption.label !== "string" || rawOption.label.trim().length === 0) issue(`富回答场景 ${scene.id} 的 ${optionPath}.label 不能为空`);
      });
    }
  }
  const stateConsumerControlIDs = new Set([
    ...visibilityControlRefs.map((reference) => reference.controlID),
    ...stateReadoutControlRefs.map((reference) => reference.controlID),
  ]);
  for (const reference of [...visibilityControlRefs, ...stateReadoutControlRefs]) {
    if (!controlIDs.has(reference.controlID)) {
      issue(`富回答场景 ${scene.id} 的 ${reference.path} 引用了不存在的控件 ${reference.controlID}`);
    }
  }
  for (const control of controlsWithoutBindings) {
    if (!stateConsumerControlIDs.has(control.id)) {
      issue(`富回答场景 ${scene.id} 的 ${control.path} 没有几何绑定，也没有驱动 visibleWhen 或 state 读数`);
    }
  }
  if (dataPointCount > registration.budgets.maxDataPoints) {
    issue(`富回答场景 ${scene.id} 的二维几何数据点超出预算：${dataPointCount}/${registration.budgets.maxDataPoints}`);
  }
  return dataPointCount;
}