import Foundation

extension RichAnswerEngine {
    static func validateEvidenceLedger(
        _ ledger: [RichAnswerEvidence],
        environment: RichAnswerEnvironment,
        diagnostics: inout [RichAnswerDiagnostic]
    ) -> EvidenceValidationResult {
        var validEvidenceByID: [String: RichAnswerEvidence] = [:]
        var seenIDs: Set<String> = []
        var duplicateIDs: Set<String> = []
        var invalidEvidenceWasSeen = ledger.count > environment.resourceBudget.maxEvidenceItems
    
        if ledger.count > environment.resourceBudget.maxEvidenceItems {
            diagnostics.append(
                RichAnswerDiagnostic(
                    code: .budgetExceeded,
                    message: "rich answer evidence ledger exceeded the allowed item budget"
                )
            )
        }
    
        for evidence in ledger.prefix(max(0, environment.resourceBudget.maxEvidenceItems)) {
            guard isSafeIdentifier(evidence.id) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .invalidValue,
                        message: "evidence id is empty or unsafe"
                    )
                )
                continue
            }
            guard seenIDs.insert(evidence.id).inserted else {
                duplicateIDs.insert(evidence.id)
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .duplicateID,
                        message: "evidence id \(evidence.id) is duplicated"
                    )
                )
                continue
            }
            guard environment.allowedSourceLabels.contains(evidence.sourceLabel) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .unsupportedEvidence,
                        message: "evidence \(evidence.id) uses a source label that is not allowed in this context"
                    )
                )
                continue
            }
            guard !evidence.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  evidence.excerpt.count <= 1_200 else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .budgetExceeded,
                        message: "evidence \(evidence.id) has an empty or oversized excerpt"
                    )
                )
                continue
            }
            guard evidence.tags.isSubset(of: environment.allowedEvidenceTags) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .unsupportedEvidence,
                        message: "evidence \(evidence.id) uses a tag that is not allowed in this context"
                    )
                )
                continue
            }
            guard evidence.assetIDs.allSatisfy({ isAllowedAssetID($0, environment: environment) }) else {
                invalidEvidenceWasSeen = true
                diagnostics.append(
                    RichAnswerDiagnostic(
                        code: .unauthorizedAsset,
                        message: "evidence \(evidence.id) references an asset that is not allowed in this context"
                    )
                )
                continue
            }
            validEvidenceByID[evidence.id] = evidence
        }
    
        for duplicateID in duplicateIDs {
            validEvidenceByID.removeValue(forKey: duplicateID)
        }
    
        return EvidenceValidationResult(
            validEvidenceByID: validEvidenceByID,
            invalidEvidenceWasSeen: invalidEvidenceWasSeen
        )
    }
}

struct EvidenceValidationResult {
    var validEvidenceByID: [String: RichAnswerEvidence]
    var invalidEvidenceWasSeen: Bool
}
