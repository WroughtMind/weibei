const languageToggle = document.querySelector('[data-language-toggle]');
const translatable = [...document.querySelectorAll('[data-en]')];
const labelled = [...document.querySelectorAll('[data-en-label]')];
const placeholders = [...document.querySelectorAll('[data-en-placeholder]')];
const feedbackForm = document.querySelector('#feedback-form');
const feedbackSubmit = feedbackForm?.querySelector('.feedback-submit');
const feedbackStatus = document.querySelector('#feedback-status');
const repository = 'https://github.com/WroughtMind/weibei';

translatable.forEach(element => { element.dataset.zh = element.textContent; });
labelled.forEach(element => { element.dataset.zhLabel = element.getAttribute('aria-label'); });
placeholders.forEach(element => { element.dataset.zhPlaceholder = element.getAttribute('placeholder'); });

const setLanguage = language => {
  const english = language === 'en';
  document.documentElement.lang = english ? 'en' : 'zh-CN';
  document.title = english ? document.documentElement.dataset.titleEn : document.documentElement.dataset.titleZh;
  translatable.forEach(element => { element.textContent = english ? element.dataset.en : element.dataset.zh; });
  labelled.forEach(element => { element.setAttribute('aria-label', english ? element.dataset.enLabel : element.dataset.zhLabel); });
  placeholders.forEach(element => { element.setAttribute('placeholder', english ? element.dataset.enPlaceholder : element.dataset.zhPlaceholder); });
  languageToggle.setAttribute('aria-label', english ? '切换为中文' : 'Switch to English');
  languageToggle.setAttribute('aria-pressed', String(english));
  localStorage.setItem('weibei-language', language);
  updateFeedbackDestination();
};

languageToggle.addEventListener('click', () => setLanguage(document.documentElement.lang === 'en' ? 'zh-CN' : 'en'));
setLanguage(localStorage.getItem('weibei-language') === 'en' ? 'en' : 'zh-CN');

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
