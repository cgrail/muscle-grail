import Foundation
import SwiftData

/// Funny plan names by the region a plan trains most, nil for full body: cartoon characters, each with a motto and a drawing,
/// `Characters/<pictureID>.png`, rendered from `Design/Characters/`.
/// They're looked up by key at runtime, so the German of names and mottos is added to Core's catalog by hand, like `catalogTerm`'s terms.
let funnyNames: [BodyRegion?: [(key: String, motto: String)]] = [
    .legs: [
        ("Leggy", "Stairs are temporary. Gains are forever."),
        ("Booty", "Built from behind."),
        ("The Quadfather", "Make them an offer they can't refuse: more squats."),
        ("Thunder Thighs", "Walk in wobbly. Walk out legendary."),
        ("Peach Protocol", "No peach left behind."),
        ("Squatzilla", "Fear the rack. Respect the depth."),
        ("Lunge Larry", "One step at a time, preferably burning."),
        ("Hamstring Hank", "Pull your weight, then some more."),
        ("Calf Carl", "Small muscle. Big attitude."),
        ("The Stair Survivor", "Leg day today. Walking sideways tomorrow."),
    ],
    .arms: [
        ("The Arm-y", "Enlisted today. Flexing forever."),
        ("Captain Curl", "Curl first, ask questions later."),
        ("Tricep Titan", "Three heads. One mission."),
    ],
    .chest: [
        ("Bench Bernie", "Keep pressing. No regrets."),
        ("Bench Bandit", "No bench is safe."),
        ("Chicken Breast Charlie", "Chest out, beak up."),
    ],
    .back: [
        ("Back Rambo", "Rows before bros."),
        ("The Pull-Up Pirate", "Steal reps. Raise the bar."),
    ],
    .shoulders: [
        ("Shoulder Shogun", "Rule from every angle."),
        ("Deltoid Diva", "Capped, not cancelled."),
    ],
    .core: [
        ("Corey", "Brace yourself. Literally."),
        ("Planky", "Hold the line."),
    ],
    nil: [
        ("Full-Body Fiona", "No muscle left untouched."),
        ("Cardio Carol", "I came for the burn. I stayed for the gossip."),
        ("The Sweaty Potato", "From couch to crusher."),
        ("Burpee Betty", "One burpee at a time, sadly."),
        ("The Treadmill Titan", "Same belt. New best time."),
        ("Mobility Pug", "Bend so you don't break."),
        ("Rest Day Rudy", "Professional napper. Amateur lifter."),
    ],
]

/// The funny names before the characters: nobody typed them either, so their plans get a character with their next change.
private let retiredNames = [
    "Leg Day Sucks", "Quadzilla", "Wobbly Walk Home", "Armageddon", "Sun's Out, Guns Out", "Curl Power", "Tricep Trouble",
    "International Chest Day", "Chesty McChestface", "Pec Deck Party", "Bench Warmers", "Back to the Future", "Lat Attack",
    "Got Your Back", "Pull Request", "Boulder Shoulders", "Delt With It", "Shrug Life", "Cold Shoulder", "Core-ocalypse",
    "Plank You Very Much", "Abs of Steel", "Six-Pack Hunt", "Everything Hurts", "The Full Monty", "Head to Toe Woe", "Total Body Meltdown",
]

/// The file name of a character's drawing: "The Pull-Up Pirate" is drawn in `the-pull-up-pirate`.
func pictureID(_ key: String) -> String { key.lowercased().split { !$0.isLetter }.joined(separator: "-") }

/// `key` in English and every language of Core's catalog.
private func spellings(_ key: String) -> [String] {
    [key] + Bundle.module.localizations.map { language in
        var resource = LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
    }
}

/// Each funny name in every language to its character, so one a device in the other language gave counts as funny too.
private let characters = Dictionary(funnyNames.values.joined().flatMap { character in spellings(character.key).map { ($0, character) } }) { first, _ in first }
private let otherAutoNames = Set((["New plan"] + retiredNames).flatMap(spellings))

public extension Plan {
    /// Whether nobody typed the plan's name: it has none, "New plan" or a funny one, of this version or an earlier one, in any language.
    var hasAutoName: Bool { name.isEmpty || otherAutoNames.contains(name) || characters[name] != nil }

    /// The motto of the character the plan is named after, nil for a name you typed.
    var motto: String? { characters[name].map { catalogTerm($0.motto) } }

    /// The plan's picture: the drawing of the character it's named after, else of one of the characters for what it trains,
    /// by its place in the list, so plans side by side differ. Nil while it trains no catalog exercise.
    var picture: URL? {
        guard let key = characters[name]?.key ?? focusRegions.flatMap({ funnyNames[$0.first].map { $0[abs(order) % $0.count].key } }) else { return nil }
        return Bundle.module.url(forResource: pictureID(key), withExtension: "png", subdirectory: "Characters")
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
