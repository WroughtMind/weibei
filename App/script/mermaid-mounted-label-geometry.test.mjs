import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {runInNewContext} from 'node:vm';
import mermaid from 'mermaid';
const source=readFileSync(new URL('../../Sources/WeiBeiWebEditorCheck/main.swift',import.meta.url),'utf8');
const program=source.match(/private func verifyGenuiLabelGeometry[\s\S]*?let script = """([\s\S]*?)"""/)[1];
const baselineSource=execFileSync('git',['show','ea58f5c1:Sources/WeiBeiWebEditorCheck/main.swift'],{encoding:'utf8'});
const baselineProgram=baselineSource.match(/private func verifyGenuiLabelGeometry[\s\S]*?let script = """([\s\S]*?)"""/)[1];
const rect=(width=100)=>({x:0,y:0,left:0,top:0,width,height:20,right:width,bottom:20});
function fixture({mounted=true,clip=false,script=program,capturePayload=false}={}) {
 const style={fontFamily:'Host Font',fontSize:'13px',fontVariantNumeric:'normal',boxSizing:'border-box'};
 const labels=['WB514_START','WB514_END'].map(text=>({textContent:text,getBoundingClientRect:()=>rect(),textNode:{textContent:text,parentElement:{}}}));
 const svg={querySelectorAll:()=>labels};
 const hiddenMeasurement={querySelectorAll:()=>labels};
 const root={querySelector:selector=>selector==='[data-genui-mermaid] svg'?(mounted?svg:null):hiddenMeasurement,appendChild() {}};
 const body={appendChild(){}};
 const document={querySelector:()=>root,body,createElement:()=>({style:{},getBoundingClientRect:()=>rect(),remove(){}}),createTreeWalker:label=>{let done=false;return {nextNode(){if(done)return null;done=true;return label.textNode;}};},createRange:()=>({setStart(){},setEnd(){},getClientRects:()=>[rect(clip?112:90)]})};
 let payload;
 const result=runInNewContext(script,{document,window:{WeiBeiGenUIHost:{render(value){payload=value;}},labelProbeStarted:!capturePayload},NodeFilter:{SHOW_TEXT:4},getComputedStyle:()=>style});
 return capturePayload?payload:result;
}
test('temporary measurement SVG is not accepted as the mounted diagram',()=>{assert.notEqual(fixture({mounted:false,script:baselineProgram}),null,'The previous gate incorrectly completes on the temporary SVG');assert.equal(fixture({mounted:false}),null);});
test('mounted label ranges retain clipping rejection',()=>assert.equal(fixture({clip:true}).passed,false));
test('mounted labels pass only when their original ranges fit',()=>{const value=fixture();assert.equal(value.passed,true);assert.equal(value.labels.length,2);});

function initialize(theme) {
 mermaid.initialize({startOnLoad:false,securityLevel:'strict',fontFamily:'inherit',theme:'base',themeVariables:{fontFamily:'inherit',fontSize:'13px',primaryColor:theme.surface??'Canvas',primaryTextColor:theme.ink??'CanvasText',primaryBorderColor:theme.border??'rgba(0,0,0,0.1)',lineColor:theme.soft??'CanvasText'}});
}
test('geometry fixture supplies the production RGBA theme contract instead of unsupported system colors',()=>{
 const baseline=fixture({mounted:false,capturePayload:true,script:baselineProgram});assert.throws(()=>initialize(baseline.theme),/Unsupported color format/);
 const current=fixture({mounted:false,capturePayload:true});assert.doesNotThrow(()=>initialize(current.theme));assert.equal(current.theme.scale,'1');assert.equal(mermaid.mermaidAPI.getConfig().securityLevel,'strict');assert.equal(mermaid.mermaidAPI.getConfig().themeVariables.fontSize,'13px');
});
