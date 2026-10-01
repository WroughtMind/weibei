import AppKit
import WebKit
import WeiBeiCore

private struct WhiteboardMeasuredAdapter: NativeLLMAdapter {
    let base: any NativeLLMAdapter
    let record: @Sendable (Int) -> Void
    var family: String { base.family }
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        if let data = try? JSONSerialization.data(withJSONObject: OpenAIResponsesProvider.payload(for: request), options: [.sortedKeys]) { record(data.count) }
        return base.stream(request)
    }
}

/// Real bundled WebKit runtime. Model timing runs only through its explicit button; never uses the shared clipboard.
final class WhiteboardHarness: NSObject, WKScriptMessageHandler {
    private var ready = false
    private var failure: String?
    private let web: WKWebView
    private var window: NSWindow?
    private var liveButton: NSButton?
    private var liveStart: Date?, firstVisible = false
    private var liveActions: [WhiteboardAction] = [], liveGate = WhiteboardActionGate()
    private var liveSession: WhiteboardSession?, generationFinished = false
    private var requestBytes: [Int: Int] = [:], pageGaps: [Double] = [], synchronization: [Double] = []
    private var firstSeconds: Double?, pageEnded: Double?, speechEnds: [String: Double] = [:], boardEnds: [String: Double] = [:]
    private var liveFailure: String?
    override init() {
        let config = WKWebViewConfiguration()
        let resources = URL(fileURLWithPath: Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String ?? FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/WeiBei/Resources/Editor")
        config.userContentController.addScriptMessageHandler(WhiteboardVoiceResources(directory: resources), contentWorld: .page, name: "voiceResource")
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(.init(source: "window.wbMessages = []; window.addEventListener('error', e => window.webkit.messageHandlers.whiteboard.postMessage({type:'harness_error',message:e.message}));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 760), configuration: config)
        super.init(); config.userContentController.add(self, name: "whiteboard")
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any] else { return }
        if let start = liveStart {
            let eventTime = value["at"] as? Double ?? 0
            if value["type"] as? String == "board_revealed" {
                if !firstVisible {
                    firstVisible = true; firstSeconds = Date().timeIntervalSince(start)
                    window?.title = String(format: "首笔 %.2f 秒 · 正在验收整堂课", firstSeconds!)
                }
                if let pageEnded { pageGaps.append(eventTime - pageEnded); self.pageEnded = nil }
            }
            if let id = value["step_id"] as? String {
                if value["type"] as? String == "speech_finished" { speechEnds[id] = eventTime }
                if value["type"] as? String == "board_finished" { boardEnds[id] = eventTime }
            }
            if value["type"] as? String == "question", let action = value["action"] as? [String: Any], let id = action["step_id"] as? String {
                Task { @MainActor in
                    do { _ = try await web.callAsyncJavaScript("window.WeiBeiWhiteboard.questionDisplayed(id)", arguments: ["id": id], in: nil, contentWorld: .page) }
                    catch { liveFailure = error.localizedDescription; writeLiveEvidence() }
                }
            }
            if value["type"] as? String == "action_step_complete", let id = value["step_id"] as? String,
               let raw = value["ticket"] as? String, let ticket = UUID(uuidString: raw), liveGate.acknowledge(stepID: id, ticket: ticket, success: true) {
                if let action = liveActions.first(where: { $0.stepID == id }) {
                    if action.type == .keypointComplete { pageEnded = eventTime }
                    if action.type == .group, let speech = action.leaves.first(where: { $0.type == .speak }), let ended = speechEnds[speech.stepID],
                       let board = action.leaves.compactMap({ boardEnds[$0.stepID] }).max() { synchronization.append(board - ended) }
                }
                dispatchLive()
            }
            if value["type"] as? String == "action_step_failed" { liveFailure = String(describing: value["message"] ?? ""); window?.title = "课堂验收失败：" + liveFailure! }
            writeLiveEvidence()
        }
        if value["type"] as? String == "ready" {
            ready = true; print("whiteboard runtime ready"); fflush(stdout)
            if window != nil { web.evaluateJavaScript(Self.check) }
        }
        if let folder = Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String,
           let data = try? JSONSerialization.data(withJSONObject: value) {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("dist-whiteboard-check/latest-event.json")
            try? data.write(to: url)
        }
        if value["type"] as? String == "harness_result" {
            let status = value["status"] as? String ?? "missing result"
            window?.title = "魏碑白板验收 · " + status
            liveButton?.isEnabled = status == "passed"
            if let folder = Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String {
                try? Data(status.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("dist-whiteboard-check/result.txt"))
            }
        }
        if value["type"] as? String == "harness_error" { failure = String(describing: value["message"]) }
        if let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) {
            web.evaluateJavaScript("window.wbMessages.push(\(json)); void 0")
        }
    }
    @objc private func light() { web.evaluateJavaScript("window.WeiBeiWhiteboard.setAppearance(false)") }
    @objc private func dark() { web.evaluateJavaScript("window.WeiBeiWhiteboard.setAppearance(true)") }
    @objc private func live() {
        guard liveStart == nil else { return }
        liveActions = []; liveGate = .init(); firstVisible = false
        Task { @MainActor in
            do {
                _ = try await web.callAsyncJavaScript("return await window.WeiBeiWhiteboard.restore([],null,'live')", arguments: [:], in: nil, contentWorld: .page)
                liveStart = Date(); window?.title = "真实模型 · 等待第一笔"
                let model = NativeProviderRouting.route(.openaiCodex).defaultModel
                let adapter = try await NativeLLMAdapterFactory.make(provider: .openaiCodex, model: model,
                    endpoint: AgentProviderEndpoint(provider: .openaiCodex, baseURL: ""))
                let source = WhiteboardSource(itemID: "timing-fixture", title: "计量经济学",
                    pages: [.init(number: 12, text: "最小二乘法使残差平方和最小。残差等于观测值减去预测值；平方避免正负抵消，且更重地惩罚较大误差。")])
                var session = WhiteboardSession(source: source, goal: "恰好安排五个关键点：残差定义、正负抵消、平方的作用、大误差惩罚、选择拟合直线。每个关键点主要用一卡一组短讲解，包含公式和一张关系图，最后出一道选择题。", lesson: .init(title: "残差"))
                if let outline = try await WhiteboardTeacher.plan(adapter: adapter, model: model, session: session) {
                    session.lesson.title = outline.title ?? session.lesson.title
                    session.lesson.actions.append(outline); liveActions.append(outline)
                }
                for page in 1...session.keyPoints.count {
                    let measured = WhiteboardMeasuredAdapter(base: adapter) { bytes in
                        Task { @MainActor in self.requestBytes[page] = bytes; self.writeLiveEvidence() }
                    }
                    let part = try await WhiteboardTeacher.teach(adapter: measured, model: model, session: session, index: page - 1) { action in
                        await MainActor.run { self.liveActions.append(action); self.dispatchLive() }
                    }
                    session.lesson.actions += part.actions; liveSession = session
                    if let folder = Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String {
                        try WhiteboardSessionStore(directory: URL(fileURLWithPath: folder).appendingPathComponent("dist-whiteboard-check/live-lesson")).save(session)
                    }
                    if page >= session.keyPoints.count { break }
                }
                generationFinished = true; liveSession?.generationComplete = true; dispatchLive(); writeLiveEvidence()
            } catch { liveFailure = error.localizedDescription; window?.title = "课堂验收失败：" + error.localizedDescription; writeLiveEvidence() }
        }
    }
    private func dispatchLive() {
        guard liveFailure == nil else { return }
        guard let (action, ticket) = liveGate.dispatch(liveActions) else {
            if liveGate.pendingID == nil {
                web.evaluateJavaScript("window.WeiBeiWhiteboard.generationWaiting(\(!generationFinished))")
                if generationFinished { writeLiveEvidence() }
            }
            return
        }
        web.evaluateJavaScript("window.WeiBeiWhiteboard.generationWaiting(false)")
        do {
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(action))
            Task { @MainActor in
                do { _ = try await web.callAsyncJavaScript("return await window.WeiBeiWhiteboard.receive(envelope)", arguments: ["envelope": ["action": value, "ticket": ticket.uuidString, "audio": [:], "voice": "animalese", "speed": 1]], in: nil, contentWorld: .page) }
                catch { liveFailure = error.localizedDescription; window?.title = "课堂验收失败：" + error.localizedDescription; writeLiveEvidence() }
            }
        } catch { liveFailure = error.localizedDescription; window?.title = "课堂验收失败：" + error.localizedDescription; writeLiveEvidence() }
    }
    private func writeLiveEvidence() {
        guard let folder = Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String, let liveStart else { return }
        let finished = generationFinished && liveGate.cursor == liveActions.count
        let groups = liveActions.filter { $0.type == .group && $0.leaves.contains(where: { $0.type == .board || $0.type == .graph }) }.count
        let passed = finished && liveFailure == nil && (liveSession?.generatedKeyPoints.count ?? 0) >= 3 && (firstSeconds ?? 999) <= 15
            && pageGaps.count >= 2 && pageGaps.allSatisfy { $0 <= 10 } && synchronization.count == groups
            && synchronization.allSatisfy { (0...3).contains($0) }
        let report: [String: Any] = ["finished": finished, "passed": passed, "first_visible_seconds": firstSeconds as Any? ?? NSNull(),
            "pages": liveSession?.generatedKeyPoints.count ?? 0, "requests_bytes": Dictionary(uniqueKeysWithValues: requestBytes.map { (String($0.key), $0.value) }),
            "page_gap_seconds": pageGaps, "board_after_speech_seconds": synchronization, "groups": groups,
            "elapsed_seconds": Date().timeIntervalSince(liveStart), "action_types": liveActions.map(\.type.rawValue),
            "failure": liveFailure as Any? ?? NSNull()]
        let root = URL(fileURLWithPath: folder).appendingPathComponent("dist-whiteboard-check")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: root.appendingPathComponent("live-result.json")) }
        if finished {
            window?.title = "五页真实课堂 · " + (passed ? "通过" : "未达标")
            if var session = liveSession { session.cursor = liveGate.cursor; try? WhiteboardSessionStore(directory: root.appendingPathComponent("live-lesson")).save(session) }
        }
    }
    private func wait(_ condition: () -> Bool) {
        let end = Date().addingTimeInterval(45)
        while !condition() && failure == nil && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        if !condition(), failure == nil {
            web.evaluateJavaScript("JSON.stringify({stage:window.wbStage,messages:window.wbMessages,result:window.wbResult,visibility:document.visibilityState})") { value, _ in
                print("whiteboard timeout details: \(String(describing: value))"); fflush(stdout)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        expect(failure == nil && condition(), "Whiteboard renderer: \(failure ?? "timed out")")
    }
    @discardableResult private func js(_ code: String) -> Any? {
        var done = false, value: Any?
        web.evaluateJavaScript(code) { result, error in
            value = result; done = true
            if let error { self.failure = String(describing: error) }
        }
        wait { done }; return value
    }
    func run() {
        if CommandLine.arguments.contains("--whiteboard-window") || Bundle.main.bundleIdentifier == "com.changfenhuang.weibei.whiteboardcheck" {
            NSApplication.shared.setActivationPolicy(.accessory); NSApplication.shared.finishLaunching()
            let value = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            let liveButton = NSButton(title: "五页真实课堂验收", target: self, action: #selector(live))
            liveButton.isEnabled = false; self.liveButton = liveButton
            let controls = NSStackView(views: [NSButton(title: "浅色板面", target: self, action: #selector(light)),
                NSButton(title: "深色板面", target: self, action: #selector(dark)), liveButton])
            controls.heightAnchor.constraint(equalToConstant: 34).isActive = true
            let content = NSStackView(views: [controls, web]); content.orientation = .vertical; content.spacing = 0
            web.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            value.title = "魏碑白板 · 渲染验收"; value.contentView = content; value.orderFront(nil); window = value
        }
        let resources = URL(fileURLWithPath: Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String ?? FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/WeiBei/Resources/Editor")
        web.loadFileURL(resources.appendingPathComponent("whiteboard.html"), allowingReadAccessTo: resources)
        if window != nil { return }
        wait { ready }
        print("whiteboard checks starting"); fflush(stdout)
        js(Self.check)
        wait { js("window.wbResult !== undefined") as? Bool == true }
        expect(js("window.wbResult") as? String == "passed", "Whiteboard checks: \(String(describing: js("window.wbResult")))")
        print("Whiteboard WebKit passed: real math and Mermaid, speech reveal gate, atomic ACK, pause, annotations, timeout failure, reflow, state reconstruction")
        if let folder = Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String {
            try? Data("passed".utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("dist-whiteboard-check/result.txt"))
        }
        web.configuration.userContentController.removeAllScriptMessageHandlers(); web.stopLoading()
    }
    private static let check = #"""
    window.wbResult = undefined;
    (async () => {
      const api=window.WeiBeiWhiteboard;
      const assert=(v,m)=>{if(!v)throw new Error(m);};
      assert((await document.fonts.load('19px Virgil','ABC 123')).length>0,'Bundled Virgil must load');
      const wait=async test=>{const end=performance.now()+12000;while(!test()){if(performance.now()>end)throw new Error('condition timed out');await new Promise(requestAnimationFrame);}};
      const messages=(type,id)=>window.wbMessages.filter(m=>m.type===type&&(!id||m.step_id===id));
      const page={type:'new_page',step_id:'p1',page_id:'page-a',title:'残差与平方和'};
      const board={type:'board',step_id:'b1',board_uid:0,title:'为什么要平方',card_type:'formula',source_page:12,
        board_content:'**观测值**与预测值之差是残差。\n\n$$e_i=y_i-\\hat{y}_i$$\n\n平方避免正负抵消。'};
      const speak={type:'speak',step_id:'s1',spoken_text:'观察误差。'};
      const extra=[{title:'先看一个例子',card_type:'example',board_content:'观测值是 8，预测值是 6。残差为 +2；反过来，残差为 −2。'},
        {title:'记住这一点',card_type:'summary',board_content:'直接相加会抵消；平方后都是 4。误差越大，平方的惩罚越重。'}]
        .map((content,i)=>({...board,...content,step_id:'extra'+(i+1),board_uid:11+i}));
      const group={type:'group',step_id:'group1',actions:[board,...extra,speak]};
      const dispatch=(action,ticket=action.step_id)=>api.receive({action,ticket,audio:{}});
      window.wbStage='restore start';await api.restore([],null,'start');window.wbStage='page';await dispatch(page);window.wbStage='group';
      const playing=dispatch(group);
      await wait(()=>window.wbMessages.some(m=>m.type==='speech_request'&&m.action.step_id==='s1'));
      const card=document.querySelector('[data-board="0"]');
      assert(card&&getComputedStyle(card).opacity==='0','Card must remain hidden until speech actually starts');
      assert(!messages('action_step_complete','group1').length,'Group must not acknowledge prepared cards');
      window.wbStage='reveal';const before=card.getBoundingClientRect().height;
      api.speechStarted('s1');await wait(()=>card.querySelector('.reveal-char'));
      api.pause(true);api.speechFinished('s1');
      assert(!messages('action_step_complete','group1').length,'Speech end cannot complete unfinished animation');
      assert(Math.abs(card.getBoundingClientRect().height-before)<1,'Reveal spans must not change layout');
      api.pause(false);await wait(()=>getComputedStyle(document.querySelector('[data-board=\"11\"]')).opacity==='1');assert(getComputedStyle(document.querySelector('[data-board=\"12\"]')).opacity==='0','Third card waits for the second');await playing;await wait(()=>messages('action_step_complete','group1').length===1);
      assert(getComputedStyle(card).backgroundColor==='rgba(0, 0, 0, 0)'&&getComputedStyle(card).borderTopWidth==='0px'&&getComputedStyle(card).boxShadow==='none','Card is an invisible layout container');
      assert(!card.querySelector('.reveal-char'),'Completed reveal must restore plain text');
      assert(card.querySelector('.katex'),'Bundled KaTeX must render formula');
      const boardViewport=document.getElementById('viewport'),webiToggle=document.querySelector('#webi-host button');
      const boardBounds=boardViewport.getBoundingClientRect(),cardX=card.getBoundingClientRect().x;
      assert(boardBounds.left===0&&boardBounds.right===innerWidth,'Webi cannot reserve a full-height empty column');
      webiToggle.click();await new Promise(requestAnimationFrame);
      assert(boardViewport.getBoundingClientRect().width===boardBounds.width&&card.getBoundingClientRect().x===cardX,'Collapsing Webi cannot move the board');
      webiToggle.click();await new Promise(requestAnimationFrame);
      const petBounds=document.querySelector('#webi-host canvas').getBoundingClientRect();
      assert(boardViewport.contains(document.elementFromPoint(petBounds.left+10,petBounds.top+10)),'Webi artwork must let board gestures through');
      await dispatch({type:'highlight',step_id:'h1',target_board_id:0,snippet:'观测值与预测值',color:'red'});
      assert(card.querySelector('.highlight'),'Annotation must match text across Markdown nodes');
      window.wbStage='graph';const graph={type:'graph',step_id:'g1',board_uid:1,title:'因果关系',card_type:'diagram',source_page:12,mermaid:'flowchart LR\nA[观测值] --> B[残差]'};
      await dispatch(graph);const diagram=document.querySelector('[data-board="1"] svg');assert(diagram,'Actual Mermaid SVG must render');
      assert(diagram.textContent.includes('观测值')&&diagram.textContent.includes('残差'),'Sanitized Mermaid must retain visible node labels');
      window.wbStage='ask';let answered=false;
      const asking=dispatch({type:'ask',step_id:'q1',mode:'open',question:'为什么平方？'}).then(()=>answered=true);
      await wait(()=>window.wbMessages.some(m=>m.type==='question'));
      assert(!answered&&!messages('action_step_complete','q1').length,'Wait for the question view to render');
      api.questionDisplayed('q1');await asking;assert(answered,'Question ACK is independent of any answer');
      const began=performance.now();await api.receive({action:{...speak,step_id:'silent'},ticket:'silent',audio:{},silent:true});assert(performance.now()-began>300,'Silent narration visibly reveals text rather than instantly completing');
      window.wbStage='restore completed';await api.restore([page,group,graph],null,'restore');
      assert(document.querySelectorAll('.card').length===4,'Restoration must rebuild completed content exactly once');
      assert(document.querySelectorAll('audio').length===1,'Only one cloud audio player');
      const stalled={type:'group',step_id:'stalled',actions:[{...board,step_id:'b2',board_uid:2},{...speak,step_id:'s2'}]};
      window.wbStage='timeout';await dispatch(stalled);
      await wait(()=>messages('action_step_failed','stalled').length===1);
      assert(!messages('action_step_complete','stalled').length,'Reveal timeout must never count as successful completion');
      assert(getComputedStyle(document.querySelector('[data-board="2"]')).opacity==='0','Timeout must not force open reveal gate');
      const many=Array.from({length:14},(_,i)=>({...board,step_id:'card'+i,board_uid:i,board_content:'卡片内容\n\n'+('一段讲解。'.repeat(70))}));
      window.wbStage='layout';await api.restore([page,...many],null,'layout');
      await wait(()=>messages('sync_whiteboard_state').at(-1)?.whiteboard_state.pages.flatMap(p=>p.overlayItems).length===14);
      const state=messages('sync_whiteboard_state').at(-1).whiteboard_state;
      assert(state.version===1&&state.revision>0&&state.pages.flatMap(p=>p.overlayItems).length===14,'State must include pages, cards, measured geometry and revision');
      const small=[0,1].map(i=>({...board,step_id:'small'+i,board_uid:i,board_content:'一段讲解。'.repeat(14)}));
      await api.restore([page,...small],null,'resize');
      const next=document.querySelector('[data-board="1"]'),oldY=parseFloat(next.style.top);
      assert(oldY>66,'Resize fixture must share a column');
      document.querySelector('[data-board="0"] .content').textContent='缩短';
      await wait(()=>parseFloat(next.style.top)<oldY);
      await api.setAppearance(true);assert(document.documentElement.dataset.theme==='dark','Native dark theme applied');await api.setAppearance(false);
      window.wbStage='Chinese audio';await api.restore([page],null,'voice');
      const audio=document.querySelector('audio');
      const voiceGroup={type:'group',step_id:'voice-group',actions:[{...board,step_id:'voice-board',board_uid:30},{...speak,step_id:'voice-speak',spoken_text:'重庆银行比较残差。平方以后，正数和负数就不会抵消。'}]};
      const audible=api.receive({action:voiceGroup,ticket:'voice-ticket',audio:{},voice:'animalese',speed:1});
      await wait(()=>audio.currentTime>.15);
      assert(document.querySelector('[data-board="30"] .reveal-char'),'Voice must finish before the final writing unit');
      const oldEnded=audio.onended;
      assert(getComputedStyle(document.querySelector('[data-board="30"]')).opacity==='1','Actual playing event reveals the board');
      const pausedEvent=new Promise(resolve=>audio.addEventListener('pause',resolve,{once:true}));
      api.pause(true);await pausedEvent;const time=audio.currentTime;
      await new Promise(resolve=>setTimeout(resolve,300));
      // WebKit may correct its estimated clock backwards after the hardware stops.
      assert(audio.paused&&audio.currentTime<=time+.06,'Paused audio must not continue forward: '+time+' -> '+audio.currentTime);
      const settledTime=audio.currentTime;
      await new Promise(resolve=>setTimeout(resolve,300));
      assert(audio.paused&&Math.abs(audio.currentTime-settledTime)<.01,'Paused media clock must remain stopped: '+settledTime+' -> '+audio.currentTime);
      assert(document.querySelector('.webi-companion').dataset.mouth==='0','Paused Webi closes its mouth');
      api.pause(false);await wait(()=>audio.currentTime>time+.15);
      await api.restore([page],null,'cancel-audio');await audible;
      assert(!messages('action_step_complete','voice-group').length,'Cancellation never acknowledges an unfinished action');
      let endedAt=0;audio.addEventListener('ended',()=>endedAt=performance.now(),{once:true});
      const replay=api.receive({action:voiceGroup,ticket:'new-ticket',audio:{},voice:'animalese',speed:1.5});
      await wait(()=>audio.currentTime>.1);oldEnded?.call(audio,new Event('ended'));
      assert(!messages('action_step_complete','voice-group').length,'An old ended callback cannot finish a replay');
      assert(audio.playbackRate===1.5&&audio.preservesPitch,'Rate changes preserve pitch');
      await replay;await wait(()=>messages('action_step_complete','voice-group').length===1);
      assert(audio.ended,'A completed replay waits for the actual ended event');
      assert(endedAt>0&&performance.now()-endedAt<3000,'The final board finishes within three seconds of speech');
      assert(messages('action_step_complete','voice-group')[0].ticket==='new-ticket','Only the current playback ticket completes');
      await api.restore([page,group,graph,{type:'circle',step_id:'visual-circle',target_board_id:0,snippet:'残差',color:'red'}],null,'visual');
      window.wbStage='zoom and ink';
      const viewport=document.getElementById('viewport'),canvas=document.getElementById('canvas');
      const originalCard=document.querySelector('[data-board="0"]');
      const logicalX=parseFloat(originalCard.style.left),logicalWidth=originalCard.offsetWidth;
      const zoom=()=>Number(getComputedStyle(canvas).transform.match(/matrix\(([^,]+)/)?.[1] ?? 1);
      api.canvasCommand('zoom_out');api.canvasCommand('zoom_out');assert(zoom()===.5,'Zoom reaches 0.5');
      await dispatch({type:'highlight',step_id:'zoom-highlight',target_board_id:0,rect:{x:.1,y:.2,w:.4,h:.2},color:'red'});
      for(let i=0;i<6;i++)api.canvasCommand('zoom_in');assert(zoom()===2,'Zoom reaches 2');
      assert(originalCard.offsetWidth===logicalWidth&&parseFloat(originalCard.style.left)===logicalX,'Zoom cannot reflow cards away from handwriting');
      await dispatch({type:'circle',step_id:'zoom-circle',target_board_id:0,rect:{x:.1,y:.2,w:.4,h:.2},color:'red'});
      const mark=originalCard.querySelector('[data-step="zoom-circle"]'),markRect=mark.getBoundingClientRect(),cardRect=originalCard.getBoundingClientRect();
      assert(Math.abs(markRect.x-cardRect.x-(logicalWidth*.1-6)*2)<1,'Annotations use unscaled local coordinates');
      api.canvasCommand('zoom_out');api.canvasCommand('zoom_out');assert(zoom()===1.5,'Ink fixture uses 1.5');
      api.canvasCommand('toggle_ink');viewport.scrollTo(0,0);
      // Synthetic pointers exercise the production handlers; actual pointer capture is checked in the visible window.
      const capture=viewport.setPointerCapture.bind(viewport),release=viewport.releasePointerCapture.bind(viewport);
      viewport.setPointerCapture=()=>{};viewport.releasePointerCapture=()=>{};
      const origin=viewport.getBoundingClientRect();
      for(let i=0;i<3;i++){
        const x=origin.x+75+i*60,y=origin.y+540;
        viewport.dispatchEvent(new PointerEvent('pointerdown',{pointerId:i+1,isPrimary:true,button:0,clientX:x,clientY:y,bubbles:true}));
        viewport.dispatchEvent(new PointerEvent('pointermove',{pointerId:i+1,isPrimary:true,clientX:x+30,clientY:y+30,bubbles:true}));
        viewport.dispatchEvent(new PointerEvent('pointerup',{pointerId:i+1,isPrimary:true,clientX:x+30,clientY:y+30,bubbles:true}));
      }
      viewport.setPointerCapture=capture;viewport.releasePointerCapture=release;
      await wait(()=>messages('sync_whiteboard_state').at(-1)?.whiteboard_state.pages[0].strokes.length===3);
      const inkState=messages('sync_whiteboard_state').at(-1).whiteboard_state;
      assert(inkState.zoom===1.5&&inkState.pages[0].strokes[0].points[0].x===50&&inkState.pages[0].strokes[0].points[0].y===360,'Ink coordinates divide by the same zoom');
      const scrollBefore=viewport.scrollLeft;
      await dispatch({...page,step_id:'ink-next',page_id:'ink-next'});
      await new Promise(resolve=>setTimeout(resolve,550));
      assert(viewport.scrollLeft===scrollBefore,'Handwriting disables the automatic camera');
      await api.restore([page,group,graph],inkState,'restore-ink');
      assert(zoom()===1.5&&document.querySelectorAll('.ink-layer path').length===3,'Three strokes and zoom survive restoration');
      await api.restore([page,group,graph,{type:'circle',step_id:'restored-circle',target_board_id:0,snippet:'残差',color:'red'}],
        {...inkState,scrollX:200,scrollY:140},'restore-camera');
      await new Promise(resolve=>setTimeout(resolve,550));
      assert(Math.abs(viewport.scrollLeft-200)<1&&Math.abs(viewport.scrollTop-140)<1,'Restoring annotations must not move the saved camera');
      api.canvasCommand('undo');assert(document.querySelectorAll('.ink-layer path').length===2,'Undo removes the last stroke');
      api.canvasCommand('clear_page');assert(document.querySelectorAll('.ink-layer path').length===0,'Clear removes only this page ink');
      await api.restore([page,group,graph],inkState,'ink-visual');
      window.wbResult='passed';window.webkit.messageHandlers.whiteboard.postMessage({type:'harness_result',status:'passed'});
    })().catch(error=>{window.wbResult=String(error);window.webkit.messageHandlers.whiteboard.postMessage({type:'harness_result',status:String(error)});}); void 0;
    """#
}
