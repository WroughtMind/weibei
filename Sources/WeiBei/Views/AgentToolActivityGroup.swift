import SwiftUI
import WeiBeiCore

/// Tool identity stays visible across running, completed and failed states.
enum AgentActivityIcon {
    static func symbol(for name: String) -> String {
        switch name {
        case "$web_search", "$web_search_sources", "weibei_web_open": "globe"
        case "weibei_search_workspace", "weibei_find_discussions": "magnifyingglass"
        case "weibei_course_read", "load_skill": "doc.text"
        case "weibei_read_discussion": "text.bubble"
        case "create_document": "doc.badge.plus"
        case "weibei_note_proposal": "square.and.pencil"
        case "weibei_course_map", "weibei_relation_proposal": "point.3.connected.trianglepath.dotted"
        case "weibei_read_learning_memory": "book.closed"
        case "weibei_update_learning_memory": "bookmark"
        case "weibei_course_profile_update": "person.text.rectangle"
        case "delegate": "person.2"
        case "weibei_visual_asset": "photo"
        case "weibei_course_retry_failed_pdf_pages": "doc.text.viewfinder"
        case "render_ui": "rectangle.3.group"
        default: "puzzlepiece.extension"
        }
    }
}

struct AgentActivityRevealTiming {
    let progress: Double
    let connector: Double
    let content: Double
    init(start: Date?, now: Date, reduceMotion: Bool) {
        guard let start, !reduceMotion else { progress = 1; connector = 1; content = 1; return }
        let age = max(0, now.timeIntervalSince(start))
        let row = min(1, age / 0.36)
        progress = row == 0 ? 0 : row == 1 ? 1 : 1 - pow(2, -10 * row)
        connector = 1 - pow(1 - min(1, age / 0.48), 5)
        content = min(1, max(0, (connector - 0.22) / 0.78))
    }
}

struct AgentToolActivityGroup: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    let message: AgentMessage
    var autoOpen: Bool? = nil
    var arrivals: [String: Date] = [:]
    @State private var userExpanded: Bool?
    @State private var detailIDs: Set<String> = []
    @State private var revealing = false
    private var running: Bool {
        message.completionState == .generating && message.toolActivities.contains { $0.state == .running }
    }
    private var expanded: Bool { userExpanded ?? autoOpen ?? running }
    private var lastArrival: Date? { arrivals.values.max() }
    private var summary: String {
        let searchNames = ["$web_search", "weibei_search_workspace", "weibei_find_discussions"]
        let readNames = ["load_skill", "weibei_course_read", "weibei_read_discussion", "weibei_web_open", "weibei_read_learning_memory"]
        let searches = message.toolActivities.filter { searchNames.contains($0.name) }.count
        let reads = message.toolActivities.filter { readNames.contains($0.name) }.count
        let others = message.toolActivities.filter {
            !searchNames.contains($0.name) && !readNames.contains($0.name) && $0.name != "$web_search_sources"
        }.count
        var parts: [String] = []
        if searches > 0 { parts.append(store.ui("搜索 \(searches) 次", "\(searches) searches")) }
        if reads > 0 { parts.append(store.ui("读取 \(reads) 次", "\(reads) reads")) }
        if others > 0 { parts.append(store.ui("执行 \(others) 项操作", "\(others) operations")) }
        if parts.isEmpty { parts.append(store.ui("查看搜索来源", "View search sources")) }
        if message.toolActivities.contains(where: { $0.state == .failed }) { parts.append(store.ui("有失败项", "Includes failures")) }
        return parts.joined(separator: " · ")
    }
    private var heading: String {
        guard running, let current = message.toolActivities.last(where: { $0.state == .running }) else { return summary }
        return current.name == "$web_search" ? store.ui("正在搜索网页", "Searching the web") : store.ui("正在", "Working: ") + title(current.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { userExpanded = !expanded } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .regular))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 22)
                    AgentActivityTitle(text: heading, active: running && !reduceMotion)
                        .transaction { $0.animation = nil }
                }
                .frame(height: 26, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? store.ui("已展开", "Expanded") : store.ui("已折叠", "Collapsed"))
            AgentActivityRevealLayout(progress: expanded ? 1 : 0) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !revealing || reduceMotion)) { tick in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(message.toolActivities.enumerated()), id: \.element.id) { entry in
                            let activity = entry.element
                            let timing = AgentActivityRevealTiming(start: arrivals[activity.id], now: tick.date, reduceMotion: reduceMotion)
                            let next = message.toolActivities.dropFirst(entry.offset + 1).first
                            let continuation = next.map { AgentActivityRevealTiming(start: arrivals[$0.id], now: tick.date, reduceMotion: reduceMotion).connector } ?? 0
                            AgentActivityRevealLayout(progress: timing.progress) {
                                activityRow(activity, timing: timing, continuation: continuation)
                            }.clipped()
                        }
                    }.padding(.top, 2).padding(.bottom, 2)
                }
            }
            .clipped()
            .opacity(expanded ? 1 : 0)
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)
        }
        .weiBeiText(12)
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: expanded)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: detailIDs)
        .task(id: lastArrival) {
            guard !reduceMotion, let lastArrival else { revealing = false; return }
            let remaining = lastArrival.addingTimeInterval(0.5).timeIntervalSinceNow
            guard remaining > 0 else { revealing = false; return }
            revealing = true
            do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
            revealing = false
        }
    }

    private func activityRow(_ activity: AgentToolActivity, timing: AgentActivityRevealTiming, continuation: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if !detailIDs.insert(activity.id).inserted { detailIDs.remove(activity.id) }
            } label: {
                HStack(spacing: 8) {
                    Text(title(activity.name)).lineLimit(1).fixedSize()
                    if !detailIDs.contains(activity.id), let detail = activity.detail, !detail.isEmpty {
                        Text(detail.replacingOccurrences(of: "\n", with: " "))
                            .lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(WeiBeiTheme.secondaryInk.opacity(0.75))
                    }
                    if activity.state == .failed {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(WeiBeiTheme.cinnabar)
                    } else if activity.state == .cancelled {
                        Text(store.ui("已取消", "Cancelled"))
                    }
                    Image(systemName: "chevron.right").font(.system(size: 8))
                        .rotationEffect(.degrees(detailIDs.contains(activity.id) ? 90 : 0))
                }
                .frame(height: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title(activity.name))
            .accessibilityValue(activity.state == .failed ? store.ui("失败", "Failed") :
                activity.state == .cancelled ? store.ui("已取消", "Cancelled") :
                activity.state == .running ? (running ? store.ui("进行中", "Running") : store.ui("已中断", "Interrupted")) : store.ui("已完成", "Completed"))
            if detailIDs.contains(activity.id) { details(activity).padding(.bottom, 10) }
        }
        .opacity(timing.content)
        .offset(y: 4 * (1 - timing.content))
        .padding(.leading, 56)
        .overlay(alignment: .leading) {
            GeometryReader { geometry in
                AgentActivityRail(progress: timing.connector, continuation: continuation)
                    .stroke(WeiBeiTheme.secondaryInk.opacity(0.24), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                    .frame(width: 48, height: geometry.size.height)
                Image(systemName: AgentActivityIcon.symbol(for: activity.name))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(activity.state == .failed ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                    .frame(width: 16, height: 16)
                    .offset(x: 32, y: 8 + 4 * (1 - timing.content))
                    .opacity(timing.content)
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func details(_ activity: AgentToolActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail = activity.detail, !detail.isEmpty { Text(detail).textSelection(.enabled) }
            if let result = activity.resultSummary, !result.isEmpty { Text(result).textSelection(.enabled) }
            else if activity.state == .failed { Text(store.ui("未能完成", "Could not complete")) }
            else if activity.state == .running && !running { Text(store.ui("已中断", "Interrupted")) }
            let urls = Array(Set(activity.sourceURLs ?? [])).sorted()
            if !urls.isEmpty {
                DisclosureGroup(store.ui("\(urls.count) 个来源", "\(urls.count) sources")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(urls, id: \.self) { raw in
                                if let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                                    Link(destination: url) {
                                        Text((url.host ?? "") + url.path).lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).help(raw)
                                }
                            }
                        }.padding(.vertical, 6)
                    }.frame(height: min(CGFloat(urls.count) * 38, 180))
                }
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func title(_ name: String) -> String {
        switch name {
        case "weibei_search_workspace": store.ui("搜索资料", "Search materials")
        case "weibei_course_read": store.ui("读取资料", "Read materials")
        case "weibei_course_map": store.ui("查看课程关联", "Explore course connections")
        case "weibei_read_learning_memory": store.ui("回顾学习记忆", "Read learning memory")
        case "weibei_update_learning_memory": store.ui("更新学习记忆", "Update learning memory")
        case "weibei_course_profile_update": store.ui("更新课程档案", "Update course profile")
        case "weibei_note_proposal": store.ui("准备笔记建议", "Prepare note proposal")
        case "load_skill": store.ui("读取技能指引", "Read skill instructions")
        case "create_document": store.ui("创建文档", "Create document")
        case "delegate": store.ui("委派子任务", "Delegate task")
        case "weibei_visual_asset": store.ui("查找视觉素材", "Find visual assets")
        case "weibei_find_discussions": store.ui("查找讨论", "Find discussions")
        case "weibei_read_discussion": store.ui("读取讨论", "Read discussion")
        case "weibei_web_open": store.ui("读取网页", "Read web page")
        case "weibei_course_retry_failed_pdf_pages": store.ui("重新识别资料页面", "Retry page recognition")
        case "weibei_relation_proposal": store.ui("准备关联建议", "Prepare relationship proposal")
        case "render_ui": store.ui("生成互动内容", "Create interactive content")
        case "$web_search": store.ui("网络搜索", "Search the web")
        case "$web_search_sources": store.ui("搜索返回的来源", "Sources returned by search")
        default: store.ui("执行工具", "Run tool") + " · " + name
        }
    }
}

private struct AgentActivityTitle: View {
    let text: String
    let active: Bool
    @State private var epoch = Date()
    var body: some View {
        Text(text).lineLimit(1)
            .overlay {
                if active {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tick in
                        GeometryReader { geometry in
                            let phase = tick.date.timeIntervalSince(epoch).truncatingRemainder(dividingBy: 3.4) / 3.4
                            LinearGradient(colors: [.clear, WeiBeiTheme.ink.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: geometry.size.width * 0.72)
                                .offset(x: geometry.size.width * (phase * 1.72 - 0.72))
                        }
                    }.mask(Text(text).lineLimit(1)).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}

private struct AgentActivityRail: Shape {
    var progress: Double
    var continuation: Double
    func path(in rect: CGRect) -> Path {
        var branch = Path()
        branch.move(to: CGPoint(x: 12.5, y: 0))
        branch.addLine(to: CGPoint(x: 12.5, y: 10))
        branch.addQuadCurve(to: CGPoint(x: 18.5, y: 16), control: CGPoint(x: 12.5, y: 16))
        branch.addLine(to: CGPoint(x: 28, y: 16))
        var result = branch.trimmedPath(from: 0, to: progress)
        if continuation > 0 {
            result.move(to: CGPoint(x: 12.5, y: 10))
            result.addLine(to: CGPoint(x: 12.5, y: 10 + max(0, rect.height - 10) * continuation))
        }
        return result
    }
}

/// Size changes propagate to the native collection while children stay anchored.
private struct AgentActivityRevealLayout: Layout {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        return CGSize(width: size.width, height: size.height * progress)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
