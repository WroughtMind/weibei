import SwiftUI
import WeiBeiCore

// MARK: - 连接卡片(Settings → 对话)
//
// 设计定稿(2026-09-29 交付/2026-09-29-对话设置页优化设计-v2.html):
// 每个配置一张两行锁定卡——服务商标志 + 模型名标题,副行是密钥尾号(点击钻入更换)
// 与联网搜索状态图标。选中的卡抬升全彩,未选中整卡降灰,点卡即切换。
// 密钥编辑行在标志下方展开,标志本身不跟着下移。
// 增(虚线卡)删(右键)改(模型菜单/密钥钻入)选(点卡)都在卡列内完成,
// 卡面上没有常驻按钮,也没有「密钥已保存」这类常态文字。

struct AgentConnectionCardsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var oauthService = AgentAccountService.shared

    @State private var addingCard = false
    @State private var addServiceIndex = 0
    @State private var addKeyDraft = ""
    @State private var addBaseURLDraft = ""
    @State private var addUsesSubscription = false
    @State private var showAddBaseURL = false
    @State private var keyEditProfileID: UUID?
    @State private var subscriptionDetailProfileID: UUID?
    @State private var keyDraft = ""
    @State private var webSearchHover = false
    @State private var probingProfileID: UUID?
    @State private var probeMarks: [UUID: ProbeMark] = [:]

    /// 账号登录的服务排在前面。只支持订阅的（如 Codex）以前被 apiKey 过滤掉了。
    private var addServices: [AgentProviderID] {
        let available = AgentProviderID.allCases.filter(oauthService.isAvailable)
        let subscription = available.filter { authTypes(for: $0).contains(.oauth) }
        let rest = available.filter { !authTypes(for: $0).contains(.oauth) }
        return subscription + rest
    }

    private var currentAddService: AgentProviderID? {
        let services = addServices
        guard addServiceIndex < services.count else { return services.first }
        return services[addServiceIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.ui("连接", "Connections"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(store.agentCredentialProfiles) { profile in
                    connectionCard(profile)
                }
                addTile
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: store.activeAgentProfileID) { previous, _ in
            // 绿和红只属于刚测完的这一眼。离开这张卡就收掉，再点回来不接着亮。
            if probingProfileID != previous {
                probeMarks[previous] = nil
            }
        }
    }

    // MARK: 单张卡

    private func connectionCard(_ profile: AgentCredentialProfile) -> some View {
        let selected = profile.id == store.activeAgentProfileID
        return ConnCardShell(selected: selected, ring: probeRing(for: profile)) {
            store.selectAgentCredentialProfile(profile.id)
            keyEditProfileID = nil
            subscriptionDetailProfileID = nil
        } content: {
            if selected {
                selectedBody(profile)
            } else {
                briefBody(profile)
            }
        }
        .contextMenu {
            if !selected {
                Button(store.ui("设为使用中", "Set as Active")) {
                    store.selectAgentCredentialProfile(profile.id)
                }
            }
            if store.agentCredentialProfiles.count > 1 {
                Button(store.ui("删除连接", "Delete Connection"), role: .destructive) {
                    deleteConnection(profile)
                }
            }
        }
    }

    /// 选中卡:服务商标志 + 模型名标题。副行是密钥尾号，或订阅的登录状态。展开行在标志下方。
    private func selectedBody(_ profile: AgentCredentialProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                ProviderLogo(provider: profile.provider)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        modelMenuButton(profile)
                        if let note = statusNote(for: profile) {
                            Text(note)
                                .font(ConnType.detail)
                                .foregroundStyle(WeiBeiTheme.cinnabar)
                                .lineLimit(1)
                        }
                    }

                    HStack(alignment: .center, spacing: 8) {
                        if method(for: profile) == .subscription {
                            subscriptionStatusButton(profile)
                        } else if hasAPIKey(profile.provider) {
                            keyTailButton(profile)
                        } else {
                            Button {
                                keyDraft = ""
                                keyEditProfileID = profile.id
                                subscriptionDetailProfileID = nil
                            } label: {
                                Text(store.ui("待填密钥", "API key needed"))
                                    .font(ConnType.pill)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(ConnType.warn)
                            }
                            .buttonStyle(.plain)
                            .help(store.ui("点击粘贴密钥", "Click to paste the API key"))
                        }
                        HStack(alignment: .center, spacing: 0) {
                            webSearchBadge(profile)
                            probeButton(profile)
                        }
                    }
                }
            }

            if keyEditProfileID == profile.id {
                keyEditor(profile)
            }
            if showsSubscriptionDetail(profile) {
                subscriptionDetail(profile)
            }
            if let error = oauthService.lastError, profile.id == store.activeAgentProfileID {
                Text(store.ui(error.chinese, error.english))
                    .font(ConnType.detail)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// 未选中卡:整卡降灰,单行。
    private func briefBody(_ profile: AgentCredentialProfile) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ProviderLogo(provider: profile.provider, dimmed: true)

            Text(profile.provider.label(language: store.interfaceLanguage))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(briefStatus(profile))
                .font(ConnType.detail)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    /// 密钥尾号副行按钮:点击钻入更换。
    private func keyTailButton(_ profile: AgentCredentialProfile) -> some View {
        Button {
            keyDraft = ""
            keyEditProfileID = keyEditProfileID == profile.id ? nil : profile.id
        } label: {
            HStack(spacing: 5) {
                Text(keyTail(profile.provider) ?? "sk-••••")
                    .font(ConnType.detail)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .rotationEffect(.degrees(keyEditProfileID == profile.id ? 90 : 0))
            }
        }
        .buttonStyle(.plain)
        .help(store.ui("更换密钥", "Replace the API key"))
    }

    /// 密钥钻入行:输入框 + 保存/取消,只在编辑时出现。
    @ViewBuilder
    private func keyEditor(_ profile: AgentCredentialProfile) -> some View {
        HStack(spacing: 12) {
            SecureField(
                "",
                text: $keyDraft,
                prompt: Text(store.ui("粘贴新密钥", "Paste a new API key"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .weiBeiText(13)
            .foregroundColor(WeiBeiTheme.ink)
            .weibeiInputSurface(active: true, height: 36)
            .frame(maxWidth: 320)

            Button(store.ui("保存", "Save")) {
                saveKey(for: profile)
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))

            Button(store.ui("取消", "Cancel")) {
                keyEditProfileID = nil
                keyDraft = ""
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())

            if oauthService.isLoggingIn {
                ProgressView()
                    .controlSize(.small)
            }
            if authTypes(for: profile.provider).contains(.oauth) {
                Button(store.ui("改用账号登录", "Use account sign-in")) {
                    keyEditProfileID = nil
                    keyDraft = ""
                    beginSubscriptionLogin(profile)
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))
            }
        }
        .padding(.top, 2)
    }

    /// 订阅副行:已连接可展开重新登录/断开;未登录直接走浏览器。
    private func subscriptionStatusButton(_ profile: AgentCredentialProfile) -> some View {
        let linked = oauthService.isLinked(profile.provider)
        let needsLogin = store.agentAuthenticationStatus.requiresLogin(for: profile.provider)
        let title: String = {
            if oauthService.isLoggingIn, profile.id == store.activeAgentProfileID {
                return store.ui("登录中…", "Signing in…")
            }
            if needsLogin { return store.ui("需要重新登录", "Sign in again") }
            if linked { return store.ui("已连接", "Linked") }
            return store.ui("浏览器登录", "Sign in with browser")
        }()
        let quiet = linked && !needsLogin && !oauthService.isLoggingIn
        return Button {
            if quiet {
                subscriptionDetailProfileID = subscriptionDetailProfileID == profile.id ? nil : profile.id
            } else {
                beginSubscriptionLogin(profile)
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(ConnType.pill)
                    .fontWeight(quiet ? .regular : .semibold)
                    .foregroundStyle(quiet ? WeiBeiTheme.secondaryInk : ConnType.warn)
                if quiet {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .rotationEffect(.degrees(subscriptionDetailProfileID == profile.id ? 90 : 0))
                }
            }
        }
        .buttonStyle(.plain)
        .help(store.ui(
            "用浏览器授权这个服务的账号",
            "Authorize this service's account in the browser"
        ))
    }

    @ViewBuilder
    private func subscriptionDetail(_ profile: AgentCredentialProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(store.ui(
                    oauthService.isLinked(profile.provider) ? "重新登录" : "浏览器登录",
                    oauthService.isLinked(profile.provider) ? "Sign in again" : "Sign in with browser"
                )) {
                    beginSubscriptionLogin(profile)
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))

                if oauthService.isLinked(profile.provider) {
                    Button(store.ui("断开", "Disconnect")) {
                        if profile.id != store.activeAgentProfileID {
                            store.selectAgentCredentialProfile(profile.id)
                        }
                        oauthService.logout(profile.provider)
                        subscriptionDetailProfileID = nil
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                if oauthService.isLoggingIn {
                    Button(store.ui("取消", "Cancel")) { oauthService.cancelLogin() }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                if authTypes(for: profile.provider).contains(.apiKey) {
                    Button(store.ui("改用 API 密钥", "Use an API key")) {
                        if profile.id != store.activeAgentProfileID {
                            store.selectAgentCredentialProfile(profile.id)
                        }
                        store.setAgentAuthMethod(.apiKey)
                        subscriptionDetailProfileID = nil
                        keyDraft = ""
                        keyEditProfileID = profile.id
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }

            if oauthService.isLoggingIn, let code = oauthService.authorizationCode {
                HStack(spacing: 12) {
                    Text(code)
                        .font(.system(.title3, design: .monospaced))
                        .textSelection(.enabled)
                    if let url = oauthService.authorizationURL {
                        Link(store.ui("打开授权页", "Open authorization page"), destination: url)
                    }
                }
            }
            if oauthService.isLoggingIn, let progress = oauthService.statusMessage {
                Text(store.ui(progress.chinese, progress.english))
                    .font(ConnType.detail)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
        }
        .padding(.top, 2)
    }

    /// 和配置卡同一栏宽。点开后就地展开，不盖遮罩，不另开小窗。
    @ViewBuilder
    private var addTile: some View {
        if addingCard {
            addForm
        } else {
            Button {
                addServiceIndex = 0
                addKeyDraft = ""
                addBaseURLDraft = ""
                showAddBaseURL = false
                if let first = addServices.first {
                    addUsesSubscription = prefersSubscription(first)
                }
                addingCard = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text(store.ui("添加连接", "Add Connection"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(WeiBeiTheme.hairline.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.ui("添加连接", "Add Connection"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer(minLength: 12)
                Button { closeAdd() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            modalSelect(currentAddService?.label(language: store.interfaceLanguage) ?? "—") {
                ForEach(addServices, id: \.self) { provider in
                    Button(provider.label(language: store.interfaceLanguage)) {
                        if let index = addServices.firstIndex(of: provider) {
                            addServiceIndex = index
                            addBaseURLDraft = ""
                            showAddBaseURL = provider.showsBaseURLField
                            addUsesSubscription = prefersSubscription(provider)
                        }
                    }
                }
            }

            if let service = currentAddService, supportsBothAuthMethods(service) {
                modalSelect(addUsesSubscription
                    ? store.ui("账号登录", "Account sign-in")
                    : store.ui("API 密钥", "API Key")) {
                    Button(store.ui("账号登录", "Account sign-in")) { addUsesSubscription = true }
                    Button(store.ui("API 密钥", "API Key")) { addUsesSubscription = false }
                }
            }

            if !addingWithSubscription {
                SecureField(
                    "",
                    text: $addKeyDraft,
                    prompt: Text(store.ui("粘贴 API Key", "Paste API key"))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                .textFieldStyle(.plain)
                .weiBeiText(13)
                .foregroundColor(WeiBeiTheme.ink)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(WeiBeiTheme.paper))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(WeiBeiTheme.hairline.opacity(0.85), lineWidth: 1)
                )
                .onSubmit { commitAdd() }
            }

            if let service = currentAddService, service.showsBaseURLField || showAddBaseURL {
                TextField(
                    "",
                    text: $addBaseURLDraft,
                    prompt: Text(store.ui("服务地址", "Base URL"))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                .textFieldStyle(.plain)
                .weiBeiText(13)
                .foregroundColor(WeiBeiTheme.ink)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(WeiBeiTheme.paper))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(WeiBeiTheme.hairline.opacity(0.85), lineWidth: 1)
                )
            }

            HStack {
                Spacer()
                Button(store.ui("取消", "Cancel")) { closeAdd() }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                Button(addingWithSubscription
                    ? store.ui("浏览器登录", "Sign in with browser")
                    : store.ui("连接", "Connect")) {
                    commitAdd()
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                .disabled(
                    oauthService.isLoggingIn
                        || (!addingWithSubscription && addKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
        )
    }

    private func closeAdd() {
        addingCard = false
        addKeyDraft = ""
    }

    private func modalSelect<MenuContent: View>(_ title: String, @ViewBuilder content: () -> MenuContent) -> some View {
        Menu {
            content()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(WeiBeiTheme.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(WeiBeiTheme.paper))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(WeiBeiTheme.hairline.opacity(0.85), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 片段

    private func probeRing(for profile: AgentCredentialProfile) -> ConnProbeRing {
        guard profile.id == store.activeAgentProfileID else { return .none }
        if probingProfileID == profile.id { return .running }
        switch probeMarks[profile.id]?.ok {
        case true: return .alive
        case false: return .dead
        case nil: return .none
        }
    }

    /// 失败才写在这张卡上，而且只留到离开这张卡。成功不写字，说明在悬停里。
    private func statusNote(for profile: AgentCredentialProfile) -> String? {
        if let mark = probeMarks[profile.id] {
            return mark.ok ? nil : mark.text
        }
        guard profile.id == store.activeAgentProfileID,
              probingProfileID == nil,
              let failure = oauthService.modelListFailure,
              failure != .superseded else { return nil }
        return modelListFailureText(failure)
    }

    private func probeHelp(for profile: AgentCredentialProfile) -> String {
        if probingProfileID == profile.id {
            return store.ui("正在确认这组凭据", "Checking this credential")
        }
        if let mark = probeMarks[profile.id] {
            return mark.text
        }
        return store.ui("确认这组凭据是否还能连通", "Check whether this credential still connects")
    }

    private func probeButton(_ profile: AgentCredentialProfile) -> some View {
        Button {
            guard probingProfileID == nil else { return }
            probingProfileID = profile.id
            probeMarks[profile.id] = nil
            let provider = profile.provider
            let baseURL = profile.baseURL
            Task { await runProbe(profileID: profile.id, provider: provider, baseURL: baseURL) }
        } label: {
            // 图标只表示「测一次」。进行中和结果都在卡片边缘，不把按钮改成转圈、对勾或感叹号。
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(probeHelp(for: profile))
    }

    private func runProbe(profileID: UUID, provider: AgentProviderID, baseURL: String) async {
        let started = Date()
        let result = await oauthService.probeConnection(
            provider: provider,
            baseURL: baseURL
        )
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 1.2, profileID == store.activeAgentProfileID {
            let rest = UInt64((1.2 - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: rest)
        }
        guard profileID == store.activeAgentProfileID else {
            if probingProfileID == profileID { probingProfileID = nil }
            return
        }
        if probingProfileID == profileID {
            probingProfileID = nil
        }
        switch result {
        case .success(let count):
            probeMarks[profileID] = ProbeMark(
                text: store.ui("凭据可用，\(count) 个模型", "Credential works, \(count) models"),
                ok: true
            )
        case .failure(let failure):
            guard failure != .superseded else { return }
            probeMarks[profileID] = ProbeMark(text: modelListFailureText(failure), ok: false)
        }
    }

    private func modelListFailureText(_ failure: AgentAccountService.ModelListFailure) -> String {
        switch failure {
        case .missingCredential:
            return store.ui("没有密钥或登录", "No key or sign-in")
        case .missingBaseURL:
            return store.ui("缺少服务地址", "Missing service address")
        case .rejected:
            return store.ui("服务商拒绝了这组凭据", "The provider rejected this credential")
        case .signInExpired:
            return store.ui("登录已失效", "Sign-in expired")
        case .superseded:
            return ""
        case .http(let status):
            return store.ui("服务商返回 \(status)", "The provider returned \(status)")
        case .offline:
            return store.ui("网络没有连上", "The network did not connect")
        case .unreadable:
            return store.ui("连上了，但没有读到模型名单", "Connected, but the model list was unreadable")
        }
    }

    private func webSearchBadge(_ profile: AgentCredentialProfile) -> some View {
        let supported = NativeProviderRouting.offersWebSearch(provider: profile.provider, model: store.modelName)
        let tip = webSearchTip(provider: profile.provider, supported: supported)
        let color = supported ? WeiBeiTheme.link : WeiBeiTheme.secondaryInk
        return ZStack {
            Image(systemName: "globe")
                .font(.system(size: 12))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
            if !supported {
                Capsule()
                    .fill(color)
                    .frame(width: 1.4, height: 15)
                    .rotationEffect(.degrees(-48))
            }
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .onHover { webSearchHover = $0 }
        .overlay(alignment: .top) {
            if webSearchHover {
                connHoverTip(tip)
            }
        }
        .zIndex(webSearchHover ? 2 : 0)
    }

    private func webSearchTip(provider: AgentProviderID, supported: Bool) -> String {
        let model = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty {
            return store.ui("联网搜索：先选定模型", "Web search: choose a model first")
        }
        if supported {
            return store.ui("联网搜索：这个模型支持，需要时由服务商联网", "Web search: this model can search when it needs to")
        }
        if NativeProviderRouting.route(provider).webSearch == .none {
            return store.ui("联网搜索：该服务不提供", "Web search: this service does not offer it")
        }
        return store.ui("联网搜索：这个模型不提供", "Web search: this model does not offer it")
    }

    /// Mac Catalyst 上 SwiftUI 的 help 不会弹出。说明画在图标上方，不参与布局，也不带动卡片上的其他动画。
    private func connHoverTip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0.976, green: 0.945, blue: 0.871))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(WeiBeiTheme.chrome))
            .fixedSize()
            .offset(y: -36)
            .allowsHitTesting(false)
    }

    private func keyTail(_ provider: AgentProviderID) -> String? {
        guard let key = try? NativeAgentCredentialStore.apiKey(forProviderID: provider.credentialProviderID),
              key.count > 4 else { return nil }
        return String(key.prefix(7)) + "••••••••"
    }

    private func saveKey(for profile: AgentCredentialProfile) {
        if profile.id != store.activeAgentProfileID {
            store.selectAgentCredentialProfile(profile.id)
        }
        store.setAgentAuthMethod(.apiKey)
        oauthService.startAPIKeyLogin(
            keyDraft,
            provider: store.agentProviderID,
            baseURL: store.agentBaseURL
        )
        keyEditProfileID = nil
        keyDraft = ""
    }

    private func commitAdd() {
        guard let service = currentAddService else { return }
        let subscription = addingWithSubscription
        let key = addKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard subscription || !key.isEmpty else { return }
        store.createAgentCredentialProfile()
        store.setAgentProviderID(service)
        if !addBaseURLDraft.isEmpty { store.updateAgentBaseURL(addBaseURLDraft) }
        store.setAgentAuthMethod(subscription ? .subscription : .apiKey)
        if subscription {
            oauthService.startLogin(service, language: store.interfaceLanguage)
            subscriptionDetailProfileID = store.activeAgentProfileID
        } else {
            oauthService.startAPIKeyLogin(key, provider: service, baseURL: store.agentBaseURL)
        }
        addingCard = false
        addKeyDraft = ""
        addBaseURLDraft = ""
    }

    private func beginSubscriptionLogin(_ profile: AgentCredentialProfile) {
        if profile.id != store.activeAgentProfileID {
            store.selectAgentCredentialProfile(profile.id)
        }
        store.setAgentAuthMethod(.subscription)
        keyEditProfileID = nil
        subscriptionDetailProfileID = profile.id
        guard !oauthService.isLoggingIn else { return }
        oauthService.startLogin(profile.provider, language: store.interfaceLanguage)
    }

    private func authTypes(for provider: AgentProviderID) -> [AgentCredentialType] {
        oauthService.authTypes(for: provider)
    }

    private func supportsBothAuthMethods(_ provider: AgentProviderID) -> Bool {
        let types = authTypes(for: provider)
        return types.contains(.oauth) && types.contains(.apiKey)
    }

    /// 只支持订阅，或两种都支持且还没有密钥时，默认走账号登录。和旧设置页同一条规则。
    private func prefersSubscription(_ provider: AgentProviderID) -> Bool {
        let types = authTypes(for: provider)
        guard types.contains(.oauth) else { return false }
        if !types.contains(.apiKey) { return true }
        let hasKey = oauthService.isConfigured(
            providerID: provider.credentialProviderID,
            type: .apiKey
        )
        return provider.kind == .subscription || !hasKey
    }

    private var addingWithSubscription: Bool {
        guard let service = currentAddService else { return false }
        let types = authTypes(for: service)
        if types.contains(.oauth), !types.contains(.apiKey) { return true }
        if supportsBothAuthMethods(service) { return addUsesSubscription }
        return false
    }

    private func method(for profile: AgentCredentialProfile) -> AgentAuthMethod {
        let types = authTypes(for: profile.provider)
        if supportsBothAuthMethods(profile.provider) { return profile.authMethod }
        return types.contains(.oauth) ? .subscription : .apiKey
    }

    private func hasAPIKey(_ provider: AgentProviderID) -> Bool {
        oauthService.isConfigured(providerID: provider.credentialProviderID, type: .apiKey)
    }

    private func showsSubscriptionDetail(_ profile: AgentCredentialProfile) -> Bool {
        guard method(for: profile) == .subscription else { return false }
        if subscriptionDetailProfileID == profile.id { return true }
        return oauthService.isLoggingIn && profile.id == store.activeAgentProfileID
    }

    private func briefStatus(_ profile: AgentCredentialProfile) -> String {
        switch method(for: profile) {
        case .subscription:
            if store.agentAuthenticationStatus.requiresLogin(for: profile.provider) {
                return store.ui("需要重新登录", "Sign in again")
            }
            if oauthService.isLinked(profile.provider) {
                return store.ui("已连接", "Linked")
            }
            return store.ui("待登录", "Sign-in needed")
        case .apiKey:
            if hasAPIKey(profile.provider), let tail = keyTail(profile.provider) {
                return tail
            }
            return store.ui("待填密钥", "API key needed")
        }
    }

    private func deleteConnection(_ profile: AgentCredentialProfile) {
        guard store.agentCredentialProfiles.count > 1 else { return }
        probeMarks[profile.id] = nil
        if probingProfileID == profile.id {
            probingProfileID = nil
        }
        if store.activeAgentProfileID != profile.id {
            store.selectAgentCredentialProfile(profile.id)
        }
        store.deleteActiveAgentCredentialProfile()
    }

// MARK: - 本地片段

/// 模型标题菜单:可用模型列表 + 头部行刷新图标。
@ViewBuilder
private func modelMenuButton(_ profile: AgentCredentialProfile) -> some View {
    Menu {
        let listed = oauthService.models(provider: profile.provider)
        let current = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        Section(store.ui("可用模型", "Available models")) {
            ForEach(listed, id: \.self) { model in
                Button(model == current ? "✓ " + model : "   " + model) {
                    store.updateModelName(model)
                }
            }
        }
        if !current.isEmpty, !listed.contains(current) {
            Section(store.ui("当前选择", "Current choice")) {
                Button("✓ " + current) {}
                    .disabled(true)
            }
        }
        Section {
            Button {
                oauthService.refreshModels(provider: profile.provider, baseURL: profile.baseURL)
                probeMarks[profile.id] = nil
            } label: {
                Label(store.ui("刷新模型名单", "Refresh model list"), systemImage: "arrow.clockwise")
            }
        }
    } label: {
        HStack(spacing: 6) {
            Text(store.modelName.isEmpty ? store.ui("选择模型…", "Select model…") : store.modelName)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(store.ui("更换模型;菜单内可刷新名单", "Change model; refresh the list from the menu"))
}

private func connCompactMenu(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    Menu {
        content()
    } label: {
        HStack(spacing: 5) {
            Text(title)
                .font(ConnType.menu)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(WeiBeiTheme.paperRaised.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .fixedSize()
}

/// 选中与未选中同一栏宽。整张卡片可点；悬停或选中时抬起阴影。阴影画在裁切之外，才不会被圆角切掉。
private enum ConnProbeRing {
    case none
    case running
    case alive
    case dead
}

private struct ConnCardShell<Content: View>: View {
    var selected: Bool
    var ring: ConnProbeRing = .none
    var onSelect: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let borderOpacity: Double = {
            switch ring {
            case .alive, .dead:
                return 0
            case .running, .none:
                return selected ? 0.42 : (hovered ? 0.62 : 0.28)
            }
        }()
        let face = content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(selected ? WeiBeiTheme.paperRaised : Color.clear))
            .overlay(
                shape.strokeBorder(
                    WeiBeiTheme.hairline.opacity(borderOpacity),
                    lineWidth: 1
                )
                .animation(.easeInOut(duration: 0.9), value: borderOpacity)
            )
            .clipShape(shape)
            .overlay { ConnProbeRingView(ring: ring) }
            .animation(.easeOut(duration: 0.2), value: selected)
            // 阴影半径保持不变，只变透明度，避免模糊半径插值把卡片拖重。
            .shadow(color: Color.black.opacity(hovered && !selected ? 0.28 : 0), radius: 22, y: 10)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.16), value: hovered)

        if selected {
            // 选中卡里有菜单和确认图标，不能再铺一层整卡点击，否则点图标没有反应。
            face
        } else {
            face
                .contentShape(shape)
                .onTapGesture(perform: onSelect)
        }
    }
}

private struct ProbeMark: Equatable {
    var text: String
    var ok: Bool
}

/// 一道光贴着整张卡片的边走。结果出来时，这道光淡出，整圈青或朱淡入。不接点击。
private struct ConnProbeRingView: View {
    var ring: ConnProbeRing
    private let corner: CGFloat = 14
    @State private var cometOpacity: Double = 1
    @State private var settledOpacity: Double = 0

    var body: some View {
        ZStack {
            if ring == .running || cometOpacity > 0.02 {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let cycle = timeline.date.timeIntervalSinceReferenceDate / 3.4
                    comet(progress: cycle - floor(cycle))
                }
                .transaction { $0.animation = nil }
                .opacity(ring == .running ? 1 : cometOpacity)
            }
            if ring == .alive || ring == .dead {
                settled(ring == .alive
                    ? Color(red: 0.20, green: 0.64, blue: 0.42)
                    : WeiBeiTheme.cinnabar)
                    .opacity(settledOpacity)
            }
        }
        .allowsHitTesting(false)
        .onAppear { apply(ring, animated: false) }
        .onChange(of: ring) { _, new in
            apply(new, animated: new == .alive || new == .dead)
        }
    }

    private func apply(_ ring: ConnProbeRing, animated: Bool) {
        let change = {
            switch ring {
            case .running:
                cometOpacity = 1
                settledOpacity = 0
            case .alive, .dead:
                cometOpacity = 0
                settledOpacity = 1
            case .none:
                cometOpacity = 0
                settledOpacity = 0
            }
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.9)) { change() }
        } else {
            change()
        }
    }

    private func comet(progress: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color(red: 0.48, green: 0.58, blue: 0.96).opacity(0.20), lineWidth: 2)
                .blur(radius: 3)
            glow(progress: progress, tail: 0.38, color: Color(red: 0.58, green: 0.46, blue: 0.96).opacity(0.34), width: 10, blur: 8)
            glow(progress: progress, tail: 0.22, color: Color(red: 0.42, green: 0.64, blue: 1).opacity(0.50), width: 6, blur: 4.5)
            glow(progress: progress, tail: 0.12, color: Color(red: 0.74, green: 0.88, blue: 1).opacity(0.72), width: 3.2, blur: 2.2)
            glow(progress: progress, tail: 0.055, color: Color(red: 0.90, green: 0.96, blue: 1).opacity(0.92), width: 1.8, blur: 1.1)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func glow(progress: Double, tail: Double, color: Color, width: CGFloat, blur: CGFloat) -> some View {
        PerimeterComet(progress: progress, tail: tail, corner: corner)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            .blur(radius: blur)
    }

    private func settled(_ color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(color.opacity(0.42), lineWidth: 7)
                .blur(radius: 6)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(color.opacity(0.92), lineWidth: 1.5)
                .blur(radius: 0.4)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

/// 卡片圆角边上的一段。跟着真实圆角走，而不是在边上放一个光点。
private struct PerimeterComet: Shape {
    var progress: Double
    var tail: Double
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let line: CGFloat = 0.6
        let inset = rect.insetBy(dx: line, dy: line)
        let base = RoundedRectangle(cornerRadius: max(0, corner - line), style: .continuous).path(in: inset)
        let start = progress - floor(progress)
        let end = start + tail
        if end <= 1 {
            return base.trimmedPath(from: start, to: end)
        }
        var wrapped = base.trimmedPath(from: start, to: 1)
        wrapped.addPath(base.trimmedPath(from: 0, to: end - 1))
        return wrapped
    }
}

private enum ConnType {
    static var rowTitle: Font { .system(size: 13, weight: .semibold) }
    static var rowTitleSecondary: Font { .system(size: 13, weight: .medium) }
    static var detail: Font { .system(size: 12, weight: .regular) }
    static var pill: Font { .system(size: 12, weight: .medium) }
    static var menu: Font { .system(size: 13, weight: .semibold) }
    /// 原型里的异常色，不用系统橙。
    static var warn: Color { Color(red: 0.788, green: 0.561, blue: 0.176) }
}
}
