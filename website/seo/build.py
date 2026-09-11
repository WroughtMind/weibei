"""Compile crawlable bilingual HTML with Python's standard library only."""
from html import escape
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import sys
from urllib.parse import urlsplit
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'website'
SITE_URL = 'https://wroughtmind.github.io/weibei/'
REPO = 'https://github.com/WroughtMind/weibei'
PAGES = json.loads((SOURCE / 'seo/pages.json').read_text())
VOID = set('area base br col embed hr img input link meta param source track wbr'.split())

class Element:
    def __init__(self, tag='', attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []
    def html(self):
        inner = ''.join(c.html() if isinstance(c, Element) else c for c in self.children)
        if not self.tag:
            return inner
        attrs = ''.join(' ' + k + ('' if v is None else '="' + escape(v, quote=True) + '"') for k, v in self.attrs.items())
        return '<' + self.tag + attrs + '>' + ('' if self.tag in VOID else inner + '</' + self.tag + '>')
    def walk(self):
        yield self
        for child in self.children:
            if isinstance(child, Element):
                yield from child.walk()

class Document(HTMLParser):
    def __init__(self, source):
        super().__init__(convert_charrefs=False)
        self.root = Element()
        self.stack = [self.root]
        self.feed(source)
        self.close()
    def handle_starttag(self, tag, attrs):
        node = Element(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in VOID:
            self.stack.append(node)
    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if tag not in VOID:
            self.handle_endtag(tag)
    def handle_endtag(self, tag):
        if self.stack[-1].tag != tag:
            raise ValueError(f'Unbalanced HTML: {tag}, expected {self.stack[-1].tag}')
        self.stack.pop()
    def handle_data(self, data):
        self.stack[-1].children.append(data)
    def handle_entityref(self, name):
        self.handle_data('&' + name + ';')
    def handle_charref(self, name):
        self.handle_data('&#' + name + ';')
    def handle_comment(self, data):
        self.handle_data('<!--' + data + '-->')
    def handle_decl(self, data):
        self.handle_data('<!' + data + '>')

def route(name, language):
    return ('en/' if language == 'en' else '') + ('' if name == 'index.html' else name)

def metadata(name, language):
    title, description = PAGES[name][language]
    url = SITE_URL + route(name, language)
    english = language == 'en'
    locale = 'en_US' if english else 'zh_CN'
    image = SITE_URL + 'assets/social-preview.png'
    tags = [Element('title'), Element('meta', [('name', 'description'), ('content', description)]),
            Element('link', [('rel', 'canonical'), ('href', url)]),
            Element('meta', [('name', 'robots'), ('content', 'index,follow,max-image-preview:large')])]
    tags[0].children = [escape(title)]
    for lang in ('zh-CN', 'en', 'x-default'):
        tags.append(Element('link', [('rel', 'alternate'), ('hreflang', lang), ('href', SITE_URL + route(name, 'zh-CN' if lang == 'x-default' else lang))]))
    for key, value in {'type': 'website', 'site_name': 'WeiBei · 魏碑', 'title': title, 'description': description, 'url': url, 'locale': locale, 'locale:alternate': 'zh_CN' if english else 'en_US', 'image': image, 'image:width': '1200', 'image:height': '630', 'image:type': 'image/png', 'image:alt': 'WeiBei — read, ask, and write at one desk.' if english else '魏碑：读、问、写，在同一张桌面。'}.items():
        tags.append(Element('meta', [('property', 'og:' + key), ('content', value)]))
    for key, value in {'card': 'summary_large_image', 'title': title, 'description': description, 'image': image, 'image:alt': 'WeiBei brand illustration' if english else '魏碑品牌插画'}.items():
        tags.append(Element('meta', [('name', 'twitter:' + key), ('content', value)]))
    for rel, href, kind in [('icon', 'favicon.ico', 'image/x-icon'), ('icon', 'favicon.svg', 'image/svg+xml'), ('apple-touch-icon', 'apple-touch-icon.png', 'image/png')]:
        tags.append(Element('link', [('rel', rel), ('href', SITE_URL + href), ('type', kind)]))
    tags.append(Element('link', [('rel', 'sitemap'), ('type', 'application/xml'), ('href', SITE_URL + 'sitemap.xml')]))
    graph = [
        {'@type': 'Organization', '@id': SITE_URL + '#organization', 'name': 'WroughtMind', 'url': 'https://github.com/WroughtMind', 'sameAs': ['https://github.com/WroughtMind']},
        {'@type': 'WebSite', '@id': SITE_URL + '#website', 'url': SITE_URL, 'name': 'WeiBei', 'alternateName': ['weibei', '魏碑'], 'inLanguage': ['zh-CN', 'en'], 'publisher': {'@id': SITE_URL + '#organization'}},
        {'@type': 'WebPage', '@id': url + '#webpage', 'url': url, 'name': title, 'description': description, 'inLanguage': language, 'isPartOf': {'@id': SITE_URL + '#website'}, 'about': {'@id': SITE_URL + '#app'}}
    ]
    if name in ('index.html', 'guide.html'):
        graph.append({'@type': 'SoftwareApplication', '@id': SITE_URL + '#app', 'name': 'WeiBei', 'alternateName': ['weibei', '魏碑'], 'url': SITE_URL, 'applicationCategory': 'ProductivityApplication', 'operatingSystem': 'macOS 14 or later', 'description': PAGES['index.html'][language][1], 'image': image, 'screenshot': SITE_URL + 'assets/第二幕-真实三窗截图-去黑边.webp', 'publisher': {'@id': SITE_URL + '#organization'}, 'sameAs': [REPO]})
    if name != 'index.html':
        graph.append({'@type': 'BreadcrumbList', '@id': url + '#breadcrumb', 'itemListElement': [{'@type': 'ListItem', 'position': 1, 'name': 'WeiBei', 'item': SITE_URL + route('index.html', language)}, {'@type': 'ListItem', 'position': 2, 'name': title, 'item': url}]})
        graph[2]['breadcrumb'] = {'@id': url + '#breadcrumb'}
    node = Element('script', [('type', 'application/ld+json')])
    node.children = [json.dumps({'@context': 'https://schema.org', '@graph': graph}, ensure_ascii=False).replace('<', '\\u003c')]
    return '\n'.join(n.html() for n in tags + [node])

def compile_page(name, language):
    document = Document((SOURCE / name).read_text())
    english = language == 'en'
    for node in list(document.root.walk()):
        attrs = node.attrs
        if node.tag == 'html':
            attrs['lang'] = language
        if english:
            if 'data-en' in attrs:
                if any(isinstance(child, Element) for child in node.children):
                    raise ValueError(f'{name}: data-en must annotate a text-only element')
                node.children = [escape(attrs['data-en'])]
            for suffix, target in [('label', 'aria-label'), ('placeholder', 'placeholder'), ('alt', 'alt'), ('title', 'title')]:
                if 'data-en-' + suffix in attrs:
                    attrs[target] = attrs['data-en-' + suffix]
            if 'data-submit-en' in attrs:
                node.children = [escape(attrs['data-submit-en'])]
        if 'data-language-toggle' in attrs:
            attrs.update(href=('../' + ('' if name == 'index.html' else name)) if english else 'en/' + ('' if name == 'index.html' else name), hreflang='zh-CN' if english else 'en', lang='zh-CN' if english else 'en')
            attrs['aria-label'] = '切换为中文' if english else 'Switch to English'
        else:
            for key in ('href', 'src'):
                value = attrs.get(key, '')
                if value.startswith('index.html'):
                    attrs[key] = './' + value[len('index.html'):]
                elif english and value and not urlsplit(value).scheme and not value.startswith(('#', '/', '../')) and not value.split('#')[0].split('?')[0].endswith('.html'):
                    attrs[key] = '../' + value
            if english:
                for key in ('srcset', 'imagesrcset'):
                    if key in attrs:
                        attrs[key] = ', '.join('../' + entry.strip() for entry in attrs[key].split(','))
        # Translation lives in static HTML, never in a second client-side state.
        for key in list(attrs):
            if key.startswith(('data-en', 'data-title-', 'data-submit-')):
                del attrs[key]
    head = next(n for n in document.root.walk() if n.tag == 'head')
    head.children = [n for n in head.children if not isinstance(n, Element) or not (n.tag == 'title' or (n.tag == 'meta' and n.attrs.get('name') == 'description') or (n.tag == 'link' and n.attrs.get('rel') == 'icon'))]
    head.children.append(metadata(name, language))
    return document.root.html()

def build(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for language in ('zh-CN', 'en'):
        for name in PAGES:
            target = destination / ('en' if language == 'en' else '') / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(compile_page(name, language))
    ET.register_namespace('', 'http://www.sitemaps.org/schemas/sitemap/0.9')
    root = ET.Element('{http://www.sitemaps.org/schemas/sitemap/0.9}urlset')
    for language in ('zh-CN', 'en'):
        for name in PAGES:
            node = ET.SubElement(root, 'url')
            ET.SubElement(node, 'loc').text = SITE_URL + route(name, language)
    ET.ElementTree(root).write(destination / 'sitemap.xml', encoding='utf-8', xml_declaration=True)
    # On project Pages this is /weibei/robots.txt, not the origin robots policy.
    (destination / 'robots.txt').write_text('User-agent: *\nAllow: /\n\nSitemap: ' + SITE_URL + 'sitemap.xml\n')
    (destination / '404.html').write_text('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,follow"><title>Page not found · WeiBei</title></head><body><main><h1>Page not found / 页面未找到</h1><p><a href="' + SITE_URL + '">魏碑首页</a> · <a href="' + SITE_URL + 'en/">WeiBei home</a></p></main></body></html>')
    for path in destination.glob('*.test.mjs'):
        path.unlink()
    for path in destination.glob('*.check.js'):
        path.unlink()
    shutil.rmtree(destination / 'seo', ignore_errors=True)
    print(f'Built {len(PAGES) * 2} localized pages, sitemap, robots discovery file and 404.')

if __name__ == '__main__':
    build(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / '_site')
