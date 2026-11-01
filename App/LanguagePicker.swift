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
/// The gear on every tab that opens the iPhone's settings.
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button("Settings", systemImage: "gear") { showing = true }
            .sheet(isPresented: $showing) { SettingsSheet() }
    }
}

/// The iPhone's settings. The Mac has its Settings window.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { LanguagePicker(); Section { TargetDefaultsLink() }; PartnerSettings(); Credits() }
                .navigationTitle("Settings")
                .toolbar { Button("Done") { dismiss() } }
        }
        .presentationDetents([.medium])
    }
}
#endif
