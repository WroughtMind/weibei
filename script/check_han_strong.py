"""Check the same cmark delimiter parser used by both Catalyst chat surfaces."""
import json
from pathlib import Path
import subprocess
import sys

cases = [
    ('好，那我给你讲一个**“两间更衣室之间的一通电话”**。', '<p>好，那我给你讲一个<strong>“两间更衣室之间的一通电话”</strong>。</p>'),
    ('这是**“重点”**内容', '<p>这是<strong>“重点”</strong>内容</p>'),
    ('这是**重点：**内容', '<p>这是<strong>重点：</strong>内容</p>'),
    ('这是**《书名》**内容', '<p>这是<strong>《书名》</strong>内容</p>'),
    ('这是***“重点”***内容', '<p>这是<em><strong>“重点”</strong></em>内容</p>'),
    ('这是**[“链接”](https://example.com)**内容', '<p>这是<strong><a href="https://example.com">“链接”</a></strong>内容</p>'),
    ('𠀀**“重点”**𠀀', '<p>𠀀<strong>“重点”</strong>𠀀</p>'),
    ('这是**普通加粗**内容', '<p>这是<strong>普通加粗</strong>内容</p>'),
    ('a**“word”**b', '<p>a**“word”**b</p>'),
    ('a **word** b', '<p>a <strong>word</strong> b</p>'),
    ('这是** “重点” **内容', '<p>这是<strong> “重点” </strong>内容</p>'),
    ('这是**“还没结束', '<p>这是**“还没结束</p>'),
    (r'这是\*\*“原样”\*\*内容', '<p>这是**“原样”**内容</p>'),
    ('`这是**“代码”**内容`', '<p><code>这是**“代码”**内容</code></p>'),
    ('```\n这是**“代码”**内容\n```', '<pre><code>这是**“代码”**内容\n</code></pre>'),
    ('[链接](https://example.com/这是**“路径”**内容)', '<p><a href="https://example.com/%E8%BF%99%E6%98%AF**%E2%80%9C%E8%B7%AF%E5%BE%84%E2%80%9D**%E5%86%85%E5%AE%B9">链接</a></p>'),
]

# The screenshot, Unicode padding, Chinese punctuation, containers and nesting.
cases += [
    ('**加拿大： **多伦多、温哥华', '<p><strong>加拿大： </strong>多伦多、温哥华</p>'),
    ('**Canada: **Toronto', '<p><strong>Canada: </strong>Toronto</p>'),
    ('** 加粗**内容', '<p><strong> 加粗</strong>内容</p>'),
    ('** 加粗 **', '<p><strong> 加粗 </strong></p>'),
    ('**label: **nested** tail**', '<p><strong>label: nested tail</strong></p>'),
    ('**一个** 普通 **另一个**', '<p><strong>一个</strong> 普通 <strong>另一个</strong></p>'),
    ('**外层 *内斜* 结束**', '<p><strong>外层 <em>内斜</em> 结束</strong></p>'),
    ('**标签： **正文 **正常**', '<p><strong>标签： </strong>正文 <strong>正常</strong></p>'),
    ('**  **', '<hr />'),
    ('段落 **  ** 文本', '<p>段落 **  ** 文本</p>'),
    ('**未完成 \n**下一行', '<p>**未完成\n**下一行</p>'),
    (r'\*\*加拿大： \*\*多伦多', '<p>**加拿大： **多伦多</p>'),
    ('`**加拿大： **多伦多`', '<p><code>**加拿大： **多伦多</code></p>'),
    ('```md\n**加拿大： **多伦多\n```', '<pre><code class="language-md">**加拿大： **多伦多\n</code></pre>'),
    ('    **加拿大： **多伦多', '<pre><code>**加拿大： **多伦多\n</code></pre>'),
    ('[**标签： **链接](https://example.com)', '<p><a href="https://example.com"><strong>标签： </strong>链接</a></p>'),
    ('[代码](https://example.com "**标题： **原样")', '<p><a href="https://example.com" title="**标题： **原样">代码</a></p>'),
]
cases.append((
    '| 地点 |\n| --- |\n| **加拿大： **多伦多 |',
    '<table>\n<thead>\n<tr>\n<th>地点</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td><strong>加拿大： </strong>多伦多</td>\n</tr>\n</tbody>\n</table>',
))
for pad in [' ', '\t', '\u00a0', '\u3000']:
    for marker in ['**', '__']:
        source = marker + '加拿大：' + pad + marker + '多伦多'
        rendered = '<strong>加拿大：' + pad + '</strong>多伦多'
        cases += [
            (source, '<p>' + rendered + '</p>'),
            ('- ' + source, '<ul>\n<li>' + rendered + '</li>\n</ul>'),
            ('1. ' + source, '<ol>\n<li>' + rendered + '</li>\n</ol>'),
            ('> ' + source, '<blockquote>\n<p>' + rendered + '</p>\n</blockquote>'),
        ]
for marker, tag in [('**', 'strong'), ('__', 'strong'), ('*', 'em'), ('_', 'em'), ('~~', 'del')]:
    for quoted in ['“重点”', '「重点」', '《重点》', '重点：', '（重点）']:
        cases.append(('中文' + marker + quoted + marker + '继续', '<p>中文<' + tag + '>' + quoted + '</' + tag + '>继续</p>'))

for marker, tag in [('**', 'strong'), ('*', 'em'), ('~~', 'del')]:
    for quoted in ['（重点）', '「重点」', '重点。']:
        cases.append(('ASCII' + marker + quoted + marker + 'ABC', '<p>ASCII<' + tag + '>' + quoted + '</' + tag + '>ABC</p>'))

for source, expected in cases:
    actual = subprocess.run([sys.argv[1], '-e', 'table', '-e', 'strikethrough'], input=source, text=True, capture_output=True, check=True, timeout=5).stdout.strip()
    assert actual == expected, (source, expected, actual)
print(f'{len(cases)} chat Markdown checks passed')

# Four explicit product extensions accept padding in strong spans. All other
# upstream examples must retain their exact parser output.
if len(sys.argv) > 2:
    spec = Path(sys.argv[2])
    examples = json.loads(subprocess.check_output([
        sys.executable, str(spec.parent / 'spec_tests.py'), '--dump-tests', '--spec', str(spec)
    ], text=True))
    padded = {
        '** foo bar**\n': '<p><strong> foo bar</strong></p>',
        '__ foo bar__\n': '<p><strong> foo bar</strong></p>',
        '**foo bar **\n': '<p><strong>foo bar </strong></p>',
        '__foo bar __\n': '<p><strong>foo bar </strong></p>',
    }
    seen = set()
    for example in examples:
        source = example['markdown']
        expected = padded.get(source, example['html'].strip())
        if source in padded:
            seen.add(source)
        command = [sys.argv[1], '--unsafe']
        for extension in example['extensions']:
            command += ['-e', extension]
        actual = subprocess.run(command, input=source, text=True, capture_output=True, check=True, timeout=5).stdout.strip()
        assert actual == expected, (example['example'], source, expected, actual)
    assert seen == set(padded)
    print(f'{len(examples)} upstream examples passed, including {len(padded)} explicit padded-strong extensions')
