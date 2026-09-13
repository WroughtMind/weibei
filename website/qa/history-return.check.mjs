// 仅本地测试：在生成的首页 head 中以 module 引入本文件，再进入详情页并后退。
// 返回后执行 await checkHistoryReturn()；同时检查每帧位置和是否发生重复定位。
const nativeScrollTo = window.scrollTo;
const scriptedScrolls = [];
window.scrollTo = function(...args) {
  scriptedScrolls.push({args, before:scrollY});
  return nativeScrollTo.apply(this,args);
};
const key = 'weibei-history-return-test';
addEventListener('pagehide', () => sessionStorage.setItem(key, String(scrollY / (document.documentElement.scrollHeight - innerHeight))));
function record(cached) {
  scriptedScrolls.length = 0;
  window.historyReturnResult = null;
  const expected = Number(sessionStorage.getItem(key)) * (document.documentElement.scrollHeight - innerHeight);
  const frames = [];
  const start = performance.now();
  function sample() {
    frames.push(scrollY);
    if (performance.now() - start < 1500) return requestAnimationFrame(sample);
    window.historyReturnResult = {scriptedScrolls, expected, first:frames[0], last:frames.at(-1), min:Math.min(...frames), max:Math.max(...frames), passed:scriptedScrolls.length === 0 && frames.every(y => Math.abs(y-expected) <= 1), cached};
  }
  requestAnimationFrame(sample);
}
if (performance.getEntriesByType('navigation')[0]?.type === 'back_forward') record(false);
addEventListener('pageshow', event => {if(event.persisted) record(true)});

window.checkHistoryReturn = async () => {
  const start = performance.now();
  while (!window.historyReturnResult) {
    if (performance.now() - start > 4000) throw new Error('没有记录到历史返回');
    await new Promise(requestAnimationFrame);
  }
  if (!window.historyReturnResult.passed) throw new Error(JSON.stringify(window.historyReturnResult));
  return window.historyReturnResult;
};
