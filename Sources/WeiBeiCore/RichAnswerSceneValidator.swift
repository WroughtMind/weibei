import Foundation

extension RichAnswerEngine {
    static func validateScenes(
        _ scenes: [RichAnswerScene],
        expressionPlan: RichAnswerExpressionPlan,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment,
        diagnostics: inout [RichAnswerDiagnostic]
    ) -> SceneValidationResult {
        var validScenes: [RichAnswerScene] = []
        var seenSceneIDs: Set<String> = []
        let maxScenes = max(0, environment.resourceBudget.maxScenes)
    
        for scene in scenes.prefix(maxScenes) {
            if !seenSceneIDs.insert(scene.id).inserted {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .duplicateID,
                        sceneID: scene.id,
                        message: "scene id \(scene.id) is duplicated"
                    )
                )
                continue
            }
    
            if let issue = validateScene(
                scene,
                expressionPlan: expressionPlan,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                diagnostics.append(issue)
                continue
            }
    
            validScenes.append(scene)
        }
    
        if scenes.count > maxScenes {
            for scene in scenes.dropFirst(maxScenes) {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .budgetExceeded,
                        sceneID: scene.id,
                        message: "scene exceeded the allowed scene budget"
                    )
                )
            }
        }
    
        return SceneValidationResult(validScenes: validScenes)
    }
    
    static func validateScene(
        _ scene: RichAnswerScene,
        expressionPlan: RichAnswerExpressionPlan,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard isSafeIdentifier(scene.id) else {
            return RichAnswerDiagnostic(
                code: .invalidValue,
                sceneID: scene.id,
                message: "scene id is empty or unsafe"
            )
        }
        guard expressionPlan.families.contains(scene.family) else {
            return RichAnswerDiagnostic(
                code: .unsupportedFamily,
                sceneID: scene.id,
                message: "scene family is not declared by the expression plan"
            )
        }
        let rendererEntryCount = [scene.program != nil, scene.ui != nil, scene.renderPlan != nil]
            .filter { $0 }
            .count
        guard rendererEntryCount > 0 || !scene.objects.isEmpty else {
            return RichAnswerDiagnostic(
                code: .emptyScene,
                sceneID: scene.id,
                message: "scene must submit one generated renderer entry or a legacy knowledge-object scene"
            )
        }
        guard rendererEntryCount <= 1 else {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "scene cannot submit more than one of program, ui, or renderPlan"
            )
        }
        guard scene.program == nil || scene.operations.isEmpty else {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "OpenUI program scenes cannot also submit legacy operations"
            )
        }
        guard scene.renderPlan == nil || scene.operations.isEmpty else {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "renderPlan scenes cannot also submit legacy operations"
            )
        }
        guard !scene.evidenceIDs.isEmpty else {
            return RichAnswerDiagnostic(
                code: .missingEvidence,
                sceneID: scene.id,
                message: "scene does not bind to any evidence"
            )
        }
        guard scene.objects.count <= environment.resourceBudget.maxObjectsPerScene,
              scene.relations.count <= environment.resourceBudget.maxRelationsPerScene,
              scene.operations.count <= environment.resourceBudget.maxOperationsPerScene,
              scene.frames.count <= environment.resourceBudget.maxFramesPerScene,
              (scene.ui?.nodes.count ?? 0) <= environment.resourceBudget.maxUINodesPerScene,
              (scene.ui?.datasets.flatMap(\.rows).count ?? 0) <= environment.resourceBudget.maxUIDataRowsPerScene,
              (scene.ui?.bindings.count ?? 0) <= environment.resourceBudget.maxUIBindingsPerScene else {
            return RichAnswerDiagnostic(
                code: .budgetExceeded,
                sceneID: scene.id,
                message: "scene exceeded the rich-answer resource budget"
            )
        }
        guard scene.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return RichAnswerDiagnostic(
                code: .missingEvidence,
                sceneID: scene.id,
                message: "scene references evidence that is missing or not allowed"
            )
        }
    
        let objectIDs = scene.objects.map(\.id)
        let relationIDs = scene.relations.map(\.id)
        let operationIDs = scene.operations.map(\.id)
        let frameIDs = scene.frames.map(\.id)
        let allLocalIDs = objectIDs + relationIDs + operationIDs + frameIDs
        guard idsAreUniqueAndSafe(allLocalIDs) else {
            return RichAnswerDiagnostic(
                code: .duplicateID,
                sceneID: scene.id,
                message: "scene object, relation, operation, and frame ids must be unique and safe"
            )
        }
    
        let objectIDSet = Set(objectIDs)
        let relationIDSet = Set(relationIDs)
        let frameIDSet = Set(frameIDs)
        let referableIDs = objectIDSet.union(relationIDSet).union(frameIDSet)
    
        for object in scene.objects {
            if let issue = validateObject(
                object,
                sceneID: scene.id,
                frameIDs: frameIDSet,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
        }
    
        for relation in scene.relations {
            if let issue = validateRelation(
                relation,
                sceneID: scene.id,
                objectIDs: objectIDSet,
                evidenceByID: evidenceByID
            ) {
                return issue
            }
        }
    
        for operation in scene.operations {
            if let issue = validateOperation(
                operation,
                sceneID: scene.id,
                referableIDs: referableIDs,
                frameIDs: frameIDSet
            ) {
                return issue
            }
        }
    
        for frame in scene.frames {
            if let issue = validateFrame(
                frame,
                sceneID: scene.id,
                objectIDs: objectIDSet,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
        }
    
        if let program = scene.program {
            if let issue = validateUIProgram(program, scene: scene) {
                return issue
            }
            return nil
        }
    
        if let ui = scene.ui {
            if let issue = validateUIComposition(
                ui,
                sceneID: scene.id,
                evidenceByID: evidenceByID,
                environment: environment
            ) {
                return issue
            }
            let boundEvidenceIDs = reachableUIEvidenceIDs(in: ui)
            guard Set(scene.evidenceIDs).isSubset(of: boundEvidenceIDs) else {
                return missingEvidence(
                    sceneID: scene.id,
                    "generated UI does not bind every scene evidence item to a reachable node or data row"
                )
            }
            return nil
        }
    
        if let renderPlan = scene.renderPlan {
            return validateRenderPlan(
                renderPlan,
                scene: scene,
                evidenceByID: evidenceByID
            )
        }
    
        if let issue = validateFamilyContract(scene) {
            return issue
        }
    
        return nil
    }
    
    static func validateRenderPlan(
        _ plan: RichAnswerRenderPlan,
        scene: RichAnswerScene,
        evidenceByID: [String: RichAnswerEvidence]
    ) -> RichAnswerDiagnostic? {
        let negotiation = RichAnswerRendererRegistry.defaultRegistry().negotiate(plan: plan)
        guard negotiation.status == .accepted else {
            let message = negotiation.mismatch?.issues.first?.message ?? "renderPlan capability negotiation failed"
            return RichAnswerDiagnostic(
                code: .invalidParameter,
                sceneID: scene.id,
                message: "renderPlan capability negotiation failed: \(message)"
            )
        }
    
        let sceneEvidenceIDs = Set(scene.evidenceIDs)
        let boundEvidenceIDs = Set(plan.sourceBindings.map(\.evidenceID))
        guard plan.sourceBindings.allSatisfy({
            sceneEvidenceIDs.contains($0.evidenceID) && evidenceByID[$0.evidenceID] != nil
        }) else {
            return missingEvidence(
                sceneID: scene.id,
                "renderPlan sourceBindings must reference evidence IDs declared by this scene and evidence ledger"
            )
        }
        guard sceneEvidenceIDs.isSubset(of: boundEvidenceIDs) else {
            return missingEvidence(
                sceneID: scene.id,
                "renderPlan sourceBindings must cover every scene evidence item"
            )
        }
    
        return nil
    }
}
