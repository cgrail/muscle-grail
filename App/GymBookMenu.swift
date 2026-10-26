#if os(macOS)
import AppKit
import Core
import SwiftData
import SwiftUI

/// History's GymBook menu on the Mac: import GymBook's log export, each of its exercises matched to one here first,
/// or export the history in its format. Both run off the main actor.
struct GymBookMenu: View {
    @Environment(\.modelContext) private var context
    @Query(Action.newer) private var newer: [Action]
    @State private var choosing = false
    @State private var logs: [GymBook.Log]?
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Menu("GymBook", systemImage: "square.and.arrow.down.on.square") {
            Button("Import from GymBook…") { choosing = true }
                .disabled(busy || !newer.isEmpty) // it makes plans, which wait for an update after a newer version's changes
            Button("Export for GymBook…", action: export).disabled(busy)
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.xml]) { result in
            if case let .success(file) = result { read(file) }
        }
        .sheet(isPresented: Binding { logs != nil } set: { if !$0 { logs = nil } }) { [logs] in
            GymBookImport(logs: logs ?? []) { run(logs ?? [], $0) }
        }
        .alert(message ?? "", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }) {}
    }

    private func read(_ file: URL) {
        Task {
            let result = await Task.detached {
                let access = file.startAccessingSecurityScopedResource()
                defer { if access { file.stopAccessingSecurityScopedResource() } }
                return Result { try GymBook.logs(Data(contentsOf: file)) }
            }.value
            switch result {
            case let .success(read): logs = read
            case let .failure(failure): message = failure.localizedDescription
            }
        }
    }

    private func run(_ logs: [GymBook.Log], _ exercises: [String: String]) {
        busy = true
        let container = context.container
        Task {
            let result = await Task.detached {
                Result {
                    let context = ModelContext(container)
                    let added = context.importGymBook(logs, exercises: exercises)
                    try context.save()
                    return added
                }
            }.value
            busy = false
            switch result {
            case let .success(added): message = String(localized: "Imported \(added) workouts from GymBook.")
            case let .failure(failure): message = failure.localizedDescription
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Muscle Grail Logs.xml"
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true
        let container = context.container
        Task {
            let result = await Task.detached { Result { try ModelContext(container).gymBookExport().write(to: url, options: .atomic) } }.value
            busy = false
            if case let .failure(failure) = result { message = failure.localizedDescription }
        }
    }
}

/// Each exercise of the GymBook file beside the exercise it becomes here: the one by that name, else a new one of the
/// user's own with its GymBook name. Click one to pick another from the catalog.
private struct GymBookImport: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let logs: [GymBook.Log]
    let onImport: ([String: String]) -> Void
    @State private var exercises: [String: String] = [:]
    @State private var picking: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(GymBook.exercises(in: logs), id: \.self) { name in
                        LabeledContent(name) {
                            Button { picking = name } label: {
                                if let id = exercises[name] { ExerciseName(id) } else { Text("New exercise") }
                            }
                        }
                    }
                } footer: {
                    Text("Each workout name becomes a plan, unless you have one by that name. Cardio stays out.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import from GymBook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import") { onImport(exercises); dismiss() } }
            }
            .sheet(isPresented: Binding { picking != nil } set: { if !$0 { picking = nil } }) {
                ExercisePicker(title: "Import as") { id in if let picking { exercises[picking] = id } }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
        .onAppear { for name in GymBook.exercises(in: logs) { exercises[name] = context.catalogID(named: name) } }
    }
}
#endif
