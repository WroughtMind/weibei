import AppKit
import WebKit
import WeiBeiCore

/// Real bundled WebKit runtime. Model timing runs only through its explicit button; never uses the shared clipboard.
final class WhiteboardHarness: NSObject, WKScriptMessageHandler {
    private var ready = false
    private var failure: String?
    private let web: WKWebView
    private var window: NSWindow?
    private var liveStart: Date?, firstVisible = false
    private var liveActions: [WhiteboardAction] = [], liveGate = WhiteboardActionGate()
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(.init(source: "window.wbMessages = []; window.addEventListener('error', e => window.webkit.messageHandlers.whiteboard.postMessage({type:'harness_error',message:e.message}));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 760), configuration: config)
        super.init(); config.userContentController.add(self, name: "whiteboard")
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any] else { return }
        if let start = liveStart {
            if value["type"] as? String == "board_revealed", !firstVisible {
                firstVisible = true
                let seconds = Date().timeIntervalSince(start)
                let result = String(format: "首笔可见 %.2f 秒（%@）", seconds, seconds <= 15 ? "通过" : "未达标")
                window?.title = result
                if let folder = Bundle.main.infoDictionary?["WeiBeiSourceDirectory"] as? String {
                    try? Data(result.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("dist-whiteboard-check/live-result.txt"))
                }
            }
            if value["type"] as? String == "action_step_complete", let id = value["step_id"] as? String,
               let raw = value["ticket"] as? String, let ticket = UUID(uuidString: raw), liveGate.acknowledge(stepID: id, ticket: ticket, success: true) { dispatchLive() }
            if value["type"] as? String == "action_step_failed" { window?.title = "模型计时失败：" + String(describing: value["message"] ?? "") }
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
                let session = WhiteboardSession(source: source, goal: "讲解残差为什么需要平方，用公式和关系图，最后出一道选择题。", lesson: .init(title: "残差"))
                _ = try await WhiteboardTeacher.generatePage(adapter: adapter, model: model, source: source, goal: session.goal, page: 1, session: session) { action in
                    await MainActor.run { self.liveActions.append(action); self.dispatchLive() }
                }
            } catch { window?.title = "模型计时失败：" + error.localizedDescription }
        }
    }
    private func dispatchLive() {
        guard !firstVisible, let (action, ticket) = liveGate.dispatch(liveActions) else { return }
        do {
            let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(action))
            Task { @MainActor in
                do { _ = try await web.callAsyncJavaScript("return await window.WeiBeiWhiteboard.receive(envelope)", arguments: ["envelope": ["action": value, "ticket": ticket.uuidString, "audio": [:], "voice": "animalese", "speed": 1]], in: nil, contentWorld: .page) }
                catch { window?.title = "模型计时失败：" + error.localizedDescription }
            }
        } catch { window?.title = "模型计时失败：" + error.localizedDescription }
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
            let controls = NSStackView(views: [NSButton(title: "浅色板面", target: self, action: #selector(light)),
                NSButton(title: "深色板面", target: self, action: #selector(dark)), NSButton(title: "模型首屏计时", target: self, action: #selector(live))])
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
      await dispatch({type:'highlight',step_id:'h1',target_board_id:0,snippet:'观测值与预测值',color:'red'});
      assert(card.querySelector('.highlight'),'Annotation must match text across Markdown nodes');
      window.wbStage='graph';const graph={type:'graph',step_id:'g1',board_uid:1,title:'因果关系',card_type:'diagram',source_page:12,mermaid:'flowchart LR\nA[观测值] --> B[残差]'};
      await dispatch(graph);assert(document.querySelector('[data-board="1"] svg'),'Actual Mermaid SVG must render');
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
      const replay=api.receive({action:voiceGroup,ticket:'new-ticket',audio:{},voice:'animalese',speed:1.5});
      await wait(()=>audio.currentTime>.1);oldEnded?.call(audio,new Event('ended'));
      assert(!messages('action_step_complete','voice-group').length,'An old ended callback cannot finish a replay');
      assert(audio.playbackRate===1.5&&audio.preservesPitch,'Rate changes preserve pitch');
      await replay;await wait(()=>messages('action_step_complete','voice-group').length===1);
      assert(audio.ended,'A completed replay waits for the actual ended event');
      assert(messages('action_step_complete','voice-group')[0].ticket==='new-ticket','Only the current playback ticket completes');
      await api.restore([page,group,graph,{type:'circle',step_id:'visual-circle',target_board_id:0,snippet:'残差',color:'red'}],null,'visual');
      window.wbResult='passed';window.webkit.messageHandlers.whiteboard.postMessage({type:'harness_result',status:'passed'});
    })().catch(error=>{window.wbResult=String(error);window.webkit.messageHandlers.whiteboard.postMessage({type:'harness_result',status:String(error)});}); void 0;
    """#
}
