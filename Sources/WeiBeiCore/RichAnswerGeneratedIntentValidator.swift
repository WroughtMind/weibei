import Foundation

// Validates expression intent and semantic contracts for generated Rich Answer scenes.
extension RichAnswerEngine {
    static func validateFamilyContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        if let issue = validateSupportedOperations(scene) {
            return issue
        }
    
        switch scene.family {
        case .textAndAlignment:
            return validateTextAlignmentContract(scene)
        case .quantityAndCoordinates:
            return validateQuantityCoordinateContract(scene)
        case .processAndState:
            return validateProcessStateContract(scene)
        case .relationAndEvidence:
            return validateRelationEvidenceContract(scene)
        case .timeAndSpace:
            return validateTimeSpaceContract(scene)
        case .imageAndOverlay:
            return validateImageOverlayContract(scene)
        case .comparisonAndEvaluation:
            return validateComparisonEvaluationContract(scene)
        case .calculationAndConstraints:
            return validateCalculationConstraintContract(scene)
        }
    }
    
    static func validateExpressionPlanIntentBudget(
        _ plan: RichAnswerExpressionPlan
    ) -> RichAnswerDiagnostic? {
        let groups = [
            plan.knowledgeObjects,
            plan.knowledgeRelations,
            plan.knowledgeProcesses,
            plan.visualPrimitives,
            plan.visualRationale,
        ]
        guard plan.knowledgeNatures.count <= 8,
              groups.allSatisfy({ $0.count <= 12 }),
              groups.flatMap({ $0 }).allSatisfy({
                  let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                  return !trimmed.isEmpty && trimmed.count <= 240
              }) else {
            return RichAnswerDiagnostic(
                code: .budgetExceeded,
                message: "rich answer expression intent exceeded its declaration budget"
            )
        }
        return nil
    }
    
    static func validateGeneratedFamilyContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let programComponents = generatedProgramComponents(in: scene.program?.source)
        let nodes = scene.ui?.nodes ?? []
        let roles = Set(nodes.map(\.role))
        let dataRowCount = scene.ui?.datasets.reduce(0) { $0 + $1.rows.count } ?? 0
        let bindingCount = scene.ui?.bindings.count ?? 0
    
        func usesProgram(_ names: Set<String>) -> Bool {
            !programComponents.isDisjoint(with: names)
        }
    
        func usesRole(_ candidates: Set<RichAnswerUIRole>) -> Bool {
            !roles.isDisjoint(with: candidates)
        }
        let hasEvidenceNode = roles.contains(.evidence)
        let semanticRelationLabelCount = nodes.filter { node in
            [.label, .text, .sequence, .metric].contains(node.role)
                && (
                    !node.evidenceIDs.isEmpty
                        || node.datasetID != nil
                        || node.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                )
        }.count
        let hasQuantityCanvas = roles.contains(.canvas)
            && usesRole([.axis, .line, .path, .point, .area, .bar, .dotMatrix, .vector, .metric])
    
        let isValid: Bool
        switch scene.family {
        case .textAndAlignment:
            isValid = usesProgram(["ArgumentReader", "ArgumentUnit", "ComparisonTable"])
                || (roles.contains(.text) && (roles.contains(.evidence) || usesRole([.select, .toggle, .probe])))
        case .quantityAndCoordinates:
            isValid = usesProgram([
                "FunctionPlot", "TwoPointLineLab", "LinkedDataChart", "DistributionBrush",
                "DependencyFlow", "ComparisonTable", "MetricStrip",
            ]) || (hasQuantityCanvas && dataRowCount > 0 && (bindingCount > 0 || roles.contains(.metric)))
        case .processAndState:
            isValid = usesProgram([
                "ProcessStepper", "QuadraticMechanism", "ExecutionTrack", "BalanceExperiment",
                "ArgumentReader", "CausalTrack",
            ]) || roles.contains(.sequence)
                || (usesRole([.slider, .scrubber, .select, .toggle, .probe])
                && (dataRowCount >= 2 || roles.contains(.text) || roles.contains(.metric)))
        case .relationAndEvidence:
            isValid = usesProgram([
                "ArgumentReader", "CausalTrack", "DependencyFlow", "LayeredSpatialView", "ComparisonTable",
            ]) || (hasEvidenceNode && (
                (roles.contains(.sequence) && dataRowCount >= 2)
                    || (usesRole([.path, .line, .vector]) && semanticRelationLabelCount >= 2)
            ))
        case .timeAndSpace:
            isValid = usesProgram(["CausalTrack", "LayeredSpatialView", "LinkedDataChart"])
                || (usesRole([.canvas, .image]) && usesRole([.path, .point, .region, .vector, .area]))
                || (roles.contains(.sequence) && dataRowCount >= 2)
        case .imageAndOverlay:
            isValid = roles.contains(.image) && usesRole([.region, .path, .point, .shape])
        case .comparisonAndEvaluation:
            let comparisonValueCount = scene.ui?.nodes.filter {
                [.metric, .text, .label, .bar, .dotMatrix].contains($0.role)
            }.count ?? 0
            isValid = usesProgram([
                "ComparisonTable", "LinkedDataChart", "DistributionBrush", "ArgumentReader",
                "MetricStrip", "DependencyFlow",
            ]) || (usesRole([.grid, .hstack, .vstack]) && comparisonValueCount >= 2)
        case .calculationAndConstraints:
            isValid = usesProgram([
                "DependencyFlow", "FunctionPlot", "TwoPointLineLab", "QuadraticMechanism",
                "DistributionBrush", "BalanceExperiment",
            ]) || (bindingCount > 0 && roles.contains(.metric)
                && usesRole([.slider, .scrubber, .probe])
                && usesRole([.shape, .line, .path, .bar, .metric]))
        }
    
        guard isValid else {
            return invalidValue(
                sceneID: scene.id,
                "generated UI structure does not satisfy the declared \(scene.family.rawValue) capability contract"
            )
        }
        return nil
    }
    
    static func validateGeneratedIntentContract(
        _ scene: RichAnswerScene,
        expressionPlan: RichAnswerExpressionPlan
    ) -> RichAnswerDiagnostic? {
        guard let ui = scene.ui else { return nil }
        let planDeclaresIntent = !expressionPlan.knowledgeNatures.isEmpty
            || !expressionPlan.knowledgeObjects.isEmpty
            || !expressionPlan.knowledgeRelations.isEmpty
            || !expressionPlan.knowledgeProcesses.isEmpty
            || !expressionPlan.visualPrimitives.isEmpty
            || !expressionPlan.visualRationale.isEmpty
        guard planDeclaresIntent else { return nil }
    
        let roles = Set(ui.nodes.map(\.role))
        if !expressionPlan.visualPrimitives.isEmpty {
            let primitiveRoles = expressionPlan.visualPrimitives.compactMap(RichAnswerUIRole.init(rawValue:))
            guard primitiveRoles.count == expressionPlan.visualPrimitives.count else {
                return invalidValue(
                    sceneID: scene.id,
                    "generated UI expression plan names primitives outside the T2 role catalog"
                )
            }
            let missingRoles = Set(primitiveRoles).subtracting(roles)
            guard missingRoles.isEmpty else {
                return invalidValue(
                    sceneID: scene.id,
                    "generated UI does not use its declared visual primitives: \(missingRoles.map(\.rawValue).sorted().joined(separator: ", "))"
                )
            }
        }
    
        let visibleText = visibleSemanticText(in: ui, sceneTitle: scene.title)
        var missingCategories: [String] = []
        if !expressionPlan.knowledgeObjects.isEmpty {
            let matchedObjectCount = expressionPlan.knowledgeObjects.filter {
                semanticText(visibleText, contains: $0)
            }.count
            let requiredObjectCount = min(2, expressionPlan.knowledgeObjects.count)
            if matchedObjectCount < requiredObjectCount {
                missingCategories.append(
                    "knowledge objects (show at least \(requiredObjectCount)): \(declarationSamples(expressionPlan.knowledgeObjects))"
                )
            }
        }
    
        if !expressionPlan.knowledgeRelations.isEmpty,
           !expressionPlan.knowledgeRelations.contains(where: {
               semanticText(visibleText, contains: $0)
           }),
           !generatedUIHasSemanticRelationStructure(
               ui,
               relations: expressionPlan.knowledgeRelations,
               visibleText: visibleText
           ) {
            missingCategories.append(
                "knowledge relation: \(declarationSamples(expressionPlan.knowledgeRelations))"
            )
        }
    
        if !expressionPlan.knowledgeProcesses.isEmpty {
            let hasVisibleProcess = expressionPlan.knowledgeProcesses.contains {
                semanticText(visibleText, contains: $0)
            }
            let declaresInteractiveProcess = expressionPlan.knowledgeProcesses.contains {
                declaresInteractionProcess($0)
            }
            let processHasVisibleAnchors = expressionPlan.knowledgeProcesses.contains {
                relationHasVisibleAnchors($0, visibleText: visibleText)
            }
            let hasStructuredProcess =
                (ui.nodes.contains(where: { $0.role == .sequence }) && processHasVisibleAnchors)
                || (generatedUIHasBoundSemanticInteraction(ui)
                    && (declaresInteractiveProcess || processHasVisibleAnchors))
            if !hasVisibleProcess && !hasStructuredProcess {
                missingCategories.append(
                    "knowledge process: \(declarationSamples(expressionPlan.knowledgeProcesses))"
                )
            }
        }
    
        if !missingCategories.isEmpty {
            return invalidValue(
                sceneID: scene.id,
                "generated UI misses declared semantic categories: \(missingCategories.joined(separator: "; ")); "
                    + "visible semantic summary: \(boundedVisibleSemanticSummary(in: ui, sceneTitle: scene.title))"
            )
        }
    
        let embodiedNatures: Set<RichAnswerKnowledgeNature> = [
            .objectMechanism,
            .spatialStructure,
            .imageObservation,
        ]
        let requiresEmbodiedVisual = !expressionPlan.knowledgeNatures.isDisjoint(with: embodiedNatures)
        if requiresEmbodiedVisual {
            let embodiedRoles: Set<RichAnswerUIRole> = [
                .shape,
                .vector,
                .region,
                .image,
                .area,
                .sequence,
                .bar,
                .dotMatrix,
                .line,
                .path,
                .point,
                .metric,
            ]
            guard !roles.isDisjoint(with: embodiedRoles) else {
                return invalidValue(
                    sceneID: scene.id,
                    "object, space, or image knowledge must bind to a visible semantic mark"
                )
            }
            if !ui.bindings.isEmpty {
                let controlDrivesEmbodiedMark = ui.bindings.contains { binding in
                    ui.nodes.contains { node in
                        node.bindingID == binding.id && embodiedRoles.contains(node.role)
                    }
                }
                guard controlDrivesEmbodiedMark else {
                    return invalidValue(
                        sceneID: scene.id,
                        "object, space, or image controls must change a visible semantic mark or readout"
                    )
                }
            }
        }
    
        return nil
    }
    
    static func visibleSemanticText(
        in ui: RichAnswerUIComposition,
        sceneTitle: String
    ) -> String {
        let nodeText = ui.nodes.flatMap { node in
            [node.label, node.text, node.unit, node.xAxis?.label, node.yAxis?.label].compactMap { $0 }
        }
        let rowText = ui.datasets.flatMap { dataset in
            dataset.rows.compactMap(\.label)
        }
        let bindingText = ui.bindings.flatMap { binding in
            [binding.label, binding.unit].compactMap { $0 }
        }
        return ([sceneTitle] + nodeText + rowText + bindingText).joined(separator: " ")
    }
    
    static func semanticText(_ haystack: String, contains needle: String) -> Bool {
        let normalizedHaystack = semanticSearchText(haystack)
        let normalizedNeedle = semanticSearchText(needle)
        if normalizedNeedle.count == 1 {
            if normalizedNeedle.range(of: #"^[a-z]$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                let escaped = NSRegularExpression.escapedPattern(for: normalizedNeedle)
                return haystack.range(
                    of: "(^|[^A-Za-z0-9])\(escaped)($|[^A-Za-z0-9])",
                    options: [.regularExpression, .caseInsensitive]
                ) != nil
            }
            return normalizedHaystack.contains(normalizedNeedle)
        }
        guard normalizedNeedle.count >= 2 else { return false }
        if normalizedHaystack.contains(normalizedNeedle) { return true }
        guard normalizedNeedle.count > 4 else { return false }
        let characters = Array(normalizedNeedle)
        let bigrams = Set((0..<(characters.count - 1)).map { index in
            String(characters[index...index + 1])
        })
        guard !bigrams.isEmpty else { return false }
        let matchedBigrams = bigrams.filter { normalizedHaystack.contains($0) }.count
        let requiredRatio = normalizedNeedle.count <= 8 ? 0.60 : 0.45
        return matchedBigrams >= 2
            && Double(matchedBigrams) / Double(bigrams.count) >= requiredRatio
    }
    
    static func semanticSearchText(_ text: String) -> String {
        let semanticSymbols: Set<Character> = ["=", "²", "π", "√", "∝", "Δ", "<", ">", "/", "≤", "≥", "±"]
        return text
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber || semanticSymbols.contains(character)
            }
            .map(String.init)
            .joined()
    }
    
    static func declaresInteractionProcess(_ text: String) -> Bool {
        let interactionTerms = [
            "拖动", "滑动", "调节", "调整", "切换", "选择", "点击", "探查", "探针",
            "观察", "联动", "播放", "暂停", "步进", "筛选", "缩放", "旋转", "重置", "对照", "比较",
        ]
        return interactionTerms.contains(where: text.contains)
    }
    
    static func generatedUIHasBoundSemanticInteraction(
        _ ui: RichAnswerUIComposition
    ) -> Bool {
        let controlRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .probe]
        let datasetsByID = Dictionary(uniqueKeysWithValues: ui.datasets.map { ($0.id, $0) })
        return ui.bindings.contains { binding in
            let hasControl = ui.nodes.contains {
                $0.bindingID == binding.id && controlRoles.contains($0.role)
            }
            return hasControl && bindingHasChangingOutcome(
                binding,
                reachableNodes: ui.nodes,
                datasetsByID: datasetsByID
            )
        }
    }
    
    private static let genericRelationBigrams: Set<String> = [
        "通过", "变化", "观察", "对应", "关系", "增加", "减少", "上升", "下降", "影响", "结果", "条件", "数据",
    ]
    
    static func semanticAnchorTokens(_ text: String) -> [String] {
        let pattern = #"[A-Za-z]+|[0-9]+(?:\.[0-9]+)?|[πΔ√][A-Za-z0-9]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Array(Set(expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { text[$0].lowercased() }
        }))
    }
    
    static func hanBigrams(_ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"[一-鿿]+"#) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let bigrams = expression.matches(in: text, range: range).flatMap { match -> [String] in
            guard let matchRange = Range(match.range, in: text) else { return [] }
            let characters = Array(text[matchRange])
            guard characters.count >= 2 else { return [] }
            return (0..<(characters.count - 1)).map { index in
                String(characters[index...index + 1])
            }
        }.filter { !genericRelationBigrams.contains($0) }
        return Array(Set(bigrams))
    }
    
    static func relationHasVisibleAnchors(
        _ relation: String,
        visibleText: String
    ) -> Bool {
        if semanticText(visibleText, contains: relation) { return true }
        let tokenMatches = semanticAnchorTokens(relation).filter {
            semanticText(visibleText, contains: $0)
        }.count
        let bigramMatches = hanBigrams(relation).filter { visibleText.contains($0) }.count
        return tokenMatches >= 2
            || bigramMatches >= 2
            || (tokenMatches >= 1 && bigramMatches >= 1)
    }
    
    static func generatedUIHasSemanticRelationStructure(
        _ ui: RichAnswerUIComposition,
        relations: [String],
        visibleText: String
    ) -> Bool {
        guard relations.contains(where: {
            relationHasVisibleAnchors($0, visibleText: visibleText)
        }) else {
            return false
        }
        let relationRoles: Set<RichAnswerUIRole> = [
            .line, .path, .point, .area, .bar, .dotMatrix, .vector, .sequence, .metric,
        ]
        let datasetsByID = Dictionary(uniqueKeysWithValues: ui.datasets.map { ($0.id, $0) })
        let hasNamedAxis = ui.nodes.contains { node in
            node.xAxis?.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || node.yAxis?.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let hasNamedBinding = ui.bindings.contains {
            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return ui.nodes.contains { node in
            guard relationRoles.contains(node.role),
                  let datasetID = node.datasetID,
                  let dataset = datasetsByID[datasetID],
                  datasetRowsHaveChangingOutcome(
                      dataset.rows,
                      acceptsSemanticOnly: node.role == .sequence
                  ) else {
                return false
            }
            let hasVisibleLabel = node.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || dataset.rows.contains {
                    $0.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
            return hasVisibleLabel || hasNamedAxis || hasNamedBinding
        }
    }
    
    static func boundedVisibleSemanticSummary(
        in ui: RichAnswerUIComposition,
        sceneTitle: String
    ) -> String {
        let roles = Set(ui.nodes.map { $0.role.rawValue }).sorted().joined(separator: ",")
        let visible = visibleSemanticText(in: ui, sceneTitle: sceneTitle)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let summary = "roles=\(roles.isEmpty ? "none" : roles); text=\(visible.isEmpty ? "none" : visible)"
        guard summary.count > 360 else { return summary }
        return String(summary.prefix(357)) + "..."
    }
    
    static func declarationSamples(_ values: [String]) -> String {
        values.prefix(2).joined(separator: "、")
    }
    
    static func generatedProgramComponents(in source: String?) -> Set<String> {
        guard let source else { return [] }
        return Set(source.split(whereSeparator: { $0.isNewline }).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.hasPrefix("$"),
                  let equals = line.firstIndex(of: "="),
                  let openParenthesis = line[equals...].firstIndex(of: "(") else {
                return nil
            }
            return line[line.index(after: equals)..<openParenthesis]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        })
    }
}
