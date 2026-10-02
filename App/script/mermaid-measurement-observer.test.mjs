import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {runInNewContext} from 'node:vm';
const source=readFileSync(new URL('../../Sources/WeiBeiWebEditorCheck/main.swift',import.meta.url),'utf8');
const program=source.match(/private static let genuiMeasurementObserver = #"""([\s\S]*?)"""#/)[1];
function observe({text='WB514_START',throws=false}={}) {
  const rectangle={x:1,y:2,width:91.4,height:21};
  class Element { getBoundingClientRect() {return rectangle;} }
  const window={};
  runInNewContext(program,{Element,window,getComputedStyle:()=>{if(throws) throw Error('diagnostic failure');return {fontFamily:'Host Font',fontSize:'13px',lineHeight:'20.8px',fontVariantNumeric:'tabular-nums',boxSizing:'border-box'};}});
  const element=new Element();element.textContent=text;element.localName='span';element.closest=()=>({});
  const result=element.getBoundingClientRect();
  return {result,rectangle,observed:window.__WeiBeiLabelMeasurements,element};
}
test('measurement observation returns the exact original rectangle and records synthetic fonts',()=>{
 const {result,rectangle,observed}=observe();assert.equal(result,rectangle);assert.equal(observed.length,1);assert.equal(observed[0].font,'Host Font');assert.equal(observed[0].fontSize,'13px');assert.deepEqual(Array.from(observed[0].rect),[1,2,91.4,21]);
});
test('ordinary content is not recorded and observer failure cannot affect layout',()=>{
 const ordinary=observe({text:'Unrelated private content'});assert.equal(ordinary.result,ordinary.rectangle);assert.equal(ordinary.observed.length,0);
 const broken=observe({throws:true});assert.equal(broken.result,broken.rectangle);assert.equal(broken.observed.length,0);
});
test('measurement evidence is bounded without changing later measurements',()=>{
 const {element,rectangle,observed}=observe();for(let i=0;i<200;i++)assert.equal(element.getBoundingClientRect(),rectangle);assert.equal(observed.length,128);
});
