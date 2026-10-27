import Core
import SwiftUI

/// The build this watch runs, down to its commit, how it syncs, and the log of plan changes that synced to it.
struct InfoView: View {
    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        List {
            LabeledContent("Version") {
                Text(verbatim: "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))")
            }
            // Stamped into Info.plist by the watch target's build phase.
            LabeledContent("Commit") { Text(verbatim: info["GitCommit"] as? String ?? "–").monospaced() }
            SyncStatusView()
            NavigationLink { PlanChanges() } label: { Label("Plan changes", systemImage: "clock.arrow.circlepath") }
        }
        .navigationTitle("Info")
    }
}
