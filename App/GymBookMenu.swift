#if os(macOS)
import AppKit
import Core
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Starts importing a GymBook file in its window.
struct ImportGymBook: Equatable {
    let start: () -> Void

    func callAsFunction() { start() }

    static func == (_: Self, _: Self) -> Bool { true } // a window's always starts the same import
}

extension EnvironmentValues {
    /// Nil while importing can't start: plans wait for an update after a newer version's changes, and one import runs
    /// at a time.
    @Entry var importGymBook: ImportGymBook?
}

extension FocusedValues {
    @Entry var importGymBook: ImportGymBook?
}

/// File → Import from GymBook…, for the window in front.
struct GymBookCommands: Commands {
    @FocusedValue(\.importGymBook) private var importGymBook

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Import from GymBook…") { importGymBook?() }.disabled(importGymBook == nil)
        }
    }
}

/// Imports a GymBook file, its log export or full backup: asks for it, shows what it brings (`GymBookImport`), then
/// imports it. Reading, matching and importing run off the main actor. The File menu and History's GymBook menu start it.
struct GymBookImporter: ViewModifier {
    @Environment(\.modelContext) private var context
    @Query(Action.newer) private var newer: [Action]
    @State private var choosing = false
    @State private var found: (file: GymBook.File, matches: [String: String], workouts: [GymBook.Session], suggestions: [String: [String]])?
    @State private var busy = false
    @State private var message: String?

    func body(content: Content) -> some View {
        let start = busy || !newer.isEmpty ? nil : ImportGymBook { choosing = true }
        content
            .environment(\.importGymBook, start)
            .focusedSceneValue(\.importGymBook, start)
            // GymBook declares the backup's type only where it's installed
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.xml, UTType(filenameExtension: "database") ?? .database]) { result in
                if case let .success(url) = result { read(url) }
            }
            .sheet(isPresented: Binding { found != nil } set: { if !$0 { found = nil } }) {
                if let found {
                    GymBookImport(file: found.file, matches: found.matches, workouts: found.workouts, suggestions: found.suggestions) {
                        run(found.file, $0, leavingOut: $1)
                    }
                }
            }
            .alert(message ?? "", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }) {}
    }

    private func read(_ url: URL) {
        busy = true
        let container = context.container
        Task {
            let result = await Task.detached {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                return Result {
                    let file = try GymBook.read(Data(contentsOf: url))
                    let context = ModelContext(container)
                    let suggestions = Dictionary(uniqueKeysWithValues: file.exercises.map { ($0, file.suggestions(for: $0).map(\.id)) })
                    return (file, context.gymBookMatches(file), context.newWorkouts(in: file), suggestions)
                }
            }.value
            busy = false
            switch result {
            case let .success(read): found = read
            case let .failure(failure): message = failure.localizedDescription
            }
        }
    }

    private func run(_ file: GymBook.File, _ exercises: [String: String], leavingOut: Set<String>) {
        busy = true
        let container = context.container
        Task {
            let result = await Task.detached {
                Result {
                    let context = ModelContext(container)
                    let added = context.importGymBook(file, exercises: exercises, leavingOut: leavingOut)
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
}

/// History's GymBook menu: import a GymBook file, or export the history in GymBook's format off the main actor.
struct GymBookMenu: View {
    @Environment(\.modelContext) private var context
    @Environment(\.importGymBook) private var importGymBook
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Menu("GymBook", systemImage: "square.and.arrow.down.on.square") {
            Button("Import from GymBook…") { importGymBook?() }.disabled(importGymBook == nil)
            Button("Export for GymBook…", action: export).disabled(busy)
        }
        .alert(message ?? "", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }) {}
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
#endif
