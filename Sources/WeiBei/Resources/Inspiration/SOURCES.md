# Empty workspace inspiration sources

WeiBei bundles the text, formulas, and three verified calligraphy alpha masks in this directory so the empty workspace works without a network connection. Source links are visible for traceability but are never required for rendering.

The offline catalog contains exactly 50 entries across six fields: Chinese classics, world literature, mathematics, physics, economics, and philosophy. It preserves Classical Chinese, Japanese, English, German, French, Italian, Spanish, Latin, and Portuguese. Formula-only entries use the BCP 47 `zxx` tag because they contain no linguistic text. The machine-readable ledger in `EmptyWorkspaceInspiration.swift` stores the exact source URL, rights URL, rights basis, language tag, author/work credit, and presentation mode for every entry.

No NC, ND, modern calligraphy font, license-unclear dataset, translation, or generated quotation is included. Formula and foreign-language entries are typeset normally and are never presented as calligraphy. WeiBei claims no copyright in mathematical, physical, economic, or logical facts.

## Catalog

| Catalog ID | Field | Original text or expression | Author and work | Reliable source | Rights basis |
| --- | --- | --- | --- | --- | --- |
| `lanting-clear-breeze` | Chinese classics / calligraphy | `天朗氣清，惠風和暢` | 王羲之《蘭亭集序》; Tang copy traditionally attributed to 馮承素 | [Wikimedia Commons file page](https://commons.wikimedia.org/wiki/File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG), checked against [Palace Museum object 故00002597](https://www.dpm.org.cn/collection/handwriting/228279.html) | Ancient public-domain work; the faithful digital reproduction is marked public domain and [Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/). |
| `lanting-universe` | Chinese classics / calligraphy | `仰觀宇宙之大` | Same work and copy | Same Commons and Palace Museum records | Same public-domain basis. |
| `lanting-observe-kinds` | Chinese classics / calligraphy | `俯察品類之盛` | Same work and copy | Same Commons and Palace Museum records | Same public-domain basis. |
| `analects-learning` | Chinese classical thought | `學而時習之，不亦說乎？` | 孔子《論語·學而》 | [Chinese Wikisource source text](https://zh.wikisource.org/zh/%E8%AB%96%E8%AA%9E/%E5%AD%B8%E8%80%8C%E7%AC%AC%E4%B8%80) | The page identifies the pre-Qin text as public domain; Wikisource text is available under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). |
| `zhuangzi-great-beauty` | Chinese classical thought | `天地有大美而不言。` | 莊子《莊子·知北遊》 | [Chinese Wikisource source text](https://zh.wikisource.org/zh-hant/%E8%8E%8A%E5%AD%90/%E7%9F%A5%E5%8C%97%E9%81%8A) | Ancient public-domain text; Wikisource CC BY-SA 4.0. |
| `laozi-name-the-way` | Chinese classical thought | `道可道，非常道；名可名，非常名。` | 老子《道德經》第一章, 王弼本 | [Chinese Wikisource source text](https://zh.wikisource.org/zh-hant/%E9%81%93%E5%BE%B7%E7%B6%93_%28%E7%8E%8B%E5%BC%BC%E6%9C%AC%29) | Ancient public-domain text; Wikisource CC BY-SA 4.0. |
| `laozi-water` | Chinese classical thought | `上善若水。水善利萬物而不爭。` | 老子《道德經》第八章, 王弼本 | Same checked Wikisource source | Ancient public-domain text; Wikisource CC BY-SA 4.0. |
| `basho-old-pond` | World literature / Japanese | `古池や蛙飛こむ水のおと` | 松尾芭蕉《蛙合》, 1686 | [National Diet Library Collaborative Reference Database](https://crd.ndl.go.jp/reference/detail?page=ref_view&id=1000087707) | Bashō died in 1694; Japan's [Copyright Act, Article 51](https://www.japaneselawtranslation.go.jp/en/laws/view/3379/tb) provides a general term of 70 years after death. No translation is bundled. |
| `shakespeare-dream-stuff` | World literature / English | `We are such stuff as dreams are made on, and our little life is rounded with a sleep.` | William Shakespeare, *The Tempest*, Act IV, Scene 1 | [Project Gutenberg eBook 1540 source text](https://www.gutenberg.org/cache/epub/1540/pg1540-images.html) | [eBook 1540](https://www.gutenberg.org/ebooks/1540) is explicitly marked public domain in the USA; Shakespeare died in 1616. No translation is bundled. The older eBook 1801 was rejected because its electronic edition carries additional restrictions. |
| `goethe-gipfeln` | World literature / German | `Ueber allen Gipfeln / Ist Ruh’,` (source line break retained in the app) | Johann Wolfgang von Goethe, *Ein Gleiches*, 1780 | [German Wikisource, twice proofread against the 1827 edition](https://de.wikisource.org/wiki/Ein_Gleiches) | Goethe died in 1832; original text is public domain. Wikisource text is available under CC BY-SA 4.0. No translation is bundled. |
| `pascal-heart-reasons` | World literature / French | `Le cœur a ses raisons, que la raison ne connaît point ; on le sent en mille choses.` | Blaise Pascal, *Pensées*, Didiot edition, 1896, p. 62 | [French Wikisource facsimile and corrected transcription](https://fr.wikisource.org/wiki/Page%3APascal_-_Pens%C3%A9es%2C_%C3%A9d._Didiot%2C_1896.djvu/80) | Pascal died in 1662 and the 1896 edition is public domain; Wikisource text is available under CC BY-SA 4.0. No translation is bundled. |
| `euler-formula` | Mathematics | `eⁱˣ = cos x + i sin x` | Leonhard Euler, *Introductio in analysin infinitorum*, 1748; modern notation | [ETH-Bibliothek e-rara, DOI 10.3931/e-rara-8740](https://www.e-rara.ch/zut/content/titleinfo/2447176) | The digitized book is marked Public Domain Mark. Mathematical expression / fact; no copyright claimed. |
| `euclid-pythagorean` | Mathematics | `a² + b² = c²` | Euclid, *Elements* I.47; modern notation | [Project Gutenberg eBook 21076](https://www.gutenberg.org/ebooks/21076) | The source edition is marked public domain in the USA. Mathematical relation / fact; see [U.S. Copyright Office Circular 33](https://www.copyright.gov/circs/circ33.pdf). |
| `bayes-theorem` | Mathematics | `P(A \| B) = P(B \| A)P(A) / P(B)` | Thomas Bayes, “An Essay towards solving a Problem in the Doctrine of Chances,” 1763; modern notation | [Royal Society, DOI 10.1098/rstl.1763.0053](https://royalsocietypublishing.org/doi/10.1098/rstl.1763.0053) | Mathematical formula / fact; no text from the paper is bundled and no copyright is claimed in the expression. Circular 33. |
| `einstein-rest-energy` | Physics | `E₀ = mc²` | Albert Einstein, “Ist die Trägheit eines Körpers von seinem Energieinhalt abhängig?”, 1905; modern notation | [Max Planck Institute for the History of Science, original paper record](https://einstein-annalen.mpiwg-berlin.mpg.de/annalen/alphabetical/Einst_Istdi_de_1905) | Physical formula / fact; no copyright claimed. Circular 33. |
| `schrodinger-equation` | Physics | `Ĥψ = Eψ` | Erwin Schrödinger, “Quantisierung als Eigenwertproblem,” 1926; modern notation | [Annalen der Physik, DOI 10.1002/andp.19263840404](https://doi.org/10.1002/andp.19263840404) | Physical formula / fact; no article text is bundled and no copyright is claimed in the expression. Circular 33. |
| `cobb-douglas-production` | Economics | `P = bLᵏC¹⁻ᵏ` | Charles W. Cobb and Paul H. Douglas, “A Theory of Production,” 1928 | [The American Economic Review 18(1), JSTOR stable record](https://www.jstor.org/stable/1811556) | Economic formula / fact; no article text is bundled and no copyright is claimed in the expression. Circular 33. |
| `fisher-exchange` | Economics | `MV + M′V′ = ΣpQ` | Irving Fisher, *The Purchasing Power of Money*, 1911 | [FRASER full text, Federal Reserve Bank of St. Louis](https://fraser.stlouisfed.org/title/purchasing-power-money-3610/fulltext) | Economic formula / fact; no source-book prose is bundled and no copyright is claimed in the expression. Circular 33. |
| `aristotle-non-contradiction` | Philosophy / logic | `¬(p ∧ ¬p)` | Aristotle, *Metaphysics* IV.3, 1005b19–20; modern logical notation | [MIT Internet Classics Archive, W. D. Ross source passage](https://classics.mit.edu/Aristotle/metaphysics.4.iv.html) | Logical principle / fact; the symbolic expression is a modern notation and no copyright is claimed. Circular 33. |

## Expanded 31-entry ledger

- Chinese classics: `analects-three-companions`, `yijing-self-renewal`, and `tao-peach-blossom` use ancient public-domain originals transcribed by Chinese Wikisource under CC BY-SA 4.0.
- World originals: `dante-midway`, `cervantes-la-mancha`, and `virgil-arms-man` use Project Gutenberg public-domain editions; `rilke-change-life` and `pessoa-poet-feigns` use proofread Wikisource originals under CC BY-SA 4.0. No translations are bundled.
- Mathematics: `quadratic-formula`, `newton-leibniz`, `fourier-transform`, and `shannon-entropy` are formula/fact entries. Sources are Circular 33, BnF Gallica, and the original Shannon-paper DOI.
- Physics: `newton-second-law`, `maxwell-gauss-law`, `planck-relation`, `boltzmann-entropy`, `uncertainty-principle`, and `de-broglie-wave` cite Project Gutenberg, original-paper DOIs, or the HAL thesis record. Only modern formula notation is bundled.
- Economics: `national-income-identity`, `price-elasticity`, `present-value`, `keynes-multiplier`, and `black-scholes-pde` cite BEA, Project Gutenberg, Investor.gov, original-paper DOI records, or the scanned original book. Only formula/fact expressions are bundled.
- Philosophy: `descartes-cogito`, `kant-sapere-aude`, `spinoza-nature`, and `hume-reason-passions` use public-domain original-language texts from Wikisource or Project Gutenberg. `mao-serve-the-people`, `mao-seek-truth`, `mao-single-spark`, and `mao-double-hundred` are extremely short historical slogans or a title with People/CPC history sources; no protected poem, essay passage, translation, or *Selected Works* excerpt is bundled.

Mao Zedong died in 1976. Article 23 of the current [Copyright Law of the People's Republic of China](https://www.npc.gov.cn/c2/c30834/202011/t20201119_308796.html) protects a natural person's economic rights through 31 December of the fiftieth year after death. Therefore Mao's poems and prose remain excluded from this 2026 package absent permission; the catalog may reconsider public-domain originals from 2027 onward.

## Calligraphy transformation

Only the three verified *Lantingji Xu* phrases use calligraphy. The source scan itself is not bundled. Product credit must say `唐摹本傳馮承素`: the Palace Museum record says the traditional attribution to Feng Chengsu is not certain.

- Commons description revision checked on 2026-07-10: [`oldid=1012610416`](https://commons.wikimedia.org/w/index.php?title=File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG&oldid=1012610416)
- Palace Museum accession number: `故00002597`
- Verified original JPEG: `28,549 × 1,300`, `42,480,264` bytes
- Original SHA-1: `a133647a8695cd06d0f5c6215d66e0b8b8d93d56`
- Original SHA-256: `534f9b912f0a1b25fff9a125696b74d62e1090c6185f5f04748850187adaa7cc`
- `lanting-clear-breeze.png`: `856 × 132`, SHA-256 `b30c54279d2e0b5c7b8221369962ba3a3c0e16b264808332da38cb1b8e63d936`
- `lanting-universe.png`: `624 × 132`, SHA-256 `a915d1e460c68a0634c2cfaad90f802fda04ea8c25227632cd4812c51647df22`
- `lanting-observe-kinds.png`: `624 × 132`, SHA-256 `1c7965b6447392a874ed75adb1ce5703f26b562b8fc5fd6f380d1fdde0621379`
- All three PNGs have zero opaque-white pixels and zero ink in the outer two-pixel border.

The manual source rectangles are `(left, top, right, bottom)` in the verified Commons JPEG. No generative fill, vector tracing, or font substitution is used; no stroke is invented.

- `天朗氣清惠風和暢`: `(22732,295,22832,414)`, `(22734,414,22818,499)`, `(22733,530,22831,628)`, `(22730,626,22818,741)`, `(22734,742,22813,849)`, `(22720,847,22829,957)`, `(22714,959,22831,1050)`, `(22728,1049,22836,1152)`
- `仰觀宇宙之大`: `(22725,1151,22832,1242)`, `(22610,9,22731,143)`, `(22622,154,22705,256)`, `(22617,276,22697,351)`, `(22615,384,22703,462)`, `(22604,475,22699,548)`
- `俯察品類之盛`: `(22598,558,22716,674)`, `(22590,678,22715,812)`, `(22588,810,22705,895)`, `(22580,902,22712,1020)`, `(22580,1005,22705,1110)`, `(22582,1095,22720,1235)`

The earlier `天` rectangle began at `y=331`, below the detached top horizontal at approximately `y=306–315`. Alpha-edge checks therefore passed the already-incomplete glyph. The corrected rectangle begins at `y=295`; semantic glyph inspection is required in addition to edge checks.

The four experimental Zhao Mengfu crops were rejected because fixed grid coordinates produced wrong glyphs, neighboring strokes, or incomplete characters. They are not part of the package or catalog. Project Gutenberg eBook 1801 was also rejected because that electronic edition says it is not public domain and restricts commercial distribution.
