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
            return language.text("晚安，灯下可写。", "Good evening. Leave a line in the lamplight.")
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
    ]

    /// Interleave fields so successive days and manual advances reveal the catalog's breadth.
    public static let rotationItems: [EmptyWorkspaceInspiration] = {
        let categoryOrder: [EmptyWorkspaceInspirationCategory] = [
            .chineseClassics, .worldLiterature, .mathematics,
            .chineseClassics, .physics, .worldLiterature,
            .chineseClassics, .economics, .mathematics,
            .chineseClassics, .philosophy, .worldLiterature,
            .chineseClassics, .physics, .economics,
            .chineseClassics, .worldLiterature, .chineseClassics, .mathematics,
        ]
        var consumed: [EmptyWorkspaceInspirationCategory: Int] = [:]
        return categoryOrder.compactMap { category in
            let categoryItems = items.filter { $0.category == category }
            let index = consumed[category, default: 0]
            guard categoryItems.indices.contains(index) else { return nil }
            consumed[category] = index + 1
            return categoryItems[index]
        }
    }()

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
