import Foundation

// Validates domain operations, scene objects, references, frames, and evidence state.
extension RichAnswerEngine {
    static func validateSupportedOperations(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let supportedKinds = supportedOperationKinds(for: scene.family)
        if let unsupportedOperation = scene.operations.first(where: { !supportedKinds.contains($0.kind) }) {
            return RichAnswerDiagnostic(
                code: .unsupportedField,
                sceneID: scene.id,
                message: "operation \(unsupportedOperation.kind.rawValue) is not supported by the \(scene.family.rawValue) renderer"
            )
        }
        return nil
    }
    
    static func supportedOperationKinds(
        for family: RichAnswerCapabilityFamily
    ) -> Set<RichAnswerOperationKind> {
        switch family {
        case .textAndAlignment:
            return [.select, .reveal, .reset]
        case .quantityAndCoordinates:
            return [.adjust, .probe, .select, .reset]
        case .processAndState:
            return [.select, .step, .playPause, .reset]
        case .relationAndEvidence:
            return [.select, .reveal, .reset]
        case .timeAndSpace:
            return [.scrub, .toggle, .reset]
        case .imageAndOverlay:
            return [.select, .toggle, .zoom]
        case .comparisonAndEvaluation:
            return [.compare, .select, .reset]
        case .calculationAndConstraints:
            return [.adjust, .reset]
        }
    }
    
    static func validateTextAlignmentContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let selectableTextIDs = Set(
            scene.objects.lazy
                .filter { $0.kind == .text && hasMeaningfulText($0.text) }
                .map(\.id)
        )
        guard !selectableTextIDs.isEmpty,
              scene.operations.contains(where: {
                  $0.kind == .select && $0.targetIDs.contains(where: selectableTextIDs.contains)
              }) else {
            return invalidValue(
                sceneID: scene.id,
                "text alignment scenes require a selectable text object"
            )
        }
        return nil
    }
    
    static func validateQuantityCoordinateContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let coordinateFrameIDs = Set(
            scene.frames.lazy
                .filter { $0.kind == .cartesian }
                .map(\.id)
        )
        guard !coordinateFrameIDs.isEmpty else {
            return invalidValue(sceneID: scene.id, "quantity scenes require a cartesian coordinate frame")
        }
    
        let plottedObjects = scene.objects.filter { object in
            (object.kind == .quantity || object.kind == .dataPoint)
                && object.coordinate?.isNormalized == true
                && object.frameID.map(coordinateFrameIDs.contains) == true
        }
        guard plottedObjects.count >= 2 else {
            return invalidValue(
                sceneID: scene.id,
                "quantity scenes require at least two coordinate points attached to a coordinate frame"
            )
        }
        return nil
    }
    
    static func validateProcessStateContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let processObjectIDs = Set(
            scene.objects.lazy
                .filter { $0.kind == .step || $0.kind == .state }
                .map(\.id)
        )
        guard processObjectIDs.count >= 2 else {
            return invalidValue(sceneID: scene.id, "process scenes require at least two step or state objects")
        }
        guard operationExists(in: scene, kind: .step, targetingAtLeast: 2, within: processObjectIDs),
              operationExists(in: scene, kind: .playPause, targetingAtLeast: 2, within: processObjectIDs) else {
            return invalidValue(sceneID: scene.id, "process scenes require step and play controls targeting process objects")
        }
        return nil
    }
    
    static func validateRelationEvidenceContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        guard !scene.relations.isEmpty else {
            return invalidValue(sceneID: scene.id, "relation scenes require at least one relationship")
        }
        return nil
    }
    
    static func validateTimeSpaceContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let navigableFrameIDs = Set(
            scene.frames.lazy
                .filter { $0.kind == .timeline || $0.kind == .space }
                .map(\.id)
        )
        guard !navigableFrameIDs.isEmpty else {
            return invalidValue(sceneID: scene.id, "time-space scenes require a timeline or space frame")
        }
    
        let navigableObjectIDs = Set(
            scene.objects.lazy
                .filter {
                    $0.coordinate?.isNormalized == true
                        && $0.frameID.map(navigableFrameIDs.contains) == true
                }
                .map(\.id)
        )
        guard navigableObjectIDs.count >= 2 else {
            return invalidValue(
                sceneID: scene.id,
                "time-space scenes require at least two positioned objects on a timeline or space frame"
            )
        }
        guard operationExists(in: scene, kind: .scrub, targetingAtLeast: 1, within: navigableObjectIDs.union(navigableFrameIDs)) else {
            return invalidValue(sceneID: scene.id, "time-space scenes require a scrub operation")
        }
        return nil
    }
    
    static func validateImageOverlayContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let imageFrames = scene.frames.filter { $0.kind == .image && $0.assetID != nil }
        let imageFrameIDs = Set(imageFrames.map(\.id))
        guard !imageFrameIDs.isEmpty else {
            return invalidValue(sceneID: scene.id, "image overlay scenes require an image frame with an asset")
        }
    
        let frameAssetIDs = Set(imageFrames.compactMap(\.assetID))
        let imageObjects = scene.objects.filter {
            $0.kind == .image
                && $0.assetID.map(frameAssetIDs.contains) == true
                && $0.frameID.map(imageFrameIDs.contains) == true
        }
        let regionObjects = scene.objects.filter {
            $0.kind == .region
                && $0.bounds != nil
                && $0.frameID.map(imageFrameIDs.contains) == true
        }
        guard !imageObjects.isEmpty, !regionObjects.isEmpty else {
            return invalidValue(
                sceneID: scene.id,
                "image overlay scenes require an image object and a bounded region in the image frame"
            )
        }
        return nil
    }
    
    static func validateComparisonEvaluationContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        let objectIDs = Set(scene.objects.map(\.id))
        guard scene.operations.contains(where: { operation in
            operation.kind == .compare
                && Set(operation.targetIDs).intersection(objectIDs).count >= 2
        }) else {
            return invalidValue(sceneID: scene.id, "comparison scenes require a compare operation with at least two object targets")
        }
        return nil
    }
    
    static func validateCalculationConstraintContract(_ scene: RichAnswerScene) -> RichAnswerDiagnostic? {
        guard scene.objects.contains(where: { $0.kind == .formula && hasMeaningfulText($0.text) }),
              scene.objects.contains(where: { $0.kind == .constraint && hasMeaningfulText($0.text) }) else {
            return invalidValue(sceneID: scene.id, "calculation scenes require a formula and a constraint")
        }
    
        let frameIDs = Set(scene.frames.map(\.id))
        guard scene.operations.contains(where: { operation in
            guard operation.kind == .adjust, operation.parameter != nil else { return false }
            let samples = numericCoordinateSamples(for: operation, in: scene, frameIDs: frameIDs)
            return samples.count >= 2 && Set(samples.compactMap { $0.coordinate?.x }).count >= 2
        }) else {
            return invalidValue(
                sceneID: scene.id,
                "calculation scenes require an adjust operation targeting at least two numeric coordinate samples"
            )
        }
        return nil
    }
    
    static func operationExists(
        in scene: RichAnswerScene,
        kind: RichAnswerOperationKind,
        targetingAtLeast minimumTargetCount: Int,
        within allowedTargetIDs: Set<String>
    ) -> Bool {
        scene.operations.contains { operation in
            operation.kind == kind
                && Set(operation.targetIDs).intersection(allowedTargetIDs).count >= minimumTargetCount
        }
    }
    
    static func numericCoordinateSamples(
        for operation: RichAnswerOperation,
        in scene: RichAnswerScene,
        frameIDs: Set<String>
    ) -> [RichAnswerObject] {
        let targetIDs = Set(operation.targetIDs)
        return scene.objects.filter { object in
            targetIDs.contains(object.id)
                && object.number != nil
                && object.coordinate?.isNormalized == true
                && object.frameID.map(frameIDs.contains) == true
        }
    }
    
    static func hasMeaningfulText(_ text: String?) -> Bool {
        text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    
    static func validateObject(
        _ object: RichAnswerObject,
        sceneID: String,
        frameIDs: Set<String>,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard object.number.map({ $0.isFinite }) ?? true else {
            return invalidValue(sceneID: sceneID, "object \(object.id) has a non-finite number")
        }
        guard object.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "object \(object.id) references missing or disallowed evidence")
        }
        if let assetID = object.assetID, !isAllowedAssetID(assetID, environment: environment) {
            return RichAnswerDiagnostic(
                code: .unauthorizedAsset,
                sceneID: sceneID,
                message: "object \(object.id) references an asset that is not allowed in this context"
            )
        }
        if let frameID = object.frameID, !frameIDs.contains(frameID) {
            return brokenReference(sceneID: sceneID, "object \(object.id) references missing frame \(frameID)")
        }
        if (object.coordinate != nil || object.bounds != nil), object.frameID == nil {
            return brokenReference(sceneID: sceneID, "object \(object.id) has coordinates without a frame reference")
        }
        if let coordinate = object.coordinate, !coordinate.isFinite {
            return invalidValue(sceneID: sceneID, "object \(object.id) has non-finite coordinates")
        }
        if let bounds = object.bounds, !bounds.isValid {
            return invalidValue(sceneID: sceneID, "object \(object.id) has invalid bounds")
        }
        return nil
    }
    
    static func validateRelation(
        _ relation: RichAnswerRelation,
        sceneID: String,
        objectIDs: Set<String>,
        evidenceByID: [String: RichAnswerEvidence]
    ) -> RichAnswerDiagnostic? {
        guard objectIDs.contains(relation.sourceID),
              objectIDs.contains(relation.targetID) else {
            return brokenReference(
                sceneID: sceneID,
                "relation \(relation.id) references an object that is not present"
            )
        }
        guard relation.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "relation \(relation.id) references missing or disallowed evidence")
        }
        return nil
    }
    
    static func validateOperation(
        _ operation: RichAnswerOperation,
        sceneID: String,
        referableIDs: Set<String>,
        frameIDs: Set<String>
    ) -> RichAnswerDiagnostic? {
        guard !operation.targetIDs.isEmpty,
              operation.targetIDs.allSatisfy({ referableIDs.contains($0) }) else {
            return brokenReference(
                sceneID: sceneID,
                "operation \(operation.id) references a target that is not present"
            )
        }
        if let frameID = operation.frameID, !frameIDs.contains(frameID) {
            return brokenReference(sceneID: sceneID, "operation \(operation.id) references missing frame \(frameID)")
        }
        if let parameter = operation.parameter, !parameter.isValid {
            return RichAnswerDiagnostic(
                code: .invalidParameter,
                sceneID: sceneID,
                message: "operation \(operation.id) has an invalid adjustment parameter"
            )
        }
        return nil
    }
    
    static func validateFrame(
        _ frame: RichAnswerFrame,
        sceneID: String,
        objectIDs: Set<String>,
        evidenceByID: [String: RichAnswerEvidence],
        environment: RichAnswerEnvironment
    ) -> RichAnswerDiagnostic? {
        guard frame.objectIDs.allSatisfy({ objectIDs.contains($0) }) else {
            return brokenReference(sceneID: sceneID, "frame \(frame.id) references an object that is not present")
        }
        guard frame.evidenceIDs.allSatisfy({ evidenceByID[$0] != nil }) else {
            return missingEvidence(sceneID: sceneID, "frame \(frame.id) references missing or disallowed evidence")
        }
        if frame.kind == .cartesian {
            guard let xAxis = frame.xAxis, let yAxis = frame.yAxis,
                  xAxis.isValid,
                  yAxis.isValid else {
                return invalidValue(sceneID: sceneID, "cartesian frame \(frame.id) requires valid x and y axes")
            }
        } else {
            guard frame.xAxis.map(\.isValid) ?? true,
                  frame.yAxis.map(\.isValid) ?? true else {
                return invalidValue(sceneID: sceneID, "frame \(frame.id) has an invalid axis")
            }
        }
        if let assetID = frame.assetID, !isAllowedAssetID(assetID, environment: environment) {
            return RichAnswerDiagnostic(
                code: .unauthorizedAsset,
                sceneID: sceneID,
                message: "frame \(frame.id) references an asset that is not allowed in this context"
            )
        }
        return nil
    }
    
    static func referencedEvidenceLedger(
        from scenes: [RichAnswerScene],
        evidenceByID: [String: RichAnswerEvidence]
    ) -> [RichAnswerEvidence] {
        let referencedIDs = Set(scenes.flatMap(\.allEvidenceIDs))
        return evidenceByID.values
            .filter { referencedIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
    }
    
    static func evidenceState(
        hasScenes: Bool,
        diagnostics: [RichAnswerDiagnostic],
        invalidEvidenceWasSeen: Bool,
        hasTruncatedEvidence: Bool
    ) -> RichAnswerEvidenceState {
        guard hasScenes else { return .missing }
        let evidenceCodes: Set<RichAnswerDiagnosticCode> = [
            .missingEvidence,
            .unsupportedEvidence,
            .unauthorizedAsset,
        ]
        if hasTruncatedEvidence
            || invalidEvidenceWasSeen
            || diagnostics.contains(where: { evidenceCodes.contains($0.code) }) {
            return .partial
        }
        return .complete
    }
    
    static func idsAreUniqueAndSafe(_ ids: [String]) -> Bool {
        ids.allSatisfy(isSafeIdentifier) && Set(ids).count == ids.count
    }
    
    static func isSafeIdentifier(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return false }
        return !trimmed.contains("://") && !trimmed.contains("<") && !trimmed.contains(">")
    }
    
    static func isAllowedAssetID(_ assetID: String, environment: RichAnswerEnvironment) -> Bool {
        isSafeIdentifier(assetID) && environment.allowedAssetIDs.contains(assetID)
    }
    
    static func brokenReference(sceneID: String, _ message: String) -> RichAnswerDiagnostic {
        RichAnswerDiagnostic(code: .brokenReference, sceneID: sceneID, message: message)
    }
    
    static func missingEvidence(sceneID: String, _ message: String) -> RichAnswerDiagnostic {
        RichAnswerDiagnostic(code: .missingEvidence, sceneID: sceneID, message: message)
    }
    
    static func invalidValue(sceneID: String, _ message: String) -> RichAnswerDiagnostic {
        RichAnswerDiagnostic(code: .invalidValue, sceneID: sceneID, message: message)
    }
}

struct SceneValidationResult {
    var validScenes: [RichAnswerScene]
}

private extension RichAnswerParameter {
    var isValid: Bool {
        minimum.isFinite
            && maximum.isFinite
            && step.isFinite
            && initialValue.isFinite
            && minimum < maximum
            && step > 0
            && initialValue >= minimum
            && initialValue <= maximum
    }
}

private extension RichAnswerAxis {
    var isValid: Bool {
        minimum.isFinite && maximum.isFinite && minimum < maximum
    }
}

private extension RichAnswerPoint {
    var isFinite: Bool {
        x.isFinite && y.isFinite
    }

    var isNormalized: Bool {
        isFinite && x >= 0 && x <= 1 && y >= 0 && y <= 1
    }
}

private extension RichAnswerRegion {
    var isValid: Bool {
        x.isFinite
            && y.isFinite
            && width.isFinite
            && height.isFinite
            && x >= 0
            && y >= 0
            && width > 0
            && height > 0
            && x + width <= 1
            && y + height <= 1
    }
}

private extension RichAnswerScene {
    var allEvidenceIDs: [String] {
        var identifiers = evidenceIDs
        identifiers.append(contentsOf: objects.flatMap(\.evidenceIDs))
        identifiers.append(contentsOf: relations.flatMap(\.evidenceIDs))
        identifiers.append(contentsOf: frames.flatMap(\.evidenceIDs))
        identifiers.append(contentsOf: ui?.allEvidenceIDs ?? [])
        identifiers.append(contentsOf: renderPlan?.sourceBindings.map(\.evidenceID) ?? [])
        return identifiers
    }
}
