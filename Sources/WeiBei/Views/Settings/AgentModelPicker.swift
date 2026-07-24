import SwiftUI
import WeiBeiCore

// MARK: - Model picker (Settings → 对话服务 → 模型)
//
// Replaces the old free-text Model field. After a provider + credential are chosen, it
// fetches the live model catalog via `WorkspaceStore.refreshModelList()` and surfaces it
// as a dropdown. Falls back to the built-in recommended list when listing is unsupported
// (e.g. Codex subscription, undocumented endpoints) or the fetch fails. Always keeps a
// "manual entry" escape hatch so users can type any id.

extension SettingsView {
    /// Triggered on appear and whenever the provider / key changes.
    func requestModelListRefresh() {
        Task { @MainActor in
            await store.refreshModelList()
        }
    }

    /// The dropdown + status + manual-entry control for the model id.
    @ViewBuilder
    func agentModelPicker() -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                if store.modelListStatus.isLoading {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        // Continuous spin while loading: drive via a monotonically increasing
                        // angle that animates itself each cycle.
                        .rotationEffect(.degrees(spinAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                                spinAngle += 360
                            }
                        }
                }
                compactMenu(displayedModelName) {
                    modelMenuContent
                }
                Button {
                    requestModelListRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: !store.modelListStatus.isLoading))
                .help(store.ui("重新获取模型列表", "Refresh model list"))
            }

            // Inline status line under the control.
            modelStatusLine
        }
    }

    private var displayedModelName: String {
        let trimmed = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? store.ui("选择模型…", "Select model…") : trimmed
    }

    @ViewBuilder
    private var modelMenuContent: some View {
        // The actual model entries (live list or built-in fallback). Menu items must be
        // title-literal Buttons; the current selection is marked with a ✓ prefix since
        // Menu does not render custom HStack/Button-label children reliably.
        let entries = effectiveModelEntries
        if !entries.isEmpty {
            Section(headerText) {
                ForEach(entries, id: \.self) { model in
                    let isSelected = model == store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button((isSelected ? "✓ " : "   ") + model) {
                        store.updateModelName(model)
                    }
                }
            }
        }

        // Always allow typing an arbitrary id.
        Section {
            Button(store.ui("手动输入…", "Enter manually…")) {
                showManualModelEntry = true
            }
        }
    }

    /// Section header reflects the listing state so the user knows whether the entries
    /// above are live or a built-in fallback.
    private var headerText: String {
        switch store.modelListStatus {
        case .loaded: return store.ui("可用模型", "Available models")
        case .builtin: return store.ui("推荐（此服务无法自动列出）", "Recommended (auto-list unavailable)")
        case .idle: return store.ui("推荐", "Recommended")
        case .failed: return store.ui("拉取失败，显示推荐", "Fetch failed; showing recommended")
        case .loading: return store.ui("推荐", "Recommended")
        }
    }

    /// Live list when loaded, otherwise the built-in recommended catalog.
    private var effectiveModelEntries: [String] {
        let current = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = store.modelListStatus == .loaded ? store.availableModels : store.agentProviderID.recommendedModels
        // Guarantee the current value is visible even if the catalog omits it.
        if !current.isEmpty, !entries.contains(current) {
            entries.insert(current, at: 0)
        }
        return entries
    }

    @ViewBuilder
    private var modelStatusLine: some View {
        // Env-var override badge takes precedence — the field is inert when set.
        if !envModelOverride.isEmpty {
            settingsPill(
                title: store.ui("环境变量 \(envModelOverride)", "Env \(envModelOverride)"),
                icon: "lock.fill",
                active: false
            )
        } else {
            switch store.modelListStatus {
            case .idle:
                EmptyView()
            case .loading:
                settingsPill(title: store.ui("正在获取模型…", "Fetching models…"), icon: "arrow.triangle.2.circlepath", active: false)
            case .loaded:
                settingsPill(title: store.ui("已列出 \(store.availableModels.count) 个模型", "\(store.availableModels.count) models listed"), icon: "checkmark.seal", active: true)
            case .builtin:
                settingsPill(title: store.ui("内置推荐", "Built-in catalog"), icon: "square.grid.2x2", active: false)
            case let .failed(message):
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .frame(width: 250, alignment: .trailing)
                    .lineLimit(2)
            }
        }
    }

    private var envModelOverride: String {
        let pi = ProcessInfo.processInfo.environment["WEIBEI_PI_MODEL"] ?? ""
        let openai = ProcessInfo.processInfo.environment["WEIBEI_OPENAI_MODEL"] ?? ""
        return !pi.isEmpty ? "WEIBEI_PI_MODEL" : (!openai.isEmpty ? "WEIBEI_OPENAI_MODEL" : "")
    }
}
