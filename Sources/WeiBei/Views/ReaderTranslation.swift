import SwiftUI
import WeiBeiCore

struct ReaderTranslationPreferences: DynamicProperty {
    @AppStorage("weibei.readerTranslation.connection") private var connectionID = ""
    @AppStorage("weibei.readerTranslation.language") private var languageID = ""

    var connection: Binding<String> { $connectionID }
    var language: Binding<String> { $languageID }

    var choices: [String] {
        var seen: Set<String> = []
        return (["zh-Hans", "en", "zh-Hant"] + Locale.preferredLanguages)
            .filter { seen.insert($0).inserted }
    }

    @MainActor
    func service(in store: WorkspaceStore) -> ReaderTranslationService? {
        let targetID = languageID.isEmpty ? store.interfaceLanguage.rawValue : languageID
        let target = Locale(identifier: "en").localizedString(forIdentifier: targetID) ?? targetID
        if connectionID.isEmpty {
            return ReaderTranslationService(
                provider: store.agentProviderID, model: store.modelName, baseURL: store.agentBaseURL,
                authMethod: store.agentAuthMethod, targetLanguage: target
            )
        }
        guard let profile = store.agentCredentialProfiles.first(where: { $0.id.uuidString == connectionID }) else {
            return nil
        }
        return ReaderTranslationService(
            provider: profile.provider, model: profile.modelName, baseURL: profile.baseURL,
            authMethod: profile.authMethod, targetLanguage: target
        )
    }
}

struct ReaderTranslationContext: Equatable {
    let itemID: String
    let revision: UInt64
    let attempt: UUID
    let service: ReaderTranslationService
}

enum ReaderTranslationProblem: Error, Equatable {
    case missingConnection, missingModel, unauthorized, rateLimited, insufficientQuota, offline, incomplete, failed

    init(_ error: Error) {
        if let error = error as? ReaderTranslationService.Failure {
            self = error == .missingModel ? .missingModel : .incomplete
        } else if let error = error as? NativeLLMFailure {
            switch error.asAgentFailureKind {
            case .unauthorized: self = .unauthorized
            case .rateLimited: self = .rateLimited
            case .insufficientQuota: self = .insufficientQuota
            case .modelUnavailable: self = .missingModel
            case .offline, .timedOut: self = .offline
            case .truncated: self = .incomplete
            default: self = .failed
            }
        } else if let error = error as? URLError, error.code == .notConnectedToInternet {
            self = .offline
        } else if error is AgentProviderEndpointError {
            self = .missingConnection
        } else {
            self = .failed
        }
    }

    var needsConnection: Bool {
        self == .missingConnection || self == .missingModel || self == .unauthorized
    }

    func message(_ language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .missingConnection:
            language.text("翻译连接不可用。请在翻译菜单中选择连接。", "The translation connection is unavailable. Choose a connection in the translation menu.")
        case .missingModel:
            language.text("请先为翻译连接选择模型。", "Choose a model for the translation connection.")
        case .unauthorized:
            language.text("翻译服务未通过验证，请检查连接凭据。", "The translation service could not authenticate. Check the connection credentials.")
        case .rateLimited:
            language.text("翻译服务请求过多，请稍后重试。", "The translation service is receiving too many requests. Try again shortly.")
        case .insufficientQuota:
            language.text("翻译服务额度不足，请查看服务商账户。", "The translation service has run out of quota. Check your provider account.")
        case .offline:
            language.text("翻译服务暂时无法连接。", "The translation service is unreachable.")
        case .incomplete:
            language.text("模型返回的译文不完整。", "The model returned an incomplete translation.")
        case .failed:
            language.text("翻译失败，请检查服务或重试。", "Translation failed. Check the service or try again.")
        }
    }
}

enum ReaderTranslationStatus: Equatable {
    case idle, translating, noText, ready, failed(ReaderTranslationProblem)
}

struct ReaderTranslationMenu: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var enabled: Bool
    @Binding var presented: Bool
    var status: ReaderTranslationStatus
    var retry: () -> Void
    private var problem: ReaderTranslationProblem? {
        if case let .failed(problem) = status { return problem }
        return nil
    }

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "character.bubble")
                .weiBeiText(13, weight: .medium)
                .foregroundStyle(enabled ? WeiBeiTheme.accent : WeiBeiTheme.secondaryInk)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(store.ui("双语阅读", "Bilingual reading")))
        .accessibilityValue(enabled ? store.ui("开启", "On") : store.ui("关闭", "Off"))
        .help(problem?.message(store.interfaceLanguage) ?? store.ui("双语阅读", "Bilingual reading"))
        .popover(isPresented: $presented) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(store.ui("双语阅读", "Bilingual reading"), isOn: $enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                ReaderTranslationOptions(manageConnections: openConnectionSettings)
                if enabled {
                    switch status {
                    case .idle, .translating:
                        Text(store.ui("正在翻译…", "Translating…"))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    case .noText:
                        Text(store.ui("当前阅读位置没有可翻译的段落。", "There are no translatable paragraphs at the current reading position."))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    case let .failed(problem):
                        ReaderTranslationProblemView(problem: problem, retry: retry)
                    case .ready:
                        EmptyView()
                    }
                } else {
                    Text(store.ui("开启后，当前阅读位置的文字会发给所选服务。", "When on, text at the current reading position is sent to the selected service."))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
            }
            .weiBeiText(12)
            .padding(14)
            .frame(width: 300)
        }
    }

    private func openConnectionSettings() {
        presented = false
        store.settingsPresented = true
    }
}

private struct ReaderTranslationOptions: View {
    @EnvironmentObject private var store: WorkspaceStore
    private var preferences = ReaderTranslationPreferences()
    var manageConnections: () -> Void

    init(manageConnections: @escaping () -> Void) {
        self.manageConnections = manageConnections
    }

    var body: some View {
        Picker(store.ui("译为", "Translate to"), selection: preferences.language) {
            Text(store.ui("跟随界面语言", "Interface language")).tag("")
            ForEach(preferences.choices, id: \.self) { id in
                Text(Locale(identifier: id).localizedString(forIdentifier: id) ?? id).tag(id)
            }
            if !preferences.language.wrappedValue.isEmpty,
               !preferences.choices.contains(preferences.language.wrappedValue) {
                let id = preferences.language.wrappedValue
                Text(Locale(identifier: id).localizedString(forIdentifier: id) ?? id).tag(id)
            }
        }
        Picker(store.ui("连接", "Connection"), selection: preferences.connection) {
            Text(store.ui("当前模型连接", "Current model connection")).tag("")
            ForEach(store.agentCredentialProfiles) { profile in
                Text(profile.name).tag(profile.id.uuidString)
            }
            if !preferences.connection.wrappedValue.isEmpty,
               !store.agentCredentialProfiles.contains(where: { $0.id.uuidString == preferences.connection.wrappedValue }) {
                Text(store.ui("连接不可用", "Connection unavailable")).tag(preferences.connection.wrappedValue)
            }
        }
        Button(store.ui("管理模型连接…", "Manage model connections…"), action: manageConnections)
        .buttonStyle(.plain)
        .foregroundStyle(WeiBeiTheme.link)
    }
}

struct ReaderTranslationProblemView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var problem: ReaderTranslationProblem
    var offersSettings = false
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(problem.message(store.interfaceLanguage))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            if problem.needsConnection {
                if offersSettings {
                    Button(store.ui("打开设置", "Open Settings")) { store.settingsPresented = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(WeiBeiTheme.link)
                }
            } else {
                Button(store.ui("重试", "Try again"), action: retry)
                    .buttonStyle(.plain)
                    .foregroundStyle(WeiBeiTheme.link)
            }
        }
    }
}

struct ReaderSelectionTranslationButton: View {
    @EnvironmentObject private var store: WorkspaceStore
    var selection: SelectionContext
    private var preferences = ReaderTranslationPreferences()
    @State private var presented = false
    @State private var attempt = UUID()
    @State private var result: Result<String, ReaderTranslationProblem>?

    init(selection: SelectionContext) {
        self.selection = selection
    }

    var body: some View {
        Button {
            result = nil
            presented = true
        } label: {
            Text(store.ui("译", "Translate"))
                .frame(minWidth: 28)
        }
        .foregroundStyle(WeiBeiTheme.link)
        .buttonStyle(WeiBeiTextActionButtonStyle(active: presented, fontSize: 13, height: 32))
        .accessibilityLabel(Text(store.ui("翻译选中文字", "Translate selected text")))
        .help(store.ui("翻译选中文字", "Translate selected text"))
        .popover(isPresented: $presented) {
            let service = preferences.service(in: store)
            VStack(alignment: .leading, spacing: 12) {
                switch result {
                case let .success(text):
                    ViewThatFits(in: .vertical) {
                        translatedText(text).fixedSize(horizontal: false, vertical: true)
                        ScrollView { translatedText(text) }
                    }
                    .frame(maxHeight: 260)
                case let .failure(problem):
                    ReaderTranslationProblemView(problem: problem) { attempt = UUID() }
                case nil:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(store.ui("正在翻译…", "Translating…"))
                    }
                }
                Divider()
                ReaderTranslationOptions {
                    presented = false
                    store.settingsPresented = true
                }
            }
            .weiBeiText(12)
            .padding(14)
            .frame(width: 320, alignment: .leading)
            .task(id: SelectionRequest(selection: selection, service: service, attempt: attempt)) {
                result = nil
                guard let service else { result = .failure(.missingConnection); return }
                do {
                    guard let text = try await service.translate([selection.text]).first else {
                        throw ReaderTranslationService.Failure.invalidTranslation
                    }
                    try Task.checkCancellation()
                    result = .success(text)
                } catch {
                    guard !Task.isCancelled else { return }
                    result = .failure(ReaderTranslationProblem(error))
                }
            }
        }
        .onChange(of: selection.id) { _, _ in presented = false }
    }

    private func translatedText(_ text: String) -> some View {
        Text(verbatim: text)
            .weiBeiText(15)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct SelectionRequest: Equatable {
        let selection: SelectionContext
        let service: ReaderTranslationService?
        let attempt: UUID
    }
}
