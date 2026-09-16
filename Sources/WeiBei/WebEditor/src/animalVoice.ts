import { AnimaleseEngine, AudioConverter, MemorySampler, PitchManager } from 'animalese-tts';
import { pinyin } from 'pinyin-pro';

export type SpeechCue = { start:number; end:number; from:number; to:number };
export type MouthCue = { start:number; end:number; phoneme?:string };
type Pack = { sampleRate:number; sprites:Record<string,{startMs:number;durationMs:number}> };
const voiceHost=globalThis as unknown as {WeiBeiChineseVoiceIndex?:Record<string,string>;WeiBeiChineseVoices?:Record<string,Pack>;
  webkit?:{messageHandlers:{voiceResource:{postMessage:(group:string)=>Promise<string>}}}};
const loading=new Map<string,Promise<MemorySampler>>();let indexLoading:Promise<void>|undefined;
const punctuation=/^[\s\p{P}\p{S}]$/u;
const letters=['诶','比','西','迪','伊','艾弗','吉','诶尺','艾','杰','开','艾勒','艾姆','恩','欧','批','丘','阿尔','艾斯','提','优','维','达不溜','艾克斯','歪','贼德'];
const digits='零一二三四五六七八九';
const normalized=(key:string)=>{let value=key.replace(/ü/g,'v').replace(/[05]$/,'1');return /\d$/.test(value)?value:value+'1';};
const script=(path:string)=>new Promise<void>((resolve,reject)=>{
  const node=document.createElement('script');node.src=path;
  const timer=setTimeout(()=>{node.remove();reject(new Error('中文音节资源加载超时：'+path));},15000);
  node.onload=()=>{clearTimeout(timer);node.remove();resolve();};node.onerror=()=>{clearTimeout(timer);node.remove();reject(new Error('中文音节资源未加载：'+path));};document.head.append(node);
});
async function samples(phonemes:string[]){
  if(!voiceHost.WeiBeiChineseVoiceIndex){
    indexLoading ??=script('chinese-voice-index.js').catch(error=>{indexLoading=undefined;throw error;});await indexLoading;
  }
  const index=voiceHost.WeiBeiChineseVoiceIndex;if(!index)throw new Error('中文音节索引缺失');
  const groups=new Set(phonemes.map(raw=>{const key=normalized(raw),group=index[key] ?? index['_'+key];
    if(!group)throw new Error('中文音节缺失：'+key+'。请选用系统语音。');return group;}));
  if(!groups.size)throw new Error('没有可朗读的文字');
  const samplers=await Promise.all(Array.from(groups,group=>{
    if(!loading.has(group))loading.set(group,(async()=>{
      if(!voiceHost.WeiBeiChineseVoices?.[group])await script('chinese-voice-'+group+'.js');
      const pack=voiceHost.WeiBeiChineseVoices?.[group];if(!pack)throw new Error('中文音节包缺失：'+group);
      const encoded=await voiceHost.webkit?.messageHandlers.voiceResource.postMessage(group);
      if(!encoded)throw new Error('本地中文声音资源未就绪');
      const bytes=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));
      const decoded=await new OfflineAudioContext(1,1,pack.sampleRate).decodeAudioData(bytes.buffer);
      const sampler=new MemorySampler(pcmWav([AudioConverter.float32ToInt16(decoded.getChannelData(0))],pack.sampleRate),pack.sprites);
      await sampler.load();delete voiceHost.WeiBeiChineseVoices![group];return sampler;
    })().catch(error=>{loading.delete(group);throw error;}));
    return loading.get(group)!;
  }));
  // MemorySampler shares its named-sample cache; only requested syllable packs are decoded.
  return samplers[0];
}

export function mandarinUnits(text:string){
  let offset=0;
  return pinyin(text,{type:'all',toneType:'num',v:true}).flatMap(part=>{
    const chars=Array.from(part.origin);
    return chars.map(char=>{
      const from=offset;offset+=char.length;
      let phonemes:string[];
      if(part.isZh)phonemes=[part.pinyin];
      else if(/[0-9]/.test(char))phonemes=pinyin(digits[Number(char)],{type:'array',toneType:'num',v:true});
      else if(/[a-z]/i.test(char))phonemes=pinyin(letters[char.toLowerCase().charCodeAt(0)-97],{type:'array',toneType:'num',v:true});
      else if(char==='%'||(char==='.'&&/\d/.test(text[from-1] ?? '')&&/\d/.test(text[offset] ?? '')))phonemes=pinyin(char==='%'?'百分号':'点',{type:'array',toneType:'num',v:true});
      else if(punctuation.test(char))phonemes=[];
      else throw new Error('动物语暂不支持这个字符：'+char+'。可以选择系统语音。');
      return {text:char,from,to:offset,phonemes};
    });
  });
}

export function pcmWav(parts:Int16Array[],rate:number):Uint8Array {
  const count=parts.reduce((n,p)=>n+p.length,0),bytes=new Uint8Array(44+count*2),view=new DataView(bytes.buffer);
  const word=(offset:number,value:string)=>{for(let i=0;i<value.length;i++)bytes[offset+i]=value.charCodeAt(i);};
  word(0,'RIFF');view.setUint32(4,36+count*2,true);word(8,'WAVEfmt ');view.setUint32(16,16,true);
  view.setUint16(20,1,true);view.setUint16(22,1,true);view.setUint32(24,rate,true);view.setUint32(28,rate*2,true);
  view.setUint16(32,2,true);view.setUint16(34,16,true);word(36,'data');view.setUint32(40,count*2,true);
  let i=44;for(const part of parts)for(const sample of part){view.setInt16(i,sample,true);i+=2;}return bytes;
}
export function audioDataURL(bytes:Uint8Array){
  let raw='';for(let i=0;i<bytes.length;i+=8192)raw+=String.fromCharCode(...bytes.subarray(i,i+8192));
  return 'data:audio/wav;base64,'+btoa(raw);
}

export async function animalSpeech(text:string,checkCanceled:()=>void){
  const units=mandarinUnits(text);checkCanceled();
  const sampler=await samples(units.flatMap(u=>u.phonemes));checkCanceled();
  const parts:Int16Array[]=[],cues:SpeechCue[]=[],mouthCues:MouthCue[]=[],rate=sampler.sampleRate!;
  let sampleCount=0,position=0,key='';
  const pitch=new PitchManager({pitch:1.8,speed:2.9,randomness:0,melodyRate:.12,melodyAmplitude:.14});
  const engine=new AnimaleseEngine({sampler,analyzer:{analyze:()=>[[{phoneme:key,mergeWithNext:false}]]},
    effect:{calculatePitch:()=>pitch.calculatePitch(position++),apply:(buffer,ratio)=>pitch.apply(buffer,ratio)}});
  for(const unit of units){
    checkCanceled();const start=sampleCount/rate;
    if(!unit.phonemes.length){
      const silence=new Int16Array(Math.round(rate*(/[，。！？；：,.!?;:\n]/.test(unit.text)?.18:.04)));
      parts.push(silence);sampleCount+=silence.length;
      mouthCues.push({start,end:sampleCount/rate});
    }
    for(const phoneme of unit.phonemes){
      const phonemeStart=sampleCount/rate;
      // Upstream explicitly removed tone-5 files because they duplicated tone 1.
      key=normalized(phoneme);
      if(!sampler.isCached(key)&&sampler.isCached('_'+key))key='_'+key;
      if(!sampler.isCached(key))throw new Error('中文音节缺失：'+key+'。请选用系统语音。');
      // One phoneme per synthesis avoids the library's sentence-level sample-skipping heuristic.
      for await(const output of engine.synthesize(unit.text,true).speak()){
        checkCanceled();if(!output.buffer.length)throw new Error('中文音节合成为空：'+key);
        const buffer=output.buffer as Int16Array;parts.push(buffer);sampleCount+=buffer.length;
      }
      mouthCues.push({start:phonemeStart,end:sampleCount/rate,phoneme:key});
    }
    cues.push({start,end:sampleCount/rate,from:unit.from,to:unit.to});
  }
  checkCanceled();if(!sampleCount)throw new Error('没有可朗读内容');
  return {url:audioDataURL(pcmWav(parts,rate)),cues,mouthCues,duration:sampleCount/rate};
}

/** Timing is measured from synthesized samples, then driven by the actual media clock. */
export function speechCaption(audio:HTMLAudioElement,text:string,cues:SpeechCue[]){
  const node=document.createElement('div');node.className='speech-caption';node.setAttribute('aria-label','讲稿字幕');
  const spans=cues.map(c=>{const span=document.createElement('span');span.textContent=text.slice(c.from,c.to);node.append(span);return span;});
  document.body.append(node);let frame=0,closed=false;
  const update=()=>{if(closed)return;const t=audio.currentTime;
    spans.forEach((s,i)=>{s.style.opacity=t>=cues[i].start?'1':'.32';s.classList.toggle('speaking',t>=cues[i].start&&t<cues[i].end);});
    if(!audio.paused&&!audio.ended)frame=requestAnimationFrame(update);
  };
  const start=()=>{cancelAnimationFrame(frame);update();};
  audio.addEventListener('playing',start);audio.addEventListener('timeupdate',start);audio.addEventListener('seeked',start);
  return ()=>{closed=true;cancelAnimationFrame(frame);audio.removeEventListener('playing',start);audio.removeEventListener('timeupdate',start);audio.removeEventListener('seeked',start);node.remove();};
}
