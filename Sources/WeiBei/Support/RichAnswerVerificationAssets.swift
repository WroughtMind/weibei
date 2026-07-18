import AppKit
import CryptoKit
import Foundation

enum RichAnswerVerificationAssets {
    struct Asset: Hashable {
        let id: String
        let title: String
        let processedFileStem: String
        let fileExtension: String
        let width: Int
        let height: Int
        let sha256: String
        let attribution: String

        init(
            id: String,
            title: String,
            processedFileStem: String,
            fileExtension: String = "jpg",
            width: Int,
            height: Int,
            sha256: String,
            attribution: String
        ) {
            self.id = id
            self.title = title
            self.processedFileStem = processedFileStem
            self.fileExtension = fileExtension
            self.width = width
            self.height = height
            self.sha256 = sha256
            self.attribution = attribution
        }
    }

    static let keplerPoster = "kepler-16b-nasa-jpl"
    static let grandCanyonTopographicMap = "grand-canyon-loc-usgs-west"
    static let barbarianMigrationMap = "butler-migrations-of-the-barbarians"
    static let lauBasinTectonicMap = "noaa-lau-basin-tectonic-features"
    static let weibeiSinglePendulumColorContrastScreenshot = "weibei-single-pendulum-color-contrast-screenshot"

    static let all: [Asset] = [
        Asset(
            id: keplerPoster,
            title: "Kepler-16b - JPL Travel Poster",
            processedFileStem: "kepler-16b-nasa-jpl-verification-2200",
            width: 1_523,
            height: 2_200,
            sha256: "50c84817f2a6bc6013dfd282029536e607cbb608e9a618e418d27441c8234506",
            attribution: "Credit: NASA/JPL-Caltech."
        ),
        Asset(
            id: grandCanyonTopographicMap,
            title: "Topographic map of the Grand Canyon National Park Arizona - West",
            processedFileStem: "grand-canyon-loc-usgs-west-verification-2200",
            width: 1_956,
            height: 2_200,
            sha256: "3b6157f979481afc9ba09ef1c5dd5dfe0762868aee7bcbe96a39ca12ab59ef99",
            attribution: "Credit: Library of Congress, Geography and Map Division; Geological Survey (U.S.)."
        ),
        Asset(
            id: barbarianMigrationMap,
            title: "Migrations of the Barbarians",
            processedFileStem: "butler-migrations-of-the-barbarians-verification-2200",
            width: 2_200,
            height: 1_471,
            sha256: "9bb3562f9611435a0d61358566b9c1713885750a5969f48e27c0156a87860790",
            attribution: "Samuel Butler, The Atlas of Ancient and Classical Geography, via Project Gutenberg / Wikimedia Commons."
        ),
        Asset(
            id: lauBasinTectonicMap,
            title: "Lau Basin Tectonic Features",
            processedFileStem: "lau-basin-noaa-tectonic-features-verification-2200",
            width: 2_200,
            height: 1_822,
            sha256: "d429ff67b22106ba3faef512315ae95a7c712eca0febc2b487a10c44c2e0c9b3",
            attribution: "Image courtesy of Submarine Ring of Fire 2012: NE Lau Basin, NOAA-OER."
        ),
        Asset(
            id: weibeiSinglePendulumColorContrastScreenshot,
            title: "WeiBei single-pendulum rich-answer color contrast screenshot",
            processedFileStem: "weibei-single-pendulum-color-contrast-original",
            fileExtension: "png",
            width: 2_616,
            height: 1_656,
            sha256: "c1c79970691385ff614f7c5a9eacedc21a094ba409bf242bb7c62d0716f06e1e",
            attribution: "WeiBei local rich-answer replay screenshot, 2026-07-18."
        ),
    ]

    static func asset(for id: String) -> Asset? {
        all.first { $0.id == id }
    }

    static func url(for id: String) -> URL? {
        guard let asset = asset(for: id) else { return nil }
        return url(
            forResource: asset.processedFileStem,
            withExtension: asset.fileExtension,
            subdirectory: "RichAnswerVerificationAssets/verification-only"
        )
    }

    static func image(for id: String) -> NSImage? {
        url(for: id).flatMap(NSImage.init(contentsOf:))
    }

    static func validateBundledResources() throws {
        let manifestURL = try requiredURL(
            forResource: "manifest",
            withExtension: "json",
            subdirectory: "RichAnswerVerificationAssets"
        )
        let manifestData = try Data(contentsOf: manifestURL)
        let manifestObject = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        let manifestAssets = manifestObject?["assets"] as? [[String: Any]] ?? []
        let manifestByID = Dictionary(uniqueKeysWithValues: manifestAssets.compactMap { entry -> (String, [String: Any])? in
            guard let id = entry["id"] as? String else { return nil }
            return (id, entry)
        })

        for asset in all {
            guard let entry = manifestByID[asset.id],
                  let derivative = entry["derivative"] as? [String: Any] else {
                throw RichAnswerVerificationAssetError.missingManifestEntry(asset.id)
            }
            guard derivative["sha256"] as? String == asset.sha256,
                  derivative["width"] as? Int == asset.width,
                  derivative["height"] as? Int == asset.height else {
                throw RichAnswerVerificationAssetError.manifestMismatch(asset.id)
            }
            let url = try requiredURL(
                forResource: asset.processedFileStem,
                withExtension: asset.fileExtension,
                subdirectory: "RichAnswerVerificationAssets/verification-only"
            )
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == asset.sha256 else {
                throw RichAnswerVerificationAssetError.hashMismatch(asset.id)
            }
            guard let representation = NSBitmapImageRep(data: data),
                  representation.pixelsWide == asset.width,
                  representation.pixelsHigh == asset.height else {
                throw RichAnswerVerificationAssetError.invalidImageSize(asset.id)
            }
        }
    }

    private static func requiredURL(
        forResource name: String,
        withExtension extensionName: String,
        subdirectory: String
    ) throws -> URL {
        guard let url = url(
            forResource: name,
            withExtension: extensionName,
            subdirectory: subdirectory
        ) else {
            throw RichAnswerVerificationAssetError.missingResource("\(subdirectory)/\(name).\(extensionName)")
        }
        return url
    }

    private static func url(
        forResource name: String,
        withExtension extensionName: String,
        subdirectory: String
    ) -> URL? {
        WeiBeiResources.bundle.url(
            forResource: name,
            withExtension: extensionName,
            subdirectory: subdirectory
        )
            ?? WeiBeiResources.bundle.url(forResource: name, withExtension: extensionName)
    }
}

enum RichAnswerVerificationAssetError: LocalizedError {
    case missingResource(String)
    case missingManifestEntry(String)
    case manifestMismatch(String)
    case hashMismatch(String)
    case invalidImageSize(String)

    var errorDescription: String? {
        switch self {
        case let .missingResource(path):
            return "Missing bundled rich-answer verification asset: \(path)"
        case let .missingManifestEntry(id):
            return "Missing manifest entry for rich-answer verification asset \(id)"
        case let .manifestMismatch(id):
            return "Manifest metadata does not match rich-answer verification asset \(id)"
        case let .hashMismatch(id):
            return "SHA-256 does not match rich-answer verification asset \(id)"
        case let .invalidImageSize(id):
            return "Image size does not match rich-answer verification asset \(id)"
        }
    }
}
