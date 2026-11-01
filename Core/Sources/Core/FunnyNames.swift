import Foundation
import SwiftData

/// Funny plan names by the region a plan trains most, nil for full body, each with the emoji that pictures it.
/// They're looked up by key at runtime, so their German is added to Core's catalog by hand, like `catalogTerm`'s terms.
let funnyNames: [BodyRegion?: [(key: String, emoji: String)]] = [
    .legs: [("Leg Day Sucks", "🍗"), ("Quadzilla", "🦖"), ("Thunder Thighs", "⚡️"), ("Wobbly Walk Home", "🥴")],
    .arms: [("Armageddon", "💪"), ("Sun's Out, Guns Out", "☀️"), ("Curl Power", "🌀"), ("Tricep Trouble", "😤")],
    .chest: [("International Chest Day", "🌍"), ("Chesty McChestface", "🦍"), ("Pec Deck Party", "🎉"), ("Bench Warmers", "🪑")],
    .back: [("Back to the Future", "🚀"), ("Lat Attack", "🦇"), ("Got Your Back", "🐢"), ("Pull Request", "🔁")],
    .shoulders: [("Boulder Shoulders", "🪨"), ("Delt With It", "😎"), ("Shrug Life", "🤷"), ("Cold Shoulder", "🧊")],
    .core: [("Core-ocalypse", "🔥"), ("Plank You Very Much", "🙏"), ("Abs of Steel", "🛡️"), ("Six-Pack Hunt", "🍺")],
    nil: [("Everything Hurts", "😵"), ("The Full Monty", "🎩"), ("Head to Toe Woe", "🫠"), ("Total Body Meltdown", "🌋")],
]

/// `key` in English and every language of Core's catalog.
private func spellings(_ key: String) -> [String] {
    [key] + Bundle.module.localizations.map { language in
        var resource = LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }
}

/// Each funny name in every language to its emoji, so one a device in the other language gave counts as funny too.
private let funnyEmoji = Dictionary(funnyNames.values.joined().flatMap { name in spellings(name.key).map { ($0, name.emoji) } }) { first, _ in first }
private let newPlanNames = Set(spellings("New plan"))

public extension Plan {
    /// Whether nobody typed the plan's name: it has none, "New plan" or a funny one, in any language.
    var hasAutoName: Bool { name.isEmpty || newPlanNames.contains(name) || funnyEmoji[name] != nil }

    /// The plan's picture: its funny name's emoji, else one of the funny names' for what it trains, by its place in the list,
    /// so plans side by side differ, else a lifter.
    var emoji: String {
        funnyEmoji[name] ?? focusRegions.flatMap { funnyNames[$0.first].map { $0[abs(order) % $0.count].emoji } } ?? "🏋️"
    }
}

public extension ModelContext {
    /// A funny name for what `plan` trains, one no other plan has while there are enough: its own while it still fits,
    /// else the first free one. `next` takes the one after its own, as the dice does. Nil while it trains no catalog exercise.
    func funnyName(for plan: Plan, next: Bool = false) -> String? {
        guard let regions = plan.focusRegions, let names = funnyNames[regions.first]?.map({ catalogTerm($0.key) }) else { return nil }
        let own = names.firstIndex(of: plan.name)
        if let own, !next { return names[own] }
        let start = own.map { $0 + 1 } ?? 0
        let taken = Set(((try? fetch(FetchDescriptor<Plan>())) ?? []).filter { $0 != plan }.map(\.name))
        let turn = names[start...] + names[..<start]
        return turn.first { !taken.contains($0) } ?? turn.first
    }

    /// Renames `plan` funnily for what it trains now, unless you typed its name. `force` does anyway, as an import does.
    func nameFunnily(_ plan: Plan?, force: Bool = false) {
        guard let plan, force || plan.hasAutoName, let name = funnyName(for: plan), name != plan.name else { return }
        rename(plan, to: name)
    }

    /// The dice: the next funny name for what `plan` trains, whoever named it.
    func rollFunnyName(_ plan: Plan) {
        if let name = funnyName(for: plan, next: true) { rename(plan, to: name) }
    }
}
