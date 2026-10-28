import Core
import SwiftUI

/// Settings → About: every failed sync since launch in full, as CloudKit and Core Data describe it, to read, copy or share.
struct SyncLog: View {
    private let sync = SyncMonitor.shared

    var body: some View {
        DisclosureGroup {
            ForEach(sync.failures) { Text(verbatim: Self.text($0)).font(.caption.monospaced()).textSelection(.enabled) }
            if !sync.failures.isEmpty { ShareLink("Share", item: sync.failures.map(Self.text).joined(separator: "\n\n")) }
        } label: {
            Text("Sync errors (\(sync.failures.count))")
        }
    }

    private static func text(_ failure: SyncFailure) -> String {
        "\(failure.date.formatted(date: .abbreviated, time: .standard)) · \(failure.kind)\n\(failure.details)"
    }
}
