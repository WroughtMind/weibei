// 从仓库根目录启动本地服务后，在首页控制台运行：await (await import('/website/qa/brand.check.mjs')).checkBrandRendering()
export async function checkBrandRendering() {
  await document.fonts.ready;
  const brand = document.querySelector('.compact-brand');
  const bounds = brand.getBoundingClientRect();
  const scale = bounds.width / brand.offsetWidth;
  if (scale > 1.01) throw new Error('字标的小尺寸合成缓存被放大，会在 Safari 中发虚');
  const actions = document.querySelector('.top-actions').getBoundingClientRect();
  if (bounds.top < 72 && bounds.right > actions.left) throw new Error('字标遮挡导航操作');
  if (document.documentElement.scrollWidth > innerWidth) throw new Error('页面横向溢出');
  const background = document.querySelector('.giant-webi');
  await background.decode();
  const box = background.getBoundingClientRect();
  if (box.width) {
    const ratio = background.naturalWidth / background.naturalHeight;
    if (Math.abs(box.width / box.height - ratio) > .01) throw new Error('灰色 Webi 背景没有保持原图比例');
  }
  return { brandScale: scale, backgroundRatio: 'passed', navigation: 'passed' };
}
