"""Check the generated crawl/navigation contract, not source strings or wording."""
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urljoin, urlsplit
from xml.etree import ElementTree as ET
from build import Document, Element, PAGES, SITE_URL, route

site = Path(sys.argv[1]).resolve()
expected = {SITE_URL + route(name, lang) for lang in ('zh-CN', 'en') for name in PAGES}
pages = {}

def local_file(url):
    parsed = urlsplit(url)
    base = urlsplit(SITE_URL)
    if parsed.netloc != base.netloc or not parsed.path.startswith(base.path):
        return None
    path = unquote(parsed.path[len(base.path):])
    if not path or path.endswith('/'):
        path += 'index.html'
    result = (site / path).resolve()
    assert result.is_relative_to(site), f'URL escapes deployment: {url}'
    return result

def nodes(document, tag, **attrs):
    return [n for n in document.root.walk() if n.tag == tag and all(n.attrs.get(k) == v for k, v in attrs.items())]

for url in sorted(expected):
    path = local_file(url)
    document = Document(path.read_text())
    pages[url] = document
    assert len(nodes(document, 'h1')) == 1, f'{url}: missing or duplicate primary heading'
    assert len(nodes(document, 'main')) == 1, f'{url}: missing main landmark'
    assert len(nodes(document, 'title')) == 1
    assert len(nodes(document, 'meta', name='description')) == 1
    assert nodes(document, 'meta', name='description')[0].attrs['content'].strip()
    assert len(nodes(document, 'link', rel='canonical')) == 1
    assert nodes(document, 'link', rel='canonical')[0].attrs['href'] == url
    assert nodes(document, 'meta', property='og:url')[0].attrs['content'] == url
    assert 'noindex' not in nodes(document, 'meta', name='robots')[0].attrs['content']
    language = nodes(document, 'html')[0].attrs['lang']
    assert language == ('en' if '/weibei/en/' in url else 'zh-CN')
    alts = {n.attrs['hreflang']: n.attrs['href'] for n in nodes(document, 'link', rel='alternate')}
    assert set(alts) == {'zh-CN', 'en', 'x-default'}
    assert alts[language] == url and alts['x-default'] == alts['zh-CN']
    assert set(alts.values()) <= expected
    switches = [n for n in nodes(document, 'a') if 'data-language-toggle' in n.attrs]
    assert len(switches) == 1
    assert urljoin(url, switches[0].attrs['href']) == alts['zh-CN' if language == 'en' else 'en']
    graph = json.loads(nodes(document, 'script', type='application/ld+json')[0].children[0])['@graph']
    page = next(n for n in graph if n['@type'] == 'WebPage')
    assert page['url'] == url and page['inLanguage'] == language
    # No fabricated offers, ratings, or reviews are needed to describe this app.
    for item in graph:
        assert not {'aggregateRating', 'review', 'offers'} & item.keys()
    for tag, attr in [('a', 'href'), ('script', 'src'), ('link', 'href'), ('img', 'src')]:
        for node in nodes(document, tag):
            value = node.attrs.get(attr, '')
            if not value:
                continue
            target = local_file(urljoin(url, value))
            if target and target.suffix == '.html':
                assert target.is_file(), f'{url}: missing page {value}'
                fragment = urlsplit(value).fragment
                if fragment:
                    destination = Document(target.read_text())
                    assert any(n.attrs.get('id') == fragment for n in destination.root.walk()), f'{url}: broken anchor {value}'
            elif target and tag in ('script', 'link'):
                assert target.is_file() and target.stat().st_size, f'{url}: missing resource {value}'
    for image in nodes(document, 'img'):
        assert 'alt' in image.attrs, f'{url}: image needs an alt decision'
        for attr in ('src', 'srcset'):
            for entry in image.attrs.get(attr, '').split(','):
                value = entry.strip().split(' ')[0]
                if not value:
                    continue
                resolved = urljoin(url, value)
                assert urlsplit(resolved).path.startswith('/weibei/assets/'), f'{url}: localized image resolved outside shared assets: {value}'
    for key in ('og:image',):
        image_path = local_file(nodes(document, 'meta', property=key)[0].attrs['content'])
        assert image_path.is_file() and image_path.stat().st_size

for url, document in pages.items():
    for alternate in nodes(document, 'link', rel='alternate'):
        other = pages[alternate.attrs['href']]
        assert url in [n.attrs['href'] for n in nodes(other, 'link', rel='alternate')], f'{url}: nonreciprocal language link'

# Search engines should discover only canonical, indexable HTML pages.
sitemap = ET.parse(site / 'sitemap.xml')
listed = [n.text for n in sitemap.iter() if n.tag.endswith('loc')]
assert len(listed) == len(set(listed)) and set(listed) == expected
assert SITE_URL + 'sitemap.xml' in (site / 'robots.txt').read_text()
error = Document((site / '404.html').read_text())
assert 'noindex' in nodes(error, 'meta', name='robots')[0].attrs['content']
assert not (site / 'seo').exists() and not (site / 'qa').exists()
assert not list(site.glob('*.test.mjs')) and not list(site.glob('*.check.js'))
print(f'PASS: {len(pages)} pages; canonical/hreflang, no-JS HTML, schema, navigation, shared asset URLs, social assets, sitemap and 404.')
