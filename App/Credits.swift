import SwiftUI

/// RepDB's license wants its attribution visible in the app: the exercises, their steps and images are RepDB's.
/// On the iPhone, About is a page of its own, so Settings stays short.
struct Credits: View {
    var body: some View {
        #if os(iOS)
        Section {
            NavigationLink("About") { Form { Section { AppInfo() }; syncAndCredits }.navigationTitle("About") }
        }
        #else
        Section("About") { AppInfo() }
        syncAndCredits
        #endif
    }

    @ViewBuilder private var syncAndCredits: some View {
        Section { SyncLog() }
        Section("Credits") {
            Link(destination: URL(string: "https://repdb.co")!) { Text(verbatim: "Exercise data by RepDB (repdb.co)") }
        }
    }
}
