import Foundation

/// The weights a gym actually has for an exercise's equipment, so a stepper goes 20 → 22 kg for dumbbells
/// and never offers 20.7 kg. A weight between two real ones steps to the nearest real one.
public enum Weights {
    public static func next(after weight: Double, for exerciseID: String, in unit: WeightUnit = .kg) -> Double {
        ladder(for: CatalogExercise.byID[exerciseID]?.equipment, in: unit).first { $0 > weight + 0.01 } ?? weight
    }

    public static func previous(before weight: Double, for exerciseID: String, in unit: WeightUnit = .kg) -> Double {
        ladder(for: CatalogExercise.byID[exerciseID]?.equipment, in: unit).last { $0 < weight - 0.01 } ?? 0
    }

    /// A typed weight with either decimal separator, "62,5" or "62.5". Nil for anything but a weight of 0 kg or more.
    public static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacing(",", with: ".")).flatMap { $0 >= 0 && $0.isFinite ? $0 : nil }
    }

    /// Every weight there is in kg, ascending, from 0. Plates (2.5 kg, a 1.25 kg disc on each side) for barbells, the Smith
    /// machine, plate-loaded machines and whatever the catalog doesn't say, the user's own exercises included.
    static func ladder(for equipment: String?, in unit: WeightUnit = .kg) -> [Double] {
        // shortcut: everything in lb steps by 5 lb, the smallest plates' pair; give lb its own ladders if a stack steps by 10
        if unit == .lb { return stride(from: 0.0, through: 1000, by: 5).map(unit.kg) }
        return switch equipment {
        case "dumbbell": [0] + Array(stride(from: 1.0, through: 10, by: 1)) + Array(stride(from: 12.0, through: 80, by: 2))
        case "kettlebell": [0, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 40, 44, 48]
        case "medicine_ball", "slam_ball", "wall_ball": Array(stride(from: 0.0, through: 15, by: 1))
        case let stack? where stack.hasSuffix("machine") ? !stack.hasPrefix("plate_loaded") && stack != "smith_machine"
            : ["cable", "leg_curl", "leg_extension", "pec_deck"].contains(stack): Array(stride(from: 0.0, through: 300, by: 5))
        default: Array(stride(from: 0.0, through: 500, by: 2.5))
        }
    }
}

/// The unit an exercise's machine shows. Weights are always stored in kg; only showing, typing and stepping use the unit.
public enum WeightUnit: String, CaseIterable, Sendable {
    case kg, lb

    static let kgPerPound = 0.45359237

    /// `kg` in this unit.
    public func value(_ kg: Double) -> Double { self == .lb ? kg / Self.kgPerPound : kg }

    /// A weight in this unit, in kg to store.
    public func kg(_ value: Double) -> Double { self == .lb ? value * Self.kgPerPound : value }

    /// "62.5 kg", "110 lb".
    public func format(_ kg: Double) -> String { "\(number(kg)) \(rawValue)" }

    /// The number alone, as the weight field shows it.
    public func number(_ kg: Double) -> String { value(kg).formatted(.number.grouping(.never).precision(.fractionLength(0...2))) }
}
