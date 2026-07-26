import SwiftUI
import WeiBeiCore

struct CourseRelationPaperView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var lens: CourseRelationLens
    let search: String
    @Binding var selectedNoteID: String?
    @Binding var selectedMaterialID: String?
    let isCompact: Bool

    @State private var scope: CourseRelationPaperScope?
    @State private var mode: CourseRelationPaperMode = .viewing
    @State private var hoveredNodeID: String?
    @State private var dropTargetNoteID: String?
    @State private var pendingConnection: CourseRelationConnectionAnchor?
    @State private var zoomScale: CGFloat = 1
    @State private var zoomGestureStartScale: CGFloat?
    @State private var fitScrollRequest = 0

    private var minimumZoomScale: CGFloat { 0.2 }
    private var maximumZoomScale: CGFloat { 1.6 }
    private static let paperOriginID = "course-relation-paper-origin"

    /// Prefer the course already open in course space; fall back to whole workspace.
    private var defaultScope: CourseRelationPaperScope {
        if let courseID = store.activeCourseID,
           store.courses.contains(where: { $0.id == courseID }) {
            return .course(courseID)
        }
        return .all
    }

    private var effectiveScope: CourseRelationPaperScope {
        let candidate = scope ?? defaultScope
        if case .course(let courseID) = candidate,
           !store.courses.contains(where: { $0.id == courseID }) {
            return defaultScope == .all ? .all : defaultScope
        }
        return candidate
    }

    private var graphModel: CourseRelationGraphModel {
        CourseRelationGraphModel(
            materials: scopedMaterials.map { graphItem(for: $0, kind: .material) },
            notes: scopedNotes.map { graphItem(for: $0, kind: .note) },
            links: store.noteSourceLinks,
            query: search,
            selectedNoteID: selectedNoteID,
            selectedMaterialID: selectedMaterialID,
            showsOnlyUnlinked: effectiveScope == .unlinked,
            maxVisibleNodes: isCompact ? 36 : 72
        )
    }

    private var scopedMaterials: [StudyItem] {
        switch effectiveScope {
        case .course(let courseID):
            return store.courseMaterials(in: courseID)
        case .all:
            return store.courseMaterials
        case .unassigned:
            return store.unassignedCourseMaterials
        case .unlinked:
            return store.courseMaterials
        }
    }

    private var scopedNotes: [StudyItem] {
        switch effectiveScope {
        case .course(let courseID):
            return store.courseNotes(in: courseID)
        case .all:
            return store.courseNotebookItems
        case .unassigned:
            return store.unassignedCourseNotes
        case .unlinked:
            return store.courseNotebookItems
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header(model: graphModel)
            CourseHairline()
            GeometryReader { proxy in
                let showCourseRail = !isCompact && proxy.size.width >= 760
                HStack(spacing: 0) {
                    if showCourseRail {
                        courseScopeRail
                        CourseHairline(axis: .vertical)
                    }
                    Group {
                        if isCompact || proxy.size.width < 660 {
                            compactPaper(model: graphModel)
                        } else {
                            graphPaper(
                                model: graphModel,
                                availableSize: CGSize(
                                    width: showCourseRail ? max(320, proxy.size.width - 212) : proxy.size.width,
                                    height: proxy.size.height
                                )
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(WeiBeiTheme.paper.opacity(0.94))
        .animation(WeiBeiMotion.hover, value: hoveredNodeID)
        .animation(WeiBeiMotion.hover, value: pendingConnection)
        .animation(WeiBeiMotion.panel, value: effectiveScope.id)
        .animation(WeiBeiMotion.panel, value: mode)
        .onAppear {
            // Seed once from the course already open in course space.
            if scope == nil {
                scope = defaultScope
            }
        }
        .onChange(of: store.activeCourseID) { _, newID in
            // Follow course switches from the title menu unless user picked a non-course filter.
            switch effectiveScope {
            case .all, .unassigned, .unlinked:
                break
            case .course:
                if let newID, store.courses.contains(where: { $0.id == newID }) {
                    scope = .course(newID)
                }
            }
        }
        .onChange(of: mode) { _, nextMode in
            if nextMode != .managing { pendingConnection = nil }
        }
        .onChange(of: effectiveScope.id) { _, _ in
            pendingConnection = nil
        }
        .onChange(of: search) { _, _ in
            pendingConnection = nil
        }
    }

    /// Thin toolbar only — page title already lives in the course-space top bar.
    private func header(model: CourseRelationGraphModel) -> some View {
        HStack(spacing: 12) {
            Text(headerDetail(model: model))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            // Narrow widths hide the rail — keep a compact course picker.
            if isCompact {
                scopeMenu
            }

            paperModeButton(.viewing)
            paperModeButton(.managing)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(WeiBeiTheme.paperRaised.opacity(0.22))
    }

    /// Left rail: courses as primary units (plus all / unassigned / unlinked).
    private var courseScopeRail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.ui("按课程", "By course"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                ForEach(store.courses) { course in
                    let materialCount = store.courseMaterials(in: course.id).count
                    let noteCount = store.courseNotes(in: course.id).count
                    courseScopeRow(
                        title: course.title,
                        detail: store.ui(
                            "文稿 \(materialCount) · 笔记 \(noteCount)",
                            "\(materialCount) materials · \(noteCount) notes"
                        ),
                        accent: courseWorkspaceAccent(colorIndex: course.colorIndex),
                        selected: {
                            if case .course(let id) = effectiveScope { return id == course.id }
                            return false
                        }()
                    ) {
                        setScope(.course(course.id))
                    }
                }

                if !store.courses.isEmpty {
                    CourseHairline()
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                }

                courseScopeRow(
                    title: store.ui("全部关系", "All relations"),
                    detail: store.ui("整份工作区", "Whole workspace"),
                    accent: WeiBeiTheme.secondaryInk,
                    selected: effectiveScope == .all
                ) {
                    setScope(.all)
                }

                courseScopeRow(
                    title: store.ui("未归属课程", "No course"),
                    detail: store.ui(
                        "文稿 \(store.unassignedCourseMaterials.count) · 笔记 \(store.unassignedCourseNotes.count)",
                        "\(store.unassignedCourseMaterials.count) materials · \(store.unassignedCourseNotes.count) notes"
                    ),
                    accent: WeiBeiTheme.tertiaryInk,
                    selected: effectiveScope == .unassigned
                ) {
                    setScope(.unassigned)
                }

                courseScopeRow(
                    title: store.ui("未建立关系", "Unlinked"),
                    detail: store.ui("尚未互相关联的项", "Items without links"),
                    accent: WeiBeiTheme.cinnabar.opacity(0.72),
                    selected: effectiveScope == .unlinked
                ) {
                    setScope(.unlinked)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .background(WeiBeiTheme.paperRaised.opacity(0.22))
    }

    private func courseScopeRow(
        title: String,
        detail: String,
        accent: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(accent)
                    .frame(width: 3, height: selected ? 28 : 18)
                    .opacity(selected ? 1 : 0.55)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected
                    ? WeiBeiTheme.cinnabarSoft.opacity(0.36)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scopeMenu: some View {
        Menu {
            Button(store.ui("全部关系", "All relations")) {
                setScope(.all)
            }
            Button(store.ui("未归属课程", "No course")) {
                setScope(.unassigned)
            }
            Button(store.ui("未建立关系", "Unlinked")) {
                setScope(.unlinked)
            }
            Divider()
            ForEach(store.courses) { course in
                Button(course.title) {
                    setScope(.course(course.id))
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(scopeTitle(effectiveScope))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(WeiBeiTheme.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(WeiBeiTheme.paperInset.opacity(0.34), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func paperModeButton(_ candidate: CourseRelationPaperMode) -> some View {
        Button {
            mode = candidate
        } label: {
            Text(candidate.label(language: store.interfaceLanguage))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mode == candidate ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    (mode == candidate ? WeiBeiTheme.cinnabarSoft : WeiBeiTheme.paperInset.opacity(0.20)),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func graphPaper(model: CourseRelationGraphModel, availableSize: CGSize) -> some View {
        let paperSize = model.paperSize(forWidth: availableSize.width, compact: false)
        let layout = model.layout(in: paperSize)

        return ZStack(alignment: .topTrailing) {
            ScrollViewReader { scrollProxy in
                ScrollView([.vertical, .horizontal]) {
                    ZStack(alignment: .topLeading) {
                        paperBackground(size: paperSize)

                    Canvas { context, _ in
                        for placedEdge in layout.edges {
                            let prominence = model.edgeProminence(placedEdge.edge, hoveredNodeID: hoveredNodeID)
                            let path = edgePath(for: placedEdge)
                            let width = edgeWidth(placedEdge.edge, prominence: prominence)
                            context.stroke(
                                path,
                                with: .color(edgeHazeColor(for: placedEdge.edge, prominence: prominence)),
                                style: StrokeStyle(
                                    lineWidth: width + edgeHazeWidth(prominence),
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                        }

                        let orderedEdges = layout.edges.sorted { lhs, rhs in
                            let lhsProminence = model.edgeProminence(lhs.edge, hoveredNodeID: hoveredNodeID)
                            let rhsProminence = model.edgeProminence(rhs.edge, hoveredNodeID: hoveredNodeID)
                            let lhsOrder = edgeDrawingOrder(lhsProminence)
                            let rhsOrder = edgeDrawingOrder(rhsProminence)
                            if lhsOrder == rhsOrder { return lhs.edge.id < rhs.edge.id }
                            return lhsOrder < rhsOrder
                        }
                        for placedEdge in orderedEdges {
                            let prominence = model.edgeProminence(placedEdge.edge, hoveredNodeID: hoveredNodeID)
                            let path = edgePath(for: placedEdge)
                            let width = edgeWidth(placedEdge.edge, prominence: prominence)
                            context.stroke(
                                path,
                                with: edgeShading(
                                    for: placedEdge.edge,
                                    prominence: prominence,
                                    from: placedEdge.from,
                                    to: placedEdge.to
                                ),
                                style: StrokeStyle(
                                    lineWidth: width,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            if prominence == .focused || prominence == .related {
                                context.stroke(
                                    path,
                                    with: .color(edgeThreadColor(prominence: prominence)),
                                    style: StrokeStyle(
                                        lineWidth: prominence == .focused ? 1.4 : 0.8,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                            }
                        }
                    }
                    .frame(width: paperSize.width, height: paperSize.height)
                    .allowsHitTesting(false)

                    paperColumnMark(store.ui("课程资料", "MATERIALS"))
                        .position(x: min(max(150, paperSize.width * 0.28), paperSize.width * 0.42), y: 38)

                    paperColumnMark(store.ui("课程笔记", "NOTES"))
                        .position(x: max(min(paperSize.width - 150, paperSize.width * 0.72), paperSize.width * 0.58), y: 38)

                    ForEach(layout.nodes) { placedNode in
                        paperNode(placedNode.node, model: model)
                            .frame(width: placedNode.frame.width, height: placedNode.frame.height)
                            .position(x: placedNode.frame.midX, y: placedNode.frame.midY)
                    }

                    if model.hiddenNodeCount > 0 {
                        hiddenCountBadge(model.hiddenNodeCount)
                            .position(x: paperSize.width / 2, y: paperSize.height - 42)
                    }

                    if !model.hasContent {
                        CourseEmptyState(
                            title: store.ui("没有匹配内容", "No matching content"),
                            detail: store.ui("换个筛选或搜索词，再看看这张关系纸面。", "Try another scope or search query."),
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                        .frame(width: min(420, paperSize.width - 80), height: 260)
                        .position(x: paperSize.width / 2, y: paperSize.height / 2)
                    }
                    }
                    .frame(width: paperSize.width, height: paperSize.height)
                    .scaleEffect(zoomScale, anchor: .topLeading)
                    .frame(
                        width: paperSize.width * zoomScale,
                        height: paperSize.height * zoomScale,
                        alignment: .topLeading
                    )
                    .id(Self.paperOriginID)
                }
                .simultaneousGesture(magnificationGesture)
                .onChange(of: fitScrollRequest) { _, _ in
                    DispatchQueue.main.async {
                        withAnimation(WeiBeiMotion.hover) {
                            scrollProxy.scrollTo(Self.paperOriginID, anchor: .topLeading)
                        }
                    }
                }
            }

            zoomControls(paperSize: paperSize, availableSize: availableSize)
                .padding(14)
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                let startingScale = zoomGestureStartScale ?? zoomScale
                if zoomGestureStartScale == nil {
                    zoomGestureStartScale = zoomScale
                }
                zoomScale = clampedZoomScale(startingScale * magnification)
            }
            .onEnded { _ in
                zoomScale = clampedZoomScale(zoomScale)
                zoomGestureStartScale = nil
            }
    }

    private func zoomControls(paperSize: CGSize, availableSize: CGSize) -> some View {
        HStack(spacing: 0) {
            Button {
                setZoomScale(zoomScale - 0.1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(zoomScale <= minimumZoomScale + 0.001)
            .help(store.ui("缩小画布", "Zoom out"))

            zoomControlDivider

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(width: 48, height: 28)
                .accessibilityLabel(store.ui("当前缩放 \(Int((zoomScale * 100).rounded()))%", "Current zoom \(Int((zoomScale * 100).rounded())) percent"))

            zoomControlDivider

            Button {
                setZoomScale(zoomScale + 0.1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(zoomScale >= maximumZoomScale - 0.001)
            .help(store.ui("放大画布", "Zoom in"))

            zoomControlDivider

            Button {
                setZoomScale(fitZoomScale(paperSize: paperSize, availableSize: availableSize))
                fitScrollRequest += 1
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(store.ui("适合", "Fit"))
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .help(store.ui("完整显示关系画布", "Fit the relationship canvas"))
        }
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.74), lineWidth: 1)
        )
        .shadow(color: WeiBeiTheme.ink.opacity(0.055), radius: 8, y: 3)
    }

    private var zoomControlDivider: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.64))
            .frame(width: 1, height: 15)
    }

    private func fitZoomScale(paperSize: CGSize, availableSize: CGSize) -> CGFloat {
        let horizontalScale = max(1, availableSize.width - 32) / max(1, paperSize.width)
        let verticalScale = max(1, availableSize.height - 32) / max(1, paperSize.height)
        return clampedZoomScale(min(horizontalScale, verticalScale))
    }

    private func setZoomScale(_ scale: CGFloat) {
        withAnimation(WeiBeiMotion.hover) {
            zoomScale = clampedZoomScale(scale)
        }
    }

    private func clampedZoomScale(_ scale: CGFloat) -> CGFloat {
        min(maximumZoomScale, max(minimumZoomScale, scale))
    }

    private func edgePath(for placedEdge: CourseRelationPlacedEdge) -> Path {
        let from = placedEdge.from
        let to = placedEdge.to
        let horizontalDistance = max(1, to.x - from.x)
        let middle = CGPoint(
            x: from.x + horizontalDistance * 0.5,
            y: (from.y + to.y) * 0.5 + min(16, max(-16, (to.y - from.y) * 0.035))
        )
        let departure = min(horizontalDistance * 0.40, max(88, horizontalDistance * 0.30))
        let waist = min(horizontalDistance * 0.16, 72)

        var path = Path()
        path.move(to: from)
        path.addCurve(
            to: middle,
            control1: CGPoint(x: from.x + departure, y: from.y),
            control2: CGPoint(x: middle.x - waist, y: middle.y)
        )
        path.addCurve(
            to: to,
            control1: CGPoint(x: middle.x + waist, y: middle.y),
            control2: CGPoint(x: to.x - departure, y: to.y)
        )
        return path
    }

    private func edgeDrawingOrder(_ prominence: CourseRelationGraphProminence) -> Int {
        switch prominence {
        case .mist:
            return 0
        case .normal:
            return 1
        case .related:
            return 2
        case .focused:
            return 3
        }
    }

    private func edgeShading(
        for edge: CourseRelationGraphEdge,
        prominence: CourseRelationGraphProminence,
        from: CGPoint,
        to: CGPoint
    ) -> GraphicsContext.Shading {
        let color = edgeColor(for: edge, prominence: prominence)
        return .linearGradient(
            Gradient(stops: [
                .init(color: color.opacity(0.76), location: 0),
                .init(color: color, location: 0.42),
                .init(color: color.opacity(0.82), location: 1),
            ]),
            startPoint: from,
            endPoint: to
        )
    }

    private func edgeThreadColor(prominence: CourseRelationGraphProminence) -> Color {
        switch prominence {
        case .focused:
            return WeiBeiTheme.paper.opacity(0.34)
        case .related:
            return WeiBeiTheme.paper.opacity(0.20)
        case .normal, .mist:
            return .clear
        }
    }

    private func compactPaper(model: CourseRelationGraphModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !model.hasContent {
                    CourseEmptyState(
                        title: store.ui("没有匹配关系", "No matching relations"),
                        detail: store.ui("换个搜索词，或切到全部关系查看。", "Try another query or switch to all relations."),
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    compactSection(title: store.ui("资料", "Materials"), nodes: model.materials, model: model)
                    compactSection(title: store.ui("笔记", "Notes"), nodes: model.notes, model: model)
                    if model.hiddenNodeCount > 0 {
                        hiddenCountBadge(model.hiddenNodeCount)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(18)
        }
        .background(WeiBeiTheme.paperRaised.opacity(0.18))
    }

    private func compactSection(
        title: String,
        nodes: [CourseRelationGraphNode],
        model: CourseRelationGraphModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(nodes) { node in
                    paperNode(node, model: model)
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
            }
        }
    }

    private func paperNode(
        _ node: CourseRelationGraphNode,
        model: CourseRelationGraphModel
    ) -> some View {
        let prominence = model.nodeProminence(node, hoveredNodeID: hoveredNodeID)
        let isDropTarget = node.kind == .note && dropTargetNoteID == node.itemID
        let connectorState = mode == .managing ? connectionState(for: node) : nil

        return CourseRelationPaperNodeView(
            node: node,
            prominence: prominence,
            accent: nodeAccent(for: node),
            mode: mode,
            connectionState: connectorState,
            isDropTarget: isDropTarget,
            select: { select(node) },
            open: { open(node) },
            connect: { handleConnectionTap(node) },
            hover: { hovering in hoveredNodeID = hovering ? node.id : (hoveredNodeID == node.id ? nil : hoveredNodeID) }
        )
        .contextMenu {
            relationMenu(for: node)
        }
        .modifier(CourseRelationDropModifier(
            node: node,
            enabled: mode == .managing,
            dropTargetNoteID: $dropTargetNoteID,
            addLink: addLink(materialID:noteID:)
        ))
    }

    @ViewBuilder
    private func relationMenu(for node: CourseRelationGraphNode) -> some View {
        Button(node.kind == .material ? store.ui("打开资料", "Open material") : store.ui("打开笔记", "Open note")) {
            open(node)
        }
        if mode == .managing {
            Divider()
            if node.kind == .material {
                let linkedNotes = linkedNoteItems(for: node.itemID)
                if linkedNotes.isEmpty {
                    Text(store.ui("没有可删除关系", "No links to remove"))
                } else {
                    Menu(store.ui("删除已关联笔记", "Remove linked note")) {
                        ForEach(linkedNotes) { note in
                            Button(role: .destructive) {
                                removeLink(noteID: note.id, materialID: node.itemID)
                            } label: {
                                Text(store.displayTitle(for: note))
                            }
                        }
                    }
                }
            } else {
                let linkedMaterials = linkedMaterialItems(for: node.itemID)
                if linkedMaterials.isEmpty {
                    Text(store.ui("没有可删除关系", "No links to remove"))
                } else {
                    Menu(store.ui("删除已关联资料", "Remove linked material")) {
                        ForEach(linkedMaterials) { material in
                            Button(role: .destructive) {
                                removeLink(noteID: node.itemID, materialID: material.id)
                            } label: {
                                Text(store.displayTitle(for: material))
                            }
                        }
                    }
                }
            }
        }
    }

    private func paperColumnMark(_ title: String) -> some View {
        Text(title)
            .font(WeiBeiTypography.englishBrandFont(size: 9.5, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.72))
    }

    private func paperBackground(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(WeiBeiTheme.paperRaised.opacity(0.22))
            Circle()
                .fill(WeiBeiTheme.cinnabarSoft.opacity(0.15))
                .frame(width: 480, height: 480)
                .blur(radius: 78)
                .offset(x: size.width * 0.12, y: -20)
            Circle()
                .fill(WeiBeiTheme.paperInset.opacity(0.28))
                .frame(width: 560, height: 560)
                .blur(radius: 92)
                .offset(x: size.width * 0.48, y: size.height * 0.30)
            Circle()
                .fill(WeiBeiTheme.secondaryInk.opacity(0.025))
                .frame(width: 440, height: 440)
                .blur(radius: 84)
                .offset(x: size.width * 0.28, y: size.height * 0.56)
            VStack {
                Spacer()
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, WeiBeiTheme.paper.opacity(0.82)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 150)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func hiddenCountBadge(_ count: Int) -> some View {
        Text(store.ui("其余 \(count) 项已收起", "\(count) more items hidden"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(WeiBeiTheme.paper.opacity(0.82), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(WeiBeiTheme.hairline.opacity(0.72), lineWidth: 1)
            )
    }

    private func graphItem(for item: StudyItem, kind: CourseRelationGraphItem.Kind) -> CourseRelationGraphItem {
        let membershipIDs = Set(store.courseIDs(for: item.id))
        let courseTitles = store.courses
            .filter { membershipIDs.contains($0.id) }
            .prefix(2)
            .map(\.title)
        let membershipLabel = courseTitles.isEmpty
            ? item.kind.label(language: store.interfaceLanguage)
            : courseTitles.joined(separator: " / ")
        return CourseRelationGraphItem(
            itemID: item.id,
            kind: kind,
            title: store.displayTitle(for: item),
            subtitle: store.displaySubtitle(for: item),
            kindLabel: membershipLabel,
            symbolName: kind == .note ? "note.text" : item.kind.systemImage
        )
    }

    private func headerDetail(model: CourseRelationGraphModel) -> String {
        if let pendingConnection {
            let title = model.visibleNodes.first(where: {
                $0.itemID == pendingConnection.itemID && $0.kind == pendingConnection.kind
            })?.item.title ?? store.ui("当前项目", "Current item")
            return store.ui(
                "已选「\(title)」· 点另一侧的 + 建立关联，点当前 + 取消",
                "Selected “\(title)” · choose + on the other side to link, or choose this + again to cancel"
            )
        }
        let scopeText = scopeTitle(effectiveScope)
        let relationText = store.ui("\(model.edges.count) 条可见关系", "\(model.edges.count) visible links")
        let nodeText = store.ui("\(model.visibleNodes.count) 个节点", "\(model.visibleNodes.count) nodes")
        let saveText = mode == .managing
            ? " · \(store.ui("更改自动保存", "Changes save automatically"))"
            : ""
        if model.hiddenNodeCount > 0 {
            return "\(scopeText) · \(relationText) · \(nodeText) · \(store.ui("其余 \(model.hiddenNodeCount) 项", "\(model.hiddenNodeCount) hidden"))\(saveText)"
        }
        return "\(scopeText) · \(relationText) · \(nodeText)\(saveText)"
    }

    private func scopeTitle(_ scope: CourseRelationPaperScope) -> String {
        switch scope {
        case .course(let courseID):
            return store.courses.first(where: { $0.id == courseID })?.title ?? store.ui("当前课程", "Active course")
        case .all:
            return store.ui("全部关系", "All relations")
        case .unassigned:
            return store.ui("未归属课程", "No course")
        case .unlinked:
            return store.ui("未建立关系", "Unlinked")
        }
    }

    private func setScope(_ nextScope: CourseRelationPaperScope) {
        scope = nextScope
        // Only pin the workspace course when the user picks a concrete course unit.
        // "All / unassigned / unlinked" are paper filters, not "leave this course".
        if case .course(let courseID) = nextScope {
            store.activateCourse(courseID)
        }
    }

    private func select(_ node: CourseRelationGraphNode) {
        switch node.kind {
        case .material:
            lens = .materials
            selectedMaterialID = node.itemID
            selectedNoteID = nil
        case .note:
            lens = .notes
            selectedNoteID = node.itemID
            selectedMaterialID = nil
        }
    }

    private func open(_ node: CourseRelationGraphNode) {
        select(node)
        switch node.kind {
        case .material:
            store.openCourseMaterial(node.itemID)
        case .note:
            store.openCourseNote(node.itemID)
        }
    }

    private func connectionState(for node: CourseRelationGraphNode) -> CourseRelationConnectionState {
        guard let pendingConnection else { return .available }
        let anchor = CourseRelationConnectionAnchor(itemID: node.itemID, kind: node.kind)
        if pendingConnection == anchor { return .source }
        return pendingConnection.kind == node.kind ? .alternate : .target
    }

    private func handleConnectionTap(_ node: CourseRelationGraphNode) {
        guard mode == .managing else { return }
        let anchor = CourseRelationConnectionAnchor(itemID: node.itemID, kind: node.kind)
        guard let pendingConnection else {
            self.pendingConnection = anchor
            select(node)
            return
        }
        if pendingConnection == anchor {
            self.pendingConnection = nil
            return
        }
        if pendingConnection.kind == anchor.kind {
            self.pendingConnection = anchor
            select(node)
            return
        }

        let materialID = pendingConnection.kind == .material ? pendingConnection.itemID : anchor.itemID
        let noteID = pendingConnection.kind == .note ? pendingConnection.itemID : anchor.itemID
        addLink(materialID: materialID, noteID: noteID)
        self.pendingConnection = nil
    }

    private func addLink(materialID: String, noteID: String) {
        guard mode == .managing,
              scopedMaterials.contains(where: { $0.id == materialID }),
              scopedNotes.contains(where: { $0.id == noteID })
        else { return }
        var linkedNoteIDs = Set(store.linkedNoteIDs(for: materialID))
        guard linkedNoteIDs.insert(noteID).inserted else {
            selectedMaterialID = materialID
            selectedNoteID = noteID
            return
        }
        store.setLinkedNoteIDs(linkedNoteIDs, for: materialID)
        selectedMaterialID = materialID
        selectedNoteID = noteID
    }

    private func removeLink(noteID: String, materialID: String) {
        var linkedMaterialIDs = Set(store.linkedCourseSourceIDs(for: noteID))
        linkedMaterialIDs.remove(materialID)
        store.setLinkedCourseSourceIDs(linkedMaterialIDs, for: noteID)
        selectedMaterialID = materialID
        selectedNoteID = noteID
    }

    private func linkedNoteItems(for materialID: String) -> [StudyItem] {
        let ids = Set(store.linkedNoteIDs(for: materialID))
        return store.courseNotebookItems.filter { ids.contains($0.id) }
    }

    private func linkedMaterialItems(for noteID: String) -> [StudyItem] {
        let ids = Set(store.linkedCourseSourceIDs(for: noteID))
        return store.courseMaterials.filter { ids.contains($0.id) }
    }

    private func nodeAccent(for node: CourseRelationGraphNode) -> Color {
        if case .course(let courseID) = effectiveScope,
           let course = store.course(withID: courseID) {
            return courseAccent(colorIndex: course.colorIndex)
        }
        guard let courseID = store.courseIDs(for: node.itemID).first,
              let course = store.course(withID: courseID)
        else {
            return node.kind == .note ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk
        }
        return courseAccent(colorIndex: course.colorIndex)
    }

    private func edgeAccent(for edge: CourseRelationGraphEdge) -> Color {
        if case .course(let courseID) = effectiveScope,
           let course = store.course(withID: courseID) {
            return courseAccent(colorIndex: course.colorIndex)
        }
        let materialCourseIDs = Set(store.courseIDs(for: edge.materialID))
        let noteCourseIDs = Set(store.courseIDs(for: edge.noteID))
        let sharedCourseIDs = materialCourseIDs.intersection(noteCourseIDs)
        let courseID = store.courses.first(where: { sharedCourseIDs.contains($0.id) })?.id
            ?? store.courses.first(where: { materialCourseIDs.contains($0.id) })?.id
        guard let courseID,
              let course = store.course(withID: courseID)
        else {
            return WeiBeiTheme.secondaryInk
        }
        return courseAccent(colorIndex: course.colorIndex)
    }

    private func courseAccent(colorIndex: Int) -> Color {
        switch ((colorIndex % 4) + 4) % 4 {
        case 0:
            return WeiBeiTheme.cinnabar
        case 1:
            return WeiBeiTheme.moss
        case 2:
            return WeiBeiTheme.link
        default:
            return WeiBeiTheme.secondaryInk
        }
    }

    private func edgeColor(
        for edge: CourseRelationGraphEdge,
        prominence: CourseRelationGraphProminence
    ) -> Color {
        let accent = edgeAccent(for: edge)
        switch prominence {
        case .focused:
            return accent.opacity(0.62)
        case .related:
            return accent.opacity(0.38)
        case .normal:
            return accent.opacity(0.15)
        case .mist:
            return accent.opacity(0.028)
        }
    }

    private func edgeHazeColor(
        for edge: CourseRelationGraphEdge,
        prominence: CourseRelationGraphProminence
    ) -> Color {
        let accent = edgeAccent(for: edge)
        switch prominence {
        case .focused:
            return accent.opacity(0.060)
        case .related:
            return accent.opacity(0.042)
        case .normal:
            return accent.opacity(0.026)
        case .mist:
            return accent.opacity(0.010)
        }
    }

    private func edgeWidth(_ edge: CourseRelationGraphEdge, prominence: CourseRelationGraphProminence) -> CGFloat {
        let base = CGFloat(min(9, 4 + max(0, edge.count - 1) * 2))
        switch prominence {
        case .focused:
            return base + 6
        case .related:
            return base + 2.5
        case .normal:
            return base
        case .mist:
            return max(1.2, base * 0.38)
        }
    }

    private func edgeHazeWidth(_ prominence: CourseRelationGraphProminence) -> CGFloat {
        switch prominence {
        case .focused:
            return 22
        case .related:
            return 16
        case .normal:
            return 11
        case .mist:
            return 7
        }
    }
}

private struct CourseRelationConnectionAnchor: Equatable {
    let itemID: String
    let kind: CourseRelationGraphItem.Kind
}

private enum CourseRelationConnectionState: Equatable {
    case available
    case alternate
    case source
    case target
}

private enum CourseRelationPaperMode: Equatable {
    case viewing
    case managing

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .viewing:
            return language.text("查看", "View")
        case .managing:
            return language.text("管理", "Manage")
        }
    }
}

private struct CourseRelationPaperNodeView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let node: CourseRelationGraphNode
    let prominence: CourseRelationGraphProminence
    let accent: Color
    let mode: CourseRelationPaperMode
    let connectionState: CourseRelationConnectionState?
    let isDropTarget: Bool
    let select: () -> Void
    let open: () -> Void
    let connect: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if node.kind == .note, let connectionState {
                connectionControl(connectionState)
            }

            Capsule()
                .fill(markerColor)
                .frame(width: prominence == .focused ? 3 : 2, height: 30)

            Button(action: select) {
                HStack(spacing: 9) {
                    Image(systemName: node.item.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.item.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.ink)
                            .lineLimit(1)
                        Text(detailText)
                            .font(.system(size: 11))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(CourseRelationNodeDragModifier(
                enabled: mode == .managing && node.kind == .material,
                itemID: node.itemID
            ))

            if node.kind == .material, let connectionState {
                connectionControl(connectionState)
            } else if mode == .viewing {
                openControl
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .opacity(opacity)
        .background(nodeBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(underlineColor)
                .frame(width: prominence == .focused ? 76 : 42, height: isDropTarget ? 2 : 1)
                .padding(.leading, 12)
        }
        .onHover(perform: hover)
    }

    private var detailText: String {
        let countText = node.relationCount == 0 ? "0" : "\(node.relationCount)"
        return "\(node.item.kindLabel) · \(countText)"
    }

    private var openControl: some View {
        Button(action: open) {
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .opacity(prominence == .mist ? 0.12 : 0.72)
    }

    @ViewBuilder
    private func connectionControl(_ state: CourseRelationConnectionState) -> some View {
        connectionButton(state)
    }

    private func connectionButton(_ state: CourseRelationConnectionState) -> some View {
        Button(action: connect) {
            Image(systemName: state == .source ? "xmark" : "plus")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(connectionForeground(state))
                .frame(width: 27, height: 27)
                .background(connectionBackground(state), in: Circle())
                .overlay(
                    Circle()
                        .stroke(connectionBorder(state), lineWidth: state == .target ? 1.4 : 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(node.item.title)：\(connectionLabel(state))")
        .help(connectionHelp(state))
    }

    private func connectionForeground(_ state: CourseRelationConnectionState) -> Color {
        switch state {
        case .available:
            return WeiBeiTheme.secondaryInk
        case .alternate:
            return WeiBeiTheme.secondaryInk.opacity(0.84)
        case .source:
            return WeiBeiTheme.onCinnabar
        case .target:
            return accent
        }
    }

    private func connectionBackground(_ state: CourseRelationConnectionState) -> Color {
        switch state {
        case .available:
            return WeiBeiTheme.paper.opacity(0.88)
        case .alternate:
            return WeiBeiTheme.paperInset.opacity(0.34)
        case .source:
            return accent.opacity(0.88)
        case .target:
            return accent.opacity(0.13)
        }
    }

    private func connectionBorder(_ state: CourseRelationConnectionState) -> Color {
        switch state {
        case .available:
            return WeiBeiTheme.hairline.opacity(0.82)
        case .alternate:
            return WeiBeiTheme.hairline.opacity(0.68)
        case .source:
            return accent.opacity(0.92)
        case .target:
            return accent.opacity(0.62)
        }
    }

    private func connectionLabel(_ state: CourseRelationConnectionState) -> String {
        switch state {
        case .available:
            return store.ui("选择为关联起点", "Choose as link start")
        case .alternate:
            return store.ui("切换为新的关联起点", "Switch to this link start")
        case .source:
            return store.ui("取消当前关联起点", "Cancel current link start")
        case .target:
            return store.ui("与当前起点建立关联", "Link with current start")
        }
    }

    private func connectionHelp(_ state: CourseRelationConnectionState) -> String {
        if state == .target {
            return connectionLabel(state)
        }
        if node.kind == .material, state != .source {
            return store.ui("点按选择资料；也可拖到笔记", "Choose this material, or drag it onto a note")
        }
        return connectionLabel(state)
    }

    private var iconColor: Color {
        prominence == .mist ? WeiBeiTheme.tertiaryInk : accent
    }

    private var nodeBackground: Color {
        if isDropTarget { return accent.opacity(0.14) }
        if connectionState == .source { return accent.opacity(0.11) }
        if connectionState == .target { return accent.opacity(0.055) }
        switch prominence {
        case .focused:
            return accent.opacity(0.080)
        case .related:
            return accent.opacity(0.042)
        case .normal:
            return WeiBeiTheme.paperRaised.opacity(0.10)
        case .mist:
            return Color.clear
        }
    }

    private var markerColor: Color {
        // Relation-paper markers stay hairline-grade; course accent only for transient connect/drop.
        if isDropTarget { return WeiBeiTheme.secondaryInk.opacity(0.72) }
        if connectionState == .source { return WeiBeiTheme.secondaryInk.opacity(0.62) }
        if connectionState == .target { return WeiBeiTheme.hairline.opacity(0.72) }
        switch prominence {
        case .focused:
            return WeiBeiTheme.secondaryInk.opacity(0.58)
        case .related:
            return WeiBeiTheme.hairline.opacity(0.78)
        case .normal:
            return WeiBeiTheme.hairline.opacity(0.62)
        case .mist:
            return WeiBeiTheme.hairline.opacity(0.20)
        }
    }

    private var underlineColor: Color {
        if isDropTarget { return accent.opacity(0.82) }
        if connectionState == .source { return accent.opacity(0.58) }
        if connectionState == .target { return accent.opacity(0.30) }
        switch prominence {
        case .focused:
            return accent.opacity(0.54)
        case .related:
            return accent.opacity(0.26)
        case .normal:
            return WeiBeiTheme.hairline.opacity(0.48)
        case .mist:
            return WeiBeiTheme.hairline.opacity(0.12)
        }
    }

    private var opacity: Double {
        if connectionState == .source { return 1 }
        if connectionState == .target { return 0.90 }
        if connectionState == .alternate { return 0.72 }
        if connectionState == .available { return 0.82 }
        switch prominence {
        case .focused:
            return 1
        case .related:
            return 0.92
        case .normal:
            return 0.82
        case .mist:
            return 0.28
        }
    }
}

private struct CourseRelationNodeDragModifier: ViewModifier {
    let enabled: Bool
    let itemID: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.draggable(itemID)
        } else {
            content
        }
    }
}

private struct CourseRelationDropModifier: ViewModifier {
    let node: CourseRelationGraphNode
    let enabled: Bool
    @Binding var dropTargetNoteID: String?
    let addLink: (String, String) -> Void

    func body(content: Content) -> some View {
        if enabled, node.kind == .note {
            content.dropDestination(
                for: String.self,
                action: { materialIDs, _ in
                    guard let materialID = materialIDs.first else { return false }
                    addLink(materialID, node.itemID)
                    return true
                },
                isTargeted: { targeted in
                    dropTargetNoteID = targeted ? node.itemID : nil
                }
            )
        } else {
            content
        }
    }
}
