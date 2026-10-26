import SwiftUI

/// RepDB's license wants its attribution visible in the app: the exercises, their steps and images are RepDB's.
struct Credits: View {
    var body: some View {
        Section("About") {
            Link(destination: URL(string: "https://repdb.co")!) { Text(verbatim: "Exercise data by RepDB (repdb.co)") }
        }
    }
}
