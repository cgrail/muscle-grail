import Foundation

/// An exercise from free-exercise-db (public domain): https://github.com/yuhonas/free-exercise-db
/// `exercises.json` is its `dist/exercises.json`, bundled unchanged.
public struct CatalogExercise: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let equipment: String?
    public let primaryMuscles: [String]
    public let images: [String]

    public static let all = load(Bundle.module.url(forResource: "exercises", withExtension: "json"))

    static func load(_ url: URL?) -> [CatalogExercise] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CatalogExercise].self, from: data)) ?? []
    }

    // shortcut: images (~100 MB in total) load from GitHub, so they show placeholders offline; bundle thumbnails if plans get built offline
    public var imageURL: URL? {
        images.first.flatMap { URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\($0)") }
    }

    public var detail: String { (primaryMuscles + [equipment].compactMap { $0 }).joined(separator: " · ") }

    public func matches(_ query: String) -> Bool {
        matchesEveryWord(of: query, in: [name, equipment ?? ""] + primaryMuscles)
    }
}

/// Whether each word of `query` turns up somewhere in `fields`, ignoring case, hyphens and a plural "s":
/// "dumbbell curl" finds Dumbbell Bicep Curl, "squats" Barbell Squat and "pull-ups" Pullups.
func matchesEveryWord(of query: String, in fields: [String]) -> Bool {
    query.split(whereSeparator: { $0 == " " || $0 == "-" }).allSatisfy { word in
        let singular = word.count > 3 && word.hasSuffix("s") ? word.dropLast() : word
        return fields.contains { $0.localizedCaseInsensitiveContains(singular) }
    }
}
