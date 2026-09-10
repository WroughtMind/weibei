#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# 合并门槛与部署复用同一套网页检查和静态站点组装。
for file in website/*.js website/*.mjs website/qa/*.mjs; do
  node --check "$file"
done
node --test website/download-selection.test.mjs

rm -rf _site
mkdir -p _site
cp -R website/. _site/
rm -rf _site/qa
python3 website/seo/build.py _site
python3 website/seo/check.py _site
touch _site/.nojekyll
test -s _site/index.html
test -s _site/feedback.html
test -s _site/assets/WeiBeiStele.ttf
test -s _site/assets/第一幕-真实首页截图-去黑边.webp
test -s _site/paper-fold.css

