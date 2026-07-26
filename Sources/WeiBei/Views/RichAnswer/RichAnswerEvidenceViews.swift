import AppKit
import SwiftUI
import WeiBeiCore

struct EvidenceStrip: View {
    let evidence: [RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        if !evidence.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(displayEvidence, id: \.id) { item in
                    EvidenceChip(evidence: item, onOpenEvidence: onOpenEvidence)
                }
            }
        }
    }

    private var displayEvidence: [RichAnswerEvidence] {
        var seenLabels: Set<String> = []
        return evidence.filter { seenLabels.insert($0.sourceLabel).inserted }
    }
}

struct RichAnswerEvidenceLedger: View {
    let evidence: [RichAnswerEvidence]
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        if !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("来源索引")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                EvidenceStrip(evidence: evidence, onOpenEvidence: onOpenEvidence)
            }
            .padding(.top, 2)
        }
    }
}

struct EvidenceChip: View {
    let evidence: RichAnswerEvidence
    var onOpenEvidence: (RichAnswerEvidence) -> Void

    var body: some View {
        Button {
            onOpenEvidence(evidence)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(evidence.sourceLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                ForEach(Array(evidence.tags).sorted().prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                if evidence.isTruncated {
                    Text("截断")
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                }
            }
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 2)
            .frame(height: 21)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.48))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .help(evidence.excerpt)
    }
}

