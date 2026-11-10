#if os(macOS)
import Core
import SwiftData
import SwiftUI

/// What a GymBook file brings, before it comes in: its plans to pick, the history it adds or leaves out, how many records
/// that adds to yours, and each exercise it uses beside the one it becomes here, with its photo, muscles and equipment.
/// One found by its name in English, German or Spanish is picked; the others come first, and Apple Intelligence guesses
/// among the likeliest, where it can. Click one to choose another (`ExerciseChooser`).
struct GymBookImport: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let file: GymBook.File
    /// The workouts not imported before, the newest first.
    let workouts: [GymBook.Session]
    let suggestions: [String: [String]]
    let onImport: (_ exercises: [String: String], _ leavingOut: Set<String>, _ history: Bool) -> Void
    @State private var exercises: [String: String]
    @State private var leavingOut: Set<String>
    @State private var history = true
    /// The records here now, which the import adds to.
    @State private var records: Int?
    @State private var choosing: String?
    /// The exercises Apple Intelligence guessed, and those you chose, which it leaves alone.
    @State private var guessed: Set<String> = []
    @State private var chosen: Set<String> = []
    @State private var guessing = false
    private let unmatched: [String]
    private let sets: [String: Int]
    private let planWorkouts: [String: Int]

    init(file: GymBook.File, matches: [String: String], workouts: [GymBook.Session], suggestions: [String: [String]],
         onImport: @escaping ([String: String], Set<String>, Bool) -> Void) {
        (self.file, self.workouts, self.suggestions, self.onImport) = (file, workouts, suggestions, onImport)
        _exercises = State(initialValue: matches)
        _leavingOut = State(initialValue: Set(file.plans.filter(\.archived).map(\.name))) // GymBook's active plans come in
        unmatched = file.exercises.filter { matches[$0] == nil }
        sets = file.sessions.flatMap(\.done).reduce(into: [:]) { $0[$1.exercise, default: 0] += 1 }
        planWorkouts = file.sessions.reduce(into: [:]) { $0[$1.plan, default: 0] += 1 }
    }

    var body: some View {
        let here = context.gymBookPlansHere(file)
        let used = context.gymBookExercisesUsed(file, workouts: history ? workouts : [], leavingOut: leavingOut)
        let unfound = unmatched.filter(used.contains)
        let matched = file.exercises.filter { used.contains($0) && !unmatched.contains($0) }
        NavigationStack {
            Form {
                Section {
                    ForEach(file.plans, id: \.name) { plan in
                        Toggle(isOn: Binding { here.contains(plan.name) || !leavingOut.contains(plan.name) } set: { on in
                            if on { leavingOut.remove(plan.name) } else { leavingOut.insert(plan.name) }
                        }) {
                            Text(plan.name)
                            if here.contains(plan.name) {
                                Text("You have this plan: it stays as it is.")
                            } else if plan.archived {
                                Text("Archived · Exercises: \(plan.exercises.count) · Workouts: \(planWorkouts[plan.name] ?? 0)")
                            } else {
                                Text("Exercises: \(plan.exercises.count) · Workouts: \(planWorkouts[plan.name] ?? 0)")
                            }
                        }
                        .disabled(here.contains(plan.name))
                    }
                } header: {
                    Text("Plans")
                } footer: {
                    Text("Each comes in with its exercises, sets, reps and weight. A workout of a plan left out has no plan here.")
                }
                Section {
                    Toggle("Import the history", isOn: $history)
                    if history, let last = workouts.first?.done.first?.date, let first = workouts.last?.done.first?.date {
                        LabeledContent("Workouts", value: workouts.count, format: .number)
                        LabeledContent("Sets", value: workouts.map(\.done.count).reduce(0, +), format: .number)
                        LabeledContent("From", value: first, format: .dateTime.day().month().year())
                        LabeledContent("To", value: last, format: .dateTime.day().month().year())
                        let planless = workouts.filter { !here.contains($0.plan) && leavingOut.contains($0.plan) }.count
                        if planless > 0 { LabeledContent("Without a plan", value: planless, format: .number) }
                    } else if history {
                        Text("Every workout of this file is here already.")
                    }
                } header: {
                    Text("History")
                } footer: {
                    Text("Cardio and skipped sets stay out. Importing again adds nothing.")
                }
                size
                if !unfound.isEmpty {
                    Section {
                        ForEach(unfound, id: \.self, content: row)
                    } header: {
                        HStack {
                            Text("Not found by name")
                            if guessing {
                                ProgressView().controlSize(.small)
                                Text("Apple Intelligence is guessing…")
                            }
                        }
                    } footer: {
                        VStack(alignment: .leading) {
                            Text("Click one to see the likeliest with their photos and steps, or to search the catalog. New exercise keeps it as your own.")
                            if !guessed.isEmpty {
                                Text("Apple Intelligence guessed the ones marked \(Image(systemName: "sparkles")): check them.")
                            } else if !ExerciseMatcher.isAvailable {
                                Text("With Apple Intelligence on, it guesses these.")
                            }
                        }
                    }
                }
                if !matched.isEmpty {
                    Section("Found in the catalog") { ForEach(matched, id: \.self, content: row) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import from GymBook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import") { onImport(exercises, leavingOut, history); dismiss() } }
            }
            .sheet(isPresented: Binding { choosing != nil } set: { if !$0 { choosing = nil } }) {
                if let choosing {
                    ExerciseChooser(name: choosing, likeliest: suggestions[choosing] ?? [], current: exercises[choosing]) {
                        choose($0, for: choosing)
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 640)
        .task {
            records = context.gymBookRecordCount()
            await guess()
        }
    }

    /// How many records the import adds with what is chosen, beside those here now.
    private var size: some View {
        let size = context.gymBookImportSize(file, workouts: history ? workouts : [], exercises: exercises, leavingOut: leavingOut)
        return Section {
            LabeledContent("Plans", value: size.plans, format: .number)
            LabeledContent("Exercises in plans", value: size.planExercises, format: .number)
            LabeledContent("Exercises of your own", value: size.exercises, format: .number)
            LabeledContent("Workouts", value: size.workouts, format: .number)
            LabeledContent("Sets", value: size.sets, format: .number)
            LabeledContent("Records added", value: size.total, format: .number).bold()
            if let records {
                LabeledContent("Records here now", value: records, format: .number)
                if records > 0 { LabeledContent("Growth", value: Double(size.total) / Double(records), format: .percent.precision(.fractionLength(0))) }
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Each record also gets an entry in the change log, and syncs to your devices.")
        }
    }

    /// Lets Apple Intelligence guess each exercise its name doesn't find among the closest, unless you chose already.
    private func guess() async {
        guard ExerciseMatcher.isAvailable else { return }
        guessing = true
        for name in unmatched where !Task.isCancelled {
            let ids = suggestions[name] ?? []
            let names = ids.map { context.exerciseName($0, localized: false) }
            guard let index = await ExerciseMatcher.pick(name, englishName: file.englishNames[name], among: names),
                  !chosen.contains(name) else { continue }
            exercises[name] = ids[index]
            guessed.insert(name)
        }
        guessing = false
    }

    private func choose(_ id: String?, for name: String) {
        exercises[name] = id
        chosen.insert(name)
        guessed.remove(name)
    }

    /// A GymBook exercise beside the one it becomes, which a click changes.
    private func row(_ name: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                if let count = sets[name] { Text("Sets: \(count)").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            Button { choosing = name } label: {
                HStack {
                    if let id = exercises[name] {
                        let bundled = CatalogExercise.byID[id], entry = context.catalogEntry(id)
                        CatalogRow(name: context.exerciseName(id), detail: bundled?.detail ?? entry?.details ?? "", photo: entry?.photo,
                                   imageURL: bundled?.imageURL)
                    } else {
                        CatalogRow(name: String(localized: "New exercise"), detail: String(localized: "Your own, by its GymBook name"))
                    }
                    if guessed.contains(name) {
                        Image(systemName: "sparkles").foregroundStyle(.tint).help("Guessed by Apple Intelligence")
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }
}
#endif
