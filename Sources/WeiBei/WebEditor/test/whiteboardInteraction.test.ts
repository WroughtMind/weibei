import assert from 'node:assert/strict';
import {test} from 'node:test';
import {WhiteboardInteraction} from '../src/whiteboardInteraction';

test('Zoom anchors the pointer; ink stays on its page and redraws after same-size restoration', t => {
  const node = (): any => Object.assign(new EventTarget(), {
    style:{}, dataset:{}, children:[] as any[], isConnected:true,
    classList:{add(){},toggle(){},remove(){}},
    setAttribute(name:string,value:string){Reflect.set(this,name,value);},
    append(child:any){this.children.push(child);},
    replaceChildren(){for(const child of this.children)child.isConnected=false;this.children=[];},
  });
  const globals={document:{createElementNS:node},requestAnimationFrame:()=>1,cancelAnimationFrame:()=>{}};
  const originals=Object.fromEntries(Object.keys(globals).map(key=>[key,Object.getOwnPropertyDescriptor(globalThis,key)]));
  Object.assign(globalThis,globals);
  t.after(()=>{for(const [key,value] of Object.entries(originals)){
    if(value)Object.defineProperty(globalThis,key,value);else Reflect.deleteProperty(globalThis,key);
  }});
  const viewport=Object.assign(node(), {
    clientWidth:600,clientHeight:700,scrollLeft:120,scrollTop:60,
    getBoundingClientRect:()=>({left:10,top:20,width:600,height:700}),
    scrollTo(x:number,y:number){this.scrollLeft=Math.max(0,x);this.scrollTop=Math.max(0,y);},
    setPointerCapture(){},hasPointerCapture:()=>false,
  });
  const canvas=Object.assign(node(),{parentElement:node()});
  let saves=0;
  const camera=new WhiteboardInteraction(viewport,canvas,()=>saves++,()=>{},()=>{});
  camera.resize(1600,900,800,['p1','p2']);
  const anchor=camera.point(210,220);
  camera.zoom(1.5,210,220);
  assert.deepEqual(camera.point(210,220),anchor);
  camera.command('toggle_ink');viewport.scrollTo(0,0);
  const pointer=(type:string,x:number,y:number)=>viewport.dispatchEvent(Object.assign(new Event(type),{
    pointerId:1,isPrimary:true,button:0,clientX:10+x*camera.scale,clientY:20+y*camera.scale,
  }));
  for(let i=0;i<3;i++){
    pointer('pointerdown',50+i*20,100);pointer('pointermove',60+i*20,110);pointer('pointerup',70+i*20,120);
  }
  assert.equal(camera.strokes('p1').length,3);
  assert.deepEqual(camera.strokes('p1')[0].points,[{x:50,y:100},{x:60,y:110},{x:70,y:120}]);
  viewport.scrollTo(1200,0);pointer('pointerdown',40,100);pointer('pointerup',60,120);
  assert.deepEqual(camera.strokes('p2')[0].points,[{x:40,y:100},{x:60,y:120}]);
  const state={zoom:1.5,pages:['p1','p2'].map(id=>({id,strokes:structuredClone(camera.strokes(id))}))};
  canvas.replaceChildren();camera.reset(state);camera.resize(1600,900,800,['p1','p2']);
  assert.equal(canvas.children[0].children.length,4,'Same geometry still redraws restored strokes');
  camera.command('clear_page');assert.equal(camera.strokes('p2').length,0);assert.equal(camera.strokes('p1').length,3);
  viewport.scrollTo(0,0);camera.command('undo');assert.equal(camera.strokes('p1').length,2);
  camera.zoom(.1);assert.equal(camera.scale,.5);camera.zoom(4);assert.equal(camera.scale,2);
  camera.command('fit_page');assert.equal(camera.scale,588/800);assert.equal(viewport.scrollLeft,0);
  camera.command('next_page');assert.equal(camera.currentPage(),'p2');assert.equal(viewport.scrollLeft,588);
  camera.command('previous_page');assert.equal(camera.currentPage(),'p1');assert.equal(viewport.scrollLeft,0);
  assert.equal(camera.strokes('p1').length,2,'Page navigation and fit never change content coordinates');
  assert.ok(saves>3);
});
