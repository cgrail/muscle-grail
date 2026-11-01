import SwiftUI

/// RepDB's license wants its attribution visible in the app: the exercises, their steps and images are RepDB's.
/// Machine Torso Rotation's drawing is adapted from Open Exercise Art, whose CC BY-SA 4.0 wants credit, a licence link and
/// a note that it was changed.
struct Credits: View {
    var body: some View {
        Section("About") {
            AppInfo()
            SyncLog()
            Link(destination: URL(string: "https://repdb.co")!) { Text(verbatim: "Exercise data by RepDB (repdb.co)") }
            Text("Machine Torso Rotation drawing adapted from [Open Exercise Art](https://github.com/AlexMollard/Open-Exercise-Art) by Alex Mollard, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)")
        }
    }
}
