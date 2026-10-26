import Foundation
import Testing
@testable import Core

struct LocalizationTests {
    /// Every String Catalog in the repo: App, Watch, Complication and Core.
    static let catalogs: [URL] = {
        let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../..").standardized
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return (files?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "xcstrings" }
    }()

    @Test func everyStringHasGerman() throws {
        let folders = Set(Self.catalogs.map { $0.deletingLastPathComponent().lastPathComponent })
        #expect(folders.isSuperset(of: ["App", "Watch", "Complication", "Core"]))
        for url in Self.catalogs {
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            for (key, entry) in catalog?["strings"] as? [String: [String: Any]] ?? [:] {
                let german = (entry["localizations"] as? [String: Any])?["de"] as? [String: Any]
                let plural = (german?["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]]
                let units = plural.map { Array($0.values) } ?? [german ?? [:]]
                let translated = units.allSatisfy { ($0["stringUnit"] as? [String: String])?["state"] == "translated" }
                #expect(translated, "\(url.lastPathComponent): “\(key)” has no German")
            }
        }
    }

    /// The catalog's terms are looked up at runtime, so the build can't add them to the String Catalog.
    func german(_ table: String) throws -> [String: String] {
        let url = try #require(Bundle.module.url(forResource: table, withExtension: "strings", subdirectory: nil, localization: "de"))
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    @Test func everyCatalogTermHasGerman() throws {
        let muscles = Set(CatalogExercise.all.flatMap(\.primaryMuscles))
        let terms = CatalogFilter.levels + CatalogFilter.equipment + CatalogFilter.categories + muscles
        #expect(try terms.filter { try german("Localizable")[$0] == nil } == [])
    }

    /// RepDB brings German itself; a new commit of it must too.
    @Test func everyExerciseComesInGerman() {
        let missing = CatalogExercise.all.filter { $0.germanName.isEmpty || $0.germanInstructions.count != $0.instructions.count }
        #expect(missing.map(\.id) == [])
    }

    @Test func coreShipsItsGermanStrings() {
        var resource = LocalizedStringResource("Not synced yet", bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = Locale(identifier: "de")
        #expect(String(localized: resource) == "Noch nicht synchronisiert")
    }
}
