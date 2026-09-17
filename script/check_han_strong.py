"""Check the same cmark delimiter parser used by both Catalyst chat surfaces."""
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
    ('这是** “重点” **内容', '<p>这是** “重点” **内容</p>'),
    ('这是**“还没结束', '<p>这是**“还没结束</p>'),
    (r'这是\*\*“原样”\*\*内容', '<p>这是**“原样”**内容</p>'),
    ('`这是**“代码”**内容`', '<p><code>这是**“代码”**内容</code></p>'),
    ('```\n这是**“代码”**内容\n```', '<pre><code>这是**“代码”**内容\n</code></pre>'),
    ('[链接](https://example.com/这是**“路径”**内容)', '<p><a href="https://example.com/%E8%BF%99%E6%98%AF**%E2%80%9C%E8%B7%AF%E5%BE%84%E2%80%9D**%E5%86%85%E5%AE%B9">链接</a></p>'),
]
for source, expected in cases:
    actual = subprocess.run([sys.argv[1]], input=source, text=True, capture_output=True, check=True).stdout.strip()
    assert actual == expected, (source, expected, actual)
print(f'{len(cases)} Han strong-emphasis checks passed')
