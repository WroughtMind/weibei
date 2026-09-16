export type InkPoint = {x:number;y:number};
export type InkStroke = {id:string;points:InkPoint[]};
export type CanvasSnapshot = {revision?:number;activePageId?:string;zoom?:number;scrollX?:number;scrollY?:number;
  pages?:{id:string;strokes?:InkStroke[];columnLayout?:{lp:{tileW:number}}}[]};

export const relativeRect = (rect:DOMRect,base:DOMRect,scale:number) =>
  new DOMRect((rect.x-base.x)/scale,(rect.y-base.y)/scale,rect.width/scale,rect.height/scale);

export function inkPath(points:InkPoint[]):string {
  if(!points.length)return '';
  const first=points[0];let d=`M${first.x},${first.y}`;
  if(points.length===1)return d+`l.01,0`;
  for(let i=1;i<points.length-1;i++){
    const a=points[i],b=points[i+1];d+=` Q${a.x},${a.y} ${(a.x+b.x)/2},${(a.y+b.y)/2}`;
  }
  const last=points.at(-1)!;return d+` L${last.x},${last.y}`;
}

/** The camera and pen use one unscaled coordinate space. Audio and captions live outside it. */
export class WhiteboardInteraction {
  scale=1;
  inking=false;
  private width=1;private height=1;private stride=1;
  private pages:string[]=[];
  private ink=new Map<string,InkStroke[]>();
  private layer:SVGSVGElement;
  private stroke?:{page:string;pointer:number;value:InkStroke;path:SVGPathElement};
  private gestureScale?:number;
  private frame=0;
  private lastControls='';
  constructor(private viewport:HTMLElement,private canvas:HTMLElement,
    private changed:(immediate?:boolean)=>void,private interrupt:()=>void,
    private controls:(state:{zoom:number;inking:boolean;canUndo:boolean;pageID?:string})=>void) {
    this.layer=this.makeLayer();
    viewport.addEventListener('wheel',event=>{
      interrupt();
      if(!event.ctrlKey)return;
      event.preventDefault();
      if(this.gestureScale===undefined)this.zoom(this.scale*Math.exp(-event.deltaY*(event.deltaMode===1?.08:.008)),event.clientX,event.clientY);
    },{passive:false});
    viewport.addEventListener('gesturestart',event=>{
      event.preventDefault();this.finish();this.gestureScale=this.scale;interrupt();
    },{passive:false});
    viewport.addEventListener('gesturechange',event=>{
      event.preventDefault();const e=event as Event & {scale:number;clientX:number;clientY:number};
      if(this.gestureScale!==undefined)this.zoom(this.gestureScale*e.scale,e.clientX,e.clientY);
    },{passive:false});
    viewport.addEventListener('gestureend',event=>{event.preventDefault();this.gestureScale=undefined;},{passive:false});
    viewport.addEventListener('scroll',()=>{this.report();changed();},{passive:true});
    viewport.addEventListener('pointerdown',event=>this.begin(event));
    viewport.addEventListener('pointermove',event=>this.move(event));
    viewport.addEventListener('pointerup',event=>{if(event.pointerId===this.stroke?.pointer){this.move(event);this.finish();}});
    viewport.addEventListener('pointercancel',event=>{if(event.pointerId===this.stroke?.pointer)this.finish();});
    viewport.addEventListener('lostpointercapture',event=>{if(event.pointerId===this.stroke?.pointer)this.finish();});
  }
  private makeLayer() {
    const node=document.createElementNS('http://www.w3.org/2000/svg','svg');
    node.classList.add('ink-layer');node.setAttribute('aria-label','手写批注');this.canvas.append(node);return node;
  }
  point(clientX:number,clientY:number):InkPoint {
    const r=this.viewport.getBoundingClientRect();
    return {x:(clientX-r.left+this.viewport.scrollLeft)/this.scale,y:(clientY-r.top+this.viewport.scrollTop)/this.scale};
  }
  private pageIndex(x=(this.viewport.scrollLeft+this.viewport.clientWidth/2)/this.scale) {
    return Math.max(0,Math.min(this.pages.length-1,Math.floor(x/this.stride)));
  }
  currentPage(){return this.pages[this.pageIndex()];}
  strokes(id:string){return this.ink.get(id) ?? [];}
  private report(){
    const state={zoom:this.scale,inking:this.inking,canUndo:this.strokes(this.currentPage()).length>0,pageID:this.currentPage()},key=JSON.stringify(state);
    if(key!==this.lastControls){this.lastControls=key;this.controls(state);}
  }
  private extent() {
    this.canvas.style.transform=`scale(${this.scale})`;
    const space=this.canvas.parentElement!;
    space.style.width=Math.max(this.viewport.clientWidth,this.width*this.scale)+'px';
    space.style.height=Math.max(this.viewport.clientHeight,this.height*this.scale)+'px';
  }
  resize(width:number,height:number,stride:number,pages:string[]) {
    const repaint=this.width!==width||this.height!==height||this.stride!==stride||this.pages.join('|')!==pages.join('|')||!this.layer.isConnected;
    this.width=width;this.height=height;this.stride=stride;this.pages=pages;this.extent();
    if(repaint)this.render();
    this.report();
  }
  zoom(value:number,clientX?:number,clientY?:number) {
    if(!Number.isFinite(value))return;
    const rect=this.viewport.getBoundingClientRect();
    const x=clientX ?? rect.left+rect.width/2,y=clientY ?? rect.top+rect.height/2;
    const anchor=this.point(x,y);this.finish();this.interrupt();
    this.scale=Math.max(.5,Math.min(2,value));this.extent();
    this.viewport.scrollTo(anchor.x*this.scale-(x-rect.left),anchor.y*this.scale-(y-rect.top));
    this.report();this.changed();
  }
  command(command:string) {
    if(command==='zoom_in')this.zoom(this.scale+.25);
    else if(command==='zoom_out')this.zoom(this.scale-.25);
    else if(command==='reset_zoom')this.zoom(1);
    else if(command==='toggle_ink'){
      this.finish();this.inking=!this.inking;this.interrupt();
      this.viewport.classList.toggle('inking',this.inking);this.report();
    }else if(command==='undo'||command==='clear_page'){
      this.finish();const strokes=this.strokes(this.currentPage());
      if(command==='undo')strokes.pop();else strokes.length=0;
      this.render();this.report();this.changed(true);
    }
  }
  reset(state?:CanvasSnapshot|null) {
    this.finish();this.ink=new Map((state?.pages ?? []).map(p=>[p.id,structuredClone(p.strokes ?? [])]));
    this.scale=state?.zoom ?? 1;this.inking=false;this.viewport.classList.remove('inking');
    this.render();this.extent();
  }
  private render() {
    if(!this.layer.isConnected)this.layer=this.makeLayer();
    this.layer.setAttribute('width',String(this.width));this.layer.setAttribute('height',String(this.height));this.layer.replaceChildren();
    this.pages.forEach((id,i)=>this.strokes(id).forEach(stroke=>this.addPath(stroke,i)));
    if(this.stroke){this.stroke.path=this.layer.querySelector<SVGPathElement>(`[data-stroke="${this.stroke.value.id}"]`)!;}
  }
  private addPath(stroke:InkStroke,page:number) {
    const path=document.createElementNS('http://www.w3.org/2000/svg','path');
    path.dataset.stroke=stroke.id;path.setAttribute('transform',`translate(${page*this.stride},0)`);
    path.setAttribute('d',inkPath(stroke.points));this.layer.append(path);return path;
  }
  private begin(event:PointerEvent) {
    if(!this.inking||!event.isPrimary||event.button!==0||this.gestureScale!==undefined||!this.pages.length)return;
    event.preventDefault();this.finish();this.interrupt();
    const point=this.point(event.clientX,event.clientY),index=this.pageIndex(point.x),page=this.pages[index];
    const stroke:InkStroke={id:crypto.randomUUID(),points:[]};
    const strokes=this.ink.get(page) ?? [];strokes.push(stroke);this.ink.set(page,strokes);
    this.stroke={page,pointer:event.pointerId,value:stroke,path:this.addPath(stroke,index)};
    this.viewport.setPointerCapture(event.pointerId);this.move(event);this.report();
  }
  private move(event:PointerEvent) {
    const stroke=this.stroke;if(!stroke||stroke.pointer!==event.pointerId)return;
    event.preventDefault();
    const samples=event.getCoalescedEvents?.() ?? [];
    for(const sample of samples.length?samples:[event]){
      const raw=this.point(sample.clientX,sample.clientY),index=this.pages.indexOf(stroke.page);
      const point={x:Math.round(Math.max(0,Math.min(this.stride,raw.x-index*this.stride))*100)/100,
        y:Math.round(Math.max(0,Math.min(this.height,raw.y))*100)/100};
      const last=stroke.value.points.at(-1);
      if(!last||Math.hypot(point.x-last.x,point.y-last.y)>=.8)stroke.value.points.push(point);
    }
    if(!this.frame)this.frame=requestAnimationFrame(()=>{this.frame=0;if(this.stroke)this.stroke.path.setAttribute('d',inkPath(this.stroke.value.points));});
    this.changed();
  }
  private finish() {
    const stroke=this.stroke;if(!stroke)return;
    this.stroke=undefined;cancelAnimationFrame(this.frame);this.frame=0;
    stroke.path.setAttribute('d',inkPath(stroke.value.points));
    if(this.viewport.hasPointerCapture(stroke.pointer))this.viewport.releasePointerCapture(stroke.pointer);
    this.report();this.changed(true);
  }
}
