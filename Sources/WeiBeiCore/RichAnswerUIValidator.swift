import Foundation

// Validates generated UI programs, composition bindings, datasets, and node trees.
extension RichAnswerEngine {
    static func validateUIProgram(
        _ program: RichAnswerUIProgram,
        scene: RichAnswerScene
    ) -> RichAnswerDiagnostic? {
        let sceneID = scene.id
        guard program.version == "weibei.openui.v1" else {
            return RichAnswerDiagnostic(
                code: .unsupportedSchema,
                sceneID: sceneID,
                message: "generated UI program uses an unsupported protocol version"
            )
        }
    
        let source = program.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = source
            .split(whereSeparator: { character in character.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !source.isEmpty,
              source.count <= 10_000,
              !lines.isEmpty,
              lines.count <= 48,
              (160...720).contains(program.maxHeight),
              !program.capabilities.isEmpty,
              program.capabilities.count <= 12,
              Set(program.capabilities).count == program.capabilities.count else {
            return RichAnswerDiagnostic(
                code: .budgetExceeded,
                sceneID: sceneID,
                message: "generated UI program exceeds its source, capability, or height budget"
            )
        }
    
        let forbiddenFragments = [
            "<script", "</script", "<svg", "<iframe", "javascript:",
            "http://", "https://", "Query(", "Mutation(", "OpenUrl(",
        ]
        guard forbiddenFragments.allSatisfy({ !source.localizedCaseInsensitiveContains($0) }) else {
            return RichAnswerDiagnostic(
                code: .unauthorizedAsset,
                sceneID: sceneID,
                message: "generated UI program attempted to use markup, network access, or executable tools"
            )
        }
    
        let allowedComponents: Set<String> = [
            "RichAnswerRoot", "LearningStage", "NarrativeBlock", "ParameterSlider",
            "ParameterReadout", "ValuePicker", "FunctionPlot", "ComparisonRow",
            "ComparisonTable", "EvidenceSnippet", "ReasonStep", "ProcessStepper",
            "QuadraticMechanism", "FollowUpAction", "ChartSeries", "LinkedDataChart",
            "MetricItem", "MetricStrip", "ExecutionFrame", "ExecutionTrack",
            "ArgumentUnit", "ArgumentReader", "CausalEvent", "CausalTrack",
            "TwoPointLineLab", "BalanceExperiment", "SpatialLayer", "SpatialRegion",
            "SpatialPath", "SpatialPoint", "LayeredSpatialView", "DistributionBrush",
            "FlowAssumption", "DependencyNode", "FlowMetric", "DependencyFlow",
        ]
        var hasRoot = false
        let evidenceBindingComponents: Set<String> = [
            "EvidenceSnippet",
            "ArgumentUnit",
            "CausalEvent",
            "SpatialPoint",
        ]
        var evidenceBindingLines: [String] = []
        for line in lines {
            if line.hasPrefix("$") {
                guard line.range(
                    of: #"^\$[A-Za-z][A-Za-z0-9_]*\s*=\s*.+$"#,
                    options: .regularExpression
                ) != nil else {
                    return invalidValue(sceneID: sceneID, "generated UI program has an invalid state declaration")
                }
                continue
            }
    
            guard let equals = line.firstIndex(of: "="),
                  let openParenthesis = line[equals...].firstIndex(of: "(") else {
                return invalidValue(sceneID: sceneID, "generated UI program has an invalid component statement")
            }
            let statementID = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            let componentName = line[line.index(after: equals)..<openParenthesis]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isSafeIdentifier(statementID), allowedComponents.contains(componentName) else {
                return RichAnswerDiagnostic(
                    code: .unsupportedField,
                    sceneID: sceneID,
                    message: "generated UI program references a component outside WeiBei's catalog"
                )
            }
            if statementID == "root" {
                hasRoot = componentName == "RichAnswerRoot"
            }
            if evidenceBindingComponents.contains(componentName) {
                evidenceBindingLines.append(line)
            }
        }
    
        guard hasRoot else {
            return brokenReference(sceneID: sceneID, "generated UI program does not define a RichAnswerRoot")
        }
        let canvasComponents = [
            "FunctionPlot(", "LinkedDataChart(", "TwoPointLineLab(",
            "LayeredSpatialView(", "DistributionBrush(",
        ]
        if program.graphics == .dom,
           canvasComponents.contains(where: source.contains) {
            return invalidValue(sceneID: sceneID, "generated UI Canvas components require the Canvas graphics kernel")
        }
        let bindsEveryEvidence = scene.evidenceIDs.allSatisfy { evidenceID in
            guard let data = try? JSONEncoder().encode(evidenceID),
                  let quotedEvidenceID = String(data: data, encoding: .utf8) else { return false }
            return evidenceBindingLines.contains { line in
                line.contains(quotedEvidenceID)
            }
        }
        guard bindsEveryEvidence else {
            return missingEvidence(
                sceneID: sceneID,
                "generated UI program must bind every scene evidence item through EvidenceSnippet, ArgumentUnit, CausalEvent, or SpatialPoint"
            )
        }
        return nil
    }
    
    static func validateUIComposition(
        _ ui: RichAnswerUIComposition,
        sceneID: String,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard !ui.nodes.isEmpty else {
            return invalidValue(sceneID: sceneID, "generated UI requires at least one node")
        }
    
        let nodeIDs = ui.nodes.map(\.id)
        let datasetIDs = ui.datasets.map(\.id)
        let bindingIDs = ui.bindings.map(\.id)
        let rowIDs = ui.datasets.flatMap { $0.rows.map(\.id) }
        guard idsAreUniqueAndSafe(nodeIDs + datasetIDs + bindingIDs + rowIDs) else {
            return RichAnswerDiagnostic(
                code: .duplicateID,
                sceneID: sceneID,
                message: "generated UI node, dataset, row, and binding ids must be unique and safe"
            )
        }
    
        let nodesByID = Dictionary(uniqueKeysWithValues: ui.nodes.map { ($0.id, $0) })
        let datasetsByID = Dictionary(uniqueKeysWithValues: ui.datasets.map { ($0.id, $0) })
        let bindingsByID = Dictionary(uniqueKeysWithValues: ui.bindings.map { ($0.id, $0) })
        guard nodesByID[ui.rootID] != nil else {
            return brokenReference(sceneID: sceneID, "generated UI root references a missing node")
        }
    
        var parentCounts: [String: Int] = [:]
        for node in ui.nodes {
            guard node.children.allSatisfy({ nodesByID[$0] != nil }) else {
                return brokenReference(sceneID: sceneID, "generated UI node \(node.id) references a missing child")
            }
            for childID in node.children {
                parentCounts[childID, default: 0] += 1
            }
            if let issue = validateUINode(
                node,
                sceneID: sceneID,
                nodesByID: nodesByID,
                datasetsByID: datasetsByID,
                bindingsByID: bindingsByID,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
        }
    
        guard parentCounts[ui.rootID, default: 0] == 0,
              parentCounts.values.allSatisfy({ $0 <= 1 }) else {
            return invalidValue(sceneID: sceneID, "generated UI must be a tree with one parent per node")
        }
    
        var visited: Set<String> = []
        var active: Set<String> = []
        func visit(_ nodeID: String, depth: Int) -> Bool {
            guard depth <= 7, let node = nodesByID[nodeID] else { return false }
            if active.contains(nodeID) { return false }
            if visited.contains(nodeID) { return true }
            active.insert(nodeID)
            for childID in node.children where !visit(childID, depth: depth + 1) {
                return false
            }
            active.remove(nodeID)
            visited.insert(nodeID)
            return true
        }
        guard visit(ui.rootID, depth: 1), visited.count == ui.nodes.count else {
            return invalidValue(sceneID: sceneID, "generated UI contains a cycle, unreachable node, or excessive nesting")
        }
        let reachableNodes = ui.nodes.filter { visited.contains($0.id) }
    
        for dataset in ui.datasets {
            guard !dataset.rows.isEmpty else {
                return invalidValue(sceneID: sceneID, "generated UI dataset \(dataset.id) is empty")
            }
            for row in dataset.rows {
                guard row.x.isFinite,
                      row.y.isFinite,
                      row.x >= 0,
                      row.x <= 1,
                      row.y >= 0,
                      row.y <= 1,
                      row.value.map(\.isFinite) ?? true,
                      row.result.map(\.isFinite) ?? true else {
                    return invalidValue(sceneID: sceneID, "generated UI row \(row.id) has invalid normalized coordinates")
                }
                let hasSecondPoint = row.x2 != nil || row.y2 != nil
                if hasSecondPoint {
                    guard let x2 = row.x2, let y2 = row.y2,
                          x2.isFinite,
                          y2.isFinite,
                          x2 >= 0,
                          x2 <= 1,
                          y2 >= 0,
                          y2 <= 1 else {
                        return invalidValue(sceneID: sceneID, "generated UI row \(row.id) has an invalid vector endpoint")
                    }
                }
                guard row.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
                    return missingEvidence(sceneID: sceneID, "generated UI row \(row.id) references missing evidence")
                }
            }
        }
    
        for binding in ui.bindings {
            guard binding.minimum.isFinite,
                  binding.maximum.isFinite,
                  binding.step.isFinite,
                  binding.initialValue.isFinite,
                  binding.minimum < binding.maximum,
                  binding.step > 0,
                  binding.initialValue >= binding.minimum,
                  binding.initialValue <= binding.maximum else {
                return RichAnswerDiagnostic(
                    code: .invalidParameter,
                    sceneID: sceneID,
                    message: "generated UI binding \(binding.id) has invalid bounds"
                )
            }
            let controlRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .probe]
            let outputRoles: Set<RichAnswerUIRole> = [
                .metric, .sequence, .line, .path, .point, .area, .shape, .bar,
                .dotMatrix, .vector, .region, .image,
            ]
            let hasControl = reachableNodes.contains {
                $0.bindingID == binding.id && controlRoles.contains($0.role)
            }
            let hasDrivenOutput = reachableNodes.contains {
                $0.bindingID == binding.id && outputRoles.contains($0.role)
            }
            guard hasControl, hasDrivenOutput else {
                return invalidValue(
                    sceneID: sceneID,
                    "generated UI binding \(binding.id) must connect a visible control to a driven mark or metric"
                )
            }
            guard bindingHasChangingOutcome(
                binding,
                reachableNodes: reachableNodes,
                datasetsByID: datasetsByID
            ) else {
                return invalidValue(
                    sceneID: sceneID,
                    "generated UI binding \(binding.id) must produce a verifiable semantic or quantitative outcome change"
                )
            }
        }
        return nil
    }
    
    static func bindingHasChangingOutcome(
        _ binding: RichAnswerUIBinding,
        reachableNodes: [RichAnswerUINode],
        datasetsByID: [String: RichAnswerUIDataset]
    ) -> Bool {
        let outputRoles: Set<RichAnswerUIRole> = [
            .metric,
            .sequence,
            .line,
            .path,
            .point,
            .area,
            .shape,
            .bar,
            .dotMatrix,
            .vector,
            .region,
            .image,
        ]
        let drivenOutputs = reachableNodes.filter {
            $0.bindingID == binding.id && outputRoles.contains($0.role)
        }
        return drivenOutputs.contains { node in
            guard let datasetID = node.datasetID,
                  let dataset = datasetsByID[datasetID] else {
                return false
            }
            return datasetRowsHaveChangingOutcome(
                dataset.rows,
                acceptsSemanticOnly: node.role == .sequence
            )
        }
    }
    
    static func datasetRowsHaveChangingOutcome(
        _ rows: [RichAnswerUIDataRow],
        acceptsSemanticOnly: Bool
    ) -> Bool {
        guard rows.count >= 2 else { return false }
        let signatures = Set(rows.map { row in
            [
                row.value.map { String(format: "%.6f", $0) } ?? "",
                row.result.map { String(format: "%.6f", $0) } ?? "",
                String(format: "%.6f", row.x),
                String(format: "%.6f", row.y),
                row.x2.map { String(format: "%.6f", $0) } ?? "",
                row.y2.map { String(format: "%.6f", $0) } ?? "",
                row.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
            ].joined(separator: "|")
        })
        let hasVaryingNumericState = Set(rows.compactMap(\.value)).count >= 2
            || Set(rows.compactMap(\.result)).count >= 2
            || Set(rows.map(\.x)).count >= 2
            || Set(rows.map(\.y)).count >= 2
            || Set(rows.compactMap(\.x2)).count >= 2
            || Set(rows.compactMap(\.y2)).count >= 2
        let hasVaryingSemanticState = Set(
            rows.compactMap { row in
                row.label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty }
        ).count >= 2
        return signatures.count >= 2
            && (hasVaryingNumericState || (acceptsSemanticOnly && hasVaryingSemanticState))
    }
    
    static func reachableUIEvidenceIDs(in ui: RichAnswerUIComposition) -> Set<String> {
        let nodesByID = Dictionary(uniqueKeysWithValues: ui.nodes.map { ($0.id, $0) })
        var visited: Set<String> = []
        var active: Set<String> = []
        func visit(_ nodeID: String, depth: Int) {
            guard depth <= 7,
                  let node = nodesByID[nodeID],
                  !active.contains(nodeID),
                  !visited.contains(nodeID) else { return }
            active.insert(nodeID)
            for childID in node.children {
                visit(childID, depth: depth + 1)
            }
            active.remove(nodeID)
            visited.insert(nodeID)
        }
        visit(ui.rootID, depth: 1)
        let reachableNodes = ui.nodes.filter { visited.contains($0.id) }
        let reachableDatasetIDs = Set(reachableNodes.compactMap(\.datasetID))
        let nodeEvidenceIDs = reachableNodes.flatMap(\.evidenceIDs)
        let rowEvidenceIDs = ui.datasets
            .filter { reachableDatasetIDs.contains($0.id) }
            .flatMap { dataset in dataset.rows.flatMap(\.evidenceIDs) }
        return Set(nodeEvidenceIDs + rowEvidenceIDs)
    }
    
    static func validateUINode(
        _ node: RichAnswerUINode,
        sceneID: String,
        nodesByID: [String: RichAnswerUINode],
        datasetsByID: [String: RichAnswerUIDataset],
        bindingsByID: [String: RichAnswerUIBinding],
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        let containerRoles: Set<RichAnswerUIRole> = [.vstack, .hstack, .zstack, .grid, .panel]
        let canvasRoles: Set<RichAnswerUIRole> = [
            .axis, .line, .path, .point, .area, .shape, .bar, .dotMatrix,
            .vector, .region, .image, .label,
        ]
        let datasetRoles: Set<RichAnswerUIRole> = [
            .metric, .sequence, .line, .path, .point, .area, .bar, .dotMatrix, .vector, .label,
        ]
        let bindingRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .probe]
    
        if containerRoles.contains(node.role) {
            guard !node.children.isEmpty else {
                return invalidValue(sceneID: sceneID, "generated UI container \(node.id) has no children")
            }
        } else if node.role == .canvas {
            guard !node.children.isEmpty,
                  node.children.allSatisfy({ childID in
                      nodesByID[childID].map { canvasRoles.contains($0.role) } == true
                  }) else {
                return invalidValue(sceneID: sceneID, "generated UI canvas \(node.id) only accepts visual mark children")
            }
            guard node.xAxis.map({ $0.minimum.isFinite && $0.maximum.isFinite && $0.minimum < $0.maximum }) ?? true,
                  node.yAxis.map({ $0.minimum.isFinite && $0.maximum.isFinite && $0.minimum < $0.maximum }) ?? true else {
                return invalidValue(sceneID: sceneID, "generated UI canvas \(node.id) has an invalid axis")
            }
        } else {
            guard node.children.isEmpty else {
                return invalidValue(sceneID: sceneID, "generated UI leaf \(node.id) cannot have children")
            }
        }
    
        if node.role == .grid {
            guard let columns = node.columns, (2...3).contains(columns) else {
                return invalidValue(sceneID: sceneID, "generated UI grid \(node.id) requires two or three columns")
            }
        } else if node.columns != nil {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses columns outside a grid"
            )
        }
    
        if datasetRoles.contains(node.role) {
            guard let datasetID = node.datasetID, datasetsByID[datasetID] != nil else {
                return brokenReference(sceneID: sceneID, "generated UI node \(node.id) references a missing dataset")
            }
        } else if node.role == .shape, let datasetID = node.datasetID {
            guard datasetsByID[datasetID] != nil else {
                return brokenReference(sceneID: sceneID, "generated UI shape \(node.id) references a missing dataset")
            }
        } else if node.datasetID != nil && node.role != .select {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) cannot bind a dataset"
            )
        }
    
        if bindingRoles.contains(node.role) {
            guard let bindingID = node.bindingID, bindingsByID[bindingID] != nil else {
                return brokenReference(sceneID: sceneID, "generated UI control \(node.id) references a missing binding")
            }
        } else if let bindingID = node.bindingID,
                  bindingsByID[bindingID] == nil {
            return brokenReference(sceneID: sceneID, "generated UI node \(node.id) references a missing binding")
        }
    
        if node.role == .text {
            guard node.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return invalidValue(sceneID: sceneID, "generated UI text \(node.id) is empty")
            }
        }
        if node.role == .sequence {
            guard let datasetID = node.datasetID,
                  let dataset = datasetsByID[datasetID],
                  dataset.rows.count >= 2 else {
                return invalidValue(sceneID: sceneID, "generated UI sequence \(node.id) requires at least two dataset rows")
            }
            guard dataset.rows.allSatisfy({ hasMeaningfulText($0.label) }) else {
                return invalidValue(sceneID: sceneID, "generated UI sequence \(node.id) requires every row to expose a visible label")
            }
        }
        if node.role == .region, node.region == nil {
            return invalidValue(sceneID: sceneID, "generated UI region \(node.id) has no bounds")
        }
        if node.role == .shape {
            guard node.shape != nil, node.region != nil, node.fill != nil else {
                return invalidValue(sceneID: sceneID, "generated UI shape \(node.id) requires a shape kind, fill, and bounds")
            }
            if node.bindingID != nil, node.datasetID == nil {
                return invalidValue(sceneID: sceneID, "generated UI movable shape \(node.id) requires a dataset")
            }
        } else if node.shape != nil {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses a shape kind outside a shape mark"
            )
        }
        let fillRoles: Set<RichAnswerUIRole> = [.shape, .bar, .dotMatrix, .region, .area]
        if node.fill != nil, !fillRoles.contains(node.role) {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses fill outside a filled visual mark"
            )
        }
        if let region = node.region,
           !(region.x.isFinite
                && region.y.isFinite
                && region.width.isFinite
                && region.height.isFinite
                && region.x >= 0
                && region.y >= 0
                && region.width > 0
                && region.height > 0
                && region.x + region.width <= 1
                && region.y + region.height <= 1) {
            return invalidValue(sceneID: sceneID, "generated UI node \(node.id) has invalid bounds")
        }
        if node.role == .image {
            guard let assetID = node.assetID, isAllowedAssetID(assetID, environment: environment) else {
                return RichAnswerDiagnostic(
                    code: .unauthorizedAsset,
                    sceneID: sceneID,
                    message: "generated UI image \(node.id) references an unauthorized asset"
                )
            }
        } else if node.assetID != nil {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: sceneID,
                message: "generated UI node \(node.id) uses an asset outside an image mark"
            )
        }
        guard node.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "generated UI node \(node.id) references missing evidence")
        }
        if node.role == .evidence, node.evidenceIDs.isEmpty {
            return missingEvidence(sceneID: sceneID, "generated UI evidence node \(node.id) has no source")
        }
        return nil
    }
}
