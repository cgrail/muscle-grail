import Core
import SwiftData
import SwiftUI
#if os(iOS)
import WidgetKit
#endif

@main
struct MuscleGrailApp: App {
    @State private var store: OpenStore
    #if os(macOS)
    @State private var mac: MacServices?
    #endif

    init() {
        _ = SyncMonitor.shared // listen before the store's first sync event
        let store = OpenStore()
        _store = State(initialValue: store)
        if let container = store.container { PartnerSync.start(container) }
        #if os(iOS)
        Self.observeSteps()
        #else
        _mac = State(initialValue: store.container.map(MacServices.init))
        #endif
    }

    #if os(iOS)
    static func observeSteps() {
        Health.observeSteps {
            WidgetCenter.shared.reloadAllTimelines() // new steps for the widget
            await PartnerSync.current?.sync()
            await SyncMonitor.shared.waitUntilIdle()
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                RootView().modelContainer(container)
                #if os(macOS)
                    .onAppear { if mac == nil { mac = MacServices(container: container) } } // after the store opened again
                #endif
            } else {
                UnreadableStore(store)
            }
        }
        #if os(macOS)
        Settings {
            if let mac {
                TabView {
                    Tab("General", systemImage: "gear") {
                        Form { LanguagePicker(); BackupSettings(); Credits() }.formStyle(.grouped).frame(width: 560).environment(mac.backup)
                    }
                    Tab("Training partner", systemImage: "person.2") { Form { PartnerSettings() }.formStyle(.grouped).frame(width: 560) }
                    Tab("Claude", systemImage: "sparkles") { ClaudeSettings().environment(mac.claude) }
                }
            }
        }
        #endif
    }
}

#if os(macOS)
/// What the Mac runs on its store, made once the store opens.
struct MacServices {
    let claude: ClaudeConnection
    let backup: BackupFolder

    init(container: ModelContainer) {
        claude = ClaudeConnection(context: container.mainContext)
        backup = BackupFolder(container: container)
    }
}
#endif

struct RootView: View {
    var body: some View {
        #if os(macOS)
        MacRootView()
        #else
        TabView {
            Tab("Train", systemImage: "figure.strengthtraining.traditional") { TrainView() }
            Tab("Plans", systemImage: "list.bullet.clipboard") { PlansView() }
            Tab("History", systemImage: "clock") { HistoryView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            await Health.requestAuthorization()
            MuscleGrailApp.observeSteps()
        }
        #endif
    }
}
