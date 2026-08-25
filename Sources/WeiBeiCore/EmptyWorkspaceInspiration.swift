import Foundation

public enum EmptyWorkspaceDayPeriod: String, CaseIterable, Sendable {
    case morning
    case midday
    case evening
    case lateNight

    public init(hour: Int) {
        switch hour {
        case 5..<11:
            self = .morning
        case 11..<17:
            self = .midday
        case 17..<23:
            self = .evening
        default:
            self = .lateNight
        }
    }

    public func greeting(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .morning:
            return language.text("早安，宜开卷。", "Good morning. Open a page.")
        case .midday:
            return language.text("午安，慢慢读。", "Good afternoon. Read unhurriedly.")
        case .evening:
            return language.text("晚上好，灯下可写。", "Good evening. Leave a line in the lamplight.")
        case .lateNight:
            return language.text("夜深了，留一页清醒。", "It is late. Keep one clear page.")
        }
    }

    public static func current(at date: Date, calendar: Calendar = .current) -> EmptyWorkspaceDayPeriod {
        EmptyWorkspaceDayPeriod(hour: calendar.component(.hour, from: date))
    }
}

public enum EmptyWorkspaceInspirationPresentation: Equatable, Sendable {
    case calligraphy(assetName: String)
    case quotation
    case formula
}

public enum EmptyWorkspaceInspirationCategory: String, CaseIterable, Hashable, Sendable {
    case chineseClassics
    case worldLiterature
    case mathematics
    case physics
    case economics
    case philosophy
}

public enum EmptyWorkspaceInspirationRightsBasis: String, Hashable, Sendable {
    case publicDomain
    case ccBySA4
    case uncopyrightableFact
}

public struct EmptyWorkspaceInspiration: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let credit: String
    public let category: EmptyWorkspaceInspirationCategory
    public let languageTag: String
    public let rightsBasis: EmptyWorkspaceInspirationRightsBasis
    public let sourceLabel: String
    public let sourceURLString: String
    public let rightsLabel: String
    public let rightsURLString: String
    public let presentation: EmptyWorkspaceInspirationPresentation

    public init(
        id: String,
        text: String,
        credit: String,
        category: EmptyWorkspaceInspirationCategory,
        languageTag: String,
        rightsBasis: EmptyWorkspaceInspirationRightsBasis,
        sourceLabel: String,
        sourceURLString: String,
        rightsLabel: String,
        rightsURLString: String,
        presentation: EmptyWorkspaceInspirationPresentation
    ) {
        self.id = id
        self.text = text
        self.credit = credit
        self.category = category
        self.languageTag = languageTag
        self.rightsBasis = rightsBasis
        self.sourceLabel = sourceLabel
        self.sourceURLString = sourceURLString
        self.rightsLabel = rightsLabel
        self.rightsURLString = rightsURLString
        self.presentation = presentation
    }

    public var sourceURL: URL? {
        URL(string: sourceURLString)
    }

    public var rightsURL: URL? {
        URL(string: rightsURLString)
    }
}

public enum EmptyWorkspaceInspirationCatalog {
    public static let items: [EmptyWorkspaceInspiration] = [
        EmptyWorkspaceInspiration(
            id: "lanting-clear-breeze",
            text: "天朗氣清，惠風和暢",
            credit: "王羲之《蘭亭集序》 · 唐摹本傳馮承素",
            category: .chineseClassics,
            languageTag: "zh-Hant",
            rightsBasis: .publicDomain,
            sourceLabel: "Wikimedia Commons / 故宫博物院",
            sourceURLString: "https://commons.wikimedia.org/wiki/File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG",
            rightsLabel: "公版原作 · Public Domain Mark 1.0",
            rightsURLString: "https://creativecommons.org/publicdomain/mark/1.0/",
            presentation: .calligraphy(assetName: "lanting-clear-breeze")
        ),
        EmptyWorkspaceInspiration(
            id: "lanting-universe",
            text: "仰觀宇宙之大",
            credit: "王羲之《蘭亭集序》 · 唐摹本傳馮承素",
            category: .chineseClassics,
            languageTag: "zh-Hant",
            rightsBasis: .publicDomain,
            sourceLabel: "Wikimedia Commons / 故宫博物院",
            sourceURLString: "https://commons.wikimedia.org/wiki/File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG",
            rightsLabel: "公版原作 · Public Domain Mark 1.0",
            rightsURLString: "https://creativecommons.org/publicdomain/mark/1.0/",
            presentation: .calligraphy(assetName: "lanting-universe")
        ),
        EmptyWorkspaceInspiration(
            id: "lanting-observe-kinds",
            text: "俯察品類之盛",
            credit: "王羲之《蘭亭集序》 · 唐摹本傳馮承素",
            category: .chineseClassics,
            languageTag: "zh-Hant",
            rightsBasis: .publicDomain,
            sourceLabel: "Wikimedia Commons / 故宫博物院",
            sourceURLString: "https://commons.wikimedia.org/wiki/File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG",
            rightsLabel: "公版原作 · Public Domain Mark 1.0",
            rightsURLString: "https://creativecommons.org/publicdomain/mark/1.0/",
            presentation: .calligraphy(assetName: "lanting-observe-kinds")
        ),
        EmptyWorkspaceInspiration(
            id: "analects-learning",
            text: "學而時習之，不亦說乎？",
            credit: "孔子《論語·學而》",
            category: .chineseClassics,
            languageTag: "zh-Hant",
            rightsBasis: .ccBySA4,
            sourceLabel: "維基文庫《論語·學而第一》",
            sourceURLString: "https://zh.wikisource.org/zh/%E8%AB%96%E8%AA%9E/%E5%AD%B8%E8%80%8C%E7%AC%AC%E4%B8%80",
            rightsLabel: "先秦原文公版 · Wikisource CC BY-SA 4.0",
            rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "zhuangzi-great-beauty",
            text: "天地有大美而不言。",
            credit: "莊子《莊子·知北遊》",
            category: .chineseClassics,
            languageTag: "zh-Hant",
            rightsBasis: .ccBySA4,
            sourceLabel: "維基文庫《莊子·知北遊》",
            sourceURLString: "https://zh.wikisource.org/zh-hant/%E8%8E%8A%E5%AD%90/%E7%9F%A5%E5%8C%97%E9%81%8A",
            rightsLabel: "先秦原文公版 · Wikisource CC BY-SA 4.0",
            rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "laozi-name-the-way",
            text: "道可道，非常道；名可名，非常名。",
            credit: "老子《道德經》第一章 · 王弼本",
            category: .chineseClassics,
            languageTag: "zh-Hant",
            rightsBasis: .ccBySA4,
            sourceLabel: "維基文庫《道德經（王弼本）》",
            sourceURLString: "https://zh.wikisource.org/zh-hant/%E9%81%93%E5%BE%B7%E7%B6%93_%28%E7%8E%8B%E5%BC%BC%E6%9C%AC%29",
            rightsLabel: "古代原文公版 · Wikisource CC BY-SA 4.0",
            rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "laozi-water",
            text: "上善若水。水善利萬物而不爭。",
            credit: "老子《道德經》第八章 · 王弼本",
            category: .chineseClassics,
            languageTag: "zh-Hant",
            rightsBasis: .ccBySA4,
            sourceLabel: "維基文庫《道德經（王弼本）》",
            sourceURLString: "https://zh.wikisource.org/zh-hant/%E9%81%93%E5%BE%B7%E7%B6%93_%28%E7%8E%8B%E5%BC%BC%E6%9C%AC%29",
            rightsLabel: "古代原文公版 · Wikisource CC BY-SA 4.0",
            rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "basho-old-pond",
            text: "古池や蛙飛こむ水のおと",
            credit: "松尾芭蕉《蛙合》 · 1686",
            category: .worldLiterature,
            languageTag: "ja",
            rightsBasis: .publicDomain,
            sourceLabel: "国立国会图书馆参考协同数据库",
            sourceURLString: "https://crd.ndl.go.jp/reference/detail?page=ref_view&id=1000087707",
            rightsLabel: "原文公版 · 日本著作权法第 51 条",
            rightsURLString: "https://www.japaneselawtranslation.go.jp/en/laws/view/3379/tb",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "shakespeare-dream-stuff",
            text: "We are such stuff as dreams are made on, and our little life is rounded with a sleep.",
            credit: "William Shakespeare · The Tempest, Act IV, Scene 1",
            category: .worldLiterature,
            languageTag: "en",
            rightsBasis: .publicDomain,
            sourceLabel: "Project Gutenberg eBook 1540",
            sourceURLString: "https://www.gutenberg.org/cache/epub/1540/pg1540-images.html",
            rightsLabel: "原作公版 · PG 1540 标记美国公版",
            rightsURLString: "https://www.gutenberg.org/ebooks/1540",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "goethe-gipfeln",
            text: "Ueber allen Gipfeln\nIst Ruh’,",
            credit: "Johann Wolfgang von Goethe · Ein Gleiches · 1780",
            category: .worldLiterature,
            languageTag: "de",
            rightsBasis: .ccBySA4,
            sourceLabel: "Deutsche Wikisource · 校对完成的 1827 版",
            sourceURLString: "https://de.wikisource.org/wiki/Ein_Gleiches",
            rightsLabel: "原文公版 · Wikisource CC BY-SA 4.0",
            rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "pascal-heart-reasons",
            text: "Le cœur a ses raisons, que la raison ne connaît point ; on le sent en mille choses.",
            credit: "Blaise Pascal · Pensées · éd. Didiot, 1896, p. 62",
            category: .worldLiterature,
            languageTag: "fr",
            rightsBasis: .ccBySA4,
            sourceLabel: "Wikisource · 1896 年影印校对页",
            sourceURLString: "https://fr.wikisource.org/wiki/Page%3APascal_-_Pens%C3%A9es%2C_%C3%A9d._Didiot%2C_1896.djvu/80",
            rightsLabel: "原文公版 · Wikisource CC BY-SA 4.0",
            rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "euler-formula",
            text: "eⁱˣ = cos x + i sin x",
            credit: "Leonhard Euler · Introductio in analysin infinitorum, 1748 · 现代记法",
            category: .mathematics,
            languageTag: "zxx",
            rightsBasis: .publicDomain,
            sourceLabel: "ETH-Bibliothek e-rara · DOI 10.3931/e-rara-8740",
            sourceURLString: "https://www.e-rara.ch/zut/content/titleinfo/2447176",
            rightsLabel: "1748 原书公版 · Public Domain Mark",
            rightsURLString: "https://creativecommons.org/publicdomain/mark/1.0/",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "euclid-pythagorean",
            text: "a² + b² = c²",
            credit: "Euclid · Elements, Book I, Proposition 47 · 现代记法",
            category: .mathematics,
            languageTag: "zxx",
            rightsBasis: .publicDomain,
            sourceLabel: "Project Gutenberg eBook 21076 · Euclid’s Elements",
            sourceURLString: "https://www.gutenberg.org/ebooks/21076",
            rightsLabel: "数学关系 / 事实 · 原书标记美国公版",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "bayes-theorem",
            text: "P(A | B) = P(B | A)P(A) / P(B)",
            credit: "Thomas Bayes · An Essay towards solving a Problem in the Doctrine of Chances, 1763 · 现代记法",
            category: .mathematics,
            languageTag: "zxx",
            rightsBasis: .uncopyrightableFact,
            sourceLabel: "Royal Society · DOI 10.1098/rstl.1763.0053",
            sourceURLString: "https://royalsocietypublishing.org/doi/10.1098/rstl.1763.0053",
            rightsLabel: "数学公式 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "einstein-rest-energy",
            text: "E₀ = mc²",
            credit: "Albert Einstein · Ist die Trägheit eines Körpers von seinem Energieinhalt abhängig?, 1905 · 现代记法",
            category: .physics,
            languageTag: "zxx",
            rightsBasis: .uncopyrightableFact,
            sourceLabel: "Max Planck Institute for the History of Science",
            sourceURLString: "https://einstein-annalen.mpiwg-berlin.mpg.de/annalen/alphabetical/Einst_Istdi_de_1905",
            rightsLabel: "物理公式 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "schrodinger-equation",
            text: "Ĥψ = Eψ",
            credit: "Erwin Schrödinger · Quantisierung als Eigenwertproblem, 1926 · 现代记法",
            category: .physics,
            languageTag: "zxx",
            rightsBasis: .uncopyrightableFact,
            sourceLabel: "Annalen der Physik · DOI 10.1002/andp.19263840404",
            sourceURLString: "https://doi.org/10.1002/andp.19263840404",
            rightsLabel: "物理公式 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "cobb-douglas-production",
            text: "P = bLᵏC¹⁻ᵏ",
            credit: "Charles W. Cobb & Paul H. Douglas · A Theory of Production, 1928",
            category: .economics,
            languageTag: "zxx",
            rightsBasis: .uncopyrightableFact,
            sourceLabel: "The American Economic Review 18(1)",
            sourceURLString: "https://www.jstor.org/stable/1811556",
            rightsLabel: "经济学公式 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "fisher-exchange",
            text: "MV + M′V′ = ΣpQ",
            credit: "Irving Fisher · The Purchasing Power of Money, 1911",
            category: .economics,
            languageTag: "zxx",
            rightsBasis: .uncopyrightableFact,
            sourceLabel: "FRASER · Federal Reserve Bank of St. Louis",
            sourceURLString: "https://fraser.stlouisfed.org/title/purchasing-power-money-3610/fulltext",
            rightsLabel: "经济学公式 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "aristotle-non-contradiction",
            text: "¬(p ∧ ¬p)",
            credit: "Aristotle · Metaphysics IV.3, 1005b19–20 · 现代逻辑记法",
            category: .philosophy,
            languageTag: "zxx",
            rightsBasis: .uncopyrightableFact,
            sourceLabel: "MIT Internet Classics Archive · W. D. Ross",
            sourceURLString: "https://classics.mit.edu/Aristotle/metaphysics.4.iv.html",
            rightsLabel: "逻辑原则 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "analects-three-companions", text: "三人行，必有我師焉。", credit: "孔子《論語·述而》",
            category: .chineseClassics, languageTag: "zh-Hant", rightsBasis: .ccBySA4,
            sourceLabel: "維基文庫《論語·述而第七》", sourceURLString: "https://zh.wikisource.org/zh-hant/%E8%AB%96%E8%AA%9E/%E8%BF%B0%E8%80%8C%E7%AC%AC%E4%B8%83",
            rightsLabel: "先秦原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "yijing-self-renewal", text: "天行健，君子以自強不息。", credit: "《周易·乾卦》",
            category: .chineseClassics, languageTag: "zh-Hant", rightsBasis: .ccBySA4,
            sourceLabel: "維基文庫《易經》", sourceURLString: "https://zh.wikisource.org/zh-hant/%E6%98%93%E7%B6%93",
            rightsLabel: "古代原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "tao-peach-blossom", text: "採菊東籬下，悠然見南山。", credit: "陶淵明《飲酒·其五》",
            category: .chineseClassics, languageTag: "zh-Hant", rightsBasis: .ccBySA4,
            sourceLabel: "維基文庫《飲酒二十首》", sourceURLString: "https://zh.wikisource.org/zh-hant/%E9%A3%B2%E9%85%92%E4%BA%8C%E5%8D%81%E9%A6%96",
            rightsLabel: "古代原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "dante-midway", text: "Nel mezzo del cammin di nostra vita\nmi ritrovai per una selva oscura,", credit: "Dante Alighieri · Inferno, Canto I",
            category: .worldLiterature, languageTag: "it", rightsBasis: .publicDomain,
            sourceLabel: "Project Gutenberg eBook 1000", sourceURLString: "https://www.gutenberg.org/ebooks/1000",
            rightsLabel: "原作公版 · Project Gutenberg 标记美国公版", rightsURLString: "https://www.gutenberg.org/policy/permission.html", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "cervantes-la-mancha", text: "En un lugar de la Mancha, de cuyo nombre no quiero acordarme…", credit: "Miguel de Cervantes · Don Quijote de la Mancha, I.1",
            category: .worldLiterature, languageTag: "es", rightsBasis: .publicDomain,
            sourceLabel: "Project Gutenberg eBook 2000", sourceURLString: "https://www.gutenberg.org/ebooks/2000",
            rightsLabel: "原作公版 · Project Gutenberg 标记美国公版", rightsURLString: "https://www.gutenberg.org/policy/permission.html", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "virgil-arms-man", text: "Arma virumque cano, Troiae qui primus ab oris…", credit: "Vergilius · Aeneis, Liber I",
            category: .worldLiterature, languageTag: "la", rightsBasis: .publicDomain,
            sourceLabel: "Project Gutenberg eBook 227", sourceURLString: "https://www.gutenberg.org/ebooks/227",
            rightsLabel: "古典原文公版 · Project Gutenberg 标记美国公版", rightsURLString: "https://www.gutenberg.org/policy/permission.html", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "rilke-change-life", text: "Du mußt dein Leben ändern.", credit: "Rainer Maria Rilke · Archaïscher Torso Apollos · 1908",
            category: .worldLiterature, languageTag: "de", rightsBasis: .ccBySA4,
            sourceLabel: "Deutsche Wikisource · 1918 版", sourceURLString: "https://de.wikisource.org/wiki/Archa%C3%AFscher_Torso_Apollos",
            rightsLabel: "原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "pessoa-poet-feigns", text: "O poeta é um fingidor.", credit: "Fernando Pessoa · Autopsicografia · 1931",
            category: .worldLiterature, languageTag: "pt", rightsBasis: .ccBySA4,
            sourceLabel: "Wikisource《Autopsicografia》", sourceURLString: "https://pt.wikisource.org/wiki/Autopsicografia",
            rightsLabel: "原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "quadratic-formula", text: "x = (−b ± √(b² − 4ac)) / 2a", credit: "二次方程求根公式 · 现代记法",
            category: .mathematics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "U.S. Copyright Office Circular 33", sourceURLString: "https://www.copyright.gov/circs/circ33.pdf",
            rightsLabel: "数学公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "newton-leibniz", text: "∫ₐᵇ f′(x) dx = f(b) − f(a)", credit: "Newton–Leibniz formula · 现代记法",
            category: .mathematics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "U.S. Copyright Office Circular 33", sourceURLString: "https://www.copyright.gov/circs/circ33.pdf",
            rightsLabel: "数学公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "fourier-transform", text: "F(ω) = ∫₋∞∞ f(t)e⁻ⁱωᵗ dt", credit: "Joseph Fourier · Théorie analytique de la chaleur, 1822 · 现代记法",
            category: .mathematics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Bibliothèque nationale de France · Gallica", sourceURLString: "https://gallica.bnf.fr/ark:/12148/bpt6k33707",
            rightsLabel: "数学公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "shannon-entropy", text: "H = −Σ pᵢ log₂ pᵢ", credit: "Claude E. Shannon · A Mathematical Theory of Communication, 1948",
            category: .mathematics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Bell System Technical Journal · DOI", sourceURLString: "https://doi.org/10.1002/j.1538-7305.1948.tb01338.x",
            rightsLabel: "数学公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "newton-second-law", text: "F = ma", credit: "Isaac Newton · Philosophiæ Naturalis Principia Mathematica · 现代记法",
            category: .physics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Project Gutenberg eBook 28233", sourceURLString: "https://www.gutenberg.org/ebooks/28233",
            rightsLabel: "物理公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "maxwell-gauss-law", text: "∇ · E = ρ / ε₀", credit: "James Clerk Maxwell · A Dynamical Theory of the Electromagnetic Field, 1865 · 现代记法",
            category: .physics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Royal Society · DOI 10.1098/rstl.1865.0008", sourceURLString: "https://doi.org/10.1098/rstl.1865.0008",
            rightsLabel: "物理公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "planck-relation", text: "E = hν", credit: "Max Planck · 1901 · 现代记法",
            category: .physics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Annalen der Physik · DOI", sourceURLString: "https://doi.org/10.1002/andp.19013090310",
            rightsLabel: "物理公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "boltzmann-entropy", text: "S = k log W", credit: "Ludwig Boltzmann · 1877 · 现代记法",
            category: .physics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Wiener Berichte · DOI", sourceURLString: "https://doi.org/10.1007/BF01517726",
            rightsLabel: "物理公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "uncertainty-principle", text: "Δx Δp ≥ ℏ / 2", credit: "Werner Heisenberg · 1927 · 现代记法",
            category: .physics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Zeitschrift für Physik · DOI", sourceURLString: "https://doi.org/10.1007/BF01397280",
            rightsLabel: "物理公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "de-broglie-wave", text: "λ = h / p", credit: "Louis de Broglie · Recherches sur la théorie des quanta, 1924 · 现代记法",
            category: .physics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "HAL theses · tel-00006807", sourceURLString: "https://theses.hal.science/tel-00006807",
            rightsLabel: "物理公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "national-income-identity", text: "Y = C + I + G + NX", credit: "National income accounting identity · 现代记法",
            category: .economics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "U.S. Bureau of Economic Analysis · NIPA Handbook", sourceURLString: "https://www.bea.gov/resources/methodologies/nipa-handbook",
            rightsLabel: "经济学恒等式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "price-elasticity", text: "ε = (dQ / Q) / (dP / P)", credit: "Alfred Marshall · Principles of Economics, 1890 · 现代记法",
            category: .economics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Project Gutenberg eBook 3375", sourceURLString: "https://www.gutenberg.org/ebooks/3375",
            rightsLabel: "经济学公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "present-value", text: "PV = Σₜ CFₜ / (1 + r)ᵗ", credit: "Present value relation · 现代记法",
            category: .economics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "U.S. SEC Investor.gov", sourceURLString: "https://www.investor.gov/introduction-investing/investing-basics/glossary/present-value",
            rightsLabel: "金融公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "keynes-multiplier", text: "k = 1 / (1 − c)", credit: "John Maynard Keynes · The General Theory, 1936 · 简化乘数记法",
            category: .economics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Internet Archive · The General Theory", sourceURLString: "https://archive.org/details/in.ernet.dli.2015.50092",
            rightsLabel: "经济学公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "black-scholes-pde", text: "∂V/∂t + ½σ²S²∂²V/∂S² + rS∂V/∂S − rV = 0", credit: "Fischer Black & Myron Scholes · The Pricing of Options and Corporate Liabilities, 1973",
            category: .economics, languageTag: "zxx", rightsBasis: .uncopyrightableFact,
            sourceLabel: "Journal of Political Economy · DOI", sourceURLString: "https://doi.org/10.1086/260062",
            rightsLabel: "金融公式 / 事实 · 不主张版权", rightsURLString: "https://www.copyright.gov/circs/circ33.pdf", presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "descartes-cogito", text: "Je pense, donc je suis.", credit: "René Descartes · Discours de la méthode, IV · 1637",
            category: .philosophy, languageTag: "fr", rightsBasis: .ccBySA4,
            sourceLabel: "Wikisource《Discours de la méthode》", sourceURLString: "https://fr.wikisource.org/wiki/Discours_de_la_m%C3%A9thode",
            rightsLabel: "原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "kant-sapere-aude", text: "Sapere aude! Habe Muth dich deines eigenen Verstandes zu bedienen!", credit: "Immanuel Kant · Beantwortung der Frage: Was ist Aufklärung? · 1784",
            category: .philosophy, languageTag: "de", rightsBasis: .ccBySA4,
            sourceLabel: "Deutsche Wikisource · Berlinische Monatsschrift", sourceURLString: "https://de.wikisource.org/wiki/Beantwortung_der_Frage%3A_Was_ist_Aufkl%C3%A4rung%3F",
            rightsLabel: "原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "spinoza-nature", text: "Deus sive Natura.", credit: "Baruch Spinoza · Ethica · 1677",
            category: .philosophy, languageTag: "la", rightsBasis: .ccBySA4,
            sourceLabel: "Latin Wikisource《Ethica》", sourceURLString: "https://la.wikisource.org/wiki/Ethica",
            rightsLabel: "原文公版 · Wikisource CC BY-SA 4.0", rightsURLString: "https://creativecommons.org/licenses/by-sa/4.0/", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "hume-reason-passions", text: "Reason is, and ought only to be the slave of the passions.", credit: "David Hume · A Treatise of Human Nature, II.iii.3 · 1739",
            category: .philosophy, languageTag: "en", rightsBasis: .publicDomain,
            sourceLabel: "Project Gutenberg eBook 4705", sourceURLString: "https://www.gutenberg.org/ebooks/4705",
            rightsLabel: "原文公版 · Project Gutenberg 标记美国公版", rightsURLString: "https://www.gutenberg.org/policy/permission.html", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "mao-serve-the-people", text: "為人民服務", credit: "毛澤東《為人民服務》 · 1944",
            category: .philosophy, languageTag: "zh-Hant", rightsBasis: .uncopyrightableFact,
            sourceLabel: "人民網黨史頻道 · 從提出到寫入黨章", sourceURLString: "https://dangshi.people.com.cn/n1/2020/0407/c85037-31663260.html",
            rightsLabel: "極短歷史口號 · 不收錄仍在保護期內的文章正文", rightsURLString: "https://www.npc.gov.cn/c2/c30834/202011/t20201119_308796.html", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "mao-seek-truth", text: "實事求是", credit: "毛澤東倡導的思想路線 · 語出《漢書·河間獻王傳》",
            category: .philosophy, languageTag: "zh-Hant", rightsBasis: .uncopyrightableFact,
            sourceLabel: "中國共產黨新聞網 · 實事求是是最大的黨性", sourceURLString: "https://cpc.people.com.cn/n1/2022/0922/c443712-32531434.html",
            rightsLabel: "古代成語與極短歷史口號 · 不收錄現代受保護正文", rightsURLString: "https://www.npc.gov.cn/c2/c30834/202011/t20201119_308796.html", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "mao-single-spark", text: "星星之火，可以燎原", credit: "毛澤東《星星之火，可以燎原》 · 1930",
            category: .philosophy, languageTag: "zh-Hant", rightsBasis: .uncopyrightableFact,
            sourceLabel: "中國共產黨新聞網 · 1930年1月5日黨史記錄", sourceURLString: "https://cpc.people.com.cn/BIG5/64162/64165/76621/76627/5231445.html",
            rightsLabel: "極短歷史口號 / 文章標題 · 不收錄仍在保護期內的正文", rightsURLString: "https://www.npc.gov.cn/c2/c30834/202011/t20201119_308796.html", presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "mao-double-hundred", text: "百花齊放，百家爭鳴", credit: "毛澤東提出的“雙百方針” · 1956",
            category: .philosophy, languageTag: "zh-Hant", rightsBasis: .uncopyrightableFact,
            sourceLabel: "中國共產黨新聞網 · 雙百方針史料", sourceURLString: "https://cpc.people.com.cn/GB/33837/2534760.html",
            rightsLabel: "傳統成語構成的極短歷史口號 · 不收錄現代受保護正文", rightsURLString: "https://www.npc.gov.cn/c2/c30834/202011/t20201119_308796.html", presentation: .quotation
        ),
    ]

    /// Interleave fields so successive days reveal the catalog's breadth.
    public static let rotationItems: [EmptyWorkspaceInspiration] = {
        let categoryOrder = EmptyWorkspaceInspirationCategory.allCases
        var consumed: [EmptyWorkspaceInspirationCategory: Int] = [:]
        var result: [EmptyWorkspaceInspiration] = []
        while result.count < items.count {
            for category in categoryOrder {
                let categoryItems = items.filter { $0.category == category }
                let index = consumed[category, default: 0]
                guard categoryItems.indices.contains(index) else { continue }
                consumed[category] = index + 1
                result.append(categoryItems[index])
            }
        }
        if result.first?.category == result.last?.category,
           let last = result.popLast(),
           let insertion = result.indices.dropFirst().first(where: {
               result[$0 - 1].category != last.category && result[$0].category != last.category
           }) {
            result.insert(last, at: insertion)
        }
        return result
    }()

    public static func randomItem<R: RandomNumberGenerator>(excludingID: String?, using generator: inout R) -> EmptyWorkspaceInspiration {
        precondition(!rotationItems.isEmpty)
        let candidates = rotationItems.filter { $0.id != excludingID }
        return candidates.randomElement(using: &generator) ?? rotationItems[0]
    }

    public static func item(for date: Date, calendar: Calendar = .current) -> EmptyWorkspaceInspiration {
        precondition(!rotationItems.isEmpty)
        let ordinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 1
        return rotationItems[(ordinal - 1) % rotationItems.count]
    }

    public static var validationErrors: [String] {
        var errors: [String] = []
        let ids = items.map(\.id)
        if Set(ids).count != ids.count {
            errors.append("inspiration IDs must be unique")
        }

        let categories = Set(items.map(\.category))
        for category in EmptyWorkspaceInspirationCategory.allCases where !categories.contains(category) {
            errors.append("inspiration category is missing: \(category.rawValue)")
        }

        for item in items {
            if item.id.isEmpty || item.text.isEmpty || item.credit.isEmpty || item.languageTag.isEmpty || item.sourceLabel.isEmpty || item.rightsLabel.isEmpty {
                errors.append("\(item.id): required metadata is missing")
            }
            if item.sourceURL?.scheme != "https" {
                errors.append("\(item.id): source URL must use HTTPS")
            }
            if item.rightsURL?.scheme != "https" {
                errors.append("\(item.id): rights URL must use HTTPS")
            }
            if case let .calligraphy(assetName) = item.presentation, assetName.isEmpty {
                errors.append("\(item.id): calligraphy asset is missing")
            }
            if case .calligraphy = item.presentation,
               item.category != .chineseClassics || item.languageTag != "zh-Hant" || item.rightsBasis != .publicDomain {
                errors.append("\(item.id): calligraphy must be a rights-cleared Chinese classic")
            }
            if item.presentation == .formula, item.languageTag != "zxx" {
                errors.append("\(item.id): formula-only entries must use the zxx language tag")
            }
            if item.presentation != .formula, item.languageTag == "zxx" {
                errors.append("\(item.id): original-language entries must preserve their language tag")
            }
        }
        return errors
    }
}
