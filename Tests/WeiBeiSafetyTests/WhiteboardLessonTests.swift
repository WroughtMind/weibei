import XCTest
@testable import WeiBei
@testable import WeiBeiCore

final class WhiteboardLessonTests: XCTestCase {
    private let source = WhiteboardSource(itemID: "material-a", title: "计量经济学",
        pages: [.init(number: 12, text: "最小二乘法使残差平方和最小。残差等于观测值减去预测值；平方避免正负抵消，且更重地惩罚较大误差。")])
    private let stream = #"""
    {"type":"new_page","step_id":"p1","title":"理解残差","page_id":"page-a"}
    {"type":"group","step_id":"group1","actions":[{"type":"board","step_id":"b1","board_uid":0,"card_type":"formula","title":"残差","board_content":"残差是观测值与预测值之差：$e_i=y_i-\\hat y_i$。","source_page":12},{"type":"speak","step_id":"s1","spoken_text":"先看观测值与预测值之差。"}]}
    {"type":"highlight","step_id":"h1","target_board_id":0,"snippet":"观测值","color":"red"}
    {"type":"ask","step_id":"q1","mode":"choice","question":"为什么平方？","options":["避免正负抵消","没有原因"],"correct_index":0,"explanation":"正负误差直接相加会抵消。"}
    """#
    private func lesson() throws -> WhiteboardLesson {
        var parser = WhiteboardActionDecoder()
        let lesson = WhiteboardLesson(title: "理解残差", actions: try parser.append(stream, final: true))
        try lesson.validate(source: source); return lesson
    }

    func testIncrementalProtocolAndAtomicAcknowledgementGate() throws {
        var parser = WhiteboardActionDecoder(), actions: [WhiteboardAction] = []
        for character in stream { actions += try parser.append(String(character)) }
        actions += try parser.append("", final: true)
        XCTAssertEqual(actions, try lesson().actions)
        var gate = WhiteboardActionGate()
        let first = try XCTUnwrap(gate.dispatch(actions))
        XCTAssertNil(gate.dispatch(actions), "One action remains in flight until ACK")
        XCTAssertFalse(gate.acknowledge(stepID: first.0.stepID, ticket: first.1, success: false))
        XCTAssertFalse(gate.acknowledge(stepID: "other", ticket: first.1, success: true))
        XCTAssertFalse(gate.acknowledge(stepID: first.0.stepID, ticket: UUID(), success: true))
        XCTAssertTrue(gate.acknowledge(stepID: first.0.stepID, ticket: first.1, success: true))
        XCTAssertFalse(gate.acknowledge(stepID: first.0.stepID, ticket: first.1, success: true))
        let group = try XCTUnwrap(gate.dispatch(actions))
        XCTAssertFalse(gate.acknowledge(stepID: "b1", ticket: group.1, success: true), "Child completion cannot advance a group")
        gate.retry()
        let retry = try XCTUnwrap(gate.dispatch(actions))
        XCTAssertEqual(retry.0.stepID, group.0.stepID)
        XCTAssertFalse(gate.acknowledge(stepID: group.0.stepID, ticket: group.1, success: true))
        XCTAssertTrue(gate.acknowledge(stepID: retry.0.stepID, ticket: retry.1, success: true))
        XCTAssertEqual(gate.cursor, 2)
    }

    func testInvalidModelOutputStopsInsteadOfInventingContent() throws {
        var parser = WhiteboardActionDecoder()
        XCTAssertThrowsError(try parser.append("```json\n"))
        parser = .init(); _ = try parser.append("{\"type\":\"board\"")
        XCTAssertThrowsError(try parser.append("", final: true))
        var value = try lesson()
        value.actions[1].actions![0].sourcePage = 99
        XCTAssertThrowsError(try value.validate(source: source))
        value = try lesson(); value.actions[2].targetBoardID = 999
        XCTAssertThrowsError(try value.validate(source: source))
        value = try lesson(); value.actions[2].rect = .init(x: 0.9, y: 0, w: 0.5, h: 1)
        XCTAssertThrowsError(try value.validate(source: source))
        value = try lesson(); value.actions[3].stepID = "b1"
        XCTAssertThrowsError(try value.validate(source: source))
        value = try lesson(); value.actions[3].correctIndex = 8
        XCTAssertThrowsError(try value.validate(source: source))
    }

    func testPersistenceRetainsStepAndContentAndNeverOverwritesOnInvalidSave() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WhiteboardSessionStore(directory: folder)
        var value = WhiteboardSession(source: source, goal: "讲解", lesson: try lesson())
        value.cursor = 2; value.generationComplete = true; value.answers["q1"] = "避免正负抵消"
        let state = #"{"version":1,"revision":42,"activePageId":"page-a","pages":[{"id":"page-a","title":"理解残差","overlayItems":[{"id":"b1","kind":"note_card","x":20,"y":66,"w":320,"h":160,"columnIndex":0,"boardUid":0,"keypoint":{"title":"残差","content":"公式","type":"formula"},"decorations":[]}],"columnLayout":{"columns":[{"w":320,"nextY":246}],"activeIndex":0,"lp":{"tileW":320}}}]}"#
        value.canvas = try JSONDecoder().decode(WhiteboardCanvasState.self, from: Data(state.utf8))
        try store.save(value)
        XCTAssertEqual(try store.load(value.id), value)
        XCTAssertEqual(try store.list(itemID: "other-material"), [])
        XCTAssertTrue(value.markdown().contains("避免正负抵消"))
        let original = try Data(contentsOf: store.url(value.id))
        value.cursor = 99
        XCTAssertThrowsError(try store.save(value))
        XCTAssertEqual(try Data(contentsOf: store.url(value.id)), original)
        try Data("damaged".utf8).write(to: store.url(value.id))
        XCTAssertThrowsError(try store.list(itemID: source.itemID))
        XCTAssertEqual(try String(contentsOf: store.url(value.id)), "damaged")
    }

    func testMediaCredentialsAreBoundToEachServiceEndpoint() throws {
        var a = WhiteboardMediaSettings.Channel(); a.baseURL = "https://one.example/v1"; a.model = "tts"
        var b = a; b.baseURL = "https://two.example/v1"
        XCTAssertNotEqual(try a.credentialID(kind: "speech"), try b.credentialID(kind: "speech"))
        b.baseURL = "http://public.example/v1"
        XCTAssertThrowsError(try b.credentialID(kind: "speech"))
    }

    @MainActor
    func testWrongChoicePausesCorrectsOnceAndResumesWithoutCompletingPendingStep() async throws {
        let capture = WhiteboardRequestCapture(), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let classroom = WhiteboardClassroom(directory: folder, provider: .custom, baseURL: "http://localhost:1/v1", model: "fixture",
            adapter: WhiteboardTestAdapter(text: #"{"type":"speak","step_id":"correction","spoken_text":"正负残差相加会抵消，平方后都非负，才能保留偏差大小。"}"#, finish: .stop, capture: capture))
        var value = WhiteboardSession(source: source, goal: "讲解", lesson: try lesson())
        value.cursor = 3; value.generationComplete = true; value.presentedQuestionIDs = ["q1"]
        classroom.session = value
        let action = value.lesson.actions[3]
        var pauses: [Bool] = []
        let resumed = expectation(description: "Correction resumes the paused action")
        classroom.attachRenderer { method, args in
            if method == "restore" { classroom.receive(["type":"restored", "request_id":args["requestID"]!]) }
            if method == "pause", let paused = args["value"] as? Bool {
                pauses.append(paused)
                if !paused && classroom.session?.discussions.last?.completed == true { resumed.fulfill() }
            }
        }
        classroom.play()
        classroom.answer("没有原因", to: action, correct: false)
        XCTAssertTrue(classroom.replying); XCTAssertFalse(classroom.playing)
        classroom.answer("没有原因", to: action, correct: false)
        await fulfillment(of: [resumed], timeout: 2)
        XCTAssertEqual(classroom.session?.discussions.count, 1)
        XCTAssertEqual(classroom.session?.cursor, 3, "A correction never acknowledges the lesson action")
        XCTAssertTrue(classroom.playing); XCTAssertTrue(pauses.contains(true))
        XCTAssertTrue(capture.request?.messages.last?.content.contains("正确答案：避免正负抵消") == true)
        let restored = try classroom.archive.load(value.id)
        var copy = restored
        XCTAssertNil(copy.recordAnswer("没有原因", to: action, correct: false), "Restoring cannot react twice")
        var correct = value
        XCTAssertNil(correct.recordAnswer("避免正负抵消", to: action, correct: true))
        var open = action; open.stepID = "open"; open.mode = .open; open.options = nil; open.correctIndex = nil
        correct.lesson.actions.append(open); correct.presentedQuestionIDs.append("open")
        XCTAssertNil(correct.recordAnswer("我的理解", to: open, correct: nil))
        XCTAssertTrue(correct.discussions.isEmpty)
        classroom.close()
    }

    func testCorrectionRejectsCardsAndLongLectures() async throws {
        let capture = WhiteboardRequestCapture(), session = WhiteboardSession(source: source, goal: "讲解", lesson: try lesson())
        let invalid = [
            #"{"type":"board","step_id":"new-card","board_uid":9,"card_type":"definition","title":"新课","board_content":"不应该展开","source_page":12}"#,
            "{\"type\":\"speak\",\"step_id\":\"too-long\",\"spoken_text\":\"\(String(repeating: "字", count: 81))\"}"
        ]
        for output in invalid {
            do {
                try await WhiteboardTeacher.reply(adapter: WhiteboardTestAdapter(text: output, finish: .stop, capture: capture),
                    model: "fixture", session: session, question: "答错了", correction: true, receive: { _ in XCTFail("Invalid correction must not reach the UI") })
                XCTFail("Correction must be short text only")
            } catch {}
        }
    }

    func testInkAndZoomPersistAndInvalidCoordinatesNeverOverwriteArchive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WhiteboardSessionStore(directory: folder)
        var value = WhiteboardSession(source: source, goal: "讲解", lesson: try lesson())
        let state = #"{"version":1,"revision":8,"zoom":1.5,"scrollX":120,"scrollY":90,"activePageId":"page-a","pages":[{"id":"page-a","title":"残差","overlayItems":[],"strokes":[{"id":"ink-1","points":[{"x":20,"y":80},{"x":80,"y":120}]},{"id":"ink-2","points":[{"x":30,"y":90}]},{"id":"ink-3","points":[{"x":40,"y":100}]}],"columnLayout":{"columns":[{"w":320,"nextY":66}],"activeIndex":0,"lp":{"tileW":320}}}]}"#
        value.canvas = try JSONDecoder().decode(WhiteboardCanvasState.self, from: Data(state.utf8))
        try store.save(value)
        XCTAssertEqual(try store.load(value.id), value)
        let before = try Data(contentsOf: store.url(value.id))
        value.canvas?.pages[0].strokes?[0].points[0].x = -.infinity
        XCTAssertThrowsError(try store.save(value))
        XCTAssertEqual(try Data(contentsOf: store.url(value.id)), before)
    }

    func testTeacherStreamsOnePageAndReplyUsesCurrentAnswers() async throws {
        let capture = WhiteboardRequestCapture()
        let pageStream = #"{"type":"session_ready","step_id":"outline","key_points":["残差","平方","比较"]}"# + "\n" + stream
            + "\n" + #"{"type":"keypoint_complete","step_id":"done","index":0}"#
        var value = WhiteboardSession(source: source, goal: "讲解", lesson: .init(title: "残差"))
        let reply = try await WhiteboardTeacher.generatePage(
            adapter: WhiteboardTestAdapter(text: pageStream, finish: .stop, capture: capture), model: "configured-model",
            source: source, goal: value.goal, page: 1, session: value, receive: { action in capture.actions.append(action) })
        XCTAssertEqual(capture.actions, reply.actions, "Do not append blockEnd after textDelta a second time")
        XCTAssertEqual(reply.actions.last?.index, 0)
        XCTAssertEqual(capture.request?.model, "configured-model")
        XCTAssertTrue(capture.request?.messages.last?.content.contains("material-a") == true)
        value.lesson = reply; value.answers["q1"] = "避免正负抵消"
        capture.actions = []
        try await WhiteboardTeacher.reply(adapter: WhiteboardTestAdapter(
            text: #"{"type":"speak","step_id":"reply1","spoken_text":"平方避免抵消。"}"#, finish: .stop, capture: capture),
            model: "m", session: value, question: "为什么平方？", receive: { capture.actions.append($0) })
        XCTAssertEqual(capture.actions.count, 1)
        XCTAssertTrue(capture.request?.messages.last?.content.contains("避免正负抵消") == true)
        XCTAssertFalse(capture.request?.messages.last?.content.contains("先看观测值与预测值之差。") == true, "History omits narration")
        XCTAssertFalse(capture.request?.messages.last?.content.contains("board_content") == true, "History omits board bodies")
        do {
            _ = try await WhiteboardTeacher.generatePage(
                adapter: WhiteboardTestAdapter(text: pageStream, finish: .length, capture: capture), model: "m",
                source: source, goal: "g", page: 1, session: .init(source: source, goal: "g", lesson: .init(title: "残差")), receive: { _ in })
            XCTFail("Truncated output must fail even if received lines contain valid JSON")
        } catch {}
    }

    func testPageMetadataIsNormalizedWithoutDroppingContentErrors() async throws {
        let outline = #"{"type":"session_ready","step_id":"outline","key_points":["残差","平方","比较"]}"#
        for output in [outline + "\n" + stream,
                       outline + "\n" + stream + "\n" + #"{"type":"keypoint_complete","step_id":"wrong-index","index":99}"#,
                       stream + "\n" + outline] {
            let capture = WhiteboardRequestCapture()
            let result = try await WhiteboardTeacher.generatePage(
                adapter: WhiteboardTestAdapter(text: output, finish: .stop, capture: capture), model: "m", source: source,
                goal: "讲解", page: 1, session: .init(source: source, goal: "讲解", lesson: .init(title: "残差")), receive: { capture.actions.append($0) })
            XCTAssertEqual(result.actions.filter { $0.type == .keypointComplete }.count, 1)
            XCTAssertEqual(result.actions.last?.index, 0)
            XCTAssertEqual(result.actions.flatMap(\.leaves).filter { $0.type == .board }.count, 1)
            XCTAssertEqual(WhiteboardSession(source: source, goal: "讲解", lesson: result).keyPoints.count, 3)
            try result.validate(source: source)
        }
        let capture = WhiteboardRequestCapture()
        do {
            _ = try await WhiteboardTeacher.generatePage(adapter: WhiteboardTestAdapter(
                text: outline + "\n" + stream.replacingOccurrences(of: #""source_page":12"#, with: #""source_page":99"#), finish: .stop, capture: capture),
                model: "m", source: source, goal: "讲解", page: 1, session: .init(source: source, goal: "讲解", lesson: .init(title: "残差")), receive: { _ in })
            XCTFail("Metadata normalization cannot weaken source boundaries")
        } catch {}
    }

    func testRequestHistoryIsBoundedAndUsesOnlyBoardIndexes() throws {
        var parser = WhiteboardActionDecoder()
        let outline = try XCTUnwrap(parser.append(#"{"type":"session_ready","step_id":"outline","key_points":["定义","正负","平方","惩罚","选择"]}"#, final: true).first)
        var session = WhiteboardSession(source: source, goal: "讲解", lesson: .init(title: "残差", actions: [outline]))
        let first = try WhiteboardTeacher.context(session)
        var second = ""
        for page in 1...4 {
            var pageAction = try lesson().actions[0]; pageAction.stepID = "p\(page)"; pageAction.pageID = "page\(page)"
            var board = try lesson().actions[1].actions![0]; board.stepID = "b\(page)"; board.boardUID = page
            board.markdown = String(repeating: "不要重传板书正文", count: 80)
            var speech = try lesson().actions[1].actions![1]; speech.stepID = "s\(page)"; speech.text = String(repeating: "不要重传讲稿", count: 80)
            session.lesson.actions += [pageAction, board, speech]; session.generatedPages = page
            if page == 1 { second = try WhiteboardTeacher.context(session) }
        }
        let fifth = try WhiteboardTeacher.context(session)
        XCTAssertFalse(fifth.contains("不要重传")); XCTAssertFalse(fifth.contains("board_content"))
        XCTAssertLessThanOrEqual(abs(fifth.utf8.count - second.utf8.count), 20)
        print("WHITEBOARD_CONTEXT_BYTES page1=\(first.utf8.count) page2=\(second.utf8.count) page5=\(fifth.utf8.count)")
    }

    @MainActor
    func testQuestionAcknowledgesReceiptWithoutMountingUIAndRestoresUnansweredFirst() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let classroom = WhiteboardClassroom(directory: folder, provider: .custom, baseURL: "http://localhost:1/v1", model: "fixture")
        var value = WhiteboardSession(source: source, goal: "讲解", lesson: try lesson())
        value.cursor = 3; value.generationComplete = true
        try classroom.archive.save(value); classroom.restore(value)
        let acknowledged = expectation(description: "Question acknowledged without a SwiftUI view")
        classroom.attachRenderer { method, args in
            if method == "restore" { classroom.receive(["type":"restored", "request_id":args["requestID"]!]) }
            if method == "receive", let envelope = args["envelope"] as? [String:Any] {
                classroom.receive(["type":"question", "action":envelope["action"]!, "ticket":envelope["ticket"]!])
            }
            if method == "questionDisplayed" { acknowledged.fulfill() }
        }
        classroom.play(); await fulfillment(of: [acknowledged], timeout: 2)
        XCTAssertTrue(classroom.session?.presentedQuestionIDs.contains("q1") == true)
        XCTAssertNil(classroom.session?.answers["q1"])
        classroom.close()
        var restored = try classroom.archive.load(value.id)
        var answered = try XCTUnwrap(restored.questions.first); answered.stepID = "answered"
        restored.lesson.actions.insert(answered, at: 3); restored.cursor = 4
        restored.presentedQuestionIDs.append("answered"); restored.answers["answered"] = "已作答"
        try classroom.archive.save(restored)
        XCTAssertEqual(try classroom.archive.load(value.id).questions.map(\.stepID), ["q1", "answered"])
    }

    @MainActor
    func testClassroomWaitsForMatchingAckAndRestoresUnfinishedAction() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let classroom = WhiteboardClassroom(directory: folder, provider: .custom, baseURL: "http://localhost:1/v1", model: "fixture")
        classroom.settings.voice = .silent
        var value = WhiteboardSession(source: source, goal: "讲解", lesson: try lesson()); value.generationComplete = true
        classroom.session = value
        var envelopes: [[String: Any]] = []
        let first = expectation(description: "First action"), second = expectation(description: "Second action")
        classroom.attachRenderer { method, args in
            if method == "restore" { classroom.receive(["type":"restored", "request_id":args["requestID"]!]) }
            if method == "receive", let env = args["envelope"] as? [String:Any] {
                envelopes.append(env)
                if envelopes.count == 1 { first.fulfill() }
                if envelopes.count == 2 { second.fulfill() }
            }
        }
        classroom.play()
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(envelopes.count, 1); XCTAssertEqual(classroom.session?.cursor, 0)
        let ticket = try XCTUnwrap(envelopes.first?["ticket"] as? String)
        classroom.receive(["type":"action_step_complete", "step_id":"wrong", "ticket":ticket])
        XCTAssertEqual(classroom.session?.cursor, 0)
        classroom.receive(["type":"action_step_complete", "step_id":"p1", "ticket":ticket])
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(classroom.session?.cursor, 1)
        classroom.receive(["type":"action_step_complete", "step_id":"p1", "ticket":ticket])
        XCTAssertEqual(classroom.session?.cursor, 1)
        let reader = ReadAloud.shared
        reader.start(id: "reading-fixture") { try await Task.sleep(for: .seconds(60)); return "残差" }
        XCTAssertFalse(classroom.playing, "Another reading source pauses the unfinished classroom action")
        XCTAssertEqual(classroom.session?.cursor, 1, "Switching speech focus must never acknowledge the unfinished group")
        XCTAssertEqual(reader.sourceID, "reading-fixture")
        classroom.play()
        XCTAssertNil(reader.sourceID, "Resuming the classroom cancels the previous reading source")
        XCTAssertEqual(classroom.session?.cursor, 1)
        classroom.close()
        let saved = try classroom.archive.load(value.id)
        XCTAssertEqual(saved.cursor, 1); XCTAssertEqual(saved.lesson, value.lesson)
    }

    func testLiveConfiguredModelProducesUsableLesson() async throws {
        guard ProcessInfo.processInfo.environment["WEIBEI_WHITEBOARD_LIVE"] == "1" else {
            throw XCTSkip("Explicit opt-in: uses the configured provider outside CI.")
        }
        let model = NativeProviderRouting.route(.openaiCodex).defaultModel
        let adapter = try await NativeLLMAdapterFactory.make(provider: .openaiCodex, model: model,
            endpoint: AgentProviderEndpoint(provider: .openaiCodex, baseURL: ""))
        let capture = WhiteboardRequestCapture(), start = Date()
        var value = WhiteboardSession(source: source, goal: "恰好三页、三个关键点：残差定义、平方避免抵消、大误差惩罚。用公式和一张 Mermaid 关系图，最后出一道选择题。", lesson: .init(title: "理解最小二乘法"))
        for page in 1...6 {
            capture.actions = []
            let part = try await WhiteboardTeacher.generatePage(adapter: adapter, model: model, source: source,
                goal: value.goal, page: page, session: value, receive: { action in
                    if capture.actions.isEmpty { print("FIRST_ACTION_SECONDS \(Date().timeIntervalSince(start))") }
                    if page == 1 && action.leaves.contains(where: { $0.type == .board || $0.type == .graph }) && !capture.actions.contains(where: { $0.leaves.contains(where: { $0.type == .board || $0.type == .graph }) }) {
                        print("FIRST_BOARD_RECEIVED_SECONDS \(Date().timeIntervalSince(start))")
                    }
                    capture.actions.append(action)
                })
            value.lesson.actions += part.actions; value.generatedPages = page
            value.lesson.title = value.lesson.actions.first?.title ?? "理解最小二乘法"
            if page >= value.keyPoints.count { value.generationComplete = true; break }
        }
        try value.lesson.validate(source: source)
        XCTAssertTrue(value.generationComplete)
        XCTAssertGreaterThanOrEqual(value.generatedPages, 2)
        let question = try XCTUnwrap(value.lesson.actions.compactMap(\.questionAction).last { $0.mode == .choice })
        let wrong = try XCTUnwrap(question.options?.enumerated().first { $0.offset != question.correctIndex }?.element)
        value.cursor = value.lesson.actions.count; value.presentedQuestionIDs.append(question.stepID)
        let correction = try XCTUnwrap(value.recordAnswer(wrong, to: question, correct: false))
        let correctionStart = Date()
        capture.actions = []
        try await WhiteboardTeacher.reply(adapter: adapter, model: model, session: value, question: correction.question, correction: true) {
            capture.actions.append($0)
            print("CORRECTION_VISIBLE_SECONDS \(Date().timeIntervalSince(correctionStart))")
        }
        let seconds = Date().timeIntervalSince(correctionStart)
        XCTAssertLessThanOrEqual(seconds, 8, "The targeted correction must arrive within eight seconds")
        XCTAssertEqual(capture.actions.count, 1)
        XCTAssertLessThanOrEqual(capture.actions.first?.text?.count ?? .max, 80)
        if let index = value.discussions.firstIndex(where: { $0.id == correction.id }) {
            value.discussions[index].text = capture.actions.first?.text ?? ""
            value.discussions[index].completed = true
        }
        if let path = ProcessInfo.processInfo.environment["WEIBEI_WHITEBOARD_EVIDENCE"] {
            try WhiteboardSessionStore(directory: URL(fileURLWithPath: path)).save(value)
            let report: [String: Any] = ["pages": value.generatedPages, "correction_seconds": seconds,
                "correction_text": capture.actions.first?.text ?? "", "scope": "model response; native window pending"]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path).appendingPathComponent("correction-timing.json"))
        }
    }

    @MainActor
    func testSystemSpeechUsesRealStartBoundaryAndCompletion() async throws {
        guard ProcessInfo.processInfo.environment["WEIBEI_SYSTEM_SPEECH_LIVE"] == "1" else {
            throw XCTSkip("Explicit opt-in: plays a short Chinese acceptance sentence using the installed system voice.")
        }
        let narrator = SystemNarrator.shared
        let started = expectation(description: "System voice starts"), finished = expectation(description: "System voice finishes")
        let text = "残差等于观测值减去预测值。"
        var ranges: [NSRange] = [], outcome: Error?
        narrator.speak(text, speed: 1, started: { started.fulfill() }, boundary: { ranges.append($0) }, completed: { error in
            outcome = error; finished.fulfill()
        })
        await fulfillment(of: [started, finished], timeout: 30, enforceOrder: true)
        XCTAssertNil(outcome); XCTAssertFalse(ranges.isEmpty)
        XCTAssertTrue(ranges.allSatisfy { $0.location >= 0 && NSMaxRange($0) <= (text as NSString).length })
        var wasCancelled = false
        narrator.speak("这句话随后会被取消。", speed: 1, started: {}, completed: { wasCancelled = $0 is CancellationError })
        narrator.stop(); XCTAssertTrue(wasCancelled)
    }
}

private final class WhiteboardRequestCapture: @unchecked Sendable {
    var request: NativeLLMRequest?
    var actions: [WhiteboardAction] = []
}
private struct WhiteboardTestAdapter: NativeLLMAdapter {
    let family = "test"
    let text: String
    let finish: NativeFinishReason
    let capture: WhiteboardRequestCapture
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        capture.request = request
        return AsyncThrowingStream { continuation in
            for character in text { continuation.yield(.textDelta(index: 0, text: String(character))) }
            continuation.yield(.blockEnd(index: 0, block: .text(text)))
            continuation.yield(.finish(reason: finish, replayState: nil)); continuation.finish()
        }
    }
}
