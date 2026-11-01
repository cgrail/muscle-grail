#if os(macOS)
import Core
import FoundationModels
import SwiftData
import SwiftUI

/// Adds exercises to a plan from a description like "3x10 bench press at 60 kg, then squats", with Apple's on-device
/// model. It reads a text field, so dictation (the dictation key) works as well as typing.
struct PlanAssistant: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [CatalogEntry]
    let plan: Plan
    @State private var request = ""
    @State private var working = false
    @State private var failed = false

    var body: some View {
        switch SystemLanguageModel.default.availability {
        case .available:
            HStack {
                TextField("Describe exercises, like 3x10 bench press at 60 kg", text: $request, axis: .vertical).onSubmit(send)
                if working {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Add", systemImage: "sparkles", action: send).disabled(request.isEmpty)
                }
            }
            if failed {
                Text("Couldn't understand that. Name each exercise with its sets, reps and weight.").foregroundStyle(.red)
            }
        case .unavailable(.appleIntelligenceNotEnabled):
            Text("Turn on Apple Intelligence to add exercises by describing them.").foregroundStyle(.secondary)
        case .unavailable:
            Text("Adding exercises by describing them needs Apple Intelligence.").foregroundStyle(.secondary)
        }
    }

    private func send() {
        let request = request, custom = entries.filter(\.isOwnExercise).map(\.name)
        (working, failed) = (true, false)
        Task {
            do {
                context.add(try await Self.exercises(from: request, custom: custom), to: plan)
                self.request = ""
            } catch {
                failed = true
            }
            working = false
        }
    }

    private static func exercises(from request: String, custom: [String]) async throws -> [PlannedExercise] {
        let defaults = targetDefaults()
        let session = LanguageModelSession(tools: [FindExercise(custom: custom)], instructions: """
            You turn a description of gym exercises into a list. For each exercise, search its English name with \
            findExercise (translate German names first: Klimmzüge are pull ups) and use the exact name it returns; \
            if nothing fits, use the user's own words. Take sets, reps and weight from the user: "3x10 at 60 kg" is \
            3 sets of 10 reps with 60 kg. Only for what the user leaves out, use \(defaults.sets) sets, \(defaults.reps) reps and 0 kg.
            """)
        return try await session.respond(to: request, generating: Draft.self).content.exercises.map {
            PlannedExercise(name: $0.name, sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg)
        }
    }
}

@Generable nonisolated private struct Draft {
    @Generable struct Exercise {
        @Guide(description: "The exact name from findExercise, or the user's own words") var name: String
        @Guide(.range(1...20)) var sets: Int
        @Guide(.range(1...100)) var reps: Int
        @Guide(description: "The weight the user gave, in kg: 60 for '60 kg'. 0 if none") var weightKg: Double
    }

    var exercises: [Exercise]
}

nonisolated private struct FindExercise: Tool {
    let name = "findExercise"
    let description = "Searches the exercise catalog by name, muscle or equipment. Returns matching exercise names."
    let custom: [String]

    @Generable struct Arguments {
        @Guide(description: "English words, like 'dumbbell curl'") var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        catalogNames(matching: arguments.query, custom: custom).joined(separator: "\n")
    }
}
#endif
