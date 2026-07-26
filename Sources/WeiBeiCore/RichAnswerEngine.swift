import Foundation

extension RichAnswerRenderSpecValue {
    func resolvingAssetReferences(using aliases: [String: String]) -> RichAnswerRenderSpecValue {
        switch self {
        case .null, .bool, .number, .string:
            return self
        case let .array(values):
            return .array(values.map { $0.resolvingAssetReferences(using: aliases) })
        case let .object(fields):
            var resolvedFields = fields.mapValues {
                $0.resolvingAssetReferences(using: aliases)
            }
            if case let .string(kind)? = fields["kind"],
               kind == "assetRef",
               case let .string(source)? = fields["source"] {
                resolvedFields["source"] = .string(aliases[source] ?? source)
            }
            return .object(resolvedFields)
        }
    }
}

public enum RichAnswerEngine {
    public static func prepare(
        envelope: RichAnswerEnvelope,
        environment: RichAnswerEnvironment
    ) -> RichAnswerPresentation {
        var diagnostics: [RichAnswerDiagnostic] = []

        guard envelope.schemaVersion == RichAnswerEnvelope.supportedSchemaVersion else {
            return narrativeFallback(
                envelope: envelope,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: .unsupportedSchema,
                        message: "unsupported rich-answer schema version \(envelope.schemaVersion)"
                    ),
                ]
            )
        }

        guard envelope.contextRevision == environment.contextRevision,
              !envelope.contextRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return narrativeFallback(
                envelope: envelope,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: .staleContext,
                        message: "rich answer context does not match the current material revision"
                    ),
                ]
            )
        }

        guard !envelope.narrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.narrative.count <= 3_200,
              !envelope.fallback.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.fallback.text.count <= 3_200,
              !envelope.expressionPlan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              envelope.expressionPlan.summary.count <= 600 else {
            return narrativeFallback(
                envelope: envelope,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: .budgetExceeded,
                        message: "rich answer narrative or expression plan exceeded its text budget"
                    ),
                ]
            )
        }

        if envelope.expressionPlan.families.isEmpty {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .unsupportedFamily,
                    message: "rich answer expression plan did not declare a capability family"
                )
            )
        }
        if let issue = validateExpressionPlanIntentBudget(envelope.expressionPlan) {
            diagnostics.append(issue)
            return narrativeFallback(envelope: envelope, diagnostics: diagnostics)
        }

        let evidenceResult = validateEvidenceLedger(
            envelope.evidenceLedger,
            environment: environment,
            diagnostics: &diagnostics
        )
        let sceneResult = validateScenes(
            envelope.scenes,
            expressionPlan: envelope.expressionPlan,
            evidenceByID: evidenceResult.validEvidenceByID,
            environment: environment,
            diagnostics: &diagnostics
        )

        let scenes = sceneResult.validScenes
        let evidenceLedger = referencedEvidenceLedger(
            from: scenes,
            evidenceByID: evidenceResult.validEvidenceByID
        )
        let directUIRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .select, .probe, .sequence]
        let hasDirectOperations = scenes.contains { scene in
            !scene.operations.isEmpty
                || scene.program?.directManipulation == true
                || scene.ui?.nodes.contains(where: { directUIRoles.contains($0.role) }) == true
                || scene.renderPlan?.interactionBindings.isEmpty == false
        }
        guard envelope.expressionPlan.directManipulation == hasDirectOperations else {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .invalidParameter,
                    message: "rich answer direct-manipulation plan does not match its accepted operations"
                )
            )
            return narrativeFallback(envelope: envelope, diagnostics: diagnostics)
        }
        let mode: RichAnswerPresentationMode = scenes.isEmpty ? .narrativeOnly : .rich
        let flow = contentFlow(
            narrative: envelope.narrative,
            scenes: scenes,
            diagnostics: &diagnostics
        )
        guard mode != .rich || !flow.narrative.isEmpty else {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .invalidValue,
                    message: "rich answer content flow must retain readable narrative"
                )
            )
            return narrativeFallback(envelope: envelope, diagnostics: diagnostics)
        }
        let narrative = scenes.isEmpty && !diagnostics.isEmpty ? envelope.fallback.text : flow.narrative

        return RichAnswerPresentation(
            mode: mode,
            narrative: narrative,
            parts: mode == .rich ? flow.parts : nil,
            expressionPlan: envelope.expressionPlan,
            scenes: scenes,
            evidenceLedger: evidenceLedger,
            fallback: envelope.fallback,
            diagnostics: diagnostics,
            evidenceState: evidenceState(
                hasScenes: !scenes.isEmpty,
                diagnostics: diagnostics,
                invalidEvidenceWasSeen: evidenceResult.invalidEvidenceWasSeen,
                hasTruncatedEvidence: evidenceLedger.contains(where: \.isTruncated)
            )
        )
    }

    public static func prepare(
        data: Data,
        fallbackText: String,
        environment: RichAnswerEnvironment
    ) -> RichAnswerPresentation {
        do {
            let envelope = try JSONDecoder().decode(RichAnswerEnvelope.self, from: data)
            return prepare(envelope: envelope, environment: environment)
        } catch {
            let code: RichAnswerDiagnosticCode = error.isUnsupportedRichAnswerField ? .unsupportedField : .decodeFailed
            return RichAnswerPresentation(
                mode: .narrativeOnly,
                narrative: fallbackText,
                diagnostics: [
                    RichAnswerDiagnostic(
                        code: code,
                        message: "rich answer payload was rejected: \(error.localizedDescription)"
                    ),
                ],
                evidenceState: .missing
            )
        }
    }

    private static func narrativeFallback(
        envelope: RichAnswerEnvelope,
        diagnostics: [RichAnswerDiagnostic]
    ) -> RichAnswerPresentation {
        RichAnswerPresentation(
            mode: .narrativeOnly,
            narrative: envelope.fallback.text,
            expressionPlan: envelope.expressionPlan,
            fallback: envelope.fallback,
            diagnostics: diagnostics,
            evidenceState: .missing
        )
    }

    private static func contentFlow(
        narrative: String,
        scenes: [RichAnswerScene],
        diagnostics: inout [RichAnswerDiagnostic]
    ) -> (narrative: String, parts: [RichAnswerPart]) {
        let scenesByID = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, $0) })
        var parts: [RichAnswerPart] = []
        var narrativeLines: [String] = []
        var referencedSceneIDs: Set<String> = []

        func flushNarrative() {
            let text = narrativeLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            narrativeLines.removeAll(keepingCapacity: true)
            if !text.isEmpty {
                parts.append(.narrative(text))
            }
        }

        for line in narrative.components(separatedBy: .newlines) {
            guard let sceneID = richAnswerSceneMarkerID(in: line) else {
                if line.contains("weibei-scene:") {
                    diagnostics.append(
                        RichAnswerDiagnostic(
                            code: .invalidValue,
                            message: "rich answer narrative contains a malformed scene marker"
                        )
                    )
                    continue
                }
                narrativeLines.append(line)
                continue
            }
            flushNarrative()
            guard scenesByID[sceneID] != nil else {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .brokenReference,
                        sceneID: sceneID,
                        message: "rich answer narrative references an unknown scene"
                    )
                )
                continue
            }
            guard referencedSceneIDs.insert(sceneID).inserted else {
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .duplicateID,
                        sceneID: sceneID,
                        message: "rich answer narrative references the same scene more than once"
                    )
                )
                continue
            }
            parts.append(.scene(sceneID))
        }
        flushNarrative()

        for scene in scenes where !referencedSceneIDs.contains(scene.id) {
            parts.append(.scene(scene.id))
        }

        let plainNarrative = parts.compactMap { part -> String? in
            guard part.kind == .narrative else { return nil }
            return part.text
        }.joined(separator: "\n\n")

        return (plainNarrative, parts)
    }

    private static func richAnswerSceneMarkerID(in line: String) -> String? {
        let marker = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "<!-- weibei-scene:"
        let suffix = "-->"
        guard marker.hasPrefix(prefix), marker.hasSuffix(suffix) else { return nil }
        let start = marker.index(marker.startIndex, offsetBy: prefix.count)
        let end = marker.index(marker.endIndex, offsetBy: -suffix.count)
        let sceneID = marker[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return isSafeIdentifier(sceneID) ? sceneID : nil
    }
}

private extension Error {
    var isUnsupportedRichAnswerField: Bool {
        guard let decodingError = self as? DecodingError else { return false }
        switch decodingError {
        case let DecodingError.dataCorrupted(context):
            return context.debugDescription.contains("Unsupported rich-answer field")
        case let DecodingError.keyNotFound(_, context),
             let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context):
            return context.debugDescription.contains("Unsupported rich-answer field")
        default:
            return false
        }
    }
}
