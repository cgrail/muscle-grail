import SwiftUI

/// The build this app runs, down to its commit, like the watch's info screen, with links to the commit and the repository.
struct AppInfo: View {
    private static let repository = URL(string: "https://github.com/cgrail/muscle-grail")!

    var body: some View {
        let info = Bundle.main.infoDictionary ?? [:]
        // Stamped into Info.plist by the target's "Stamp Git Commit" build phase, "unknown" where git wasn't there.
        let commit = (info["GitCommit"] as? String).flatMap { $0 == "unknown" ? nil : $0 }
        LabeledContent("Version") {
            Text(verbatim: "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))")
        }
        LabeledContent("Commit") {
            if let commit {
                Link(destination: Self.repository.appending(path: "commit/\(commit)")) { Text(verbatim: commit).monospaced() }
            } else {
                Text(verbatim: "–")
            }
        }
        Link("Muscle Grail on GitHub", destination: Self.repository)
    }
}
