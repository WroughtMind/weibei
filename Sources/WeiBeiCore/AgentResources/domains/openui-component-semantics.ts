import { OpenUIComponentName } from "./rich-answer-catalog";
import { RichAnswerSceneParam } from "./rich-answer-render-validation";
import {
  OpenUIComponentDeclaration,
  OpenUIStateDeclaration,
  OpenUIValue,
  openUIArrayItems,
  openUIArrayStateInitialValues,
  openUIBooleanValue,
  openUINumberValue,
  openUIProgramFailure,
  openUIStateInitialValue,
  openUIStringStateInitialValue,
  openUIStringValue,
  validateOpenUIIndexedState,
  validateOpenUIReactiveName,
} from "./openui-parser";


export function validateOpenUIComponentSemantics(
  scene: RichAnswerSceneParam,
  declaration: OpenUIComponentDeclaration,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
  componentsByID: ReadonlyMap<string, OpenUIComponentDeclaration>,
): void {
  const fail = (message: string, fix: string, argumentIndex?: number): never => openUIProgramFailure(
    scene.id,
    `组件 ${declaration.id}（${declaration.component}）${message}`,
    fix,
    declaration.line,
    argumentIndex === undefined ? declaration.column : declaration.arguments[argumentIndex].column,
  );
  const validateNamedState = (nameIndex: number, stateIndex: number): void =>
    validateOpenUIReactiveName(scene, declaration, nameIndex, stateIndex);

  switch (declaration.component) {
    case "ParameterSlider": {
      validateNamedState(0, 2);
      const minimum = openUINumberValue(declaration, 3);
      const maximum = openUINumberValue(declaration, 4);
      const step = openUINumberValue(declaration, 5);
      const initialValue = openUIStateInitialValue(declaration, 2, statesByName);
      if (maximum <= minimum || step <= 0 || initialValue < minimum || initialValue > maximum) {
        fail(
          `的范围无效：minimum=${minimum}、maximum=${maximum}、step=${step}、初值=${initialValue}`,
          "保证 maximum > minimum、step > 0，且状态初值位于范围内",
          3,
        );
      }
      return;
    }
    case "ParameterReadout":
      validateNamedState(0, 1);
      return;
    case "ValuePicker": {
      validateNamedState(0, 2);
      const initialValue = openUIStateInitialValue(declaration, 2, statesByName);
      const options = openUIArrayItems(declaration, 3).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      if (!options.includes(initialValue)) {
        fail(`的状态初值 ${initialValue} 不在 options 中`, "把状态初值设为 options 中的一个数字", 2);
      }
      return;
    }
    case "FunctionPlot": {
      validateNamedState(2, 3);
      const minimum = openUINumberValue(declaration, 5);
      const maximum = openUINumberValue(declaration, 6);
      if (maximum <= minimum) fail("的横轴范围无效", "保证 xMaximum 大于 xMinimum", 5);
      return;
    }
    case "ComparisonTable": {
      validateNamedState(0, 1);
      const initialValue = openUIStateInitialValue(declaration, 1, statesByName);
      const coefficients = openUIArrayItems(declaration, 2).map((value) => {
        const row = componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!;
        return openUINumberValue(row, 1);
      });
      if (!coefficients.includes(initialValue)) {
        fail(`的焦点初值 ${initialValue} 没有对应 ComparisonRow`, "让 $focus 初值等于某一行的 coefficient", 1);
      }
      return;
    }
    case "ProcessStepper":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, openUIArrayItems(declaration, 2).length, statesByName);
      return;
    case "QuadraticMechanism":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, 4, statesByName);
      return;
    case "LinkedDataChart": {
      validateNamedState(0, 1);
      const labelCount = openUIArrayItems(declaration, 3).length;
      validateOpenUIIndexedState(scene, declaration, 1, labelCount, statesByName);
      for (const value of openUIArrayItems(declaration, 4)) {
        const seriesID = (value as Extract<OpenUIValue, { kind: "reference" }>).id;
        const series = componentsByID.get(seriesID)!;
        const valueCount = openUIArrayItems(series, 2).length;
        if (valueCount !== labelCount) {
          fail(
            `引用的序列 ${seriesID} 有 ${valueCount} 个值，但 xLabels 有 ${labelCount} 项`,
            "让每个 ChartSeries.values 与 xLabels 等长",
            4,
          );
        }
      }
      return;
    }
    case "ExecutionFrame": {
      const valueCount = openUIArrayItems(declaration, 2).length;
      const changedIndices = openUIArrayItems(declaration, 3).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      if (new Set(changedIndices).size !== changedIndices.length || changedIndices.some((index) => index >= valueCount)) {
        fail("的 changedIndices 重复或超出 values 范围", "只保留不重复且小于 values 长度的索引", 3);
      }
      return;
    }
    case "ExecutionTrack": {
      validateNamedState(0, 1);
      const frames = openUIArrayItems(declaration, 4);
      validateOpenUIIndexedState(scene, declaration, 1, frames.length, statesByName);
      const codeLineCount = openUIArrayItems(declaration, 3).length;
      for (const value of frames) {
        const frameID = (value as Extract<OpenUIValue, { kind: "reference" }>).id;
        const frame = componentsByID.get(frameID)!;
        if (openUINumberValue(frame, 1) >= codeLineCount) {
          fail(`引用的执行帧 ${frameID} 指向不存在的代码行`, "让每个 ExecutionFrame.activeLine 小于 codeLines 长度", 4);
        }
      }
      return;
    }
    case "ArgumentReader":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, openUIArrayItems(declaration, 3).length, statesByName);
      return;
    case "CausalTrack":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, openUIArrayItems(declaration, 3).length, statesByName);
      return;
    case "TwoPointLineLab": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      validateNamedState(4, 5);
      validateNamedState(6, 7);
      const xMinimum = openUINumberValue(declaration, 9);
      const xMaximum = openUINumberValue(declaration, 10);
      const yMinimum = openUINumberValue(declaration, 11);
      const yMaximum = openUINumberValue(declaration, 12);
      const xValues = [
        openUIStateInitialValue(declaration, 1, statesByName),
        openUIStateInitialValue(declaration, 5, statesByName),
      ];
      const yValues = [
        openUIStateInitialValue(declaration, 3, statesByName),
        openUIStateInitialValue(declaration, 7, statesByName),
      ];
      if (xMaximum <= xMinimum || yMaximum <= yMinimum) {
        fail("的坐标范围无效", "保证 xMaximum > xMinimum 且 yMaximum > yMinimum", 9);
      }
      if (xValues.some((value) => value < xMinimum || value > xMaximum) ||
          yValues.some((value) => value < yMinimum || value > yMaximum)) {
        fail("的初始点超出坐标范围", "把四个点状态初值放进声明的横纵轴范围", 1);
      }
      return;
    }
    case "BalanceExperiment": {
      validateNamedState(0, 1);
      const initialValue = openUIStateInitialValue(declaration, 1, statesByName);
      if (initialValue < -1 || initialValue > 1) {
        fail("的 shift 初值超出 -1 到 1", "把 shift 初值限制在 -1 到 1", 1);
      }
      return;
    }
    case "SpatialRegion":
    case "SpatialPath": {
      if (openUIArrayItems(declaration, 3).length % 2 !== 0) {
        fail("的 coordinates 不是完整的 x,y 坐标对", "让 coordinates 使用偶数个 0–1 数值", 3);
      }
      return;
    }
    case "LayeredSpatialView": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      const layers = openUIArrayItems(declaration, 5).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const regions = openUIArrayItems(declaration, 6).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const paths = openUIArrayItems(declaration, 7).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const points = openUIArrayItems(declaration, 8).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const layerKinds = new Map(layers.map((layer) => [
        openUIStringValue(layer, 0),
        openUIStringValue(layer, 2),
      ]));
      if (layerKinds.size !== layers.length) {
        fail("引用了重复的语义图层 id", "让每个 SpatialLayer.id 唯一", 5);
      }
      const spatialItems = [...regions, ...paths, ...points];
      const spatialIDs = spatialItems.map((item) => openUIStringValue(item, 0));
      if (new Set(spatialIDs).size !== spatialIDs.length) {
        fail("引用了重复的区域、路径或点位 id", "让 SpatialRegion、SpatialPath、SpatialPoint 的语义 id 全局唯一", 6);
      }
      const expectedKind: Partial<Record<OpenUIComponentName, string>> = {
        SpatialRegion: "region",
        SpatialPath: "path",
        SpatialPoint: "point",
      };
      const mismatched = spatialItems.find((item) =>
        layerKinds.get(openUIStringValue(item, 1)) !== expectedKind[item.component]
      );
      if (mismatched) {
        fail(
          `中的 ${mismatched.component} ${openUIStringValue(mismatched, 0)} 指向缺失或类型不匹配的图层`,
          "让每个空间对象的 layerID 指向同 kind 的 SpatialLayer",
        );
      }
      const visibleLayerIDs = openUIArrayStateInitialValues(declaration, 1, statesByName).map((value) =>
        (value as Extract<OpenUIValue, { kind: "string" }>).value
      );
      if (new Set(visibleLayerIDs).size !== visibleLayerIDs.length ||
          visibleLayerIDs.some((layerID) => !layerKinds.has(layerID))) {
        fail("的初始可见图层重复或不存在", "让 $visibleLayerIDs 只包含不重复的 SpatialLayer.id", 1);
      }
      const defaultVisibleLayerIDs = layers
        .filter((layer) => openUIBooleanValue(layer, 3))
        .map((layer) => openUIStringValue(layer, 0));
      if (defaultVisibleLayerIDs.length !== visibleLayerIDs.length ||
          defaultVisibleLayerIDs.some((layerID) => !visibleLayerIDs.includes(layerID))) {
        fail(
          "的初始可见状态与 SpatialLayer.defaultVisible 不一致",
          "让 $visibleLayerIDs 恰好包含 defaultVisible 为 true 的图层 id",
          1,
        );
      }
      const pointIDs = new Set(points.map((point) => openUIStringValue(point, 0)));
      const selectedPointID = openUIStringStateInitialValue(declaration, 3, statesByName);
      if (!pointIDs.has(selectedPointID)) {
        fail("的初始选中点不存在", "让 $selectedPointID 等于某个 SpatialPoint.id", 3);
      }
      return;
    }
    case "DistributionBrush": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      const values = openUIArrayItems(declaration, 5).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      const minimum = Math.min(...values);
      const maximum = Math.max(...values);
      const range = maximum - minimum;
      const center = openUIStateInitialValue(declaration, 1, statesByName);
      const span = openUIStateInitialValue(declaration, 3, statesByName);
      if (range <= 0) {
        fail("的总体数值没有分布范围", "至少提供两个不同的有限数值", 5);
      }
      if (span <= 0 || span > range || center - span / 2 < minimum || center + span / 2 > maximum) {
        fail(
          `的初始窗口超出总体范围：center=${center}、span=${span}`,
          "windowSpan 是完整宽度；让 span 大于 0 且不超过总体极差，并让 [center - span/2, center + span/2] 完整落在最小值与最大值之间。例如覆盖 10–13 应使用 center=11.5、span=3",
          1,
        );
      }
      return;
    }
    case "DependencyFlow": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      const assumptions = openUIArrayItems(declaration, 5).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const nodes = openUIArrayItems(declaration, 6).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const metrics = openUIArrayItems(declaration, 7).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const assumptionIDs = assumptions.map((item) => openUIStringValue(item, 0));
      const nodeIDs = nodes.map((item) => openUIStringValue(item, 0));
      const semanticIDs = [...assumptionIDs, ...nodeIDs];
      if (new Set(semanticIDs).size !== semanticIDs.length) {
        fail("的输入假设与计算节点存在重复语义 id", "让 FlowAssumption.id 与 DependencyNode.id 全部唯一", 5);
      }
      const inputValues = openUIArrayStateInitialValues(declaration, 1, statesByName).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      if (inputValues.length !== assumptions.length) {
        fail("的输入状态数量与 assumptions 不一致", "让 $inputValues 与 assumptions 等长并按相同顺序排列", 1);
      }
      assumptions.forEach((assumption, index) => {
        const minimum = openUINumberValue(assumption, 2);
        const maximum = openUINumberValue(assumption, 3);
        const step = openUINumberValue(assumption, 4);
        if (maximum <= minimum || step <= 0 || inputValues[index] < minimum || inputValues[index] > maximum) {
          fail(
            `的输入 ${openUIStringValue(assumption, 0)} 范围或初值无效`,
            "保证每个输入 maximum > minimum、step > 0，且对应初值位于范围内",
            1,
          );
        }
      });
      validateOpenUIIndexedState(scene, declaration, 3, assumptions.length, statesByName);
      const layerByID = new Map<string, number>(assumptionIDs.map((id) => [id, 0]));
      nodes.forEach((node) => layerByID.set(openUIStringValue(node, 0), openUINumberValue(node, 2)));
      const dependenciesByNode = new Map<string, string[]>();
      nodes.forEach((node) => {
        const nodeID = openUIStringValue(node, 0);
        const layer = openUINumberValue(node, 2);
        const operation = openUIStringValue(node, 3);
        const sources = openUIArrayItems(node, 4).map((value) =>
          (value as Extract<OpenUIValue, { kind: "string" }>).value
        );
        const parameters = openUIArrayItems(node, 5);
        dependenciesByNode.set(nodeID, sources);
        if (new Set(sources).size !== sources.length ||
            sources.some((sourceID) => layerByID.get(sourceID) === undefined || layerByID.get(sourceID)! >= layer)) {
          fail(
            `的节点 ${nodeID} 引用了重复、缺失或非前序来源`,
            "每个 sourceID 必须唯一，并指向输入假设或更低层的 DependencyNode",
            6,
          );
        }
        const exactTwo = operation === "ratio" || operation === "percentChange";
        const exactOne = operation === "identity" || operation === "power";
        if ((exactTwo && sources.length !== 2) || (exactOne && sources.length !== 1)) {
          fail(
            `的节点 ${nodeID} 为 ${operation} 提供了错误数量的来源`,
            `${operation} ${exactTwo ? "必须有两个来源" : "必须有一个来源"}`,
            6,
          );
        }
        if (operation === "difference" && sources.length < 2) {
          fail(`的节点 ${nodeID} 缺少被减项`, "difference 至少提供两个来源", 6);
        }
        if (operation === "weightedSum" &&
            parameters.length !== sources.length && parameters.length !== sources.length + 1) {
          fail(
            `的节点 ${nodeID} 权重数量与来源不一致`,
            "weightedSum 的 parameters 应与来源等长，或多一项作为常数偏置",
            6,
          );
        }
        if (operation === "power" && parameters.length !== 1) {
          fail(`的节点 ${nodeID} 缺少唯一指数`, "power 的 parameters 只提供一个指数", 6);
        }
        if (operation !== "weightedSum" && operation !== "power" && parameters.length !== 0) {
          fail(`的节点 ${nodeID} 不需要 parameters`, `删除 ${operation} 的 parameters`, 6);
        }
      });
      const metricNodeIDs = metrics.map((metric) => openUIStringValue(metric, 0));
      if (metricNodeIDs.some((nodeID) => !nodeIDs.includes(nodeID))) {
        fail("的结果指标引用了不存在的计算节点", "让每个 FlowMetric.nodeID 指向一个 DependencyNode.id", 7);
      }
      const usedIDs = new Set(metricNodeIDs);
      const queue = [...metricNodeIDs];
      while (queue.length > 0) {
        const currentID = queue.pop()!;
        for (const sourceID of dependenciesByNode.get(currentID) ?? []) {
          if (usedIDs.add(sourceID)) queue.push(sourceID);
        }
      }
      const unusedSemanticID = semanticIDs.find((id) => !usedIDs.has(id));
      if (unusedSemanticID) {
        fail(
          `包含未参与任何结果指标的输入或节点 ${unusedSemanticID}`,
          "删除无关声明，或让结果指标的依赖链真实经过该输入或节点",
        );
      }
      return;
    }
    default:
      return;
  }
}