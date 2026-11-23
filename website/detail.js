const feedbackForm = document.querySelector('#feedback-form');
const feedbackSubmit = feedbackForm?.querySelector('.feedback-submit');
const feedbackStatus = document.querySelector('#feedback-status');
const repository = 'https://github.com/WroughtMind/weibei';

try {
  const saved = JSON.parse(sessionStorage.getItem('weibei-home-position'));
  if (/^scene-[1-4]$/.test(saved?.scene)) {
    document.querySelectorAll('a[href="index.html"], a[href="index.html#scene-1"], a[href="./"], a[href="./#scene-1"]').forEach(link => {
      link.hash = saved.scene;
    });
  }
} catch {}

function updateFeedbackDestination() {
  if (!feedbackForm || !feedbackSubmit) return;
  const type = new FormData(feedbackForm).get('type');
  const issue = type === 'issue';
  feedbackSubmit.textContent = document.documentElement.lang === 'en'
    ? (issue ? 'Continue to GitHub Issue' : 'Continue to GitHub Discussion')
    : (issue ? '前往 GitHub Issue' : '前往 GitHub Discussion');
}

feedbackForm?.addEventListener('change', event => {
  if (event.target.name === 'type') updateFeedbackDestination();
});

feedbackForm?.addEventListener('submit', event => {
  event.preventDefault();
  const data = Object.fromEntries(new FormData(event.currentTarget));
  const english = document.documentElement.lang === 'en';
  const labels = english
    ? { issue: 'Experience issue', feature: 'Feature request', content: 'Content and copy', other: 'Other' }
    : { issue: '体验问题', feature: '功能建议', content: '内容与表达', other: '其他' };
  const title = `[${labels[data.type]}] ${data.title.trim()}`;
  const body = english
    ? `## Details\n\n${data.message.trim()}\n\nSubmitted from the WeiBei website.`
    : `## 具体内容\n\n${data.message.trim()}\n\n来自魏碑官网反馈页。`;
  const query = new URLSearchParams({ title, body });
  const destination = data.type === 'issue'
    ? `${repository}/issues/new?${query}`
    : `${repository}/discussions/new?category=${data.type === 'other' ? 'general' : 'ideas'}&${query}`;

  feedbackStatus.textContent = english ? 'Opening GitHub…' : '正在打开 GitHub……';
  window.location.assign(destination);
});

updateFeedbackDestination();


if (window.WeiBeiMotion) {
  document.querySelectorAll('a[href^="#"]').forEach(link => {
    link.addEventListener('click', event => {
      if (event.button > 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const target = document.getElementById(link.hash.slice(1));
      if (!target) return;
      event.preventDefault();
      if (link.hash !== location.hash) history.pushState(null, '', link.hash);
      // A native hash navigation moves the keyboard starting point to the
      // section. Preserve that when the animation owns the scroll.
      if (!target.matches('[tabindex], a[href], button, input, select, textarea')) {
        target.setAttribute('tabindex', '-1');
        target.addEventListener('blur', () => target.removeAttribute('tabindex'), { once: true });
      }
      target.focus({ preventScroll: true });
      window.WeiBeiMotion.scrollIntoView(target, { duration: 'lg' });
    });
  });
}
