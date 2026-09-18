# 官网 SEO 与中英文页面

官网源文件仍为 `website/*.html`。中文正文及现有 `data-en` 翻译一起维护；`website/seo/build.py` 在部署前生成独立的中文页面与 `/en/` 英文页面。语言链接是普通超链接，不依赖 JavaScript、浏览器语言或 localStorage。英文资源复用上一级 CSS、脚本和图片；下载信息相对于 `app.js` 加载。

运行与部署使用同一个命令：

```bash
bash script/check_website.sh
python3 -m http.server 8000 --directory _site
```

该命令检查脚本与安装包匹配，生成并检查 12 个页面、sitemap、404 和分享元数据。不要直接把源目录当作发布产物；英文页面和 SEO 头部在 `_site` 中。源码与检查文件不进入发布目录。新页面须在 `pages.json` 注册中英文标题和摘要，并提供可见的正文与站内入口。`data-en` 只用于纯文本元素；含链接等子元素时分别标注，避免翻译抹掉结构。

## 这次改变

- 首页保留四幕结构，原标语升级为唯一 H1，在原文案区加入简短产品说明与「了解魏碑」入口。
- 增加中英文使用介绍，内容来自当前 README、隐私说明与 FAQ：文件格式、原文引用、Markdown 笔记、本地数据、可选 AI、Mac 要求与源码运行。
- 每页独立 title/description、self-canonical、双向 hreflang 与 x-default；导航优先使用规范首页路径。
- Open Graph 与 Twitter 大图元数据复用已有 `DesignSystem/assets/social/weibei-og-1200x630.png` 品牌图，复制到官网自身域名下；统一 favicon 与触屏图标。
- JSON-LD 描述 WebSite、WroughtMind、WebPage、SoftwareApplication 和详情页面包屑。没有虚构价格、评分、评价或正式发布版本；SoftwareApplication 的语义标记不代表符合 Google 应用富结果的全部要求。
- 响应式首屏预加载与图片 srcset 一致；首页与介绍页图片使用实际尺寸预留空间。保留现有品牌字体及动画。
- sitemap 仅包含规范的可索引页面；不编造 lastmod，不把抓取时间或每次部署时间当内容修改时间。404 保持真正的错误页，不跳到首页，并声明 noindex。

## 上线后的收录与测量

正式地址目前为 `https://wroughtmind.github.io/weibei/`，来自仓库 README。域名变更时同时更新 `build.py` 的 SITE_URL、检查中的 URL 约束和相应品牌链接。

1. 在 Google Search Console 中验证 URL-prefix 属性 `https://wroughtmind.github.io/weibei/`，提交 `https://wroughtmind.github.io/weibei/sitemap.xml`；用 URL Inspection 检查中文首页、英文首页、介绍页与 FAQ。站点所有者提供的验证文件可放在 website 根目录，构建会保留它。没有实际验证令牌时不要添加占位验证码。
2. Bing Webmaster Tools 可验证同一网站并提交同一 sitemap。提交记录与账号数据需在各自站长工具中确认，代码检查不代表已经提交或收录。
3. GitHub 项目 Pages 下生成的 `/weibei/robots.txt` 不会被当作域名根抓取规则。抓取规则只在 `https://wroughtmind.github.io/robots.txt` 生效；如以后维护组织主页，可在那里声明 sitemap。目前通过 sitemap、页面链接及站长工具完成发现，不修改其他仓库或全域抓取策略。
4. 部署后测量真实页面的移动端 LCP、CLS、INP，观察 Search Console 的收录、查询词、曝光和点击。重点比较 weibei / 魏碑、Mac PDF 阅读、Mac Markdown 笔记与相应英文查询。没有测量数据时不宣称 Lighthouse 满分、排名上升或一定收录。

参考：[Google 多语言网址](https://developers.google.com/search/docs/specialty/international/managing-multi-regional-sites)、[hreflang](https://developers.google.com/search/docs/specialty/international/localized-versions)、[站点地图](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)、[robots 作用范围](https://developers.google.com/crawling/docs/robots-txt/robots-txt-spec)、[应用结构化数据](https://developers.google.com/search/docs/appearance/structured-data/software-app)。
