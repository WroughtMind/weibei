import type * as Voice from './animalVoice';
const voice = () => (globalThis as unknown as {WeiBeiVoice:typeof Voice}).WeiBeiVoice;
import { createWebiCompanion, webiMouthForPinyin } from './webiCompanion';
import { WhiteboardInteraction, relativeRect, type CanvasSnapshot, type InkStroke } from './whiteboardInteraction';
import { unified } from 'unified';
import remarkParse from 'remark-parse';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import { toHast } from 'mdast-util-to-hast';
import { toHtml } from 'hast-util-to-html';
import DOMPurify from 'dompurify';

type Action = { type: string; step_id: string; title?: string; page_id?: string; board_uid?: number; card_type?: string;
  board_content?: string; mermaid?: string; spoken_text?: string; source_page?: number; actions?: Action[];
  target_board_id?: number; snippet?: string; rect?: {x:number;y:number;w:number;h:number}; color?: string;
  mode?:'choice'|'open'; question?: string; options?: string[]; explanation?: string };
type Envelope = { action: Action; ticket: string; audio: Record<string, string>; voice?:string; silent?:boolean; speed?:number };
type Card = { action: Action; node: HTMLElement; revealed: boolean; page: number; column: number; x: number; y: number; decorations:Action[] };
type Deferred = { resolve: () => void; reject: (error: Error) => void };
type Page = { id:string; title:string; overlayItems:unknown[]; strokes:InkStroke[];
  columnLayout:{columns:{w:number;nextY:number}[];activeIndex:number;lp:{tileW:number}} };
const host = window as unknown as { webkit?: { messageHandlers?: { whiteboard?: { postMessage: (data: unknown) => void } } };
  WeiBeiKaTeX: { renderToString: (text: string, options: unknown) => string };
  WeiBeiMermaid: Promise<{ initialize: (options: unknown) => void; render: (id: string, text: string) => Promise<{svg:string}> }>;
  WeiBeiWhiteboard: typeof api; initialWhiteboardDark?:boolean };
const send = (data: Record<string,unknown>) => host.webkit?.messageHandlers?.whiteboard?.postMessage({...data,at:performance.now()/1000});
const canvas = document.getElementById('canvas')!;
const viewport = document.getElementById('viewport')!;
const audio = document.getElementById('narration') as HTMLAudioElement;
const companion = createWebiCompanion(document.getElementById('webi-host')!);
new ResizeObserver(()=>{document.documentElement.style.setProperty('--webi-width',companion.element.querySelector('canvas')!.hidden?'86px':'156px');layout();}).observe(companion.element);
let entries: ({type:'page'|'column';id?:string;title?:string} | Card)[] = [], cards = new Map<number, Card>();
let pages:Page[] = [], activePageId:string|undefined, layoutJSON='';
let epoch = 0, camera = 0, revision = 0, active: Envelope | undefined, paused = false, pausedAt = 0, pauseTotal = 0;
let snapshotTimer: ReturnType<typeof setTimeout> | undefined;
let layoutWidth:number|undefined;
const interaction=new WhiteboardInteraction(viewport,canvas,(immediate)=>{revision++;snapshot(immediate);},()=>{camera++;},
  state=>send({type:'canvas_controls',...state}));
const revealing = new Map<number, Deferred>(), speeches = new Map<string, Deferred>(), questions = new Map<string, Deferred>();
const preparedVoice=new Map<string,Awaited<ReturnType<typeof Voice.animalSpeech>>>();
const speechClocks=new Map<string,{progress:number;finished:boolean;audio?:HTMLAudioElement;error?:string}>();
type RevealSpeech={id:string;part:number;total:number};
const opened = new Set<number>(), animations = new Set<Animation>();
const reduced = () => matchMedia('(prefers-reduced-motion: reduce)').matches;
const now = () => performance.now() - pauseTotal - (paused ? performance.now() - pausedAt : 0);
const deferred = <K>(map: Map<K, Deferred>, id: K) => new Promise<void>((resolve, reject) => map.set(id, {resolve, reject}));
const paint = () => new Promise<void>(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
const assertEpoch = (token:number) => { if(token!==epoch) throw new Error('课堂已切换'); };

// A deadline reports failure; it never acknowledges unfinished work as successful.
function deadline<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  const start = now();
  return new Promise((resolve, reject) => {
    let timer: ReturnType<typeof setTimeout>;
    const check = () => {
      const left = ms - (now() - start);
      if (!paused && left <= 0) reject(new Error(label + '超时，请重试当前动作'));
      else timer = setTimeout(check, paused ? 500 : Math.max(1, left));
    };
    timer = setTimeout(check, ms);
    promise.then(value => { clearTimeout(timer); resolve(value); }, error => { clearTimeout(timer); reject(error); });
  });
}

function markdown(text: string): string {
  const tree = unified().use(remarkParse).use(remarkGfm).use(remarkMath).parse(text);
  const math = (value: string, displayMode: boolean) => ({
    type: 'raw' as const, value: host.WeiBeiKaTeX.renderToString(value, {displayMode, throwOnError: true, trust: false}),
  });
  const html = toHtml(toHast(tree, {handlers: {
    math: (_state, node) => math(node.value, true), inlineMath: (_state, node) => math(node.value, false),
  }})!, {allowDangerousHtml: true});
  return DOMPurify.sanitize(html, {FORBID_TAGS: ['img','iframe','script','style','a','input','button','form']});
}

function snapshot(immediate=false) {
  clearTimeout(snapshotTimer);
  const write=()=>send({type:'sync_whiteboard_state', whiteboard_state:{
    version:1,revision,activePageId:interaction.currentPage() ?? activePageId ?? null,
    zoom:interaction.scale,scrollX:viewport.scrollLeft,scrollY:viewport.scrollTop,
    pages:pages.map(page=>({...page,strokes:interaction.strokes(page.id)})),
  }});
  if(immediate)write();else snapshotTimer=setTimeout(write,500);
}

function layout() {
  // Keep page geometry stable while zooming or resizing; handwriting shares these coordinates.
  const width = layoutWidth ?? Math.max(260, Math.min(360, (viewport.clientWidth/interaction.scale - 60) / 2));
  if(entries.length)layoutWidth=width;
  const stride=2*width+72;
  pages=[];
  let page=-1,column=0,nextY=66,maxY=900;
  const addPage=(id?:string,title?:string) => {
    page++;column=0;nextY=66;
    pages.push({id:id ?? 'page-'+page,title:title ?? '续页',overlayItems:[],strokes:interaction.strokes(id ?? 'page-'+page),columnLayout:{
      columns:[{w:width,nextY:66},{w:width,nextY:66}],activeIndex:0,lp:{tileW:width},
    }});
  };
  for (const entry of entries) {
    if ('type' in entry) {
      if (entry.type === 'page') addPage(entry.id,entry.title);
      else { column++;if(column>1)addPage();else nextY=pages[page]?.columnLayout.columns[column].nextY ?? 66; if(pages[page])pages[page].columnLayout.activeIndex=column; }
      continue;
    }
    const wide=entry.action.type==='graph',tileWidth=wide?width*1.5:width;
    entry.node.style.width=tileWidth+'px';
    const height=entry.node.offsetHeight;
    if(page<0)addPage();
    if(wide){column=0;nextY=Math.max(...pages[page].columnLayout.columns.map(c=>c.nextY));}
    else nextY=Math.max(nextY,pages[page].columnLayout.columns[column].nextY);
    if(nextY>66&&nextY+height>850){
      if(wide)addPage();
      else{column++;if(column>1)addPage();else {nextY=pages[page].columnLayout.columns[column].nextY;if(nextY>66&&nextY+height>850)addPage();}}
    }
    entry.page=page;entry.column=column;entry.x=20+page*stride+column*(width+24);entry.y=nextY;
    entry.node.style.left=entry.x+'px';entry.node.style.top=nextY+'px';
    for(const mark of Array.from(entry.node.querySelectorAll<SVGSVGElement>('.annotation'))){
      const action=entry.decorations.find(a=>a.step_id===mark.dataset.step);
      if(action){const r=annotationRect(entry,action);mark.style.left=(r.x-6)+'px';mark.style.top=(r.y-5)+'px';mark.style.width=Math.max(8,r.width+12)+'px';mark.style.height=Math.max(8,r.height+10)+'px';}
    }
    const a=entry.action;
    pages[page].overlayItems.push({id:a.step_id,kind:a.type==='graph'?'mermaid_graph':'note_card',
      x:entry.x-page*stride,y:nextY,w:tileWidth,h:height,columnIndex:column,boardUid:a.board_uid,
      ...(a.type==='graph'?{mermaidGraph:{source:a.mermaid}}:{keypoint:{title:a.title ?? '',content:a.board_content,type:a.card_type ?? 'definition'}}),
      decorations:entry.decorations,
    });
    nextY+=height+32;maxY=Math.max(maxY,nextY+30);
    pages[page].columnLayout.columns[column].nextY=nextY;pages[page].columnLayout.activeIndex=column;
    if(wide)pages[page].columnLayout.columns[1].nextY=nextY;
  }
  const canvasWidth=Math.max(width*2+72,(page+1)*stride);
  canvas.style.width=canvasWidth+'px';canvas.style.height=maxY+'px';
  interaction.resize(canvasWidth,maxY,stride,pages.map(p=>p.id));
  canvas.querySelectorAll('.page-title').forEach(node=>node.remove());
  pages.forEach((p,i)=>{
    const label=document.createElement('div');label.className='page-title';label.textContent=`${i+1} / ${p.title}`;
    label.style.cssText=`position:absolute;left:${20+i*stride}px;top:20px`;canvas.append(label);
  });
  if(!pages.some(p=>p.id===activePageId))activePageId=pages[0]?.id;
  const serialized=JSON.stringify(pages);
  if(serialized!==layoutJSON){layoutJSON=serialized;revision++;snapshot();}
}
const sizes = new ResizeObserver(() => layout());
new ResizeObserver(() => layout()).observe(viewport);

async function prepare(a: Action, restoring = false): Promise<Card> {
  if (a.board_uid===undefined) throw new Error('板书缺少编号');
  const existing=cards.get(a.board_uid);if(existing)return existing;
  const token=epoch,node=document.createElement('article');node.className='card '+(a.card_type ?? 'definition');
  node.dataset.board=String(a.board_uid);
  const title=document.createElement('h2'), marker=document.createElement('span');marker.className='title-marker';marker.textContent=a.title ?? '';title.append(marker);
  if(restoring)marker.style.backgroundSize='100% 100%';
  const body=document.createElement('div');body.className='content';
  node.append(title,body);canvas.append(node);
  const card:Card={action:a,node,revealed:restoring,page:0,column:0,x:0,y:0,decorations:[]};
  cards.set(a.board_uid,card);entries.push(card);node.style.opacity=restoring?'1':'0';
  if(a.type==='graph') {
    if (/%%\{|\bclick\s|<\/?(?:script|iframe|img)/i.test(a.mermaid ?? '')) throw new Error('图示包含不支持的指令');
    const value=await (await host.WeiBeiMermaid).render('graph-'+a.step_id.replace(/[^a-z0-9]/gi,'')+'-'+epoch,a.mermaid ?? '');
    assertEpoch(token);
    body.innerHTML=DOMPurify.sanitize(value.svg,{USE_PROFILES:{svg:true,svgFilters:true}});
    body.querySelector('svg')?.setAttribute('width','100%');
  } else {body.innerHTML=markdown(a.board_content ?? '');}
  await document.fonts.ready;await paint();assertEpoch(token);sizes.observe(node);layout();return card;
}

function follow(card: Pick<Card,'x'|'y'|'page'>) {
  if(interaction.inking)return;
  const fromX=viewport.scrollLeft,fromY=viewport.scrollTop;
  const toX=Math.max(0,card.x*interaction.scale-20),toY=Math.max(0,card.y*interaction.scale-70),start=performance.now(),token=++camera;
  activePageId=pages[card.page]?.id;revision++;snapshot();
  if(reduced()){viewport.scrollTo(toX,toY);return;}
  const tick=(t:number)=>{
    if(token!==camera||paused)return;
    const p=Math.min(1,(t-start)/450),e=1-Math.pow(1-p,3);
    viewport.scrollTo(fromX+(toX-fromX)*e,fromY+(toY-fromY)*e);
    if(p<1)requestAnimationFrame(tick);
  };requestAnimationFrame(tick);
}

async function animate(node:Element,frames:Keyframe[],duration:number,delay=0) {
  if(reduced())return;
  const animation=node.animate(frames,{duration,delay,fill:'both'});
  animations.add(animation);if(paused)animation.pause();
  try {await animation.finished;} finally {animations.delete(animation);animation.cancel();}
}

async function waitSpeech(speech:RevealSpeech,fraction:number,token:number){
  const target=(speech.part+fraction)/speech.total;
  for(;;){
    assertEpoch(token);const clock=speechClocks.get(speech.id);
    if(clock?.error)throw new Error(clock.error);
    const progress=clock?.audio&&Number.isFinite(clock.audio.duration)&&clock.audio.duration>0
      ? Math.min(.999,clock.audio.currentTime/clock.audio.duration) : clock?.progress ?? 0;
    if(!paused&&(clock?.finished||(target<1&&progress>=target)))return;
    await new Promise(requestAnimationFrame);
  }
}

async function reveal(card:Card,track=true,speech?:RevealSpeech) {
  if(card.revealed)return;
  const token=epoch,ticket=active?.ticket;
  const visible=()=>{if(track&&token===epoch)send({type:'board_revealed',ticket});};
  card.node.style.opacity='1';if(track)follow(card);
  const marker=card.node.querySelector<HTMLElement>('.title-marker');
  const spans:HTMLSpanElement[]=[],units:{node:Element;math:boolean;title:boolean}[]=[];
  const collect=(parent:Node)=>{
    for(const node of Array.from(parent.childNodes)){
      if(node instanceof Text){
        const fragment=document.createDocumentFragment();
        for(const char of node.data){const span=document.createElement('span');span.className='reveal-char';span.textContent=char;fragment.append(span);spans.push(span);units.push({node:span,math:false,title:marker?.contains(node) ?? false});}
        node.replaceWith(fragment);
      }else if(node instanceof Element){
        if(node.matches('.katex-display,.katex,svg,pre'))units.push({node,math:true,title:false});else collect(node);
      }
    }
  };const title=card.node.querySelector('h2');if(title)collect(title);collect(card.node.querySelector('.content')!);
  for(const unit of units)(unit.node as HTMLElement).style.opacity='0';
  const interval=Math.max(18,Math.min(50,2880/Math.max(1,units.length)));
  const lastTitle=units.map((u,i)=>u.title?i:-1).reduce((a,b)=>Math.max(a,b),-1);
  const pen=document.createElement('div');pen.className='write-pen';pen.setAttribute('aria-hidden','true');
  pen.innerHTML='<svg class="pen-body" width="28" height="28" viewBox="0 0 24 24" fill="#fde68a" stroke="#b45309" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5L17 3z"/><path d="m15 5 4 4" fill="none"/></svg>';
  card.node.append(pen);let markerFinished:Promise<void>|undefined;
  try {
    await Promise.all(units.map(async(u,i)=>{
      if(speech)await waitSpeech(speech,units.length===1?1:i/(units.length-1),token);
      await animate(u.node,[{opacity:0,filter:'blur(3px)'},{opacity:1,filter:'blur(0)'}],u.math?280:360,speech?0:i*interval);
      (u.node as HTMLElement).style.opacity='1';
      if(!track&&card.action.type==='speak'){
        const clock=speechClocks.get(card.action.step_id);if(clock)clock.progress=Math.max(clock.progress,Math.min(.999,(i+1)/units.length));
      }
      if(i===0){await paint();visible();}
      const rect=relativeRect(u.node.getBoundingClientRect(),card.node.getBoundingClientRect(),track?interaction.scale:1);
      pen.style.left=rect.right+'px';pen.style.top=rect.bottom+'px';pen.style.opacity='1';
      if(i===lastTitle&&marker)markerFinished=animate(marker,[{backgroundSize:'0% 100%'},{backgroundSize:'100% 100%'}],420)
        .then(()=>{marker.style.backgroundSize='100% 100%';});
    }));
    await markerFinished;card.revealed=true;
    await animate(pen,[{opacity:1},{opacity:0}],180);
  } finally {pen.remove();for(const span of spans)span.replaceWith(document.createTextNode(span.textContent ?? ''));card.node.normalize();}
  await paint();
  if(track&&token===epoch)send({type:'board_finished',step_id:card.action.step_id,ticket});
}

function annotationRect(card:Card,a:Action):DOMRect {
  let r:DOMRect;
  if(a.rect){const {x,y,w,h}=a.rect;r=new DOMRect(x*card.node.clientWidth,y*card.node.clientHeight,w*card.node.clientWidth,h*card.node.clientHeight);}
  else {
    const walker=document.createTreeWalker(card.node.querySelector('.content')!,NodeFilter.SHOW_TEXT);
    const nodes:Text[]=[];let n:Node|null,text='';
    while((n=walker.nextNode())){if(n.parentElement?.closest('.katex-mathml'))continue;nodes.push(n as Text);text+=n.textContent;}
    const start=text.indexOf(a.snippet ?? '');if(start<0||!a.snippet)throw new Error('没有找到要标注的原文');
    const end=start+a.snippet.length,range=document.createRange();let offset=0;
    for(const node of nodes){const next=offset+node.length;if(start>=offset&&start<next)range.setStart(node,start-offset);if(end>offset&&end<=next)range.setEnd(node,end-offset);offset=next;}
    r=relativeRect(range.getBoundingClientRect(),card.node.getBoundingClientRect(),interaction.scale);
  }
  return r;
}

async function annotate(a:Action,restoring=false) {
  const card=cards.get(a.target_board_id ?? -1);if(!card)throw new Error('标注目标不存在');
  const r=annotationRect(card,a);
  const ns='http://www.w3.org/2000/svg',mark=document.createElementNS(ns,'svg');mark.classList.add('annotation',a.type);mark.dataset.step=a.step_id;mark.setAttribute('preserveAspectRatio','none');
  const width=Math.max(8,r.width+12),height=Math.max(8,r.height+10),id='mark-'+crypto.randomUUID();
  mark.setAttribute('width',String(width));mark.setAttribute('height',String(height));mark.setAttribute('viewBox',`0 0 ${width} ${height}`);
  mark.style.cssText=`left:${r.x-6}px;top:${r.y-5}px;overflow:visible;color:${({red:'var(--red)',green:'var(--example)',blue:'var(--definition)',ink:'var(--ink)'} as Record<string,string>)[a.color ?? 'red']}`;
  if(a.type==='circle')mark.innerHTML=`<defs><filter id="${id}" x="-10%" y="-20%" width="120%" height="140%"><feTurbulence type="fractalNoise" baseFrequency=".05" numOctaves="2" seed="5" result="noise"/><feDisplacementMap in="SourceGraphic" in2="noise" scale="1.3"/></filter></defs><ellipse cx="${width/2}" cy="${height/2}" rx="${width/2-2}" ry="${height/2-2}" fill="none" stroke="currentColor" stroke-width="2" pathLength="1" filter="url(#${id})"/>`;
  else mark.innerHTML=`<defs><clipPath id="${id}"><rect width="${width}" height="${height}"/></clipPath></defs><path d="M3 ${height*.6} Q${width*.5} ${height*.48} ${width-3} ${height*.56}" fill="none" stroke="currentColor" stroke-width="${height*.65}" opacity=".25" stroke-linecap="round" clip-path="url(#${id})"/>`;
  card.node.append(mark);card.decorations.push(a);layout();follow(card);
  if(!restoring){
    if(a.type==='circle'){
      const ellipse=mark.querySelector('ellipse')!;ellipse.setAttribute('stroke-dasharray','1');
      await animate(ellipse,[{strokeDashoffset:'1'},{strokeDashoffset:'0'}],920);
    }else await animate(mark.querySelector('clipPath rect')!,[{width:'0px',easing:'cubic-bezier(0.22,1,0.36,1)'},{width:width+'px'}],1000);
  }
}

async function execute(a:Action,env:Envelope,restoring=false):Promise<void> {
  if(a.type==='session_ready'||a.type==='keypoint_complete'){await deadline(paint(),4000,'课堂进度显示');return;}
  if(a.type==='new_page'||a.type==='new_column'){
    entries.push({type:a.type==='new_page'?'page':'column',id:a.page_id ?? a.step_id,title:a.title});layout();
    if(!restoring){const width=pages.at(-1)?.columnLayout.lp.tileW ?? 360, page=pages.length-1, column=pages.at(-1)?.columnLayout.activeIndex ?? 0;follow({x:20+page*(2*width+72)+column*(width+24),y:66,page});}
    await deadline(paint(),4000,'页面显示');return;
  }
  if(a.type==='group'){
    const children=a.actions ?? [],boardActions=children.filter(c=>c.type==='board'||c.type==='graph'),token=epoch;
    for(const child of children)if(child.type==='speak')speechClocks.set(child.step_id,{progress:0,finished:false});
    await Promise.all(boardActions.map(c=>deadline(prepare(c,restoring),30000,'板书排版')));assertEpoch(token);
    const boards=(async()=>{for(const c of boardActions)await execute(c,env,restoring);})();
    await Promise.all([boards,...children.filter(c=>!boardActions.includes(c)).map(async c=>{
      if(c.type==='highlight'||c.type==='circle')await boards;
      await execute(c,env,restoring);
    })]);return;
  }
  if(a.type==='board'||a.type==='graph'){
    const token=epoch,card=await deadline(prepare(a,restoring),30000,'板书排版');assertEpoch(token);
    if(restoring)return;
    const speak=env.action.actions?.find(c=>c.type==='speak');
    if(speak&&!opened.has(a.board_uid!))await deadline(deferred(revealing,a.board_uid!),8000,'语音揭示');
    const boards=env.action.actions?.filter(c=>c.type==='board'||c.type==='graph') ?? [];
    const speech=speak?{id:speak.step_id,part:boards.indexOf(a),total:boards.length}:undefined;
    await deadline(reveal(card,true,speech),speech?183000:Math.min(30000,4000+24*(a.board_content?.length ?? 200)),'板书显示');return;
  }
  if(a.type==='speak'){
    if(restoring)return;
    if(env.silent){
      const node=document.createElement('div');node.className='silent-caption';
      node.innerHTML='<div class="content"></div>';
      node.querySelector('.content')!.textContent=a.spoken_text ?? '';document.body.append(node);
      api.speechStarted(a.step_id);
      try{await deadline(reveal({action:a,node,revealed:false,page:0,column:0,x:0,y:0,decorations:[]},false),30000,'讲稿阅读');}
      finally{node.remove();api.speechFinished(a.step_id);}return;
    }
    const token=epoch;
    const local=preparedVoice.get(a.step_id);preparedVoice.delete(a.step_id);
    assertEpoch(token);
    const pending=deferred(speeches,a.step_id),finished=deadline(pending,180000,'语音播放');
    const bytes=local?.url ?? env.audio[a.step_id];
    const cleanCaption=local?voice().speechCaption(audio,a.spoken_text ?? '',local.cues):undefined;
    const detachWebi=bytes?companion.followAudio(audio,local?.mouthCues ?? []):undefined;
    if(bytes){
      speechClocks.set(a.step_id,{progress:0,finished:false,audio});
      audio.src=bytes;audio.playbackRate=env.speed ?? 1;audio.preservesPitch=true;
      audio.onplaying=()=>{if(token===epoch)api.speechStarted(a.step_id);};
      audio.onended=()=>{if(token===epoch)api.speechFinished(a.step_id);};
      audio.onerror=()=>{if(token===epoch)api.speechFinished(a.step_id,'音频播放失败');};
      // play() may stay pending while buffering; the completion deadline still guards it.
      if(!paused)void audio.play().catch(error=>{if(token===epoch)api.speechFinished(a.step_id,String(error));});
    }else{send({type:'speech_request',action:a,ticket:env.ticket});}
    try {await finished;} finally {if(token===epoch){speeches.delete(a.step_id);audio.onplaying=null;audio.onended=null;audio.onerror=null;companion.setMouth(0);companion.setAction('idle');}cleanCaption?.();detachWebi?.();}
    return;
  }
  if(a.type==='highlight'||a.type==='circle'){await deadline(annotate(a,restoring),4000,'标注');return;}
  if(a.type==='ask'){
    if(restoring)return;
    const pending=deferred(questions,a.step_id);send({type:'question',action:a,ticket:env.ticket});
    // The native receiver acknowledges the persisted question, independently of the learner's answer.
    try{await deadline(pending,4000,'题目显示');}finally{questions.delete(a.step_id);}return;
  }
  throw new Error('不支持的课堂动作');
}

const api={
  canvasCommand(command:string){interaction.command(command);},
  async receive(env:Envelope){
    if(active)throw new Error('上一步尚未完成');active=env;const token=epoch;
    companion.setAction(env.action.type==='new_page'?'hi':env.action.type==='ask'?'wait':env.action.type==='keypoint_complete'?'celebrate':env.action.type==='highlight'||env.action.type==='circle'?'point':'think');
    try{
      if(env.voice==='animalese'){
        for(const action of env.action.type==='group'?env.action.actions ?? []:[env.action])if(action.type==='speak'){
          const local=await deadline(voice().animalSpeech(action.spoken_text ?? '',()=>assertEpoch(token)),30000,'中文动物语合成');
          assertEpoch(token);preparedVoice.set(action.step_id,local);
        }
      }
      await execute(env.action,env);
      for(const action of env.action.actions ?? [env.action])if(action.type==='speak')speechClocks.delete(action.step_id);
      if(token===epoch){active=undefined;send({type:'action_step_complete',step_id:env.action.step_id,ticket:env.ticket});}
    }catch(error){
      if(token===epoch){api.pause(true);send({type:'action_step_failed',step_id:env.action.step_id,ticket:env.ticket,message:String(error)});}
    }
  },
  speechStarted(id:string){
    send({type:'speech_started',step_id:id,ticket:active?.ticket});
    if(active?.action.step_id===id||active?.action.actions?.some(a=>a.type==='speak'&&a.step_id===id))companion.setAction('talk');
    const children=active?.action.type==='group'?active.action.actions:[];
    if(!children?.some(a=>a.type==='speak'&&a.step_id===id))return;
    for(const a of children.filter(a=>a.type==='board'||a.type==='graph')){
      opened.add(a.board_uid!);revealing.get(a.board_uid!)?.resolve();revealing.delete(a.board_uid!);
    }
  },
  speechFinished(id:string,error?:string){
    const clock=speechClocks.get(id);if(clock){clock.finished=!error;clock.error=error;}
    send({type:'speech_finished',step_id:id,ticket:active?.ticket,error});
    const d=speeches.get(id);error?d?.reject(new Error(error)):d?.resolve();
  },
  speechBoundary(id:string,text:string,progress=0){
    if(!speeches.has(id))return;
    const clock=speechClocks.get(id);if(clock)clock.progress=Math.max(clock.progress,Math.min(.999,progress));
    try{const phoneme=voice().mandarinUnits(text).flatMap(u=>u.phonemes)[0];companion.setMouth(phoneme?webiMouthForPinyin(phoneme):0);}catch{companion.setMouth(0);}
  },
  questionDisplayed(id:string){questions.get(id)?.resolve();},
  feedback(correct:boolean){companion.setAction(correct?'celebrate':'surprise');},
  generationWaiting(value:boolean){
    document.getElementById('generation-waiting')!.hidden=!value;
    companion.setAction(value?'think':'idle');
  },
  async supplement(action:Action,replyID:string){
    const token=epoch;
    try{await deadline(prepare(action,true),30000,'补充板书');assertEpoch(token);await paint();send({type:'supplement_complete',reply_id:replyID});}
    catch(error){if(token===epoch)send({type:'supplement_failed',reply_id:replyID,message:String(error)});}
  },
  async setAppearance(dark:boolean){
    if(document.documentElement.dataset.theme===(dark?'dark':'light'))return;
    await setAppearance(dark);const token=epoch;
    for(const card of cards.values())if(card.action.type==='graph'){
      const value=await (await host.WeiBeiMermaid).render('theme-'+card.action.step_id.replace(/[^a-z0-9]/gi,'')+'-'+token,card.action.mermaid ?? '');
      assertEpoch(token);card.node.querySelector('.content')!.innerHTML=DOMPurify.sanitize(value.svg,{USE_PROFILES:{svg:true,svgFilters:true}});
      card.node.querySelector('svg')?.setAttribute('width','100%');
    }
    await paint();layout();
  },
  pause(value:boolean){
    if(value===paused)return;
    companion.setPaused(value);
    if(value){pausedAt=performance.now();audio.pause();}
    else{pauseTotal+=performance.now()-pausedAt;const token=epoch;if(speeches.size&&audio.getAttribute('src')&&!audio.ended)void audio.play().catch(error=>{
      if(token===epoch)for(const d of speeches.values())d.reject(new Error(String(error)));
    });}
    paused=value;document.documentElement.dataset.paused=String(value);for(const animation of animations)value?animation.pause():animation.play();
  },
  async restore(actions:Action[],state:CanvasSnapshot|undefined,requestID:string){
    companion.setPaused(false);companion.setMouth(0);companion.setAction('idle');
    epoch++;camera++;active=undefined;audio.onplaying=null;audio.onended=null;audio.onerror=null;audio.pause();audio.removeAttribute('src');audio.load();opened.clear();preparedVoice.clear();speechClocks.clear();api.generationWaiting(false);
    clearTimeout(snapshotTimer);
    for(const map of [revealing,speeches,questions]){for(const d of map.values())d.reject(new Error('课堂已切换'));map.clear();}
    for(const animation of animations)animation.cancel();animations.clear();
    sizes.disconnect();cards.clear();entries=[];canvas.replaceChildren();revision=state?.revision ?? 0;layoutJSON='';activePageId=state?.activePageId;
    layoutWidth=state?.pages?.[0]?.columnLayout?.lp.tileW;interaction.reset(state);
    paused=false;pauseTotal=0;document.documentElement.dataset.paused='false';
    const token=epoch;
    for(const action of actions){assertEpoch(token);await execute(action,{action,ticket:'restore',audio:{}},true);}
    assertEpoch(token);layout();
    const page=pages.findIndex(p=>p.id===state?.activePageId),width=pages[0]?.columnLayout.lp.tileW ?? 360;
    viewport.scrollTo(state?.scrollX ?? Math.max(0,page)*(2*width+72)*interaction.scale,state?.scrollY ?? 0);
    send({type:'restored',request_id:requestID});
  },
};
host.WeiBeiWhiteboard=api;
async function setAppearance(dark:boolean){
  document.documentElement.dataset.theme=dark?'dark':'light';
  (await host.WeiBeiMermaid).initialize({startOnLoad:false,securityLevel:'strict',look:'handDrawn',fontFamily:'Virgil, Kaiti SC, STKaiti, serif',htmlLabels:false,theme:'base',themeVariables:{
    darkMode:dark,background:'transparent',primaryColor:dark?'#263e50':'#dbeafe',primaryTextColor:dark?'#cee2ed':'#25435b',primaryBorderColor:dark?'#86abc2':'#5488a8',
    secondaryColor:dark?'#44374f':'#ede9fe',tertiaryColor:dark?'#27453f':'#ccfbf1',lineColor:dark?'#b0aba0':'#716b60',textColor:dark?'#e7e2d7':'#36332e',
    mainBkg:dark?'#263e50':'#dbeafe',nodeTextColor:dark?'#cee2ed':'#25435b',edgeLabelBackground:dark?'#242421':'#faf8f2',
  }});
}
void Promise.all([document.fonts.load('19px Virgil','ABC 123'),window.WeiBeiKaTeXReady]).then(([fonts])=>{
  if(!fonts.length)throw new Error('白板手写字体未能加载');
  return setAppearance(host.initialWhiteboardDark ?? matchMedia('(prefers-color-scheme: dark)').matches);
})
  .then(()=>send({type:'ready'})).catch(error=>send({type:'initialization_failed',message:String(error)}));
