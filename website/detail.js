const feedbackForm = document.querySelector('#feedback-form');
const feedbackSubmit = feedbackForm?.querySelector('.feedback-submit');
const feedbackStatus = document.querySelector('#feedback-status');
const repository = 'https://github.com/WroughtMind/weibei';

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

