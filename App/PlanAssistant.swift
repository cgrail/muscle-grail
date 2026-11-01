#if os(macOS)
import Core
import FoundationModels
import SwiftData
import SwiftUI

/// Adds exercises to a plan from a description like "3x10 bench press at 60 kg, then squats", with Apple's on-device
/// model. Sits beside Add exercise at the bottom of the plan and opens a sheet to describe them.
struct PlanAssistant: View {
    let plan: Plan
    @State private var describing = false

    var body: some View {
        Button("Describe exercises", systemImage: "sparkles") { describing = true }
            .sheet(isPresented: $describing) { AssistantSheet(plan: plan) }
    }
}

/// Reads a text field, so dictation (the dictation key) works as well as typing. Suggest shows what the model understood,
/// each exercise as the catalog one it becomes or a new one of the user's own, and Add puts them into the plan.
private struct AssistantSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [CatalogEntry]
    let plan: Plan
    @State private var request = ""
    @State private var working = false
    @State private var failed = false
    /// Each exercise the model proposes with the catalog id it gets, nil for a new exercise.
    @State private var proposal: [(exercise: PlannedExercise, id: String?)] = []

    var body: some View {
        NavigationStack {
            Form {
                switch SystemLanguageModel.default.availability {
                case .available:
                    Section {
                        TextField(text: $request, prompt: Text("Describe exercises, like 3x10 bench press at 60 kg"), axis: .vertical) {
                            Text("Describe exercises")
                        }
                        .labelsHidden()
                        .lineLimit(3...6)
                        .onSubmit(suggest)
                        HStack {
                            if failed {
                                Text("Couldn't understand that. Name each exercise with its sets, reps and weight.").foregroundStyle(.red)
                            }
                            Spacer()
                            if working {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Suggest", systemImage: "sparkles", action: suggest).disabled(request.isEmpty)
                            }
                        }
                    }
                    if !proposal.isEmpty {
                        Section("Suggestion") {
                            ForEach(proposal.indices, id: \.self) { ProposalRow(exercise: proposal[$0].exercise, id: proposal[$0].id) }
                        }
                    }
                case .unavailable(.appleIntelligenceNotEnabled):
                    Text("Turn on Apple Intelligence to add exercises by describing them.").foregroundStyle(.secondary)
                case .unavailable:
                    Text("Adding exercises by describing them needs Apple Intelligence.").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Describe exercises")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.add(proposal.map { $0.exercise }, to: plan)
                        dismiss()
                    }
                    .disabled(proposal.isEmpty || working)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .onChange(of: request) { (proposal, failed) = ([], false) } // a suggestion always shows what the text says
    }

    private func suggest() {
        guard !request.isEmpty, !working else { return }
        let request = request, custom = entries.filter(\.isOwnExercise).map(\.name)
        (working, failed, proposal) = (true, false, [])
        Task {
            do {
                proposal = try await Self.exercises(from: request, custom: custom).map { (exercise: $0, id: context.catalogID(named: $0.name)) }
                failed = proposal.isEmpty
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

/// An exercise as the assistant would add it: its photo and name, or "New exercise" for one the catalog lacks, with its targets.
private struct ProposalRow: View {
    @Environment(\.modelContext) private var context
    let exercise: PlannedExercise
    let id: String?

    var body: some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(id: id ?? "", size: 36)
            VStack(alignment: .leading) {
                if let id {
                    ExerciseName(id)
                    if let detail = CatalogExercise.byID[id]?.detail { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary) }
                } else {
                    Text(verbatim: exercise.name)
                    Text("New exercise").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(verbatim: "\(exercise.sets) × \(exercise.reps)").monospacedDigit()
            if exercise.weightKg > 0 {
                Text(verbatim: context.weightUnit(of: id ?? "").format(exercise.weightKg)).monospacedDigit().frame(minWidth: 60, alignment: .trailing)
            }
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
