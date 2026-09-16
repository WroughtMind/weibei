import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile, writeFile } from 'node:fs/promises';
import vm from 'node:vm';
import { animalSpeech, mandarinUnits } from '../src/animalVoice';
import { speechParagraphs } from '../src/readingVoice';

test('Chinese offline synthesis retains character boundaries, punctuation and cancellation',async()=>{
  const scope={window:{} as Record<string,unknown>};
  const text='重庆银行的2.5%，OLS，重新比较残差。';
  vm.runInNewContext(await readFile('Sources/WeiBei/Resources/Editor/chinese-voice-index.js','utf8'),scope);
  const index=scope.window.WeiBeiChineseVoiceIndex as Record<string,string>;
  for(const group of new Set(mandarinUnits(text).flatMap(u=>u.phonemes).map(key=>index[key.replace(/[05]$/,'1')]))){
    assert.ok(group);vm.runInNewContext(await readFile('Sources/WeiBei/Resources/Editor/ChineseVoice/'+group+'.js','utf8'),scope);
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
  }finally{globalThis.fetch=original;}
});

test('Reading keeps visible words, strips source IDs, and explicitly skips math and code',()=>{
  const result=speechParagraphs('# 标题\n\n**保留**[原文](weibei-source://private-id)。\n\n<internal_context>私密内部标记</internal_context>\n\n$$x^2$$\n\n```js\nsecretId\n```\n\n'+('长文。'.repeat(300)));
  assert.equal(result.skipped,true);assert.equal(result.paragraphs[0],'标题');
  const text=result.paragraphs.join('');assert.ok(text.includes('保留原文'));assert.ok(!/private-id|私密|secretId|x\^2/.test(text));
  assert.equal(text.match(/长文。/g)?.length,300);assert.ok(result.paragraphs.every(p=>p.length<=350));
});
