#if os(macOS)
import Foundation
import FoundationModels

/// Asks Apple's on-device model which of a few catalog exercises another app's exercise is, for one its name doesn't find.
/// It reads names in English, German and Spanish, but seldom answers that none is, so its pick is a guess to check.
enum ExerciseMatcher {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    /// Which of `candidates`, English catalog names, the exercise `name` is: nil for none, or when the model fails.
    /// `englishName` is the other app's own, if it keeps one.
    static func pick(_ name: String, englishName: String?, among candidates: [String]) async -> Int? {
        // permissive: the default guardrails refuse harmless names like "Lat-Ziehen mit breitem Griff"
        let session = LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: """
            You know gym exercises by their English, German and Spanish names. You say which catalog exercise is the same \
            as an exercise from another app: the same movement with the same equipment, though grip width or alternating \
            arms may differ. You answer with its number only, or 0 if none is the same.
            """)
        let list = candidates.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let prompt = "Exercise: \(name)" + (englishName.map { " (in the other app also \($0))" } ?? "") + "\n\(list)\n0. None of them"
        guard let answer = try? await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines),
              let number = answer.firstMatch(of: #/\d+/#).flatMap({ Int($0.output) }), candidates.indices.contains(number - 1)
        else { return nil }
        return number - 1
    }
}
#endif
