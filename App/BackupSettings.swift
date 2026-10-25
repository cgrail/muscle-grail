#if os(macOS)
import Core
import CoreData
import SwiftData
import SwiftUI

/// Backs up into the folder picked in Settings: at launch, and a moment after each save or sync, off the main actor.
@MainActor @Observable final class BackupFolder {
    private let container: ModelContainer
    private(set) var url: URL?
    private(set) var lastBackup: Date?
    private(set) var error: String?
    private var pending: Task<Void, Never>?

    init(container: ModelContainer) {
        self.container = container
        url = Self.resolve()
        for name in [ModelContext.didSave, NSPersistentCloudKitContainer.eventChangedNotification] {
            _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.schedule() }
            }
        }
        schedule()
    }

    func choose(_ folder: URL) {
        url?.stopAccessingSecurityScopedResource()
        _ = folder.startAccessingSecurityScopedResource()
        UserDefaults.standard.set(try? folder.bookmarkData(options: .withSecurityScope), forKey: "backupFolder")
        url = folder
        schedule()
    }

    /// Saves come in bursts while editing and syncing, so this waits for a quiet moment and writes once.
    private func schedule() {
        guard let url else { return }
        pending?.cancel()
        pending = Task { [container] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            let result = await Task.detached { Result { try Backup.write(container, to: url) } }.value
            switch result {
            case .success: (lastBackup, error) = (.now, nil)
            case let .failure(failure): error = failure.localizedDescription
            }
        }
    }

    /// The sandbox only lets the app into the folder through the bookmark saved when it was picked.
    private static func resolve() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: "backupFolder") else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale { UserDefaults.standard.set(try? url.bookmarkData(options: .withSecurityScope), forKey: "backupFolder") }
        return url
    }
}

/// Settings → General: the folder the backup goes to.
struct BackupSettings: View {
    @Environment(BackupFolder.self) private var backup
    @State private var choosing = false

    var body: some View {
        Section("Backup") {
            LabeledContent("Folder") {
                Button(backup.url?.lastPathComponent ?? String(localized: "Choose…")) { choosing = true }
            }
            if let error = backup.error {
                Text(error).foregroundStyle(.red)
            } else if let date = backup.lastBackup {
                Text("Last backup \(date, format: .dateTime.hour().minute().second())").foregroundStyle(.secondary)
            }
            Text("Plans, workouts and your exercises are saved to this folder whenever they change.").foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case let .success(folder) = result { backup.choose(folder) }
        }
    }
}
#endif
