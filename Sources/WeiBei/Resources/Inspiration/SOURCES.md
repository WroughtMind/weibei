# Empty workspace inspiration sources

WeiBei bundles the text and selected calligraphy alpha masks in this directory so the empty workspace works without a network connection. Source links are shown in the interface for traceability; they are never required for rendering.

No NC, ND, modern calligraphy font, or license-unclear dataset is included. Mathematical and scientific expressions are typeset with system serif text and are not rendered as calligraphy.

## Catalog

| Catalog ID | Original text or expression | Author and work | Reliable source | Rights basis |
| --- | --- | --- | --- | --- |
| `lanting-clear-breeze` | `天朗氣清，惠風和暢` | 王羲之《蘭亭集序》; glyphs from the Tang copy traditionally attributed to 馮承素 | [Wikimedia Commons file page, Palace Museum source](https://commons.wikimedia.org/wiki/File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG) | The ancient work and its faithful digital reproduction are marked public domain and [Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/). The bundled PNG is a transparent crop derived from that scan. |
| `lanting-universe` | `仰觀宇宙之大` | 王羲之《蘭亭集序》; glyphs from the Tang copy traditionally attributed to 馮承素 | [Wikimedia Commons file page, Palace Museum source](https://commons.wikimedia.org/wiki/File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG) | Same public-domain and Public Domain Mark 1.0 basis as above. |
| `basho-old-pond` | `古池や蛙飛こむ水のおと` | 松尾芭蕉《蛙合》, 1686 | [National Diet Library Collaborative Reference Database](https://crd.ndl.go.jp/reference/detail?page=ref_view&id=1000087707) | Public-domain original text; Matsuo Bashō died in 1694. Japan's [Copyright Act, Article 51](https://www.japaneselawtranslation.go.jp/en/laws/view/3379/tb) provides a general term of 70 years after the author's death. No translation is bundled. |
| `euler-formula` | `eⁱˣ = cos x + i sin x` | Leonhard Euler, *Introductio in analysin infinitorum*, 1748; modern notation | [ETH-Bibliothek e-rara, DOI 10.3931/e-rara-8740](https://www.e-rara.ch/zut/content/titleinfo/2447176) | The digitized 1748 book is marked [Public Domain Mark](https://creativecommons.org/publicdomain/mark/1.0/). WeiBei claims no copyright in the mathematical expression. |
| `einstein-rest-energy` | `E₀ = mc²` | Albert Einstein, *Ist die Trägheit eines Körpers von seinem Energieinhalt abhängig?*, 1905; modern notation | [Max Planck Institute for the History of Science, original paper](https://einstein-annalen.mpiwg-berlin.mpg.de/annalen/alphabetical/Einst_Istdi_de_1905) | Physical formula / fact. WeiBei claims no copyright in the expression; see [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf). |
| `cobb-douglas-production` | `P = bLᵏC¹⁻ᵏ` | Charles W. Cobb and Paul H. Douglas, “A Theory of Production,” 1928 | [The American Economic Review 18(1), JSTOR stable record](https://www.jstor.org/stable/1811556) | Economic formula / fact. WeiBei claims no copyright in the expression; see Circular 33 above. |

## Calligraphy transformation

Only the two verified `Lantingji Xu` phrases are included. The source scan itself is not bundled. The generation record below preserves the glyph coordinates used to convert selected ink into transparent alpha masks. WeiBei applies semantic ink color at runtime, so the same PNG has no white box and stays legible in both paper and inkstone modes.

- Commons description revision checked on 2026-07-10: [`oldid=1012610416`](https://commons.wikimedia.org/w/index.php?title=File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG&oldid=1012610416)
- Palace Museum accession number: `故00002597`
- Verified original JPEG: `28,549 × 1,300`, SHA-1 `a133647a8695cd06d0f5c6215d66e0b8b8d93d56`
- `lanting-clear-breeze.png`: `856 × 132`, SHA-256 `e5c6827f44b22f5441bb208b1770103da8a076564b52f41e64f77b0da7e1835c`
- `lanting-universe.png`: `624 × 132`, SHA-256 `a915d1e460c68a0634c2cfaad90f802fda04ea8c25227632cd4812c51647df22`
- Both PNGs have zero opaque-white pixels and zero ink in the outer two-pixel border.

The manual source rectangles are recorded below as `(left, top, right, bottom)` in the verified Commons JPEG. No generative fill, vector tracing, or font substitution is used.

- `天朗氣清惠風和暢`: `(22732,331,22832,414)`, `(22734,414,22818,499)`, `(22733,530,22831,628)`, `(22730,626,22818,741)`, `(22734,742,22813,849)`, `(22720,847,22829,957)`, `(22714,959,22831,1050)`, `(22728,1049,22836,1152)`
- `仰觀宇宙之大`: `(22725,1151,22832,1242)`, `(22610,9,22731,143)`, `(22622,154,22705,256)`, `(22617,276,22697,351)`, `(22615,384,22703,462)`, `(22604,475,22699,548)`

The four experimental Zhao Mengfu crops from the research workspace were rejected because they contained neighboring strokes or incomplete glyphs. They are not part of this package or catalog.
