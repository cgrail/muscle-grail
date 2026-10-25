import Foundation

/// The weights a gym actually has for an exercise's equipment, so a stepper goes 20 → 22 kg for dumbbells
/// and never offers 20.7 kg. A weight between two real ones steps to the nearest real one.
public enum Weights {
    public static func next(after weight: Double, for exerciseID: String) -> Double {
        ladder(for: CatalogExercise.byID[exerciseID]?.equipment).first { $0 > weight + 0.01 } ?? weight
    }

    public static func previous(before weight: Double, for exerciseID: String) -> Double {
        ladder(for: CatalogExercise.byID[exerciseID]?.equipment).last { $0 < weight - 0.01 } ?? 0
    }

    /// Every weight there is, ascending, from 0. Plates (2.5 kg, a 1.25 kg disc on each side) for barbells
    /// and whatever the catalog doesn't say, the user's own exercises included.
    static func ladder(for equipment: String?) -> [Double] {
        switch equipment {
        case "dumbbell": [0] + Array(stride(from: 1.0, through: 10, by: 1)) + Array(stride(from: 12.0, through: 80, by: 2))
        case "kettlebells": [0, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 40, 44, 48]
        case "machine", "cable": Array(stride(from: 0.0, through: 300, by: 5))
        case "medicine ball": Array(stride(from: 0.0, through: 15, by: 1))
        default: Array(stride(from: 0.0, through: 500, by: 2.5))
        }
    }
}
