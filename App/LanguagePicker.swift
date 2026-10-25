import SwiftUI

/// Switches the app between English and German. Apple reads `AppleLanguages` at launch, so the switch shows once the app reopens.
struct LanguagePicker: View {
    private static let launched = Bundle.main.preferredLocalizations.first ?? "en"
    @State private var language = launched

    var body: some View {
        Picker("Language", selection: $language) {
            Text(verbatim: "English").tag("en")
            Text(verbatim: "Deutsch").tag("de")
        }
        .onChange(of: language) { UserDefaults.standard.set([language], forKey: "AppleLanguages") }
        if language != Self.launched {
            Text("Reopen Muscle Grail to switch the language.").foregroundStyle(.secondary)
        }
    }
}

#if os(iOS)
/// The iPhone's settings, behind the gear on the Train tab. The Mac has its Settings window.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { LanguagePicker() }
                .navigationTitle("Settings")
                .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium])
    }
}
#endif
