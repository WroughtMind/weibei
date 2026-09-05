const viewer = document.querySelector('.webi-viewer');
const fullImage = viewer.querySelector('.webi-full');
const caption = viewer.querySelector('#webi-caption');
const original = viewer.querySelector('.webi-original');

document.querySelectorAll('[data-artwork]').forEach(link => {
  link.addEventListener('click', event => {
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    caption.textContent = link.closest('figure').querySelector('figcaption').textContent;
    fullImage.alt = caption.textContent;
    fullImage.src = link.href;
    original.href = link.href;
    viewer.showModal();
  });
});

viewer.querySelector('.webi-close').addEventListener('click', () => viewer.close());
viewer.addEventListener('click', event => { if (event.target === viewer) viewer.close(); });
viewer.addEventListener('close', () => fullImage.removeAttribute('src'));
