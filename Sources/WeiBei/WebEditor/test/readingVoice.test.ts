import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import vm from 'node:vm';
import { animalSpeech, mandarinUnits } from '../src/animalVoice';
import { speechParagraphs } from '../src/readingVoice';

test('Chinese offline synthesis retains character boundaries, punctuation and cancellation',{skip:process.platform!=='darwin'},async()=>{
  const folder=await mkdtemp(join(tmpdir(),'weibei-voice-')),run=promisify(execFile);let serial=0;
  // Node has no Web Audio. Decode the actual packaged Opus with the same system
  // codec; the WebKit check separately exercises OfflineAudioContext itself.
  const previousContext=Object.getOwnPropertyDescriptor(globalThis,'OfflineAudioContext');
  Object.defineProperty(globalThis,'OfflineAudioContext',{configurable:true,value:class {
    async decodeAudioData(bytes:ArrayBuffer){
      const path=join(folder,String(serial++));await writeFile(path+'.caf',new Uint8Array(bytes));
      await run('/usr/bin/afconvert',[path+'.caf',path+'.wav','-f','WAVE','-d','LEI16@16000']);
      const wav=await readFile(path+'.wav');let start=12;
      while(wav.toString('ascii',start,start+4)!=='data'){const size=wav.readUInt32LE(start+4);start+=8+size+(size%2);assert.ok(start+8<=wav.length);}
      const length=wav.readUInt32LE(start+4)/2,pcm=new Float32Array(length);
      for(let i=0;i<length;i++){const value=wav.readInt16LE(start+8+i*2);pcm[i]=value/(value<0?32768:32767);}
      return {getChannelData:()=>pcm};
    }
  }});
  const previousWebKit=Object.getOwnPropertyDescriptor(globalThis,'webkit');
  Object.defineProperty(globalThis,'webkit',{configurable:true,value:{messageHandlers:{voiceResource:{postMessage:async(group:string)=>{
    assert.match(group,/^[a-z]$/);return (await readFile('Sources/WeiBei/Resources/Editor/chinese-voice-'+group+'.caf')).toString('base64');
  }}}}});
  const scope={window:{} as Record<string,unknown>};
  const text='重庆银行的2.5%，OLS，重新比较残差。';
  vm.runInNewContext(await readFile('Sources/WeiBei/Resources/Editor/chinese-voice-index.js','utf8'),scope);
  const index=scope.window.WeiBeiChineseVoiceIndex as Record<string,string>;
  for(const group of new Set(mandarinUnits(text).flatMap(u=>u.phonemes).map(key=>index[key.replace(/[05]$/,'1')]))){
    assert.ok(group);vm.runInNewContext(await readFile('Sources/WeiBei/Resources/Editor/chinese-voice-'+group+'.js','utf8'),scope);
  }
  Object.assign(globalThis,scope.window);
  const original=globalThis.fetch;globalThis.fetch=async()=>{throw new Error('No network in offline synthesis');};
  try{
    const units=mandarinUnits(text);
    assert.deepEqual(units.slice(0,4).flatMap(x=>x.phonemes),['chong2','qing4','yin2','hang2']);
    assert.equal(units.map(x=>text.slice(x.from,x.to)).join(''),text);
    const sound=await animalSpeech(text,()=>{}),bytes=Buffer.from(sound.url.split(',')[1],'base64');
    assert.equal(bytes.subarray(0,4).toString(),'RIFF');assert.equal(bytes.readUInt32LE(24),16000);
    assert.equal(bytes.length,44+Math.round(sound.duration*16000)*2);
    assert.equal(sound.cues.length,Array.from(text).length);
    sound.cues.forEach((cue,i)=>{assert.ok(cue.end>cue.start);if(i)assert.equal(cue.start,sound.cues[i-1].end);});
    assert.equal(sound.cues.at(-1)?.to,text.length);
    assert.ok(sound.mouthCues.length>sound.cues.length, 'Latin letter names preserve their multiple synthesized syllables');
    assert.equal(sound.mouthCues.at(-1)?.end,sound.duration);
    sound.mouthCues.forEach((cue,i)=>{assert.ok(cue.end>cue.start);if(i)assert.equal(cue.start,sound.mouthCues[i-1].end);});
    await assert.rejects(animalSpeech(text,()=>{throw new Error('cancelled');}),/cancelled/);
    if(process.env.WEIBEI_VOICE_SAMPLE)await writeFile(process.env.WEIBEI_VOICE_SAMPLE,bytes);
  }finally{
    globalThis.fetch=original;await rm(folder,{recursive:true});
    if(previousContext)Object.defineProperty(globalThis,'OfflineAudioContext',previousContext);else Reflect.deleteProperty(globalThis,'OfflineAudioContext');
    if(previousWebKit)Object.defineProperty(globalThis,'webkit',previousWebKit);else Reflect.deleteProperty(globalThis,'webkit');
  }
});

test('Reading keeps visible words, strips source IDs, and explicitly skips math and code',()=>{
  const result=speechParagraphs('# 标题\n\n**保留**[原文](weibei-source://private-id)。\n\n<internal_context>私密内部标记</internal_context>\n\n$$x^2$$\n\n```js\nsecretId\n```\n\n'+('长文。'.repeat(300)));
  assert.equal(result.skipped,true);assert.equal(result.paragraphs[0],'标题');
  const text=result.paragraphs.join('');assert.ok(text.includes('保留原文'));assert.ok(!/private-id|私密|secretId|x\^2/.test(text));
  assert.equal(text.match(/长文。/g)?.length,300);assert.ok(result.paragraphs.every(p=>p.length<=350));
});
