import { unified } from 'unified';
import remarkParse from 'remark-parse';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import type * as Voice from './animalVoice';
const voice = () => (globalThis as unknown as {WeiBeiVoice:typeof Voice}).WeiBeiVoice;
import { createWebiCompanion, webiMouthForPinyin } from './webiCompanion';
import type { Root, RootContent } from 'mdast';

export function speechParagraphs(markdown:string){
  const clean=markdown.replace(/<(?:weibei_context|context|internal_context|system_reminder)\b[^>]*>[\s\S]*?<\/(?:weibei_context|context|internal_context|system_reminder)>/gi,'')
    .replace(/[^]*/g,'');
  const tree=unified().use(remarkParse).use(remarkGfm).use(remarkMath).parse(clean) as Root;
  let skipped=false;
  const plain=(node:RootContent):string=>{
    if(['code','inlineCode','math','inlineMath'].includes(node.type)){skipped=true;return ' ';}
    if(['html','definition','footnoteDefinition'].includes(node.type))return '';
    if(node.type==='text')return node.value;
    if(node.type==='image')return node.alt ?? '';
    if('children' in node)return node.children.map(n=>plain(n as RootContent)).join(node.type==='paragraph'?'':' ');
    return '';
  };
  const paragraphs=tree.children.flatMap(node=>{
    const text=plain(node).replace(/[ \t]+/g,' ').trim(),chunks:string[]=[];
    // Each paragraph is synthesized on demand; long paragraphs split without rewriting their words.
    for(let start=0;start<text.length;){
      let end=Math.min(start+350,text.length);
      if(end<text.length&&/[\uD800-\uDBFF]/.test(text[end-1]))end--;
      chunks.push(text.slice(start,end));start=end;
    }return chunks;
  });
  return {paragraphs,skipped};
}

if(typeof window!=='undefined'){
  const audio=document.querySelector('audio')!;
  const companion=createWebiCompanion(document.getElementById('webi-host')!);
  let run='',rejectPlay:((error:Error)=>void)|undefined,paused=false;
  const api={
    prepare(markdown:string){return speechParagraphs(markdown);},
    async play(text:string,mode:string,speed:number,id:string,cloud:string){
      run=id;const start=performance.now();
      const valid=()=>{if(run!==id)throw new Error('朗读已停止');if(performance.now()-start>30000)throw new Error('中文动物语合成超时，请重试。');};
      const local=mode==='animalese'?await voice().animalSpeech(text,valid):undefined;valid();
      const url=local?.url ?? cloud;if(!url)throw new Error('音频为空');
      audio.src=url;audio.playbackRate=speed;audio.preservesPitch=true;
      const detachWebi=companion.followAudio(audio,local?.mouthCues ?? []);
      let watchdog:ReturnType<typeof setInterval>|undefined,lastTime=0,lastProgress=performance.now();
      try{await new Promise<void>((resolve,reject)=>{
        rejectPlay=reject;audio.onended=()=>{if(run===id)resolve();};audio.onerror=()=>reject(new Error('音频播放失败'));
        audio.onplaying=()=>{if(run===id)(window as any).webkit.messageHandlers.readingVoice.postMessage({type:'playing',run:id});};
        watchdog=setInterval(()=>{
          if(paused||audio.currentTime!==lastTime){lastProgress=performance.now();lastTime=audio.currentTime;}
          else if(performance.now()-lastProgress>15000)reject(new Error('音频播放停滞，请重试。'));
        },500);
        if(!paused)void audio.play().catch(reject);
      });}finally{clearInterval(watchdog);detachWebi();if(run===id){audio.pause();rejectPlay=undefined;audio.onended=null;audio.onerror=null;audio.onplaying=null;}}
    },
    systemStarted(id:string,value:boolean){run=id;paused=value;companion.setPaused(paused);companion.setAction('talk');},
    systemBoundary(text:string,id:string){if(run!==id)return;
      try{const phoneme=voice().mandarinUnits(text).flatMap(u=>u.phonemes)[0];companion.setMouth(phoneme?webiMouthForPinyin(phoneme):0);}catch{companion.setMouth(0);}
    },
    systemFinished(id:string){if(run===id){companion.setMouth(0);companion.setAction('idle');}},
    visible(value:boolean){companion.setCollapsed(!value);},
    pause(value:boolean,id:string){if(run!==id)return;paused=value;companion.setPaused(value);if(value)audio.pause();else if(audio.getAttribute('src'))void audio.play().catch(e=>rejectPlay?.(e));},
    stop(id:string){if(run!==id)return;run='';paused=false;companion.setPaused(false);companion.setMouth(0);companion.setAction('idle');audio.pause();audio.removeAttribute('src');audio.load();rejectPlay?.(new Error('朗读已停止'));rejectPlay=undefined;},
  };
  (window as any).WeiBeiReadingVoice=api;
  (window as any).webkit.messageHandlers.readingVoice.postMessage({type:'ready'});
}
