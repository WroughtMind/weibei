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

public struct EmptyWorkspaceInspiration: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let credit: String
    public let sourceLabel: String
    public let sourceURLString: String
    public let rightsLabel: String
    public let rightsURLString: String
    public let presentation: EmptyWorkspaceInspirationPresentation

    public init(
        id: String,
        text: String,
        credit: String,
        sourceLabel: String,
        sourceURLString: String,
        rightsLabel: String,
        rightsURLString: String,
        presentation: EmptyWorkspaceInspirationPresentation
    ) {
        self.id = id
        self.text = text
        self.credit = credit
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
            sourceLabel: "Wikimedia Commons / 故宫博物院",
            sourceURLString: "https://commons.wikimedia.org/wiki/File:%E7%A5%9E%E9%BE%8D%E8%98%AD%E4%BA%AD%E5%BA%8F%E5%85%A8.JPG",
            rightsLabel: "公版原作 · Public Domain Mark 1.0",
            rightsURLString: "https://creativecommons.org/publicdomain/mark/1.0/",
            presentation: .calligraphy(assetName: "lanting-universe")
        ),
        EmptyWorkspaceInspiration(
            id: "basho-old-pond",
            text: "古池や蛙飛こむ水のおと",
            credit: "松尾芭蕉《蛙合》 · 1686",
            sourceLabel: "国立国会图书馆参考协同数据库",
            sourceURLString: "https://crd.ndl.go.jp/reference/detail?page=ref_view&id=1000087707",
            rightsLabel: "原文公版 · 日本著作权法第 51 条",
            rightsURLString: "https://www.japaneselawtranslation.go.jp/en/laws/view/3379/tb",
            presentation: .quotation
        ),
        EmptyWorkspaceInspiration(
            id: "euler-formula",
            text: "eⁱˣ = cos x + i sin x",
            credit: "Leonhard Euler · Introductio in analysin infinitorum, 1748 · 现代记法",
            sourceLabel: "ETH-Bibliothek e-rara · DOI 10.3931/e-rara-8740",
            sourceURLString: "https://www.e-rara.ch/zut/content/titleinfo/2447176",
            rightsLabel: "1748 原书公版 · Public Domain Mark",
            rightsURLString: "https://creativecommons.org/publicdomain/mark/1.0/",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "einstein-rest-energy",
            text: "E₀ = mc²",
            credit: "Albert Einstein · Ist die Trägheit eines Körpers von seinem Energieinhalt abhängig?, 1905 · 现代记法",
            sourceLabel: "Max Planck Institute for the History of Science",
            sourceURLString: "https://einstein-annalen.mpiwg-berlin.mpg.de/annalen/alphabetical/Einst_Istdi_de_1905",
            rightsLabel: "物理公式 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
        EmptyWorkspaceInspiration(
            id: "cobb-douglas-production",
            text: "P = bLᵏC¹⁻ᵏ",
            credit: "Charles W. Cobb & Paul H. Douglas · A Theory of Production, 1928",
            sourceLabel: "The American Economic Review 18(1)",
            sourceURLString: "https://www.jstor.org/stable/1811556",
            rightsLabel: "经济学公式 / 事实 · 不主张版权",
            rightsURLString: "https://www.copyright.gov/circs/circ33.pdf",
            presentation: .formula
        ),
    ]

    public static func item(for date: Date, calendar: Calendar = .current) -> EmptyWorkspaceInspiration {
        precondition(!items.isEmpty)
        let ordinal = calendar.ordinality(of: .day, in: .era, for: date) ?? 1
        return items[(ordinal - 1) % items.count]
    }

    public static var validationErrors: [String] {
        var errors: [String] = []
        let ids = items.map(\.id)
        if Set(ids).count != ids.count {
            errors.append("inspiration IDs must be unique")
        }

        for item in items {
            if item.id.isEmpty || item.text.isEmpty || item.credit.isEmpty || item.sourceLabel.isEmpty || item.rightsLabel.isEmpty {
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
        }
        return errors
    }
}
