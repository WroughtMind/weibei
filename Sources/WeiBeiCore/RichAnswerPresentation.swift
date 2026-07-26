import Foundation

public enum RichAnswerPartKind: String, Codable, Hashable, Sendable {
    case narrative
    case scene
}

public struct RichAnswerPart: Codable, Hashable, Sendable {
    public var kind: RichAnswerPartKind
    public var text: String?
    public var sceneID: String?

    public init(kind: RichAnswerPartKind, text: String? = nil, sceneID: String? = nil) {
        self.kind = kind
        self.text = text
        self.sceneID = sceneID
    }

    public static func narrative(_ text: String) -> RichAnswerPart {
        RichAnswerPart(kind: .narrative, text: text)
    }

    public static func scene(_ sceneID: String) -> RichAnswerPart {
        RichAnswerPart(kind: .scene, sceneID: sceneID)
    }
}

public struct RichAnswerPresentation: Codable, Hashable, Sendable {
    public var mode: RichAnswerPresentationMode
    public var narrative: String
    public var parts: [RichAnswerPart]?
    public var expressionPlan: RichAnswerExpressionPlan?
    public var scenes: [RichAnswerScene]
    public var evidenceLedger: [RichAnswerEvidence]
    public var fallback: RichAnswerFallback?
    public var diagnostics: [RichAnswerDiagnostic]
    public var evidenceState: RichAnswerEvidenceState

    public init(
        mode: RichAnswerPresentationMode,
        narrative: String,
        parts: [RichAnswerPart]? = nil,
        expressionPlan: RichAnswerExpressionPlan? = nil,
        scenes: [RichAnswerScene] = [],
        evidenceLedger: [RichAnswerEvidence] = [],
        fallback: RichAnswerFallback? = nil,
        diagnostics: [RichAnswerDiagnostic] = [],
        evidenceState: RichAnswerEvidenceState = .missing
    ) {
        self.mode = mode
        self.narrative = narrative
        self.parts = parts
        self.expressionPlan = expressionPlan
        self.scenes = scenes
        self.evidenceLedger = evidenceLedger
        self.fallback = fallback
        self.diagnostics = diagnostics
        self.evidenceState = evidenceState
    }

    public var resolvedParts: [RichAnswerPart] {
        if let parts, !parts.isEmpty {
            return parts
        }
        var fallbackParts: [RichAnswerPart] = []
        let trimmedNarrative = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNarrative.isEmpty {
            fallbackParts.append(.narrative(trimmedNarrative))
        }
        fallbackParts.append(contentsOf: scenes.map { .scene($0.id) })
        return fallbackParts
    }

    public func resolvingAssetIDs(using aliases: [String: String]) -> RichAnswerPresentation {
        guard !aliases.isEmpty else { return self }
        var resolved = self
        resolved.scenes = scenes.map { scene in
            var resolvedScene = scene
            resolvedScene.objects = scene.objects.map { object in
                var resolvedObject = object
                if let assetID = object.assetID {
                    resolvedObject.assetID = aliases[assetID] ?? assetID
                }
                return resolvedObject
            }
            resolvedScene.frames = scene.frames.map { frame in
                var resolvedFrame = frame
                if let assetID = frame.assetID {
                    resolvedFrame.assetID = aliases[assetID] ?? assetID
                }
                return resolvedFrame
            }
            if var ui = scene.ui {
                ui.nodes = ui.nodes.map { node in
                    var resolvedNode = node
                    if let assetID = node.assetID {
                        resolvedNode.assetID = aliases[assetID] ?? assetID
                    }
                    return resolvedNode
                }
                resolvedScene.ui = ui
            }
            if var renderPlan = scene.renderPlan {
                renderPlan.spec.fields = renderPlan.spec.fields.mapValues {
                    $0.resolvingAssetReferences(using: aliases)
                }
                resolvedScene.renderPlan = renderPlan
            }
            return resolvedScene
        }
        resolved.evidenceLedger = evidenceLedger.map { evidence in
            var resolvedEvidence = evidence
            resolvedEvidence.assetIDs = evidence.assetIDs.map { aliases[$0] ?? $0 }
            return resolvedEvidence
        }
        return resolved
    }
}
